#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)
architecture=$(/usr/bin/uname -m)
release_dir="$PWD/dist/releases/$version"
if [[ -e "$release_dir" ]]; then
    echo "Release directory already exists: $release_dir" >&2
    exit 1
fi
# Catch optimizer-only regressions before producing an installation package.
swift run --build-system native -c release MyTermChecks
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/myterm-release-check.XXXXXX")
trap '/bin/rm -rf -- "$check_dir"' EXIT
python_bin="${MYTERM_TEST_PYTHON:-/Users/junliz/.venvs/codex-py314/bin/python}"
if [[ ! -x "$python_bin" ]]; then python_bin=python3; fi
"$python_bin" scripts/codex-execution-check.py .build/release/MyTermChecks
/bin/bash scripts/build-app.sh debug "$check_dir/MyTerm.app"
"$python_bin" scripts/window-controls-check.py "$check_dir/MyTerm.app"
mkdir -p "$release_dir"
/bin/bash scripts/build-app.sh release "$release_dir/MyTerm.app"
/usr/bin/codesign --verify --deep --strict "$release_dir/MyTerm.app"
"$python_bin" scripts/window-controls-check.py "$release_dir/MyTerm.app"
cp "packaging/RELEASE-NOTES-$version.md" "$release_dir/RELEASE-NOTES.md"
archive="MyTerm-$version-macos-$architecture.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release_dir/MyTerm.app" "$release_dir/$archive"
cd "$release_dir"
/usr/bin/shasum -a 256 "$archive" > SHA256SUMS.txt
echo "Release package: $release_dir/$archive"
