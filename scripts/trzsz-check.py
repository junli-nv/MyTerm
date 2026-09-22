#!/usr/bin/env python3
"""Real bundled trzsz over PTYs and tmux; chooser responses are isolated test fixtures."""
import fcntl, os, platform, pathlib, pty, select, shlex, shutil, signal, struct, subprocess, tempfile, termios, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = pathlib.Path(os.environ.get('MYTERM_TEST_APP', str(ROOT / 'dist/MyTerm.app')))
HELPER = APP / 'Contents/MacOS/trzsz'
TOOLS = ROOT / 'vendor/trzsz/1.2.0' / platform.machine()
TMUX = shutil.which('tmux')
assert TMUX and HELPER.exists()
# Do not let test downloads follow a user's configured save directory.
config = pathlib.Path.home() / '.trzsz.conf'
if config.exists() and any(x.strip().lower().startswith('defaultdownloadpath') for x in config.read_text().splitlines()):
    raise RuntimeError('A user trzsz download directory is configured; refusing to write test files there')

class Terminal:
    def __init__(self, command, env, cwd):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 110, 0, 0))
        self.process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=env, cwd=cwd, start_new_session=True)
        os.close(slave)
        self.output = bytearray()
    def send(self, value): os.write(self.master, value.encode() if isinstance(value, str) else value)
    def wait(self, predicate, seconds=20):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if select.select([self.master], [], [], .05)[0]:
                try: self.output.extend(os.read(self.master, 65536))
                except OSError: pass
            if predicate(): return
            if self.process.poll() is not None: break
        # The child can exit between the predicate and poll above.
        if predicate(): return
        raise AssertionError(bytes(self.output[-6000:]).decode(errors='replace'))
    def settle(self):
        deadline = time.monotonic() + 1.5
        self.wait(lambda: time.monotonic() >= deadline)
    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try: self.process.wait(timeout=5)
            except subprocess.TimeoutExpired: self.process.kill(); self.process.wait(timeout=5)
        os.close(self.master)

with tempfile.TemporaryDirectory(prefix='myterm-trzsz-', dir='/tmp') as name:
    root = pathlib.Path(name)
    shim = root / 'bin'; shim.mkdir()
    # Upstream zenity invokes osascript via PATH. Only this child environment uses the stub.
    chooser = shim / 'osascript'
    chooser.write_text('#!/bin/bash\n/bin/cat >/dev/null\n/bin/cat "$MYTERM_TRZSZ_SELECTION"\n')
    chooser.chmod(0o755)
    selection = root / 'selection'
    for tmux in [False, True]:
        source = root / ('source-tmux' if tmux else 'source-plain'); source.mkdir()
        destination = root / ('remote-tmux' if tmux else 'remote-plain'); destination.mkdir()
        downloads = root / ('downloads-tmux' if tmux else 'downloads-plain'); downloads.mkdir()
        upload = source / "中文 file 'quoted'.bin"; upload.write_bytes(os.urandom(200000))
        folder = source / 'folder with spaces'; folder.mkdir(); (folder/'child.bin').write_bytes(os.urandom(80000))
        env = os.environ.copy(); env['PATH'] = str(shim) + ':' + str(TOOLS) + ':' + env['PATH']
        env.update(TERM='xterm-256color', LANG='en_US.UTF-8', BASH_SILENCE_DEPRECATION_WARNING='1', MYTERM_TRZSZ_SELECTION=str(selection))
        for key in ['TMUX', 'TMUX_PANE']: env.pop(key, None)
        socket = root / ('tmux.sock' if tmux else 'unused.sock')
        inner = [TMUX, '-S', str(socket), '-f', '/dev/null', 'new-session', '-s', 'check', '/bin/bash --noprofile --norc'] if tmux else ['/bin/bash', '--noprofile', '--norc']
        terminal = Terminal([str(HELPER), '--dragfile'] + inner, env, destination)
        try:
            terminal.send("printf 'READY_%s\\n' 'TRZSZ'\r")
            terminal.wait(lambda: b'READY_TRZSZ' in terminal.output)
            # Verify real manual trz upload through the bundled helper (picker is stubbed).
            selection.write_text(str(upload))
            terminal.send('trz\r')
            target = destination / upload.name
            terminal.wait(lambda: target.exists() and target.read_bytes() == upload.read_bytes())
            terminal.wait(lambda: b'Saved' in terminal.output or b'saved' in terminal.output)
            terminal.settle()
            # Real tsz download through tmux; content must match exactly.
            selection.write_text(str(downloads))
            terminal.send('tsz ' + shlex.quote(str(target)) + '\r')
            result = downloads / upload.name
            terminal.wait(lambda: result.exists() and result.read_bytes() == upload.read_bytes())
            terminal.settle()
            # Drag a directory; the filter starts trz -d and preserves nested bytes.
            terminal.send(shlex.quote(str(folder)) + ' ')
            directory_target = destination / folder.name / 'child.bin'
            terminal.wait(lambda: directory_target.exists() and directory_target.read_bytes() == (folder/'child.bin').read_bytes())
            terminal.settle()
            # Interrupt a real uncompressed transfer and confirm that the shell recovers.
            large = destination / 'cancel.bin'
            with large.open('wb') as stream: stream.truncate(256 * 1024 * 1024)
            selection.write_text(str(downloads))
            terminal.send('tsz -c no ' + shlex.quote(str(large)) + '\r')
            partial = downloads / large.name
            terminal.wait(lambda: partial.exists() and partial.stat().st_size > 0)
            terminal.send(b'\x03')
            terminal.wait(lambda: b'Stop and keep transferred files' in terminal.output)
            terminal.send('\r')
            terminal.settle()
            assert partial.stat().st_size < large.stat().st_size
            terminal.send("printf 'CANCEL_%s\\n' 'RECOVERED'\r")
            terminal.wait(lambda: b'CANCEL_RECOVERED' in terminal.output)
            # Resize still reaches the underlying shell after transfer.
            fcntl.ioctl(terminal.master, termios.TIOCSWINSZ, struct.pack('HHHH', 38, 125, 0, 0))
            os.kill(terminal.process.pid, signal.SIGWINCH)
            time.sleep(.3)
            terminal.send("printf 'SIZE_%s ' 'CHECK'; stty size\r")
            terminal.wait(lambda: b'SIZE_CHECK 38 125' in terminal.output or (tmux and b'SIZE_CHECK 37 125' in terminal.output))
            terminal.send('exit 7\r')
            terminal.wait(lambda: terminal.process.poll() is not None)
            assert terminal.process.returncode == (0 if tmux else 7), terminal.process.returncode
            print('PASS:', 'tmux' if tmux else 'plain shell', 'manual upload, download, directory drag, Unicode/quoted paths, hashes, cancellation, resize and exit', flush=True)
        finally:
            terminal.close()
            if tmux: subprocess.run([TMUX, '-S', str(socket), 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
