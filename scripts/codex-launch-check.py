#!/usr/bin/env python3
"""Validate production launch arguments with real Codex TOML parsing and MCP startup.
No model request, terminal history read, credential output or config write.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
binary = app / "Contents/MacOS/MyTerm"
codex = shutil.which("codex")
if not codex:
    raise SystemExit("Codex CLI is required for the release MCP launch check")
with tempfile.TemporaryDirectory(prefix="myterm-codex-launch-") as directory:
    alias = pathlib.Path(directory) / 'My Term "quoted" 中文' / "MyTerm"
    alias.parent.mkdir()
    alias.symlink_to(binary)
    for path in [binary, alias]:
        args = json.loads(subprocess.check_output([str(binary), "--smoke-test", "--codex-launch-arguments", str(path)], text=True))
        overrides = []
        for index, value in enumerate(args):
            if value == "-c":
                overrides.extend(["-c", args[index + 1]])
        parsed = json.loads(subprocess.check_output([codex, *overrides, "mcp", "get", "myterm", "--json"], text=True, timeout=15))
        transport = parsed["transport"]
        assert transport["command"] == str(path), "Codex parsed an incorrect executable path"
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "fixture", "version": "1"}}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        ]
        result = subprocess.run([transport["command"], *transport["args"]],
                                input="".join(json.dumps(r) + "\n" for r in requests),
                                capture_output=True, text=True, timeout=10, check=True)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        assert replies[0]["result"]["serverInfo"]["name"] == "MyTerm"
        assert {t["name"] for t in replies[1]["result"]["tools"]} == {"list_sessions", "read_output", "capture_history", "read_history_page", "execute_command", "command_status", "cancel_command", "propose_plan"}
print("PASS: production arguments parsed by real Codex; executable path round trip and MCP startup (including spaces, quotes and Unicode)")
