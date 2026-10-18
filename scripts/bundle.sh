#!/bin/bash
# Builds, bundles and signs myCapture.app.
#   scripts/bundle.sh           build build/myCapture.app
#   scripts/bundle.sh install   also copy to ~/Applications and launch
#   scripts/bundle.sh driver    build build/myCaptureDriver.app (UI test driver)
# Signing with a stable identity keeps Screen Recording and Accessibility grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${MYCAPTURE_SIGN_IDENTITY:-Apple Development}"
# Bump with every tagged version (see CHANGELOG.md).
VERSION=0.2.1
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && COMMIT="$COMMIT-dirty"

# bundle <product> <bundle id>
bundle() {
    local product=$1 id=$2 app=build/$1.app
    # UITEST=1: a test build with the test hooks (scripts/smoke.sh). Never install one.
    local flags=()
    [[ "${UITEST:-}" == 1 ]] && flags=(-Xswiftc -DUITEST)
    xcrun swift build -c release --product "$product" ${flags[@]+"${flags[@]}"}
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp ".build/release/$product" "$app/Contents/MacOS/$product"
    if [[ -n "${icon:-}" ]]; then
        # Icon Composer document -> Assets.car (+ fallback .icns); macOS 26 renders it natively.
        # Absolute paths: actool runs in a long-lived service that resolves relative ones against an earlier caller's folder.
        mkdir -p "$app/Contents/Resources"
        xcrun actool "$PWD/$icon" --compile "$PWD/$app/Contents/Resources" --platform macosx \
            --minimum-deployment-target 26.0 --app-icon AppIcon \
            --output-partial-info-plist "$(mktemp -d)/partial.plist" >/dev/null
    fi
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$id</string>
    <key>CFBundleName</key><string>$product</string>
    <key>CFBundleExecutable</key><string>$product</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>GitCommit</key><string>$COMMIT</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHumanReadableCopyright</key><string>Personal build</string>
</dict>
</plist>
PLIST
    codesign --force --options runtime --sign "$IDENTITY" "$app"
    codesign --verify --strict "$app"
    echo "built $app"
}

if [[ "${1:-}" == "driver" ]]; then
    bundle myCaptureDriver dev.maciek.mycapture.driver
    exit
fi

icon=Resources/AppIcon.icon bundle myCapture dev.maciek.mycapture

if [[ "${1:-}" == "install" ]]; then
    [[ "${UITEST:-}" == 1 ]] && { echo "a test build is never installed"; exit 1; }
    pkill -x myCapture || true
    while pgrep -x myCapture >/dev/null; do sleep 0.1; done
    mkdir -p ~/Applications
    rm -rf ~/Applications/myCapture.app
    cp -R build/myCapture.app ~/Applications/myCapture.app
    # LaunchServices can still hold the old instance for a moment after it exits (error -600).
    open ~/Applications/myCapture.app || { sleep 1; open ~/Applications/myCapture.app; }
    echo "installed ~/Applications/myCapture.app"
fi
