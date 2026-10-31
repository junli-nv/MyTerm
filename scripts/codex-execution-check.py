#!/usr/bin/env python3
"""Exercise production execution against an isolated loopback SSH server. No user SSH configuration or credentials are used."""
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import threading

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
        assert "one\ntwo\n$HOME 'quotes' 中文\n" in result['output'], result
        assert master.poll() is None, 'Execution terminated the parent SSH connection'
        def free_port():
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                return sock.getsockname()[1]

        def control(operation, kind, listen, target, success=True):
            response = subprocess.run([str(checks), '--forward-fixture', str(root / 'control'),
                operation, kind, str(listen), str(target)], capture_output=True, text=True, timeout=9)
            assert (response.returncode == 0) == success, (operation, kind, response.stdout, response.stderr)

        def receive(stream, count):
            data = b''
            while len(data) < count:
                chunk = stream.recv(count - len(data))
                assert chunk, 'Premature socket EOF'
                data += chunk
            return data

        # A real echo service proves traffic, not merely successful control requests.
        with socket.socket() as echo:
            echo.bind(('127.0.0.1', 0)); echo.listen(); echo.settimeout(0.2)
            target = echo.getsockname()[1]
            stop = threading.Event()
            def serve():
                while not stop.is_set():
                    try:
                        conn, _ = echo.accept()
                    except socket.timeout:
                        continue
                    with conn:
                        conn.settimeout(2)
                        try:
                            data = conn.recv(100)
                            if data: conn.sendall(data)
                        except OSError:
                            pass
            worker = threading.Thread(target=serve, daemon=True); worker.start()
            try:
                for kind in ('local', 'remote', 'dynamic'):
                    listen = free_port()
                    for _ in range(2):
                        control('forward', kind, listen, target)
                        with socket.create_connection(('127.0.0.1', listen), timeout=2) as stream:
                            if kind == 'dynamic':
                                stream.sendall(b'\x05\x01\x00')
                                assert receive(stream, 2) == b'\x05\x00'
                                stream.sendall(b'\x05\x01\x00\x01\x7f\x00\x00\x01' + target.to_bytes(2, 'big'))
                                reply = receive(stream, 10)
                                assert len(reply) == 10 and reply[1] == 0, reply
                            stream.sendall(b'forward-fixture')
                            assert receive(stream, len(b'forward-fixture')) == b'forward-fixture'
                        control('cancel', kind, listen, target)
                        try:
                            unexpected = socket.create_connection(('127.0.0.1', listen), timeout=0.3)
                        except OSError:
                            pass
                        else:
                            unexpected.close(); raise AssertionError('Cancelled listener remained open')
                    assert master.poll() is None
                with socket.socket() as occupied:
                    occupied.bind(('127.0.0.1', 0)); occupied.listen()
                    control('forward', 'local', occupied.getsockname()[1], target, success=False)
                    assert master.poll() is None, 'Forward failure killed SSH'
                control('check', 'local', 8080, target)
            finally:
                stop.set(); worker.join(timeout=3)
        print('PASS: production local/remote/SOCKS forwarding traffic, cancel/re-enable, occupied port and preserved SSH')
        print('PASS: production SSH execution over real loopback mux, multiline loop/heredoc/Unicode, stdout/stderr, exit code, parent transport preserved')
    finally:
        for process in (master, server):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
