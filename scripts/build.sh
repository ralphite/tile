#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
TILE_STAGE=$(mktemp -d "$PWD/.build/package.XXXXXX")
trap 'rm -rf "$TILE_STAGE"' EXIT
TILE_BUNDLE="$TILE_STAGE/Tile.app"
mkdir -p "$TILE_BUNDLE/Contents/MacOS" "$TILE_BUNDLE/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" -module-cache-path .build/module-cache \
  -framework AppKit -framework ApplicationServices \
  Sources/*.swift -o "$TILE_BUNDLE/Contents/MacOS/Tile"
cp Info.plist "$TILE_BUNDLE/Contents/Info.plist"
# A persistent certificate keeps the designated requirement stable across builds.
# Ad-hoc signing binds Accessibility grants to a changing executable cdhash.
TILE_SIGNER="${TILE_SIGNING_IDENTITY:-Logue Local Code Signing}"
codesign --force --sign "$TILE_SIGNER" --identifier dev.yadong.tile --timestamp=none "$TILE_BUNDLE"
codesign --verify --deep --strict "$TILE_BUNDLE"
# A failed compile/sign must leave the installed application untouched.
if [[ -d Tile.app ]]; then mv Tile.app "$TILE_STAGE/previous.app"; fi
if ! mv "$TILE_BUNDLE" Tile.app; then
  if [[ -d "$TILE_STAGE/previous.app" ]]; then mv "$TILE_STAGE/previous.app" Tile.app; fi
  exit 1
fi
echo "Built: $PWD/Tile.app"
