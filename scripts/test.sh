#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -module-cache-path .build/module-cache \
  Sources/Layout.swift Tests/LayoutTests.swift -o .build/layout-tests
.build/layout-tests
