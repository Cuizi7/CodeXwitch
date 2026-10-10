#!/bin/bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
swift build -c release --product CodeXwitch
task_bin=$(swift build -c release --show-bin-path)
task_app="$task_root/build/CodeXwitch.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
install -m 755 "$task_bin/CodeXwitch" "$task_app/Contents/MacOS/CodeXwitch"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$task_app/Contents/Resources/AppIcon.icns"
rm -rf "$task_app/Contents/Resources/CodeXwitch_CodeXwitchKit.bundle"
cp -R "$task_bin/CodeXwitch_CodeXwitchKit.bundle" "$task_app/Contents/Resources/"
/usr/bin/codesign --force --sign - "$task_app"
printf 'Built %s\n' "$task_app"
