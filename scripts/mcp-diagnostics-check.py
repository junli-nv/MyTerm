#!/usr/bin/env python3
"""Exercise real MCP pipes with isolated opt-in metadata; never call SSH tools."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

binary = Path(sys.argv[1]).resolve() / 'Contents/MacOS/MyTerm'
with tempfile.TemporaryDirectory(prefix='myterm-mcp-diagnostics-') as root:
    log = Path(root) / 'events.json'
    env = dict(os.environ, MYTERM_TEST_MCP_DIAGNOSTICS=str(log))
    command = [str(binary), '--smoke-test', '--myterm-mcp']

    def start():
        log.write_text(json.dumps({'expires': time.time() - 978307200 + 900,
                                   'recording': True, 'dropped': 0, 'entries': []}))
        log.chmod(0o600)

    def events():
        return [entry['event'] for entry in json.loads(log.read_text())['entries']]

    requests = b'{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' \
               b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n' \
               b'{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n'
    subprocess.run(command, input=requests, capture_output=True, env=env, check=True, timeout=10)
    assert not log.exists(), 'Disabled capture created a file'
    start()
    result = subprocess.run(command, input=requests, capture_output=True, env=env, check=True, timeout=10)
    assert len(result.stdout.splitlines()) == 2, 'Diagnostics contaminated protocol stdout'
    assert events() == ['started', 'initializeReceived', 'initializeReplied', 'initialized',
                        'toolsListReceived', 'toolsListReplied', 'inputEOF'], events()
    start()
    subprocess.run(command, input=b'secret-sentinel-invalid-json\n', capture_output=True,
                   env=env, check=True, timeout=10)
    assert 'parseError' in events()
    assert 'secret-sentinel' not in log.read_text(), 'Input leaked into diagnostics'
    start()
    subprocess.run(command, input=b'x' * 262145, capture_output=True, env=env, check=True, timeout=10)
    assert events()[-1] == 'inputLimit'
    start()
    # Close the reader before providing input, so the first reply gets EPIPE.
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env)
    process.stdout.close()
    process.stdin.write(requests)
    process.stdin.close()
    try:
        assert process.wait(timeout=10) == 0
        assert events()[-1] == 'outputError', events()
        assert json.loads(log.read_text())['entries'][-1]['errorNumber'] == 32
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        process.stderr.close()
print('PASS: isolated MCP initialization, discovery, EOF, malformed input, size limit, EPIPE and opt-in privacy')
