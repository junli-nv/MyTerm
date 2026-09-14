#!/usr/bin/env python3
"""Exercise production execution against an isolated loopback SSH server. No user SSH configuration or credentials are used."""
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import time

checks = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='myterm-exec-', dir='/tmp') as directory:
    root = pathlib.Path(directory)
    subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root / 'key')], check=True)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    (root / 'config').write_text(f'Port {port}\nListenAddress 127.0.0.1\nHostKey {root}/key\nPidFile {root}/pid\nAuthorizedKeysFile {root}/key.pub\nStrictModes no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nUsePAM no\n')
    server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(root / 'config')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    master = None
    try:
        time.sleep(0.3)
        assert server.poll() is None, 'Fixture sshd failed'
        master = subprocess.Popen(['/usr/bin/ssh', '-F', '/dev/null', '-M', '-N', '-S', str(root / 'control'), '-i', str(root / 'key'), '-p', str(port), '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'BatchMode=yes', '127.0.0.1'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 5
        while not (root / 'control').exists() and master.poll() is None and time.monotonic() < deadline:
            time.sleep(0.05)
        assert (root / 'control').exists(), 'Fixture multiplexed connection failed'
        result = json.loads(subprocess.check_output([str(checks), '--codex-execution-fixture', str(root / 'control')], text=True, timeout=10))
        assert result['state'] == 'completed' and result['exit_code'] == 7, result
        assert 'mux-execution-fixture\n' in result['output'] and 'stderr-fixture\n' in result['output'], result
        assert master.poll() is None, 'Execution terminated the parent SSH connection'
        print('PASS: production SSH execution over real loopback mux, stdout/stderr, exit code, parent transport preserved')
    finally:
        for process in (master, server):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
