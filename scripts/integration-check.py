#!/usr/bin/env python3
"""Loopback-only checks: temporary SSH keys/daemons, HTTP/SOCKS proxies, tunnels and Zmodem."""
import contextlib
import getpass
import json
import os
from pathlib import Path
import select
import pty
import sys
import shlex
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
TEST_APP = Path(os.environ.get('MYTERM_TEST_APP', str(ROOT / 'dist/MyTerm.app')))
CHECKS = ROOT / '.build/arm64-apple-macosx/debug/MyTermChecks'
if not CHECKS.exists():
    candidates = list((ROOT / '.build').glob('*/debug/MyTermChecks'))
    CHECKS = candidates[0]

def run(args, **kwargs):
    return subprocess.check_output(args, timeout=30, **kwargs)

def console_escape_check(root, arguments, wrapped):
    helper = root / 'console-escape.py'
    helper.write_text("import os, tty\ntty.setraw(0)\nos.write(1,b'CONSOLE_READY')\ndata=b''\nwhile len(data)<3: data+=os.read(0,3-len(data))\nos.write(1,b'RECEIVED:'+data.hex().encode())\nassert data==b'~.\\r', data\nassert os.read(0,1)==b'q'\nos.write(1,b'CONSOLE_DONE')\n")
    command = ['/usr/bin/ssh', '-o', 'ControlMaster=no', '-o', 'ControlPath=none', '-o', 'ClearAllForwardings=yes'] + arguments + [shlex.join([sys.executable, str(helper)])]
    if wrapped:
        command = [str(ROOT / 'dist/MyTerm.app/Contents/MacOS/trzsz'), '--dragfile'] + command
    master, slave = pty.openpty()
    process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    output = bytearray()
    def expect(marker):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if marker in output: return
            if select.select([master], [], [], .05)[0]:
                try: output.extend(os.read(master, 65536))
                except OSError: break
        raise AssertionError('Console escape check failed: ' + output.decode(errors='replace'))
    try:
        expect(b'CONSOLE_READY')
        # First input after login: OpenSSH treats this as the start of a line.
        os.write(master, b'~.\r')
        expect(b'RECEIVED:7e2e0d')
        assert process.poll() is None, 'Outer SSH disconnected'
        os.write(master, b'q')
        expect(b'CONSOLE_DONE')
        assert process.wait(timeout=10) == 0
        print('PASS: console ~. reaches remote unchanged; SSH stays alive (' + ('trzsz' if wrapped else 'direct') + ')', flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
        os.close(master)

def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]

def exact(sock, n):
    result = b''
    while len(result) < n:
        chunk = sock.recv(n - len(result))
        if not chunk:
            raise EOFError('short proxy request')
        result += chunk
    return result

def pump(a, b):
    while True:
        ready, _, _ = select.select([a, b], [], [], 20)
        if not ready:
            return
        for source in ready:
            data = source.recv(65536)
            if not data:
                return
            (b if source is a else a).sendall(data)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        while data := self.request.recv(65536):
            self.request.sendall(data)

class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            self.request.settimeout(15)
            if self.server.kind == 'http':
                data = b''
                while b'\r\n\r\n' not in data:
                    data += exact(self.request, 1)
                    assert len(data) < 8192
                method, address, _ = data.split(b'\r\n', 1)[0].split()
                assert method == b'CONNECT'
                host, port = address.decode().rsplit(':', 1)
            else:
                version, count = exact(self.request, 2)
                assert version == 5 and 0 in exact(self.request, count)
                self.request.sendall(b'\x05\x00')
                version, command, _, kind = exact(self.request, 4)
                assert version == 5 and command == 1
                if kind == 1:
                    host = socket.inet_ntoa(exact(self.request, 4))
                elif kind == 3:
                    host = exact(self.request, exact(self.request, 1)[0]).decode()
                else:
                    raise AssertionError('unexpected address type')
                port = int.from_bytes(exact(self.request, 2), 'big')
            assert host in ('127.0.0.1', 'localhost'), host
            with socket.create_connection((host, int(port)), timeout=5) as upstream:
                if self.server.kind == 'http':
                    self.request.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n')
                else:
                    self.request.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00')
                self.server.connections += 1
                pump(self.request, upstream)
        except (OSError, EOFError):
            pass

@contextlib.contextmanager
def service(handler, kind=None):
    server = Server(('127.0.0.1', 0), handler)
    server.kind, server.connections = kind, 0
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()

def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)

