#!/usr/bin/env python3
"""Exercise real jump-probe authentication, routed SSH, failure and cancellation on loopback."""
import getpass
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import uuid

app = pathlib.Path(sys.argv[1]).resolve() / 'Contents/MacOS/MyTerm'
with tempfile.TemporaryDirectory(prefix='myterm-jump-probe-', dir='/tmp') as directory:
    root = pathlib.Path(directory)
    for name in ('key', 'wrong'):
        subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root / name)], check=True)
    servers = []
    ports = []
    try:
        for i in range(2):
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
            ports.append(port)
            config = root / f'sshd-{i}'
            config.write_text(f'Port {port}\nListenAddress 127.0.0.1\nHostKey {root}/key\nPidFile {root}/pid-{i}\nAuthorizedKeysFile {root}/key.pub\nStrictModes no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nUsePAM no\nAllowTcpForwarding yes\n')
            servers.append(subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(0.3)
        assert all(p.poll() is None for p in servers)
        client = root / 'client'
        client.write_text('Host *\n StrictHostKeyChecking no\n UserKnownHostsFile /dev/null\n GlobalKnownHostsFile /dev/null\n IdentitiesOnly yes\n IdentityAgent none\n')
        def hop(port, key='key'):
            identifier = str(uuid.uuid4())
            return dict(id=identifier, profileID=identifier, host='127.0.0.1', port=str(port), user=getpass.getuser(), identityFile=str(root/key), authentication='key')
        first, second = hop(ports[0]), hop(ports[1])
        route = dict(id=str(uuid.uuid4()), name='Loopback route', host='unused.invalid', user='', port='', identityFile='', jumpServers=[first, second])
        cases = [(first, None, None, True, False), (second, route, 1, True, False), (hop(ports[0], 'wrong'), None, None, False, False), (first, None, None, False, True)]
        for index, (profile, via, position, success, cancel) in enumerate(cases):
            fixture = root / f'fixture-{index}.json'
            fixture.write_text(json.dumps(dict(profile=profile, route=via, index=position, configPath=str(client), credentials=str(root/'credentials'), expectSuccess=success, cancel=cancel)))
            subprocess.run([str(app), '--smoke-test', '--jump-probe-check', str(fixture)], check=True, timeout=20)
        print('PASS: real jump probe direct and preceding-hop SSH, wrong-key rejection and cancellation; isolated keys/configuration')
    finally:
        for process in servers:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=3)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=3)
