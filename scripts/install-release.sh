#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)
architecture=$(/usr/bin/uname -m)
release_dir="$PWD/dist/releases/$version"
image="$release_dir/MyTerm-$version-macos-$architecture.dmg"
target=/Applications/MyTerm.app
python_bin="${MYTERM_TEST_PYTHON:-/Users/junliz/.venvs/codex-py314/bin/python}"
if [[ ! -x "$python_bin" ]]; then python_bin=python3; fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/myterm-install-check.XXXXXX")
mounted=0
replacing=0
success=0
cleanup() {
    if [[ "$replacing" == 1 && "$success" == 0 ]]; then
        /bin/rm -rf -- "$target"
        if [[ -d "$stage/previous.app" ]]; then /usr/bin/ditto "$stage/previous.app" "$target"; fi
    fi
    if [[ "$mounted" == 1 ]]; then /usr/bin/hdiutil detach "$stage/mounted" >/dev/null; fi
    /bin/rm -rf -- "$stage"
}
trap cleanup EXIT
mkdir "$stage/mounted"
/usr/bin/hdiutil attach "$image" -readonly -nobrowse -mountpoint "$stage/mounted"
mounted=1
"$python_bin" scripts/verify-app-copy.py "$release_dir/MyTerm.app" "$stage/mounted/MyTerm.app"
/usr/bin/osascript -e 'tell application "MyTerm" to quit'
for ((attempt=0; attempt<50; attempt++)); do
    if ! /usr/bin/pgrep -x MyTerm >/dev/null; then break; fi
    sleep 0.2
done
if /usr/bin/pgrep -x MyTerm >/dev/null; then echo 'MyTerm did not quit; installation stopped.' >&2; exit 1; fi
if [[ -d "$target" ]]; then /usr/bin/ditto "$target" "$stage/previous.app"; fi
replacing=1
/bin/rm -rf -- "$target"
/usr/bin/ditto "$stage/mounted/MyTerm.app" "$target"
"$python_bin" scripts/verify-app-copy.py "$release_dir/MyTerm.app" "$target"
/usr/bin/codesign --verify --deep --strict "$target"
"$python_bin" scripts/window-controls-check.py "$target"
# The convenience development path uses the exact tested bundle, not another build.
/bin/rm -rf -- "$PWD/dist/MyTerm.app"
/usr/bin/ditto "$target" "$PWD/dist/MyTerm.app"
"$python_bin" scripts/verify-app-copy.py "$target" "$PWD/dist/MyTerm.app"
/usr/bin/hdiutil detach "$stage/mounted"
mounted=0
/usr/bin/open -n "$target"
for ((attempt=0; attempt<50; attempt++)); do
    if /usr/bin/pgrep -f '^/Applications/MyTerm.app/Contents/MacOS/MyTerm$' >/dev/null; then break; fi
    sleep 0.2
done
if ! /usr/bin/pgrep -f '^/Applications/MyTerm.app/Contents/MacOS/MyTerm$' >/dev/null; then
    echo 'Installed MyTerm did not start.' >&2
    exit 1
fi
success=1
echo "Installed and opened: $target ($version)"