def echo_check(port, target=None):
    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        sock.settimeout(5)
        if target:
            sock.sendall(b'\x05\x01\x00')
            assert exact(sock, 2) == b'\x05\x00'
            sock.sendall(b'\x05\x01\x00\x01\x7f\x00\x00\x01' + target.to_bytes(2, 'big'))
            reply = exact(sock, 4)
            assert reply[1] == 0
            exact(sock, 6 if reply[3] == 1 else 18)
        payload = b'MyTerm tunnel ' + os.urandom(128)
        sock.sendall(payload)
        assert exact(sock, len(payload)) == payload

def ssh_checks(root):
    key, hostkey = root / 'key', root / 'hostkey'
    for path in (key, hostkey):
        run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(path)])
    ports = [free_port(), free_port(), free_port()]
    known = root / 'known_hosts'
    known.write_text(''.join(f'[127.0.0.1]:{port} {hostkey.with_suffix(".pub").read_text()}' for port in ports))
    processes, logs = [], []
    try:
        for i, port in enumerate(ports):
            config = root / f'sshd-{i}'
            config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {hostkey}
PidFile {root}/pid-{i}
AuthorizedKeysFile {key}.pub
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
UseDNS no
AllowTcpForwarding yes
PermitRootLogin yes
LogLevel ERROR
Subsystem sftp /usr/libexec/sftp-server
''')
            log = open(root / f'sshd-{i}.log', 'wb'); logs.append(log)
            process = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], stderr=log, stdout=subprocess.DEVNULL)
            processes.append(process)
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError((root / f'sshd-{i}.log').read_text())
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                except OSError: time.sleep(.05)
            else: raise RuntimeError('sshd did not start')
        fixture = root / 'ssh_config'
        fixture.write_text(f'''Host jump
  HostName 127.0.0.1
  Port {ports[1]}
