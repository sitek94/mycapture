#!/bin/bash
# The one gate: format, lint, build with warnings as errors, tests. CI runs this script.
set -euo pipefail
cd "$(dirname "$0")/.."

paths=(Package.swift Sources Tests)
swiftlint=.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint

echo "== format"
xcrun swift format lint --strict --recursive --parallel "${paths[@]}"

echo "== lint"
[[ -x $swiftlint ]] || xcrun swift package resolve
"$swiftlint" lint --strict --quiet "${paths[@]}"

echo "== build"
xcrun swift build --build-tests -Xswiftc -warnings-as-errors

echo "== test"
xcrun swift test --skip-build
