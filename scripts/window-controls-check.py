#!/usr/bin/env python3
"""Run UI behavior checks in either the Debug or Release application bundle."""
import os
import pathlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
# The bilingual layout, native-menu and real-transfer suites have individual
# bounded waits. Leave headroom for their cumulative duration on a busy desktop.
try:
    result = subprocess.run([str(app / 'Contents/MacOS/MyTerm'), '--smoke-test', '--window-controls-check'],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
except subprocess.TimeoutExpired as error:
    captured = error.stdout or b""
    print(captured.decode(errors="replace") if isinstance(captured, bytes) else captured, end="", flush=True)
    raise
print(result.stdout, end='')
if result.returncode or 'PASS: window controls:' not in result.stdout:
    raise SystemExit(result.returncode or 1)

login = subprocess.run([str(app / 'Contents/MacOS/MyTerm'), '--smoke-test', '--codex-login-check'],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
print(login.stdout, end='')
if login.returncode or 'PASS: Codex real PTY' not in login.stdout:
    raise SystemExit(login.returncode or 1)

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('codex-launch-check.py')), str(app)], check=True)

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("jump-probe-check.py")), str(app)], check=True)

password_python = pathlib.Path(os.environ.get("MYTERM_PASSWORD_TEST_PYTHON", str(pathlib.Path(__file__).resolve().parents[1] / ".test-venv/bin/python")))
if not password_python.is_file():
    raise SystemExit("Create .test-venv with scripts/requirements-password-test.txt, or set MYTERM_PASSWORD_TEST_PYTHON")
subprocess.run([str(password_python), str(pathlib.Path(__file__).with_name("jump-password-probe-check.py")), str(app)], check=True)
