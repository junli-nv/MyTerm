#!/bin/bash
# Runs independently after the GUI exits. All paths are positional arguments, never shell source.
set -euo pipefail
parent_pid=$1
source_app=$2
target_app=$3
expected_version=$4
staging_root=$5
[[ "$staging_root" == */myterm-update-* && "$source_app" == "$staging_root/unpacked/MyTerm.app" ]] || exit 1
[[ "$parent_pid" =~ ^[0-9]+$ && "$target_app" == */MyTerm.app && "$source_app" == */MyTerm.app ]] || exit 1
[[ -d "$source_app" && -d "$target_app" && ! -L "$target_app" && "$source_app" != "$target_app" ]] || exit 1
parent_dir=$(dirname "$target_app")
pending=$(mktemp -d "$parent_dir/.myterm-update.XXXXXX")
backup="$pending/previous.app"
replacement="$pending/MyTerm.app"
replaced=0
success=0
parent_exited=0
cleanup() {
    status=$?
    if [[ "$replaced" == 1 && "$success" == 0 && -d "$backup" ]]; then
        /bin/rm -rf -- "$target_app"
        /bin/mv -- "$backup" "$target_app"
        echo 'Update failed; previous application restored.'
    fi
    if [[ "$parent_exited" == 1 && "$success" == 0 ]]; then /usr/bin/open -n "$target_app" || true; fi
    /bin/rm -rf -- "$pending" "$staging_root"
    exit "$status"
}
trap cleanup EXIT
: > "$staging_root/ready"
for ((attempt=0; attempt<120; attempt++)); do
    if ! /bin/kill -0 "$parent_pid" 2>/dev/null; then break; fi
    /bin/sleep 1
done
if /bin/kill -0 "$parent_pid" 2>/dev/null; then echo 'Application did not exit; update cancelled.'; exit 1; fi
parent_exited=1
/usr/bin/ditto "$source_app" "$replacement"
/usr/bin/codesign --verify --deep --strict "$replacement"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$replacement/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$replacement/Contents/Info.plist")" == "$expected_version" ]] || exit 1
/bin/mv -- "$target_app" "$backup"
replaced=1
/bin/mv -- "$replacement" "$target_app"
/usr/bin/open -n "$target_app"
success=1
echo 'Update installed and application reopened.'
