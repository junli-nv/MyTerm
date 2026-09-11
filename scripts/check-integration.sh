#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native --product MyTermChecks
swift build --build-system native --product MyTermProxy
python_bin="${MYTERM_TEST_PYTHON:-/Users/junliz/.venvs/codex-py314/bin/python}"
if [[ ! -x "$python_bin" ]]; then python_bin=python3; fi
"$python_bin" scripts/integration-check.py
