#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""KonomiTV Viewer の自動テスト (シミュレータ確認) 用の仮サーバー。

アプリが実際に使う入口だけを、固定の材料で返す小さなサーバー。
Python の標準機能だけで書いてある (追加の部品は要らない)。
実在のサーバー情報・認証情報は一切含まない。番組名なども
テスト専用の作り物。

使い方: python3 stub_server.py [ポート番号] [--fmp4 [--audio]]  (既定 18080、TSのみ)
"""

import argparse
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA_DIR = os.path.join(HERE, "media")
# 時刻が連続した長いfixtureを使い、短いTS反復による時計の巻き戻りを避ける。
with open(os.path.join(MEDIA_DIR, "index.m3u8"), encoding="utf-8") as stream:
    PLAYLIST_LINES = stream.read().splitlines()
SEGMENT_FILES = [line for line in PLAYLIST_LINES if line and not line.startswith("#")]
SEGMENT_COUNT = len(SEGMENT_FILES)
FMP4_MEDIA_DIR = os.path.join(HERE, "media-fmp4")
with open(os.path.join(FMP4_MEDIA_DIR, "index.m3u8"), encoding="utf-8") as stream:
    FMP4_PLAYLIST_LINES = stream.read().splitlines()
FMP4_SEGMENT_FILES = [line for line in FMP4_PLAYLIST_LINES if line and not line.startswith("#")]
FMP4_AUDIO_MEDIA_DIR = os.path.join(HERE, "media-fmp4-audio")
with open(os.path.join(FMP4_AUDIO_MEDIA_DIR, "index.m3u8"), encoding="utf-8") as stream:
    FMP4_AUDIO_PLAYLIST_LINES = stream.read().splitlines()
FMP4_AUDIO_SEGMENT_FILES = [line for line in FMP4_AUDIO_PLAYLIST_LINES if line and not line.startswith("#")]
FIXTURE_DURATION = sum(float(line.split(":", 1)[1].split(",", 1)[0])
                       for line in PLAYLIST_LINES if line.startswith("#EXTINF:"))


# 録画番組の材料 (形はアプリ側 Models.swift の読み取りに合わせる)。
PROGRAM_1 = {
    "id": 1,
    "recorded_video": {
        "id": 1,
        "status": "Recorded",
        "duration": FIXTURE_DURATION,
        "file_size": sum(os.path.getsize(os.path.join(MEDIA_DIR, name)) for name in SEGMENT_FILES),
        "video_codec": "H.265",
        "video_resolution_width": 640,
        "video_resolution_height": 360,
    },
    "channel": {
        "id": "gr001",
        "display_channel_id": "GR001",
        "name": "テスト放送",
        "type": "GR",
        "channel_number": "1",
    },
    "title": "スモークテスト番組",
    "description": "自動テスト用の番組です。",
    "genres": [{"major": "その他", "middle": "その他"}],
    "detail": {},
    "is_partially_recorded": False,
    "start_time": "2026-11-20T19:00:00+09:00",
    "end_time": "2026-11-20T19:03:00+09:00",
    "duration": FIXTURE_DURATION,
    "is_protected": False,
    "watched_ratio": 0.0,
    "recording_start_margin": 0.0,
}

PROGRAM_2 = dict(PROGRAM_1)
PROGRAM_2["id"] = 2
PROGRAM_2["recorded_video"] = dict(PROGRAM_1["recorded_video"])
PROGRAM_2["recorded_video"]["id"] = 2
PROGRAM_2["title"] = "スモークテスト番組2"
PROGRAM_2["start_time"] = "2026-11-20T20:00:00+09:00"
PROGRAM_2["end_time"] = "2026-11-20T20:03:00+09:00"

PROGRAMS = {1: PROGRAM_1, 2: PROGRAM_2}
PROGRAM_1["next_episode_id"] = 2
PROGRAM_2["previous_episode_id"] = 1

# 過去ログコメントの材料 (時刻は再生位置の秒数)。
COMMENTS = [
    {"time": 1.0 + i * 1.5, "type": "right", "size": "medium",
     "color": "#FFFFFF", "author": "テスト", "text": "テストコメント%d" % (i + 1)}
    for i in range(10)
]

STORAGE_STATUS = {
    "total_bytes": 1099511627776,
    "used_bytes": 549755813888,
    "free_bytes": 549755813888,
    "recordings_bytes": 1408000,
}

EMPTY_CHANNELS = {"GR": [], "BS": [], "CS": [], "CATV": [], "SKY": [], "BS4K": []}
LIVE_CHANNELS = dict(EMPTY_CHANNELS, GR=[{
    "id": "gr%03d" % index, "display_channel_id": "gr%03d" % index,
    "name": "スモーク生放送%d" % index, "type": "GR", "channel_number": "%03d" % index,
    "is_display": True, "is_watchable": True,
    "program_present": {"title": "生放送テスト%d" % index, "description": "合成素材",
                        "start_time": "2026-11-20T19:00:00+09:00", "end_time": "2026-11-20T22:00:00+09:00"}
} for index in (1, 2)])


def playlist_body(session_id, fmp4=False, audio=False):
    """実際の分割尺と連続タイムスタンプを保持し、URIだけAPI形式へ置き換える。"""
    lines = []
    seq = 0
    source = (FMP4_AUDIO_PLAYLIST_LINES if audio else FMP4_PLAYLIST_LINES) if fmp4 else PLAYLIST_LINES
    format_query = "&segment_format=fmp4" if fmp4 else ""
    for line in source:
        if line.startswith("#EXT-X-MAP:"):
            lines.append('#EXT-X-MAP:URI="init?session_id=%s&segment_format=fmp4"' % session_id)
        elif line and not line.startswith("#"):
            lines.append("segment?session_id=%s&sequence=%d%s" % (session_id, seq, format_query))
            seq += 1
        else:
            lines.append(line)
    lines.append("")
    return "\n".join(lines).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ログは標準出力へ (CI のログで要求の流れを追えるように)。
    def log_message(self, fmt, *args):
        sys.stdout.write("stub: %s\n" % (fmt % args))
        sys.stdout.flush()

    def _send(self, status, body, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _send_json(self, status, obj):
        self._send(status, json.dumps(obj).encode("utf-8"), "application/json")

    def _send_file(self, path, content_type):
        try:
            with open(path, "rb") as f:
                body = f.read()
        except OSError:
            self._send_json(404, {"detail": "not found"})
            return
        self._send(200, body, content_type)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        parts = [p for p in path.split("/") if p != ""]

        if path == "/health":
            self._send_json(200, {"status": "ok"})
            return
        if path == "/api/videos":
            self._send_json(200, {
                "total": len(PROGRAMS),
                "recorded_programs": [PROGRAMS[1], PROGRAMS[2]],
            })
            return
        if path == "/api/videos/storage-status":
            self._send_json(200, STORAGE_STATUS)
            return
        if path == "/api/channels":
            self._send_json(200, LIVE_CHANNELS if getattr(self.server, "lifecycle", False) else EMPTY_CHANNELS)
            return
        if (getattr(self.server, "lifecycle", False) and len(parts) == 6
                and parts[:3] == ["api", "streams", "live"] and parts[5] == "mpegts"
                and parts[3] in ("gr001", "gr002")):
            self._send_live_ts()
            return
        # /api/channels/{局}/logo (録画一覧のカードが局ロゴを取りに来る)。
        if len(parts) == 4 and parts[0] == "api" and parts[1] == "channels" and parts[3] == "logo":
            self._send_file(os.path.join(MEDIA_DIR, "thumbnail.png"), "image/png")
            return

        # /api/videos/{番号} と、その下の入口。
        if len(parts) >= 3 and parts[0] == "api" and parts[1] == "videos":
            try:
                video_id = int(parts[2])
            except ValueError:
                video_id = None
            program = PROGRAMS.get(video_id)
            if program is not None:
                if len(parts) == 3:
                    self._send_json(200, program)
                    return
                sub = parts[3]
                if sub == "thumbnail":
                    self._send_file(os.path.join(MEDIA_DIR, "thumbnail.png"), "image/png")
                    return
                if sub == "jikkyo":
                    self._send_json(200, {
                        "is_success": True,
                        "comments": COMMENTS,
                        "detail": "",
                    })
                    return
                if sub == "bookmarks":
                    self._send_json(200, [])
                    return

        # /api/streams/video/{番号}/{画質}/playlist と /segment。
        if len(parts) == 6 and parts[0] == "api" and parts[1] == "streams" and parts[2] == "video":
            try:
                video_id = int(parts[3])
            except ValueError:
                video_id = None
            if video_id in PROGRAMS:
                kind = parts[5]
                # 対応を明示した仮サーバーだけfMP4を返す。形式指定なしのTS経路は残す。
                fmp4 = (getattr(self.server, "supports_fmp4", False)
                        and query.get("segment_format") == ["fmp4"])
                audio = fmp4 and getattr(self.server, "fixture_audio", False)
                fmp4_directory = FMP4_AUDIO_MEDIA_DIR if audio else FMP4_MEDIA_DIR
                if kind == "playlist":
                    session_id = query.get("session_id", ["smoke"])[0]
                    self._send(200, playlist_body(session_id, fmp4=fmp4, audio=audio),
                               "application/vnd.apple.mpegurl")
                    return
                if kind == "init" and fmp4:
                    self._send_file(os.path.join(fmp4_directory, "init.mp4"), "video/mp4")
                    return
                if kind == "segment":
                    try:
                        seq = int(query.get("sequence", ["0"])[0])
                    except ValueError:
                        seq = -1
                    fmp4_files = FMP4_AUDIO_SEGMENT_FILES if audio else FMP4_SEGMENT_FILES
                    files = fmp4_files if fmp4 else SEGMENT_FILES
                    directory = fmp4_directory if fmp4 else MEDIA_DIR
                    if 0 <= seq < len(files):
                        self._send_file(os.path.join(directory, files[seq]), "video/mp4" if fmp4 else "video/MP2T")
                    else:
                        self._send_json(404, {"detail": "not found"})
                    return

        self._send_json(404, {"detail": "not found"})

    def _send_live_ts(self):
        # 実APIと同じ連続TS。HLSで代用せず、188byte境界の塊を素材尺に合わせて流す。
        # 180秒で終了する有限fixtureで、切断時はその接続の送出だけを終える。
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        try:
            for name in SEGMENT_FILES:
                with open(os.path.join(MEDIA_DIR, name), "rb") as stream:
                    body = stream.read()
                started = time.monotonic()
                for offset in range(0, len(body), 188 * 128):
                    chunk = body[offset:offset + 188 * 128]
                    self.wfile.write(("%x\r\n" % len(chunk)).encode() + chunk + b"\r\n")
                    self.wfile.flush()
                    deadline = started + 6 * min(len(body), offset + len(chunk)) / len(body)
                    time.sleep(max(0, deadline - time.monotonic()))
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_PUT(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p != ""]
        # /api/streams/video/{番号}/{画質}/keep-alive は成功だけ返す。
        if (len(parts) == 6 and parts[0] == "api" and parts[1] == "streams"
                and parts[2] == "video" and parts[5] == "keep-alive"):
            self._send_json(200, {})
            return
        self._send_json(404, {"detail": "not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p != ""]
        # 本体 (再生位置の報告など) は読み捨てて、成功だけ返す。
        length = int(self.headers.get("Content-Length") or 0)
        if length > 0:
            self.rfile.read(length)
        # /api/videos/{番号}/watched は成功だけ返す。
        if (len(parts) == 4 and parts[0] == "api" and parts[1] == "videos"
                and parts[3] == "watched"):
            self._send_json(200, {})
            return
        self._send_json(404, {"detail": "not found"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", type=int, nargs="?", default=18080)
    parser.add_argument("--fmp4", action="store_true", help="Enable opt-in fMP4 fixture responses")
    parser.add_argument("--audio", action="store_true", help="Use the controlled AAC alternative with --fmp4")
    parser.add_argument("--lifecycle", action="store_true", help="Enable two live channels and paced MPEG-TS")
    args = parser.parse_args()
    if args.audio and not args.fmp4:
        parser.error("--audio requires --fmp4")
    port = args.port
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.supports_fmp4 = args.fmp4
    server.fixture_audio = args.audio
    server.lifecycle = args.lifecycle
    print("Stub server listening on http://127.0.0.1:%d" % port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
