#!/usr/bin/env python3
"""Capture synthetic tmux copy-mode redraws using an isolated server and PTY."""
import argparse
import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--swift', type=Path, required=True)
args = parser.parse_args()
tmux = shutil.which('tmux')
assert tmux, 'tmux required'
records = {i: f'RECORD_{i:03d} ' + 'abcdefghij' * 9 + ' END' for i in range(80)}
with tempfile.TemporaryDirectory(prefix='myterm-copy-mode-') as temporary:
    root = Path(temporary)
    socket = str(root / 'tmux.sock')
    content = root / 'lines.txt'
    content.write_text('\n'.join(records.values()) + '\n')
    config = root / 'tmux.conf'
    config.write_text('set -g default-shell /bin/bash\nset -g status off\nset -g mouse off\nset -g set-titles off\n')
    def control(*command):
        return subprocess.check_output([tmux, '-S', socket, *command], text=True)
    shell = '/bin/sleep 1; /bin/cat ' + shlex.quote(str(content)) + '; /bin/sleep 300'
    subprocess.run([tmux, '-u', '-S', socket, '-f', str(config), 'new-session', '-d', '-s', 'fixture', '-x', '40', '-y', '12', shell], check=True)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 12, 40, 0, 0))
    environment = {k: v for k, v in os.environ.items() if k not in ('TMUX', 'TMUX_PANE')}
    environment.update(TERM='xterm-256color', LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8')
    process = subprocess.Popen([tmux, '-u', '-S', socket, 'attach-session', '-t', 'fixture'], stdin=slave, stdout=slave, stderr=slave, env=environment)
    os.close(slave)
    def receive(duration=.25):
        output = bytearray()
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if select.select([master], [], [], .03)[0]:
                chunk = os.read(master, 65536)
                output.extend(chunk)
                if b'\x1b[6n' in chunk:
                    os.write(master, b'\x1b[1;1R')
        return re.sub(rb'\d\d:\d\d', b'00:00', bytes(output))
    frames = []
    try:
        initial = receive(1.5)
        stages = [('initial', None), ('copy-mode', ['copy-mode']), ('page-up', ['send-keys', '-X', 'page-up']),
                  ('page-up-again', ['send-keys', '-X', 'page-up']), ('page-down', ['send-keys', '-X', 'page-down']),
                  ('scroll-up', ['send-keys', '-X', 'scroll-up']), ('scroll-down', ['send-keys', '-X', 'scroll-down'])]
        for name, command in stages:
            if command:
                control(*command)
            data = initial if command is None else receive()
            # capture-pane reads the backing pane; copy mode has a separate
            # viewport. Resolve its scroll offset for an independent oracle.
            offset = int(control('display-message', '-p', '#{scroll_position}').strip() or '0')
            screen = control('capture-pane', '-p', '-S', str(-offset), '-E', str(11-offset)).splitlines()
            target = next((row, int(match.group(1))) for row, text in enumerate(screen)
                          if 0 < row < 8 and (match := re.match(r'^RECORD_(\d+) ', text)))
            frames.append(dict(name=name, cols=40, rows=12, data=base64.b64encode(data).decode(),
                               targetRow=target[0], expected=records[target[1]]))
    finally:
        subprocess.run([tmux, '-S', socket, 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        process.wait(timeout=5)
        os.close(master)
    encoded = base64.b64encode(json.dumps(frames, separators=(',', ':')).encode()).decode()
    chunks = '\n'.join(encoded[i:i+120] for i in range(0, len(encoded), 120))
    args.swift.write_text('// Synthetic isolated tmux copy-mode captures; regenerate with scripts/capture-tmux-copy-fixture.py.\n'
                          'enum TmuxCopyModeFixture {\n    static let data = """\n' + chunks + '\n"""\n}\n')
    print('Captured:', ', '.join(frame['name'] for frame in frames))
