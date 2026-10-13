#!/bin/bash
# Draws the app icon: our own glyph (Sources/MyCapture/Glyph.swift, via scripts/make-glyph.swift) on the brand
# gradient, as an Icon Composer document in Resources/AppIcon.icon. bundle.sh compiles it.
set -euo pipefail
cd "$(dirname "$0")/.."
mykit=$([[ -d Packages/mykit ]] && echo Packages/mykit || echo .build/checkouts/mykit)
tmp=$(mktemp -d)
xcrun swiftc -parse-as-library -O Sources/MyCapture/Glyph.swift scripts/make-glyph.swift -o "$tmp/make-glyph"
"$tmp/make-glyph" "$tmp"
# Front first: the camera over the brackets.
xcrun swift "$mykit/scripts/make-icon.swift" "$PWD/Resources/AppIcon.icon" 22D3EE 0891B2 "$tmp/camera.png" "$tmp/brackets.png"
