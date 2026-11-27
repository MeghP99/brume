#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

app="${1:-.build/SpaceMouse.app}"
mkdir -p "$app/Contents/MacOS"
install -m 644 Resources/Info.plist "$app/Contents/Info.plist"
sdk="$(/usr/bin/xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null ||
    /usr/bin/xcrun --sdk macosx26 --show-sdk-path 2>/dev/null ||
    /usr/bin/xcrun --sdk macosx --show-sdk-path)"
/usr/bin/xcrun swiftc -sdk "$sdk" -O -swift-version 5 -target "$(uname -m)-apple-macosx26.0" \
    Sources/*.swift -o "$app/Contents/MacOS/SpaceMouse"
/usr/bin/codesign --force --sign - --identifier local.spacemouse.app "$app"
printf '%s\n' "Built $app"
