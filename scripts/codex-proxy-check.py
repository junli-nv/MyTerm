#!/usr/bin/env python3
"""Verify the installed Codex CLI routes synthetic requests through HTTP/SOCKS.
No real API key, model endpoint, SSH session, user config, or saved thread is used.
"""
import os
import base64
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time

codex = shutil.which('codex')
assert codex, 'Codex CLI is required for this integration check'

for scheme in ('http', 'socks5h'):
    with socket.socket() as listener, tempfile.TemporaryDirectory(prefix='myterm-codex-proxy-') as work:
        listener.bind(('127.0.0.1', 0)); listener.listen(); listener.settimeout(.2)
        port = listener.getsockname()[1]
        seen = []; stop = threading.Event()
        def exact(client, length):
            data = b''
            while len(data) < length:
                part = client.recv(length - len(data))
                if not part: raise OSError('closed')
                data += part
            return data
        def serve():
            while not stop.is_set():
                try:
                    client, _ = listener.accept()
                except socket.timeout:
                    continue
                with client:
                    client.settimeout(2)
                    try:
                        first = client.recv(4096) if scheme == 'http' else exact(client, 3)
                        if scheme == 'http':
                            if first.startswith(b'CONNECT myterm-proxy-fixture.invalid:443 '):
                                assert b'proxy-authorization: basic ' + base64.b64encode(b'fixture:synthetic-proxy-password').lower() in first.lower()
                                seen.append(True)
                            client.sendall(b'HTTP/1.1 502 Fixture proxy refusal\r\nContent-Length: 0\r\n\r\n')
                        else:
                            assert first == b'\x05\x01\x02'
                            client.sendall(b'\x05\x02')
                            auth = exact(client, 2); assert auth[0] == 1
                            assert exact(client, auth[1]) == b'fixture'
                            assert exact(client, exact(client, 1)[0]) == b'synthetic-proxy-password'
                            client.sendall(b'\x01\x00')
                            connect = exact(client, 5); assert connect[:4] == b'\x05\x01\x00\x03'
                            target = exact(client, connect[4]); assert exact(client, 2) == b'\x01\xbb'
                            client.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x01')
                            if target == b'echo.invalid':
                                payload = exact(client, 32768)
                                client.sendall(payload)
                            elif target == b'myterm-proxy-fixture.invalid':
                                assert exact(client, 2) == b'\x16\x03'
                                seen.append(True)
                    except OSError:
                        pass
        worker = threading.Thread(target=serve, daemon=True); worker.start()
        environment = dict(os.environ)
        keys = ('http_proxy', 'https_proxy', 'all_proxy', 'ws_proxy', 'wss_proxy', 'no_proxy')
        environment = {k: v for k, v in environment.items() if k.lower() not in keys}
        for key in keys[:-1]:
            environment[key] = environment[key.upper()] = f'{scheme}://fixture:synthetic-proxy-password@127.0.0.1:{port}'
        environment['NO_PROXY'] = environment['no_proxy'] = 'localhost,127.0.0.1,::1'
        environment['MYTERM_PROXY_FIXTURE_KEY'] = 'synthetic-not-a-real-api-key'
        relay = None
        if scheme == 'socks5h':
            checks = next((Path(__file__).resolve().parents[1] / '.build').glob('*/' + os.environ.get('MYTERM_TEST_CONFIGURATION', 'debug') + '/MyTermChecks'))
            relay = subprocess.Popen([str(checks), '--codex-socks-proxy', str(port)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            import json, urllib.parse, base64
            proxy_environment = json.loads(relay.stdout.readline())
            environment.update(proxy_environment)
            endpoint = urllib.parse.urlparse(proxy_environment['HTTPS_PROXY'])
            with socket.create_connection((endpoint.hostname, endpoint.port), timeout=4) as probe:
                probe.sendall(b'CONNECT echo.invalid:443 HTTP/1.1\r\nHost: echo.invalid\r\n\r\n')
                assert b'407' in probe.recv(4096), 'Unauthenticated local proxy request was accepted'
            authorization = base64.b64encode((urllib.parse.unquote(endpoint.username) + ':' + urllib.parse.unquote(endpoint.password)).encode())
            with socket.create_connection((endpoint.hostname, endpoint.port), timeout=4) as probe:
                probe.sendall(b'CONNECT echo.invalid:443 HTTP/1.1\r\nProxy-Authorization: Basic ' + authorization + b'\r\n\r\n')
                header = b''
                while b'\r\n\r\n' not in header: header += probe.recv(1)
                assert b'200' in header
                payload = bytes(range(256)) * 128
                probe.sendall(payload); assert exact(probe, len(payload)) == payload
            print('PASS: authenticated local HTTP-to-SOCKS5 relay, upstream authentication, DNS forwarding and binary round trip')
        # SSH's existing proxy helper must use its explicit endpoint even while
        # a separate Codex proxy is running and its environment is present.
        with socket.socket() as ssh_listener:
            ssh_listener.bind(('127.0.0.1', 0)); ssh_listener.listen(); ssh_listener.settimeout(4)
            ssh_seen = []
            def ssh_proxy():
                client, _ = ssh_listener.accept()
                with client:
                    client.settimeout(4); header = b''
                    while b'\r\n\r\n' not in header: header += client.recv(1)
                    assert header.startswith(b'CONNECT ssh-fixture.invalid:22 ')
                    ssh_seen.append(True)
                    client.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
                    assert exact(client, 18) == b'SSH_PROXY_FIXTURE!'
                    client.sendall(b'SSH_PROXY_OK')
            ssh_worker = threading.Thread(target=ssh_proxy, daemon=True); ssh_worker.start()
            helper = next((Path(__file__).resolve().parents[1] / '.build').glob('*/' + os.environ.get('MYTERM_TEST_CONFIGURATION', 'debug') + '/MyTermProxy'))
            result = subprocess.run([str(helper), 'http', '127.0.0.1', str(ssh_listener.getsockname()[1]), 'ssh-fixture.invalid', '22'],
                                    input=b'SSH_PROXY_FIXTURE!', stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=environment, timeout=5)
            ssh_worker.join(4)
            assert result.returncode == 0 and result.stdout == b'SSH_PROXY_OK' and ssh_seen
            print('PASS: SSH proxy stays on its own endpoint independently of Codex proxy/environment')
        args = [codex, 'exec', '--ignore-user-config', '--ephemeral', '--skip-git-repo-check', '--sandbox', 'read-only', '--json']
        settings = {
            'model_provider': 'myterm_fixture', 'model': 'myterm-fixture',
            'model_providers.myterm_fixture.name': 'MyTerm fixture',
            'model_providers.myterm_fixture.base_url': 'https://myterm-proxy-fixture.invalid/v1',
            'model_providers.myterm_fixture.env_key': 'MYTERM_PROXY_FIXTURE_KEY',
            'model_providers.myterm_fixture.wire_api': 'responses',
        }
        import json
        for key, value in settings.items(): args += ['-c', key + '=' + json.dumps(value)]
        args += ['-c', 'model_providers.myterm_fixture.request_max_retries=0', '-c', 'model_providers.myterm_fixture.stream_max_retries=0', 'Reply ok.']
        proc = subprocess.Popen(args, cwd=work, env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 20
        while proc.poll() is None and not seen and time.monotonic() < deadline: time.sleep(.1)
        if proc.poll() is None: proc.terminate()
        try: proc.wait(timeout=4)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()
        if relay:
            relay.stdin.close(); relay.wait(timeout=5)
        stop.set(); worker.join(3)
        assert seen, f'Codex did not contact the {scheme} fixture proxy'
        print(f'PASS: installed Codex CLI uses {scheme} proxy for synthetic HTTPS endpoint')
