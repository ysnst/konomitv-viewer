#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""KonomiTV Viewer の自動テスト (シミュレータ確認) 用の仮サーバー。

アプリが実際に使う入口だけを、固定の材料で返す小さなサーバー。
Python の標準機能だけで書いてある (追加の部品は要らない)。
実在のサーバー情報・認証情報は一切含まない。番組名なども
テスト専用の作り物。

使い方: python3 stub_server.py [ポート番号]  (既定 18080)
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA_DIR = os.path.join(HERE, "media")

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18080

# 録画番組の材料 (形はアプリ側 Models.swift の読み取りに合わせる)。
PROGRAM_1 = {
    "id": 1,
    "recorded_video": {
        "id": 1,
        "status": "Recorded",
        "duration": 1800.0,
        "file_size": 1408000,
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
    "end_time": "2026-11-20T19:30:00+09:00",
    "duration": 1800.0,
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
PROGRAM_2["end_time"] = "2026-11-20T20:30:00+09:00"

PROGRAMS = {1: PROGRAM_1, 2: PROGRAM_2}

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


def playlist_body(session_id):
    """見本の区切り3つ分を指す再生リスト (実物の書き方に合わせる)。"""
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-TARGETDURATION:6",
        "#EXT-X-MEDIA-SEQUENCE:0",
        "#EXT-X-PLAYLIST-TYPE:VOD",
    ]
    for seq in range(3):
        lines.append("#EXTINF:6.000000,")
        lines.append("segment?session_id=%s&sequence=%d" % (session_id, seq))
    lines.append("#EXT-X-ENDLIST")
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
            self._send_json(200, EMPTY_CHANNELS)
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
                if kind == "playlist":
                    session_id = query.get("session_id", ["smoke"])[0]
                    self._send(200, playlist_body(session_id),
                               "application/vnd.apple.mpegurl")
                    return
                if kind == "segment":
                    try:
                        seq = int(query.get("sequence", ["0"])[0])
                    except ValueError:
                        seq = 0
                    seq = min(max(seq, 0), 2)
                    self._send_file(os.path.join(MEDIA_DIR, "seg%d.ts" % seq),
                                    "video/MP2T")
                    return

        self._send_json(404, {"detail": "not found"})

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
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("stub server listening on http://127.0.0.1:%d" % PORT, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
