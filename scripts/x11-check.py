#!/usr/bin/env python3
"""Real XQuartz windows through production SSH arguments and an isolated sshd.

The server's xauth wrapper writes only a temporary authority file. No user SSH
configuration, known_hosts or .Xauthority is modified. XQuartz must be running.
"""
import getpass
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
CONFIGURATION = os.environ.get("MYTERM_TEST_CONFIGURATION", "debug")
if CONFIGURATION not in ("debug", "release"):
    raise ValueError("Invalid build configuration")
CHECKS = ROOT / ".build" / CONFIGURATION / "MyTermChecks"
X11 = Path("/opt/X11/bin")
environment = dict(os.environ)
environment["DISPLAY"] = environment.get("DISPLAY") or subprocess.check_output(
    ["/bin/launchctl", "getenv", "DISPLAY"], text=True).strip()
if not environment["DISPLAY"]:
    raise RuntimeError("Start XQuartz and initialize its DISPLAY before running this check")
subprocess.run([str(X11 / "xdpyinfo")], env=environment, stdout=subprocess.DEVNULL, check=True, timeout=10)


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


with tempfile.TemporaryDirectory(prefix="myterm-x11-", dir="/tmp") as temporary:
    root = Path(temporary)
    subprocess.run(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(root / "key")], check=True)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    authority = root / "remote-authority"
    authority.touch(mode=0o600)
    wrapper = root / "xauth"
    wrapper.write_text("#!/bin/bash\nexport XAUTHORITY=" + shlex.quote(str(authority)) + '\nexec /opt/X11/bin/xauth "$@"\n')
    wrapper.chmod(0o700)
    config = root / "sshd_config"
    config.write_text(f"""Port {port}
ListenAddress 127.0.0.1
HostKey {root}/key
PidFile {root}/pid
AuthorizedKeysFile {root}/key.pub
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
X11Forwarding yes
X11UseLocalhost yes
XAuthLocation {wrapper}
""")
    client_config = root / "ssh_config"
    client_config.write_text(f"Host *\n  UserKnownHostsFile {root}/known_hosts\n  IdentitiesOnly yes\n  BatchMode yes\n")
    server_environment = dict(environment)
    server_environment.pop("DISPLAY", None)
    with (root / "sshd.log").open("w+") as log:
        daemon = subprocess.Popen(["/usr/sbin/sshd", "-D", "-e", "-f", str(config)], env=server_environment,
                                  stdout=log, stderr=log)
        window = None
        try:
            for _ in range(100):
                if daemon.poll() is not None:
                    raise RuntimeError("Temporary X11 sshd failed to start")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise RuntimeError("Temporary X11 sshd did not listen")
            for mode in ("disabled", "untrusted", "trusted"):
                definition = root / "server.json"
                definition.write_text(json.dumps(dict(id=str(uuid.uuid4()), name="X11 fixture", host="127.0.0.1",
                    user=getpass.getuser(), port=str(port), identityFile=str(root / "key"), x11Forwarding=mode)))
                launch = json.loads(subprocess.check_output([str(CHECKS), "--ssh-args", str(definition),
                    str(client_config), str(root / f"mux-{mode}"), str(root / "generated_config")], text=True, timeout=10))
                command = ["/usr/bin/ssh", *launch["arguments"]]
                if mode == "disabled":
                    subprocess.run(command + ['test -z "$DISPLAY"'], env=environment, capture_output=True, check=True, timeout=15)
                    print("PASS: X11 disabled exposes no remote DISPLAY", flush=True)
                    continue
                prefix = "export XAUTHORITY=" + shlex.quote(str(authority)) + "; "
                details = subprocess.run(command + [prefix + "/opt/X11/bin/xdpyinfo"], env=environment,
                                         capture_output=True, text=True, timeout=20)
                if details.returncode != 0:
                    raise RuntimeError(f"{mode} X11 forwarding failed: {details.stdout}\n{details.stderr}")
                title = "MyTerm-X11-" + mode + "-" + uuid.uuid4().hex
                remote = prefix + shlex.join([str(X11 / "xmessage"), "-title", title, "-timeout", "15", "MyTerm X11 " + mode])
                window = subprocess.Popen(command + [remote], env=environment, stdout=subprocess.DEVNULL, stderr=log)
                for _ in range(100):
                    tree = subprocess.check_output([str(X11 / "xwininfo"), "-root", "-tree"], env=environment, text=True, timeout=5)
                    if title in tree:
                        break
                    if window.poll() is not None:
                        raise RuntimeError(f"{mode} X11 window exited before display")
                    time.sleep(.05)
                else:
                    raise RuntimeError(f"{mode} X11 window not found")
                stop(window)
                for _ in range(100):
                    tree = subprocess.check_output([str(X11 / "xwininfo"), "-root", "-tree"], env=environment, text=True, timeout=5)
                    if title not in tree:
                        break
                    time.sleep(.05)
                else:
                    raise RuntimeError("X11 window survived closing its SSH channel")
                print(f"PASS: {mode} SSH X11: display query, real XQuartz window and channel-exit cleanup", flush=True)
        finally:
            stop(window)
            stop(daemon)