Host *
  User {getpass.getuser()}
  IdentityFile {key}
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  UserKnownHostsFile {known}
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  LogLevel ERROR
''')
        (root / 'network-source').write_bytes(os.urandom(90000))
        with service(Echo) as echo, service(Proxy, 'http') as http, service(Proxy, 'socks5') as socks:
            echo_port = echo.server_address[1]
            for mode in ('direct', 'http', 'socks5', 'jump', 'http+jump', 'socks5+jump', 'http+inherited',
                         'detailed', 'multi', 'http+multi', 'socks5+multi'):
                local_port, remote_port, dynamic_port = free_port(), free_port(), free_port()
                data = dict(id=str(uuid.uuid4()), name=mode, host='127.0.0.1', user=getpass.getuser(),
                            port=str(ports[0]), identityFile=str(key), compression=True, authentication='key')
                data['forwards'] = [dict(id=str(uuid.uuid4()), kind=kind, bindAddress='127.0.0.1', listenPort=str(port),
                    destinationHost='127.0.0.1', destinationPort=str(echo_port)) for kind, port in
                    [('local', local_port), ('remote', remote_port), ('dynamic', dynamic_port)]]
                if 'jump' in mode: data['jumpHost'] = 'jump'
                if mode == 'detailed' or 'multi' in mode:
                    data['jumpServers'] = [dict(id=str(uuid.uuid4()), host='127.0.0.1', port=str(port),
                        user=getpass.getuser(), identityFile=str(key), authentication='key')
                        for port in (ports[1:] if 'multi' in mode else ports[1:2])]
                active_fixture = fixture
                if 'inherited' in mode:
                    active_fixture = root / 'inherited_config'
                    active_fixture.write_text('Host 127.0.0.1\n  ProxyJump jump\n' + fixture.read_text())
                proxy = http if 'http' in mode else socks if 'socks5' in mode else None
                if proxy:
                    data['proxy'] = dict(kind=proxy.kind, host='127.0.0.1', port=str(proxy.server_address[1]))
                before = proxy.connections if proxy else 0
                profile = root / 'server.json'; profile.write_text(json.dumps(data))
                control, generated = root / 'control', root / 'generated_config'
                launch = json.loads(run([str(CHECKS), '--ssh-args', str(profile), str(active_fixture), str(control), str(generated)]))
                if launch['config']: generated.write_text(launch['config'])
                profile.write_text(launch['server'])
                logpath = root / 'master.log'
                with open(logpath, 'wb') as log:
                    ssh_command = ['/usr/bin/ssh', '-N'] + launch['arguments']
                    if os.environ.get('MYTERM_TRZSZ_CHECK') == '1':
                        ssh_command = [str(ROOT / 'dist/MyTerm.app/Contents/MacOS/trzsz'), '--dragfile'] + ssh_command
                    master = subprocess.Popen(ssh_command, stdin=subprocess.PIPE if os.environ.get('MYTERM_TRZSZ_CHECK') == '1' else subprocess.DEVNULL, stdout=log, stderr=log)
                    try:
                        for _ in range(200):
                            if master.poll() is not None: raise RuntimeError(f'{mode}: {logpath.read_text()}\nSSHD: {(root / "sshd-0.log").read_text()[-10000:]}')
                            if control.exists(): break
                            time.sleep(.05)
                        else: raise RuntimeError(f'{mode}: master timeout: {logpath.read_text()}')
                        echo_check(local_port)
                        echo_check(remote_port)
                        echo_check(dynamic_port, echo_port)
                        output = run([str(CHECKS), '--sftp-ssh', str(profile), launch['configPath'], str(control), str(root)])
                        assert b'PASS' in output
                        if proxy: assert proxy.connections > before, 'proxy was bypassed'
                        print(f'PASS: {mode}: SSH, compression, L/R/D forwarding, multiplexed SFTP', flush=True)
                        if mode == 'direct':
                            console_escape_check(root, launch['arguments'], False)
                            if (ROOT / 'dist/MyTerm.app/Contents/MacOS/trzsz').is_file():
                                console_escape_check(root, launch['arguments'], True)
                        if mode == 'direct' and os.environ.get('MYTERM_TMUX_CHECK') == '1':
                            tmux = shutil.which('tmux')
                            assert tmux, 'tmux is required'
                            tmux_socket = str(root / 'tmux.sock')
                            command = shlex.join(['/usr/bin/env', 'LANG=en_US.UTF-8', 'LC_ALL=en_US.UTF-8', 'BASH_SILENCE_DEPRECATION_WARNING=1', tmux, '-u', '-S', tmux_socket, '-f', '/dev/null', 'new-session', '-s', 'check', '/bin/bash', '--noprofile', '--norc'])
                            args = ['-o', 'ControlMaster=no', '-o', 'ClearAllForwardings=yes'] + launch['arguments'] + [command]
                            tmux_fixture = root / 'tmux-fixture.json'
                            tmux_fixture.write_text(json.dumps(dict(arguments=args, socket=tmux_socket, tmux=tmux)))
                            try:
                                output = subprocess.check_output([str(TEST_APP / 'Contents/MacOS/MyTerm'), '--smoke-test', '--tmux-check', str(tmux_fixture)], timeout=55, stderr=subprocess.STDOUT)
                                print(output.decode(), end='', flush=True)
                            except subprocess.CalledProcessError as error:
                                raise RuntimeError(error.output.decode()) from error
                            finally:
                                subprocess.run([tmux, '-S', tmux_socket, 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
                    finally:
                        stop(master)
                        if control.exists(): control.unlink()
    finally:
        for process in processes: stop(process)
        for log in logs: log.close()

def zmodem_check(root):
    sender = shutil.which('lsz') or shutil.which('sz')
    receiver = shutil.which('lrz') or shutil.which('rz')
    assert sender and receiver, 'lrzsz is required for Zmodem checks'
    source_dir, target_dir = root / 'zsend', root / 'zreceive'
    source_dir.mkdir(); target_dir.mkdir()
    source = source_dir / 'binary.bin'; source.write_bytes(os.urandom(180000))
    # Two unmodified lrzsz helpers exchange protocol over pipes, as the app's bridge does.
    with open(root / 'zmodem.log', 'wb') as log:
        recv = subprocess.Popen([receiver, '--binary', '--escape', '--restricted', '--protect'],
            cwd=target_dir, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
        send = subprocess.Popen([sender, '--binary', '--escape', '--resume', '--', str(source)],
            cwd=source_dir, stdin=recv.stdout, stdout=recv.stdin, stderr=log)
        recv.stdout.close(); recv.stdin.close()
        try:
            assert send.wait(timeout=25) == 0, (root / 'zmodem.log').read_text()
            assert recv.wait(timeout=25) == 0, (root / 'zmodem.log').read_text()
            assert (target_dir / source.name).read_bytes() == source.read_bytes()
            print('PASS: Zmodem binary transfer using production helper options', flush=True)
        finally:
            stop(send); stop(recv)

with tempfile.TemporaryDirectory(prefix='myterm-check-', dir='/tmp') as name:
    root = Path(name)
    ssh_checks(root)
    zmodem_check(root)
print('All loopback integration checks passed.', flush=True)
