#!/usr/bin/env python3
"""Temporary password-only SSH server; never reads or changes any real user's password."""
import socket
import subprocess
import tempfile
import threading
from pathlib import Path
import paramiko

root = Path(__file__).resolve().parents[1]
key = paramiko.RSAKey.generate(2048)
class Server(paramiko.ServerInterface):
    def __init__(self, password):
        self.password = password
        self.command = threading.Event()
    def get_allowed_auths(self, username):
        return 'password'
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if username == 'fixture' and password == self.password else paramiko.AUTH_FAILED
    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
    def check_channel_exec_request(self, channel, command):
        self.command.set()
        return True

with tempfile.TemporaryDirectory(prefix='myterm-password-', dir='/tmp') as directory, socket.socket() as listener:
    listener.bind(('127.0.0.1', 0)); listener.listen(4); listener.settimeout(30)
    port = listener.getsockname()[1]
    known = Path(directory) / 'known_hosts'
    known.write_text(f'[127.0.0.1]:{port} {key.get_name()} {key.get_base64()}\n')
    failures = []
    def serve():
        try:
            for phase in range(4):
                client, _ = listener.accept()
                with paramiko.Transport(client) as transport:
                    transport.add_server_key(key)
                    server = Server('fixture-before' if phase < 2 else 'fixture-after')
                    transport.start_server(server=server)
                    channel = transport.accept(20)
                    assert channel and server.command.wait(20)
                    channel.sendall(b'fixture-ok\n')
                    channel.send_exit_status(0); channel.shutdown_write()
                    channel.close()
        except Exception as error:
            failures.append(error)
    worker = threading.Thread(target=serve, daemon=True); worker.start()
    checks = next((root / '.build').glob('*/debug/MyTermChecks'))
    subprocess.run([str(checks), '--password-integration', str(port), str(known), str(root / 'dist/MyTerm.app/Contents/MacOS/MyTerm')], check=True, timeout=90)
    worker.join(3)
    if failures: raise failures[0]
