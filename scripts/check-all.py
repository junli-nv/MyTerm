#!/usr/bin/env python3
"""Run the feature suites serially against an explicit, already-built app.

No packaging, installation or publication. Logs and a machine-readable summary
are retained even on failure. GUI suites must not compete for window focus.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--configuration", choices=("debug", "release"), required=True)
    parser.add_argument("--password-python", type=Path, default=Path(".test-venv/bin/python"))
    parser.add_argument("--logs", type=Path)
    parser.add_argument("--x11", action="store_true", help="Require running XQuartz and test real forwarded windows")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    app = args.app.resolve()
    binary = app / "Contents/MacOS/MyTerm"
    checks = root / ".build" / args.configuration / "MyTermChecks"
    # Keep the venv executable path: resolving its symlink selects the base
    # interpreter and loses the venv's installed test dependencies.
    password_python = args.password_python.absolute()
    for path in (binary, checks, root / ".build" / args.configuration / "MyTermProxy", password_python):
        if not path.is_file():
            parser.error(f"Required executable missing: {path}")
    for tool in ("codex", "tmux", "rz", "sz"):
        if not shutil.which(tool):
            parser.error(f"Required tool missing: {tool}")
    subprocess.run([str(password_python), "-c", "import paramiko"], check=True)
    logs = args.logs.resolve() if args.logs else Path(tempfile.mkdtemp(prefix="myterm-check-all-"))
    logs.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, MYTERM_TEST_APP=str(app), MYTERM_TEST_CONFIGURATION=args.configuration,
                       MYTERM_TMUX_CHECK="1", MYTERM_TRZSZ_CHECK="1", PYTHONUNBUFFERED="1")
    metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identity = dict(version=metadata["CFBundleShortVersionString"], build=metadata["CFBundleVersion"],
                    executable_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    checks_sha256=hashlib.sha256(checks.read_bytes()).hexdigest())
    python = sys.executable
    suites = [
        ("core", [str(checks)], 120),
        ("ssh-integration", [python, "scripts/integration-check.py"], 300),
        ("window-controls", [python, "scripts/window-controls-check.py", str(app)], 150),
        ("zmodem", [str(binary), "--smoke-test", "--transfer-check"], 90),
        ("trzsz", [python, "scripts/trzsz-check.py"], 150),
        ("password", [str(password_python), "scripts/password-check.py"], 120),
        ("codex-proxy", [python, "scripts/codex-proxy-check.py"], 90),
        ("codex-execution", [python, "scripts/codex-execution-check.py", str(checks)], 60),
    ]
    if args.configuration == "debug":
        suites.append(("app-smoke", [str(binary), "--smoke-test"], 60))
    if args.x11:
        suites.append(("x11", [python, "scripts/x11-check.py"], 90))
    results = []
    print(f"App: {app}\nConfiguration: {args.configuration}\nLogs: {logs}", flush=True)
    for name, command, timeout in suites:
        print(f"Running {name}…", flush=True)
        started = time.monotonic()
        with (logs / f"{name}.log").open("w") as log:
            try:
                result = subprocess.run(command, cwd=root, env=environment, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=timeout)
                code = result.returncode
            except subprocess.TimeoutExpired:
                log.write(f"\nFAIL: suite exceeded {timeout} seconds\n")
                code = 124
        results.append(dict(suite=name, exit_code=code, seconds=round(time.monotonic() - started, 2)))
        (logs / "summary.json").write_text(json.dumps(dict(app=str(app), configuration=args.configuration, x11_requested=args.x11, identity=identity,
                                                        results=results), indent=2) + "\n")
        print(f"{'PASS' if code == 0 else 'FAIL'}: {name} ({results[-1]['seconds']}s)", flush=True)
        if code != 0:
            # A failed GUI suite may leave fixtures active; stop before launching another.
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
