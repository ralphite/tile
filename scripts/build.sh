#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache Tile.app/Contents/MacOS Tile.app/Contents/Resources
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" -module-cache-path .build/module-cache \
  -framework AppKit -framework ApplicationServices \
  Sources/*.swift -o Tile.app/Contents/MacOS/Tile
cp Info.plist Tile.app/Contents/Info.plist
# A persistent certificate keeps the designated requirement stable across builds.
# Ad-hoc signing binds Accessibility grants to a changing executable cdhash.
TILE_SIGNER="${TILE_SIGNING_IDENTITY:-Logue Local Code Signing}"
codesign --force --sign "$TILE_SIGNER" --identifier dev.yadong.tile --timestamp=none Tile.app
codesign --verify --deep --strict Tile.app
echo "Built: $PWD/Tile.app"
