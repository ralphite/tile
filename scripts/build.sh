#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache Tile.app/Contents/MacOS Tile.app/Contents/Resources
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" -module-cache-path .build/module-cache \
  -framework AppKit -framework ApplicationServices \
  Sources/*.swift -o Tile.app/Contents/MacOS/Tile
cp Info.plist Tile.app/Contents/Info.plist
codesign --force --sign - --identifier dev.yadong.tile Tile.app
echo "Built: $PWD/Tile.app"
