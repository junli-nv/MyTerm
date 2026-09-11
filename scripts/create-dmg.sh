#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)
architecture=$(/usr/bin/uname -m)
release_dir="$PWD/dist/releases/$version"
image="$release_dir/MyTerm-$version-macos-$architecture.dmg"
[[ -d "$release_dir/MyTerm.app" && ! -e "$image" ]]
stage=$(mktemp -d "${TMPDIR:-/tmp}/myterm-installer.XXXXXX")
mount_dir="$stage/mounted"
mounted=0
cleanup() {
    if [[ "$mounted" == 1 ]]; then /usr/bin/hdiutil detach "$mount_dir" >/dev/null; fi
    /bin/rm -rf -- "$stage"
}
trap cleanup EXIT
/usr/bin/ditto "$release_dir/MyTerm.app" "$stage/MyTerm.app"
ln -s /Applications "$stage/Applications"
cp "$release_dir/RELEASE-NOTES.md" "$stage/README.md"
/usr/bin/hdiutil create -volname "MyTerm $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$image"
/usr/bin/hdiutil verify "$image"
mkdir "$mount_dir"
/usr/bin/hdiutil attach "$image" -readonly -nobrowse -mountpoint "$mount_dir"
mounted=1
python_bin="${MYTERM_TEST_PYTHON:-/Users/junliz/.venvs/codex-py314/bin/python}"
if [[ ! -x "$python_bin" ]]; then python_bin=python3; fi
"$python_bin" scripts/verify-app-copy.py "$release_dir/MyTerm.app" "$mount_dir/MyTerm.app"
# Exercise the installed form, copied from the actual image instead of rebuilt.
/usr/bin/ditto "$mount_dir/MyTerm.app" "$stage/installed/MyTerm.app"
"$python_bin" scripts/verify-app-copy.py "$release_dir/MyTerm.app" "$stage/installed/MyTerm.app"
/usr/bin/codesign --verify --deep --strict "$stage/installed/MyTerm.app"
"$python_bin" scripts/window-controls-check.py "$stage/installed/MyTerm.app"
/usr/bin/hdiutil detach "$mount_dir"
mounted=0
cd "$release_dir"
/usr/bin/shasum -a 256 "MyTerm-$version-macos-$architecture.zip" "MyTerm-$version-macos-$architecture.dmg" > SHA256SUMS.txt
echo "Installer: $image"
