#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)
architecture=$(/usr/bin/uname -m)
release_dir="$PWD/dist/releases/$version"
image="$release_dir/MyTerm-$version-macos-$architecture.dmg"
[[ -d "$release_dir/MyTerm.app" && ! -e "$image" ]]
stage=$(mktemp -d "${TMPDIR:-/tmp}/myterm-installer.XXXXXX")
trap '/bin/rm -rf -- "$stage"' EXIT
/usr/bin/ditto "$release_dir/MyTerm.app" "$stage/MyTerm.app"
ln -s /Applications "$stage/Applications"
cp "$release_dir/RELEASE-NOTES.md" "$stage/README.md"
/usr/bin/hdiutil create -volname "MyTerm $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$image"
/usr/bin/hdiutil verify "$image"
cd "$release_dir"
/usr/bin/shasum -a 256 "MyTerm-$version-macos-$architecture.zip" "MyTerm-$version-macos-$architecture.dmg" > SHA256SUMS.txt
echo "Installer: $image"
