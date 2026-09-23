#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build results/jev-app 'Jev Clipboard.app/Contents/MacOS'
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path .build/module-cache Sources/*.swift -o 'Jev Clipboard.app/Contents/MacOS/LayaClipboard'
cp Info.plist 'Jev Clipboard.app/Contents/Info.plist'
print 'Built Jev Clipboard.app (local, no explicit signing or notarization).'
