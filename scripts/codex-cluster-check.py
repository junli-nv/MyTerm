#!/usr/bin/env python3
"""Exercise official thread APIs and native CLI resume in an isolated CODEX_HOME.
No real credentials, user history, SSH connections or model requests.
"""
import fcntl
import http.server
import os
import pathlib
import pty
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import uuid

checks = pathlib.Path(sys.argv[1]).resolve()
codex = shutil.which("codex")
assert codex, "Codex CLI required for cluster integration check"
requests = []
class Provider(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"data":[]}')
    def do_POST(self):
        requests.append(self.path)
        self.send_response(503); self.end_headers()

with tempfile.TemporaryDirectory(prefix="myterm-cluster-check-") as temporary:
    root = pathlib.Path(temporary)
    home = root / "codex-home"; home.mkdir()
    directory = root / "GMI Dallas 集群"; directory.mkdir()
    provider = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    worker = threading.Thread(target=provider.serve_forever, daemon=True); worker.start()
    (home / "config.toml").write_text('model_provider="fixture"\nmodel="fixture-model"\n'
        '[model_providers.fixture]\nname="fixture"\nbase_url="http://127.0.0.1:' + str(provider.server_port) + '/v1"\nenv_key="OPENAI_API_KEY"\nwire_api="responses"\n')
    env = {k: v for k, v in os.environ.items() if "proxy" not in k.lower()}
    env.update(CODEX_HOME=str(home), OPENAI_API_KEY="synthetic-not-a-key", TERM="xterm-256color", NO_PROXY="127.0.0.1,localhost")
    try:
        result = subprocess.run([str(checks), "--codex-cluster-fixture", codex, str(directory)],
                                env=env, capture_output=True, text=True, timeout=60, check=True)
        thread = result.stdout.strip(); uuid.UUID(thread)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        process = None
        try:
            process = subprocess.Popen([codex, "--cd", str(directory), "--sandbox", "read-only", "resume", thread],
                                       stdin=slave, stdout=slave, stderr=slave, env=env, cwd=directory, start_new_session=True)
            os.close(slave); slave = -1
            captured = bytearray(); deadline = time.monotonic() + 12
            while time.monotonic() < deadline and process.poll() is None:
                if select.select([master], [], [], .1)[0]:
                    data = os.read(master, 65536); captured.extend(data)
                    if b'\x1b[6n' in data: os.write(master, b'\x1b[1;1R')
                    if b'\x1b[c' in data: os.write(master, b'\x1b[?1;2c')
                    if b'\x1b[>c' in data: os.write(master, b'\x1b[>0;0;0c')
            text = captured.decode(errors="replace")
            assert process.poll() is None, text[-3000:]
            assert 'Fatal error' not in text and 'Error:' not in text, text[-3000:]
            assert thread in text or 'fixture-model' in text, text[-3000:]
            assert not requests, requests
        finally:
            if process is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
            if slave >= 0: os.close(slave)
            os.close(master)
    finally:
        provider.shutdown(); provider.server_close()
print("PASS: official Codex create/name/read, persisted metadata, rename, cluster isolation and native UUID resume; no model requests")
