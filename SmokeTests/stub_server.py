"""段階A専用の連続HEVC/TS fixture。fMP4やアプリの再生処理は含まない。"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import time
from urllib.parse import urlsplit, parse_qs

MEDIA = Path(__file__).with_name('media')
LINES = (MEDIA / 'index.m3u8').read_text().splitlines()
SEGMENTS = [line for line in LINES if line and not line.startswith('#')]
PROGRAMS = json.loads('{"1": {"id": 1, "recorded_video": {"id": 1, "status": "Recorded", "duration": 180.0, "file_size": 6388616, "video_codec": "H.265", "video_resolution_width": 640, "video_resolution_height": 360}, "channel": {"id": "gr001", "display_channel_id": "GR001", "name": "テスト放送", "type": "GR", "channel_number": "1"}, "title": "スモークテスト番組", "description": "自動テスト用の番組です。", "genres": [{"major": "その他", "middle": "その他"}], "detail": {}, "is_partially_recorded": false, "start_time": "2026-11-20T19:00:00+09:00", "end_time": "2026-11-20T19:03:00+09:00", "duration": 180.0, "is_protected": false, "watched_ratio": 0.0, "recording_start_margin": 0.0, "next_episode_id": 2}, "2": {"id": 2, "recorded_video": {"id": 2, "status": "Recorded", "duration": 180.0, "file_size": 6388616, "video_codec": "H.265", "video_resolution_width": 640, "video_resolution_height": 360}, "channel": {"id": "gr001", "display_channel_id": "GR001", "name": "テスト放送", "type": "GR", "channel_number": "1"}, "title": "スモークテスト番組2", "description": "自動テスト用の番組です。", "genres": [{"major": "その他", "middle": "その他"}], "detail": {}, "is_partially_recorded": false, "start_time": "2026-11-20T20:00:00+09:00", "end_time": "2026-11-20T20:03:00+09:00", "duration": 180.0, "is_protected": false, "watched_ratio": 0.0, "recording_start_margin": 0.0, "previous_episode_id": 1}}')
for program in PROGRAMS.values():
    program['recorded_video']['thumbnail_info']={'version':1,'tile':{'format':'png','image_width':320,'image_height':180,'tile_width':320,'tile_height':180,'total_tiles':1,'column_count':1,'row_count':1,'interval_sec':180}}
COMMENTS = [{'time': 1.0 + i * 2, 'type': 'right', 'size': 'medium', 'color': '#FFFFFF', 'author': 'fixture', 'text': '合成コメント'} for i in range(60)]
CHANNELS = {key: [] for key in ['GR','BS','CS','CATV','SKY','BS4K']}
CHANNELS['GR'] = [{'id': 'gr001', 'display_channel_id': 'gr001', 'name': '段階A生放送', 'type': 'GR', 'channel_number': '001', 'is_display': True, 'is_watchable': True,
                  'program_present': {'title': '合成生放送', 'description': '合成素材', 'start_time': '2026-11-20T19:00:00+09:00', 'end_time': '2026-11-20T22:00:00+09:00'}}]

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, fmt, *args):
        print('fixture: ' + fmt % args, flush=True)
    def send(self, status, body=b'', kind='application/json'):
        self.send_response(status); self.send_header('Content-Type',kind); self.send_header('Content-Length',str(len(body))); self.end_headers()
        if body: self.wfile.write(body)
    def send_json(self, value): self.send(200,json.dumps(value).encode())
    def do_GET(self):
        url=urlsplit(self.path);parts=url.path.strip('/').split('/');query=parse_qs(url.query)
        if url.path=='/health': return self.send_json({'status':'ok'})
        if url.path=='/api/videos': return self.send_json({'total':2,'recorded_programs':list(PROGRAMS.values())})
        if url.path=='/api/videos/storage-status': return self.send_json({'total_bytes':1000000000,'used_bytes':0,'free_bytes':1000000000,'recordings_bytes':0})
        if url.path=='/api/channels': return self.send_json(CHANNELS)
        if len(parts)==4 and parts[:2]==['api','channels'] and parts[3]=='logo': return self.send(200,(MEDIA/'thumbnail.png').read_bytes(),'image/png')
        if len(parts)>=3 and parts[:2]==['api','videos'] and parts[2] in PROGRAMS:
            if len(parts)==3: return self.send_json(PROGRAMS[parts[2]])
            if parts[3]=='thumbnail':
                if len(parts)>4 and parts[4]=='tiled': time.sleep(1)
                return self.send(200,(MEDIA/'thumbnail.png').read_bytes(),'image/png')
            if parts[3]=='jikkyo': return self.send_json({'is_success':True,'comments':COMMENTS,'detail':''})
            if parts[3]=='bookmarks': return self.send_json([])
        if len(parts)==6 and parts[:3]==['api','streams','video'] and parts[3] in PROGRAMS:
            if parts[5]=='playlist':
                lines=[];sequence=0;session=query.get('session_id',['fixture'])[0]
                for line in LINES:
                    if line and not line.startswith('#'):
                        lines.append('segment?session_id=%s&sequence=%d'%(session,sequence));sequence+=1
                    else: lines.append(line)
                return self.send(200,('\n'.join(lines)+'\n').encode(),'application/vnd.apple.mpegurl')
            if parts[5]=='segment':
                try: sequence=int(query.get('sequence',['-1'])[0])
                except ValueError: sequence=-1
                if 0<=sequence<len(SEGMENTS): return self.send(200,(MEDIA/SEGMENTS[sequence]).read_bytes(),'video/mp2t')
        if len(parts)==6 and parts[:3]==['api','streams','live'] and parts[5]=='mpegts': return self.send_live()
        self.send(404)
    def send_live(self):
        self.send_response(200);self.send_header('Content-Type','video/mp2t');self.send_header('Transfer-Encoding','chunked');self.send_header('Connection','close');self.end_headers();self.close_connection=True
        try:
            for name in SEGMENTS:
                body=(MEDIA/name).read_bytes();started=time.monotonic()
                for offset in range(0,len(body),188*128):
                    chunk=body[offset:offset+188*128];self.wfile.write(('%x\r\n'%len(chunk)).encode()+chunk+b'\r\n');self.wfile.flush()
                    time.sleep(max(0,started+6*min(len(body),offset+len(chunk))/len(body)-time.monotonic()))
            self.wfile.write(b'0\r\n\r\n')
        except (BrokenPipeError,ConnectionResetError): pass
    def do_PUT(self): self.send_json({})
    def do_POST(self):
        length=int(self.headers.get('Content-Length') or 0)
        if length: self.rfile.read(length)
        self.send_json({})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('port',type=int,nargs='?',default=18080);args=parser.parse_args()
    with ThreadingHTTPServer(('127.0.0.1',args.port),Handler) as server: server.serve_forever()
