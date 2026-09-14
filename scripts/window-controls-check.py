#!/usr/bin/env python3
"""Run UI behavior checks in either the Debug or Release application bundle."""
import pathlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
result = subprocess.run([str(app / 'Contents/MacOS/MyTerm'), '--smoke-test', '--window-controls-check'],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
print(result.stdout, end='')
if result.returncode or 'PASS: window controls:' not in result.stdout:
    raise SystemExit(result.returncode or 1)

login = subprocess.run([str(app / 'Contents/MacOS/MyTerm'), '--smoke-test', '--codex-login-check'],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
print(login.stdout, end='')
if login.returncode or 'PASS: Codex real PTY' not in login.stdout:
    raise SystemExit(login.returncode or 1)

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('codex-launch-check.py')), str(app)], check=True)
