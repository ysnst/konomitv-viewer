"""macOSで実StreamRelayServerを合成HTTPサーバーへ接続して契約を調べる。"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
AUTH = {"CF-Access-Client-Id": "relay-contract-client", "CF-Access-Client-Secret": "relay-contract-secret"}
PAYLOAD = bytes(range(256)) * 4
PLAYLIST = b'''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MAP:URI="init.bin?asset=init"
#EXT-X-KEY:METHOD=AES-128,URI="https://example.invalid/key"
#EXTINF:1,
segment.bin?asset=seg
#EXT-X-ENDLIST
'''


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.streams = {}
        self.cancelled = 0
        self.requests = []


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        # 合成認証値も含めてヘッダー・URLを出さず、状態は最後の件数だけ保存する。
        pass

    def send(self, status, body=b'', **headers):
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        for name, value in headers.items():
            self.send_header(name.replace('_', '-'), value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = urlsplit(self.path).path
        state = self.server.contract_state
        if path == '/metrics':
            with state.lock:
                metrics = {'active_streams': len(state.streams), 'cancelled_streams': state.cancelled}
            self.send(200, json.dumps(metrics).encode(), Content_Type='application/json')
            return
        authorized = all(self.headers.get(key) == value for key, value in AUTH.items())
        with state.lock:
            state.requests.append({'path': path, 'authorized': authorized, 'range': self.headers.get('Range')})
        if not authorized:
            self.send(401)
            return
        if path == '/media/master.m3u8':
            self.send(200, PLAYLIST, Content_Type='application/vnd.apple.mpegurl')
        elif path == '/media/init.bin':
            self.send(200, b'synthetic-init', Content_Type='video/mp4')
        elif path == '/media/segment.bin':
            requested = self.headers.get('Range')
            if requested == 'bytes=10-19':
                self.send(206, PAYLOAD[10:20], Content_Type='video/mp2t', Content_Range='bytes 10-19/1024')
            elif requested is not None:
                self.send(416, Content_Range='bytes */1024')
            else:
                self.send(200, PAYLOAD, Content_Type='video/mp2t')
        elif path == '/api/streams/live/contract/720p/mpegts':
            self.close_connection = True
            self.send_response(200)
            self.send_header('Content-Type', 'video/mp2t')
            self.send_header('Transfer-Encoding', 'chunked')
            self.send_header('Connection', 'close')
            self.end_headers()
            with state.lock:
                state.streams[self.connection] = threading.current_thread()
            try:
                # 無期限の接続は試験自身が必ず取消す。上限は異常時の安全弁で成功条件ではない。
                deadline = time.monotonic() + 30
                block = bytes([0x47]) + bytes(187)
                chunk = block * 128
                while time.monotonic() < deadline:
                    self.wfile.write(('%x\r\n' % len(chunk)).encode() + chunk + b'\r\n')
                    self.wfile.flush()
                    time.sleep(0.01)
                self.wfile.write(b'0\r\n\r\n')
            except (BrokenPipeError, ConnectionResetError, OSError):
                with state.lock:
                    state.cancelled += 1
            finally:
                with state.lock:
                    state.streams.pop(self.connection, None)
        else:
            self.send(404)


def run_owned(command, log, timeout):
    # 保存した専用プロセス群だけを停止し、タイムアウトでもコンパイラ等の子を残さない。
    with log.open('wb') as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result = process.wait(timeout=timeout)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
    return result


def assert_free(port):
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', port)) == 0:
            raise AssertionError('Owned port remains occupied')
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(('127.0.0.1', port))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/relay-contracts')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        raise SystemExit('This test requires macOS Network.framework; no production source is rewritten.')
    args.output.mkdir(parents=True, exist_ok=True)
    executable = args.output.resolve() / 'relay-contract-tests'
    source = ROOT / 'KonomiTV-Viewer/KonomiTV-Viewer'
    compile_result = run_owned(['swiftc', '-swift-version', '5', '-parse-as-library',
                               str(source / 'StreamRelayServer.swift'), str(source / 'TSID3Extractor.swift'),
                               'scripts/relay-test-stubs.swift', 'scripts/RelayContractTests.swift', '-o', str(executable)],
                              args.output / 'compile.log', 120)
    if compile_result:
        print((args.output / 'compile.log').read_text())
        raise SystemExit(compile_result)
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.contract_state = State()
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    result = 1
    try:
        result = run_owned([str(executable), 'http://127.0.0.1:%d' % port], args.output / 'test.log', 60)
        print((args.output / 'test.log').read_text())
    finally:
        server.shutdown()
        with server.contract_state.lock:
            active = list(server.contract_state.streams.items())
        for connection, _ in active:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        server.server_close()
        thread.join(timeout=5)
        for _, stream_thread in active:
            stream_thread.join(timeout=5)
            if stream_thread.is_alive():
                raise AssertionError('Owned fixture stream thread did not exit')
        if thread.is_alive():
            raise AssertionError('Owned fixture listener thread did not exit')
        assert_free(port)
        text = (args.output / 'test.log').read_text() if (args.output / 'test.log').exists() else ''
        for relay_port in re.findall(r'RELAY_PORT=(\d+)', text):
            assert_free(int(relay_port))
        with server.contract_state.lock:
            requests = list(server.contract_state.requests)
        (args.output / 'requests.json').write_text(json.dumps(requests, indent=2) + '\n')
        (args.output / 'cleanup.json').write_text(json.dumps({'fixture_thread_exited': True, 'fixture_port_free': True,
                                                            'relay_ports_free': True, 'subprocess_exited': True}, indent=2) + '\n')
    raise SystemExit(result)


if __name__ == '__main__':
    main()
