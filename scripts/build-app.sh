#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release] [output.app]" >&2
    exit 1
fi
swift build --build-system native -c "$configuration" --product MyTerm
swift build --build-system native -c "$configuration" --product MyTermProxy
bin_dir="$(swift build --build-system native -c "$configuration" --show-bin-path)"
app_dir="${2:-$PWD/dist/MyTerm.app}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/MyTerm" "$app_dir/Contents/MacOS/MyTerm"
install -m 755 "$bin_dir/MyTermProxy" "$app_dir/Contents/MacOS/MyTermProxy"
codesign --force --sign - "$app_dir/Contents/MacOS/MyTermProxy"
architecture="$(uname -m)"
(cd vendor/trzsz/1.2.0 && /usr/bin/shasum -a 256 -c SHA256SUMS.txt)
install -m 755 "vendor/trzsz/1.2.0/$architecture/trzsz" "$app_dir/Contents/MacOS/trzsz"
codesign --force --sign - "$app_dir/Contents/MacOS/trzsz"
install -m 644 vendor/trzsz/1.2.0/LICENSE "$app_dir/Contents/Resources/trzsz-LICENSE.txt"
install -m 644 vendor/trzsz/1.2.0/THIRD-PARTY-NOTICES.txt "$app_dir/Contents/Resources/trzsz-THIRD-PARTY-NOTICES.txt"
for resource in "$bin_dir"/*.bundle; do
    [[ -d "$resource" ]] || continue
    ditto "$resource" "$app_dir/Contents/Resources/$(basename "$resource")"
done
cp packaging/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/generate-icon.swift "$PWD/dist/MyTerm.iconset"
iconutil -c icns "$PWD/dist/MyTerm.iconset" -o "$app_dir/Contents/Resources/MyTerm.icns"
ditto packaging/localizations "$app_dir/Contents/Resources"
install -m 644 .build/checkouts/SwiftTerm/LICENSE "$app_dir/Contents/Resources/SwiftTerm-LICENSE.txt"
codesign --force --sign - "$app_dir"
echo "Built: $app_dir"
