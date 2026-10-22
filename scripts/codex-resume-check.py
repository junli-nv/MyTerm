#!/usr/bin/env python3
"""Resume a synthetic conversation with the real CLI and a fresh MCP association.
Isolated CODEX_HOME, dummy credentials and loopback-only provider; no model calls.
"""
import datetime
import fcntl
import http.server
import json
import os
import pathlib
import pty
import re
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

binary = pathlib.Path(sys.argv[1]).resolve() / "Contents/MacOS/MyTerm"
codex = shutil.which("codex")
assert codex, "Codex CLI required"
with tempfile.TemporaryDirectory(prefix="myterm-resume-fixture-") as directory:
    root = pathlib.Path(directory)
    home = root / "codex-home"
    home.mkdir()
    trace = root / "mcp.jsonl"
    helper = root / "fixture-mcp"
    helper.write_text("#!" + sys.executable + "\n" + '''import json, os, sys
for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    with open(''' + repr(str(trace)) + ''', "a") as stream:
        stream.write(json.dumps({"method": method, "association": os.environ.get("MYTERM_CODEX_ASSOCIATION")}) + "\\n")
    if "id" not in request: continue
    if method == "initialize":
        result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "fixture", "version": "1"}}
    elif method == "tools/list":
        result = {"tools": [{"name": name, "description": "Synthetic fixture", "inputSchema": {"type": "object", "properties": {}}} for name in ["list_sessions", "read_output", "capture_history", "read_history_page", "execute_command", "command_status", "cancel_command"]]}
    else: result = {}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
''')
    helper.chmod(0o700)
    thread = str(uuid.uuid4())
    timestamp = datetime.datetime.now(datetime.timezone.utc)
    stamp = timestamp.isoformat().replace("+00:00", "Z")
    sessions = home / "sessions" / timestamp.strftime("%Y/%m/%d")
    sessions.mkdir(parents=True)
    rollout = sessions / ("rollout-" + timestamp.strftime("%Y-%m-%dT%H-%M-%S") + "-" + thread + ".jsonl")
    records = [
        {"timestamp": stamp, "type": "session_meta", "payload": {"id": thread, "timestamp": stamp, "cwd": str(root), "originator": "codex_cli_rs", "cli_version": "0.162.1", "source": "cli", "model_provider": "fixture"}},
        {"timestamp": stamp, "type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Synthetic completed discussion. Do not run commands."}]}},
        {"timestamp": stamp, "type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Synthetic discussion completed."}]}},
    ]
    records.extend([
        {"timestamp": stamp, "type": "event_msg", "payload": {"type": "user_message", "message": "Synthetic completed discussion. Do not run commands.", "images": [], "local_images": []}},
        {"timestamp": stamp, "type": "event_msg", "payload": {"type": "agent_message", "message": "Synthetic discussion completed."}},
    ])
    rollout.write_text("".join(json.dumps(item) + "\n" for item in records))
    requests = []
    class Provider(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_GET(self):
            requests.append(("GET", self.path))
            self.send_response(200); self.end_headers(); self.wfile.write(b'{"data":[]}')
        def do_POST(self):
            requests.append(("POST", self.path))
            self.send_response(503); self.end_headers()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    worker = threading.Thread(target=server.serve_forever, daemon=True); worker.start()
    args = json.loads(subprocess.check_output([str(binary), "--smoke-test", "--codex-launch-arguments", str(helper), "--codex-scoped-check", "--codex-resume"], text=True))
    assert args[-2:] == ["resume", "--all"]
    # Explicit ID exercises the same resume operation after the interactive picker.
    args = args[:-2] + ["-c", 'model_provider="fixture"', "-c", 'model="fixture-model"', "-c",
        'model_providers.fixture={name="fixture",base_url="http://127.0.0.1:' + str(server.server_port) + '/v1",env_key="OPENAI_API_KEY",wire_api="responses"}', "resume", thread]
    env = {key: value for key, value in os.environ.items() if "proxy" not in key.lower()}
    env.update(CODEX_HOME=str(home), OPENAI_API_KEY="synthetic-not-a-key", TERM="xterm-256color", NO_PROXY="127.0.0.1,localhost")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    process = None
    output = bytearray()
    rendered = b""
    history_emitted = False
    try:
        process = subprocess.Popen([codex, *args], stdin=slave, stdout=slave, stderr=slave, cwd=root, env=env, start_new_session=True)
        os.close(slave); slave = -1
        deadline = time.monotonic() + 20
        initialized = False
        while time.monotonic() < deadline and process.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try: chunk = os.read(master, 65536)
                except OSError: break
                output.extend(chunk)
                if b"\x1b[6n" in chunk: os.write(master, b"\x1b[1;1R")
            if trace.exists():
                events = [json.loads(line) for line in trace.read_text().splitlines()]
                if any(event["method"] == "tools/list" for event in events):
                    assert all(event["association"] == "11111111-2222-3333-4444-555555555555" for event in events)
                    initialized = True
            rendered = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", bytes(output))
            # Fullscreen TUI may draw word gaps with cursor positioning rather than
            # literal spaces. Check the unique assistant marker, independent of layout.
            history_emitted = b"Syntheticdiscussioncompleted." in re.sub(rb"\s+", b"", rendered)
            if initialized and history_emitted:
                break
        assert initialized, "Real Codex resume did not initialize the fresh MCP: " + output.decode(errors="replace")[-5000:]
        assert history_emitted, "Saved conversation was not rendered: " + rendered.decode(errors="replace")[-3000:]
        assert not any(method == "POST" for method, _ in requests), "Resume unexpectedly requested inference"
        print("PASS: real Codex resumes synthetic history and initializes MCP with fresh association; no model requests")
    finally:
        if process and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait()
        os.close(master)
        if slave >= 0: os.close(slave)
        server.shutdown(); server.server_close()
