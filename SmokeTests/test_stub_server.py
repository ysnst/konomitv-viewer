import json
from http.server import ThreadingHTTPServer
import socket
import threading
import unittest
from urllib.request import urlopen
import stub_server

class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.server=ThreadingHTTPServer(('127.0.0.1',0),stub_server.Handler)
        self.port=self.server.server_address[1]
        self.thread=threading.Thread(target=self.server.serve_forever);self.thread.start()
        self.base='http://127.0.0.1:%d'%self.port
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join(timeout=5)
        self.assertFalse(self.thread.is_alive())
        with ThreadingHTTPServer(('127.0.0.1',self.port),stub_server.Handler): pass
    def test_recorded_fixture_and_real_continuous_segments(self):
        with urlopen(self.base+'/api/videos') as response: listing=json.load(response)
        self.assertEqual(listing['total'],2)
        with urlopen(self.base+'/api/videos/1/jikkyo') as response: comments=json.load(response)
        self.assertGreater(len(comments['comments']),0)
        with urlopen(self.base+'/api/streams/video/1/720p-hevc/playlist?session_id=contract') as response: playlist=response.read().decode()
        self.assertNotIn('EXT-X-MAP',playlist)
        segments=[line for line in playlist.splitlines() if line and not line.startswith('#')]
        self.assertEqual(len(segments),30)
        for index,relative in enumerate(segments):
            with urlopen(self.base+'/api/streams/video/1/720p-hevc/'+relative) as response: body=response.read()
            self.assertEqual(body,(stub_server.MEDIA/stub_server.SEGMENTS[index]).read_bytes())
            self.assertEqual(len(body)%188,0)
    def test_live_endpoint_is_chunked_ts(self):
        with urlopen(self.base+'/api/channels') as response: channels=json.load(response)
        self.assertEqual(channels['GR'][0]['name'],'段階A生放送')
        with urlopen(self.base+'/api/streams/live/gr001/720p/mpegts',timeout=3) as response:
            self.assertEqual(response.headers['Transfer-Encoding'],'chunked')
            self.assertIsNone(response.headers.get('Content-Length'))
            body=response.read(188*3)
            self.assertEqual(len(body),188*3)
            self.assertTrue(all(body[i]==0x47 for i in [0,188,376]))

if __name__=='__main__': unittest.main()
