#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
/usr/bin/xcrun swiftc -swift-version 5 \
    Sources/Shortcuts.swift Sources/ShortcutEngine.swift Tests/ShortcutChecks.swift \
    -o .build/shortcut-checks
.build/shortcut-checks
