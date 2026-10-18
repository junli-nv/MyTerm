#!/usr/bin/env python3
"""Password-only SSH with no session/exec support, using synthetic secrets on loopback."""
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import paramiko

binary = pathlib.Path(sys.argv[1]).resolve() / 'Contents/MacOS/MyTerm'
key = paramiko.RSAKey.generate(2048)
accepted = []
channels = []
failures = []

class NoShellServer(paramiko.ServerInterface):
    def get_allowed_auths(self, username):
        return 'password'
    def check_auth_password(self, username, password):
        valid = username == 'Administrator' and password == 'synthetic-jump-password'
        accepted.append(valid)
        return paramiko.AUTH_SUCCESSFUL if valid else paramiko.AUTH_FAILED
    def check_channel_request(self, kind, chanid):
        channels.append(kind)
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

with tempfile.TemporaryDirectory(prefix='myterm-no-shell-', dir='/tmp') as directory, socket.socket() as listener:
    root = pathlib.Path(directory)
    listener.bind(('127.0.0.1', 0)); listener.listen(4); listener.settimeout(20)
    port = listener.getsockname()[1]
    def serve():
        try:
            for _ in range(2):
                client, _ = listener.accept()
                with paramiko.Transport(client) as transport:
                    transport.add_server_key(key)
                    transport.start_server(server=NoShellServer())
                    deadline = time.monotonic() + 20
                    while transport.is_active() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    assert not transport.is_active(), 'Probe left an authenticated connection running'
        except Exception as error:
            failures.append(error)
    worker = threading.Thread(target=serve, daemon=True); worker.start()
    config = root / 'client'
    config.write_text('Host *\n StrictHostKeyChecking no\n UserKnownHostsFile /dev/null\n GlobalKnownHostsFile /dev/null\n IdentityAgent none\n')
    profile_id = str(uuid.uuid4())
    profile = dict(id=profile_id, profileID=profile_id, host='127.0.0.1', user='Administrator', port=str(port), identityFile='', authentication='password')
    for i, password in enumerate(['synthetic-jump-password', 'synthetic-wrong-password']):
        fixture = root / f'fixture-{i}.json'
        fixture.write_text(json.dumps(dict(profile=profile, configPath=str(config), credentials=str(root/'credentials'), password=password, expectSuccess=i == 0, cancel=False)))
        subprocess.run([str(binary), '--smoke-test', '--jump-probe-check', str(fixture)], check=True, timeout=20)
    worker.join(5)
    assert not worker.is_alive(), 'Probe connection was not closed'
    if failures: raise failures[0]
    assert sum(accepted) == 1 and False in accepted, 'Cached-password authentication was not exercised'
    assert not channels, f'Probe requested remote channels: {channels}'
    print('PASS: saved-password reuse, wrong-password rejection, zero remote shell/exec channels, connection cleanup')
