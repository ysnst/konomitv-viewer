"""Fixture の HTTP 契約を実通信で確認する。実ユーザーのサーバーや素材は使わない。"""
import json
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

    def test_hls_playlist_resolves_real_transport_streams(self):
        path = '/api/streams/video/1/720p-hevc/playlist?session_id=contract'
        headers, body = self.fetch(path)
        self.assertEqual(headers['Content-Type'], 'application/vnd.apple.mpegurl')
        playlist = body.decode('utf-8')
        self.assertIn('#EXT-X-ENDLIST', playlist)
        segments = [line for line in playlist.splitlines() if line and not line.startswith('#')]
        self.assertEqual(len(segments), 30)
        self.assertEqual(playlist.count("#EXT-X-DISCONTINUITY"), 9)
        for index, relative in enumerate(segments):
            headers, stream = self.fetch(urljoin(path, relative))
            self.assertEqual(headers['Content-Type'], 'video/MP2T')
            self.assertEqual(stream, (Path(stub_server.MEDIA_DIR) / ('seg%d.ts' % (index % 3))).read_bytes())
            self.assertGreater(len(stream), 188)
            self.assertEqual(len(stream) % 188, 0)
            self.assertTrue(all(stream[offset] == 0x47 for offset in range(0, len(stream), 188)))
        self.fetch('/api/streams/video/1/720p-hevc/keep-alive', method='PUT')
        self.fetch('/api/videos/1/watched', method='POST', body=b'{"position": 2}')

    def test_unknown_resource_fails(self):
        for path in ('/unknown', '/api/videos/999', '/api/streams/video/999/720p-hevc/playlist'):
            with self.subTest(path=path):
                with self.assertRaises(HTTPError) as error:
                    self.fetch(path)
                self.assertEqual(error.exception.code, 404)
                error.exception.close()


if __name__ == '__main__':
    unittest.main()
