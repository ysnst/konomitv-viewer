"""Fixture の HTTP 契約を実通信で確認する。実ユーザーのサーバーや素材は使わない。"""
import json
import hashlib
import subprocess
import sys
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import urljoin
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer

import stub_server


class StubContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # OS に空きポートを選ばせ、テスト専用 thread だけを終了処理の対象にする。
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), stub_server.Handler)
        cls.port = cls.server.server_address[1]
        cls.base = 'http://127.0.0.1:%d' % cls.port
        cls.thread = threading.Thread(target=cls.server.serve_forever)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)
        if cls.thread.is_alive():
            raise AssertionError('Fixture server thread did not stop')
        # 同じポートへ新たに bind できることを確認する。
        with ThreadingHTTPServer(('127.0.0.1', cls.port), stub_server.Handler):
            pass

    def fetch(self, path, method='GET', body=None):
        request = Request(urljoin(self.base, path), data=body, method=method)
        with urlopen(request, timeout=3) as response:
            return response.headers, response.read()

    def test_home_program_detail_and_overlays(self):
        _, health = self.fetch('/health')
        self.assertEqual(json.loads(health), {'status': 'ok'})
        _, listing = self.fetch('/api/videos?order=desc&page=1')
        programs = json.loads(listing)['recorded_programs']
        self.assertEqual([p['id'] for p in programs], [1, 2])
        _, detail = self.fetch('/api/videos/1')
        self.assertEqual(json.loads(detail)['title'], 'スモークテスト番組')
        _, comments = self.fetch('/api/videos/1/jikkyo')
        self.assertTrue(json.loads(comments)['is_success'])
        self.assertGreater(len(json.loads(comments)['comments']), 0)
        headers, thumbnail = self.fetch('/api/videos/1/thumbnail')
        self.assertEqual(headers['Content-Type'], 'image/png')
        self.assertTrue(thumbnail.startswith(b'\x89PNG\r\n\x1a\n'))

    def test_live_channel_contract_and_paced_transport_stream(self):
        self.server.lifecycle = True
        try:
            _, body = self.fetch('/api/channels')
            self.assertEqual([c['display_channel_id'] for c in json.loads(body)['GR']], ['gr001', 'gr002'])
            for channel in ('gr001', 'gr002'):
                with urlopen(self.base + '/api/streams/live/' + channel + '/720p/mpegts', timeout=3) as response:
                    self.assertEqual(response.headers['Content-Type'], 'video/mp2t')
                    self.assertIsNone(response.headers.get('Content-Length'))
                    packets = response.read(188 * 3)
                    self.assertEqual(len(packets), 188 * 3)
                    self.assertTrue(all(packets[offset] == 0x47 for offset in (0, 188, 376)))
            _, first = self.fetch('/api/videos/1')
            _, second = self.fetch('/api/videos/2')
            self.assertEqual(json.loads(first)['next_episode_id'], 2)
            self.assertEqual(json.loads(second)['previous_episode_id'], 1)
        finally:
            self.server.lifecycle = False

    def test_hls_playlist_resolves_real_transport_streams(self):
        path = '/api/streams/video/1/720p-hevc/playlist?session_id=contract'
        headers, body = self.fetch(path)
        self.assertEqual(headers['Content-Type'], 'application/vnd.apple.mpegurl')
        playlist = body.decode('utf-8')
        self.assertIn('#EXT-X-ENDLIST', playlist)
        segments = [line for line in playlist.splitlines() if line and not line.startswith('#')]
        self.assertEqual(len(segments), 30)
        self.assertNotIn("#EXT-X-DISCONTINUITY", playlist)
        durations = [float(line.split(':', 1)[1].split(',', 1)[0])
                     for line in playlist.splitlines() if line.startswith('#EXTINF:')]
        self.assertAlmostEqual(sum(durations), stub_server.PROGRAM_1['duration'], places=6)
        self.assertGreaterEqual(sum(durations), 180)
        hashes = set()
        for index, relative in enumerate(segments):
            headers, stream = self.fetch(urljoin(path, relative))
            self.assertEqual(headers['Content-Type'], 'video/MP2T')
            self.assertEqual(stream, (Path(stub_server.MEDIA_DIR) / ('seg%d.ts' % index)).read_bytes())
            hashes.add(hashlib.sha256(stream).digest())
            self.assertGreater(len(stream), 188)
            self.assertEqual(len(stream) % 188, 0)
            self.assertTrue(all(stream[offset] == 0x47 for offset in range(0, len(stream), 188)))
        self.assertEqual(len(hashes), 30, 'Repeated transport streams must not reset the fixture clock')
        self.fetch('/api/streams/video/1/720p-hevc/keep-alive', method='PUT')
        self.fetch('/api/videos/1/watched', method='POST', body=b'{"position": 2}')

    def test_unsupported_fmp4_request_keeps_ts_route(self):
        path = '/api/streams/video/1/720p-hevc/playlist?session_id=contract&segment_format=fmp4'
        _, body = self.fetch(path)
        self.assertNotIn(b'#EXT-X-MAP:', body)
        with self.assertRaises(HTTPError) as error:
            self.fetch('/api/streams/video/1/720p-hevc/init?segment_format=fmp4')
        self.assertEqual(error.exception.code, 404)
        error.exception.close()

    def test_fmp4_map_fragments_and_same_session_ts_fallback(self):
        self.server.supports_fmp4 = True
        try:
            path = '/api/streams/video/1/720p-hevc/playlist?session_id=contract&segment_format=fmp4'
            _, body = self.fetch(path)
            playlist = body.decode('utf-8')
            self.assertIn('#EXT-X-ENDLIST', playlist)
            self.assertNotIn('#EXT-X-DISCONTINUITY', playlist)
            init_line = next(line for line in playlist.splitlines() if line.startswith('#EXT-X-MAP:'))
            init_uri = init_line.split('URI="', 1)[1].split('"', 1)[0]
            headers, init = self.fetch(urljoin(path, init_uri))
            self.assertEqual(headers['Content-Type'], 'video/mp4')
            self.assertEqual(init, (Path(stub_server.FMP4_MEDIA_DIR) / 'init.mp4').read_bytes())
            self.assertIn(b'ftyp', init)
            self.assertIn(b'hvc1', init)
            segments = [line for line in playlist.splitlines() if line and not line.startswith('#')]
            self.assertEqual(len(segments), 30)
            durations = [float(line.split(':', 1)[1].split(',', 1)[0])
                         for line in playlist.splitlines() if line.startswith('#EXTINF:')]
            self.assertAlmostEqual(sum(durations), stub_server.FIXTURE_DURATION, places=6)
            hashes = set()
            for index, relative in enumerate(segments):
                self.assertIn('segment_format=fmp4', relative)
                headers, fragment = self.fetch(urljoin(path, relative))
                self.assertEqual(headers['Content-Type'], 'video/mp4')
                self.assertEqual(fragment, (Path(stub_server.FMP4_MEDIA_DIR) / ('seg%d.m4s' % index)).read_bytes())
                self.assertIn(b'moof', fragment)
                self.assertIn(b'mdat', fragment)
                hashes.add(hashlib.sha256(fragment).digest())
            self.assertEqual(len(hashes), 30)
            for sequence in ('-1', '30', 'invalid'):
                with self.subTest(sequence=sequence):
                    with self.assertRaises(HTTPError) as error:
                        self.fetch('/api/streams/video/1/720p-hevc/segment?segment_format=fmp4&sequence=' + sequence)
                    self.assertEqual(error.exception.code, 404)
                    error.exception.close()
            # 同じセッションでも形式指定なしは従来のTSへ直接戻せる。
            fallback_path = '/api/streams/video/1/720p-hevc/playlist?session_id=contract'
            _, fallback = self.fetch(fallback_path)
            self.assertNotIn(b'#EXT-X-MAP:', fallback)
            first = next(line for line in fallback.decode().splitlines() if line and not line.startswith('#'))
            headers, stream = self.fetch(urljoin(fallback_path, first))
            self.assertEqual(headers['Content-Type'], 'video/MP2T')
            self.assertEqual(stream, (Path(stub_server.MEDIA_DIR) / 'seg0.ts').read_bytes())
        finally:
            self.server.supports_fmp4 = False

    def test_fmp4_audio_alternative_has_two_tracks_and_preserves_ts(self):
        self.server.supports_fmp4 = True
        self.server.fixture_audio = True
        try:
            path = '/api/streams/video/1/720p-hevc/playlist?session_id=audio-contract&segment_format=fmp4'
            _, body = self.fetch(path)
            playlist = body.decode('utf-8')
            init_line = next(line for line in playlist.splitlines() if line.startswith('#EXT-X-MAP:'))
            init_uri = init_line.split('URI="', 1)[1].split('"', 1)[0]
            headers, init = self.fetch(urljoin(path, init_uri))
            self.assertEqual(headers['Content-Type'], 'video/mp4')
            self.assertEqual(init, (Path(stub_server.FMP4_AUDIO_MEDIA_DIR) / 'init.mp4').read_bytes())
            self.assertIn(b'hvc1', init)
            self.assertIn(b'mp4a', init)
            self.assertEqual(init.count(b'trak'), 2)
            segments = [line for line in playlist.splitlines() if line and not line.startswith('#')]
            self.assertEqual(len(segments), 30)
            durations = [float(line.split(':', 1)[1].split(',', 1)[0])
                         for line in playlist.splitlines() if line.startswith('#EXTINF:')]
            self.assertAlmostEqual(sum(durations), stub_server.FIXTURE_DURATION, places=6)
            for index, relative in enumerate(segments):
                headers, fragment = self.fetch(urljoin(path, relative))
                self.assertEqual(headers['Content-Type'], 'video/mp4')
                self.assertEqual(fragment, (Path(stub_server.FMP4_AUDIO_MEDIA_DIR) / ('seg%d.m4s' % index)).read_bytes())
                self.assertEqual(fragment.count(b'traf'), 2)
            fallback_path = '/api/streams/video/1/720p-hevc/playlist?session_id=audio-contract'
            _, fallback = self.fetch(fallback_path)
            self.assertNotIn(b'#EXT-X-MAP:', fallback)
            first = next(line for line in fallback.decode().splitlines() if line and not line.startswith('#'))
            headers, stream = self.fetch(urljoin(fallback_path, first))
            self.assertEqual(headers['Content-Type'], 'video/MP2T')
            self.assertEqual(stream, (Path(stub_server.MEDIA_DIR) / 'seg0.ts').read_bytes())
        finally:
            self.server.fixture_audio = False
            self.server.supports_fmp4 = False

    def test_audio_flag_requires_fmp4(self):
        result = subprocess.run([sys.executable, str(Path(stub_server.__file__)), '--audio'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--audio requires --fmp4', result.stderr)

    def test_unknown_resource_fails(self):
        for path in ('/unknown', '/api/videos/999', '/api/streams/video/999/720p-hevc/playlist',
                     '/api/streams/video/1/720p-hevc/segment?sequence=-1',
                     '/api/streams/video/1/720p-hevc/segment?sequence=30'):
            with self.subTest(path=path):
                with self.assertRaises(HTTPError) as error:
                    self.fetch(path)
                self.assertEqual(error.exception.code, 404)
                error.exception.close()


if __name__ == '__main__':
    unittest.main()
