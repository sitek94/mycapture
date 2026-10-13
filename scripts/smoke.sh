#!/bin/bash
# Smoke test of the main flows in safe mode, before every hand-off: captures of the driver's own test window only,
# with no user input. The installed myCapture (if any) quits while it runs and restarts at the end.
# usage: scripts/smoke.sh [out dir]    (default build/smoke; screenshots for a look review land there too)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/smoke}"
mkdir -p "$OUT" && OUT="$(cd "$OUT" && pwd)"  # the driver runs elsewhere
WORK="$(mktemp -d)"
D=scripts/drive.sh
fail=0
# check <name> <condition>: retries the condition for up to 3 s, since windows can take a moment to show.
check() {
    for _ in $(seq 1 15); do eval "$2" && { echo "ok   $1"; return; }; sleep 0.2; done
    echo "FAIL $1"; $D windows myCapture | sed "s/^/     /"; fail=1
}

quit() { pkill -f 'myCapture.app/Contents/MacOS/myCapture$|myCapture.app/Contents/MacOS/myCapture ' ; while pgrep -f 'myCapture.app/Contents/MacOS/myCapture' >/dev/null; do sleep 0.1; done; }
restore() {
    $D testwindow hide >/dev/null; $D stop; quit
    [[ -d ~/Applications/myCapture.app ]] && { open ~/Applications/myCapture.app || { sleep 1; open ~/Applications/myCapture.app; }; }
}
trap restore EXIT

UITEST=1 scripts/bundle.sh >/dev/null 2>&1 && scripts/bundle.sh driver >/dev/null 2>&1 || { echo "bundle failed"; exit 1; }
quit; sleep 0.5
SAVE="$WORK/saved"
open -g -n build/myCapture.app --args -uiTest YES -thumbnailHover YES -tempDir "$WORK" -saveFolder "$SAVE" ||
    { sleep 1; open -g -n build/myCapture.app --args -uiTest YES -thumbnailHover YES -tempDir "$WORK" -saveFolder "$SAVE"; }
until pgrep -f 'myCapture.app/Contents/MacOS/myCapture' >/dev/null; do sleep 0.2; done; sleep 2

frame=$($D testwindow show | sed -E 's/.*frame=([0-9,]+) .*/\1/' | tr ',' ' ')
read -r x y w h <<<"$frame"
report() { grep -E "\"$1\"" "$WORK/last-capture.json" 2>/dev/null; }

$D capture area $x $y $w $h >/dev/null; sleep 2.5
check "area capture names the test window" 'report title | grep "myCaptureDriver test window" >/dev/null'
check "area capture is a file with the template name" 'ls "$WORK"/*/ | grep "myCaptureDriver - myCaptureDriver test window.png" >/dev/null'
check "a thumbnail shows" '$D windows myCapture | grep "layer=25 onscreen=1" >/dev/null'

$D capture area $((x + 20)) $((y + 40)) $((w / 2)) $((h / 2)) >/dev/null; sleep 2.5
check "a second capture stacks a second thumbnail" '[[ $($D windows myCapture | grep -c "layer=25 onscreen=1") -ge 2 ]]'
$D testwindow hide >/dev/null; sleep 0.3
$D screenshot "$OUT/thumbnails.png" >/dev/null
thumbs() { $D windows myCapture | grep -c "layer=25 onscreen=1"; }

$D thumbnail save >/dev/null
check "save writes the named file" 'ls "$SAVE" 2>/dev/null | grep "myCaptureDriver - myCaptureDriver test window.png" >/dev/null'
check "the saved file is marked as a screenshot" 'xattr -p com.apple.metadata:kMDItemIsScreenCapture "$SAVE"/*.png >/dev/null 2>&1'
check "save closes the thumbnail" '[[ $(thumbs) -eq 1 ]]'
$D thumbnail close >/dev/null
check "close removes a thumbnail" '[[ $(thumbs) -eq 0 ]]'
$D testwindow show >/dev/null; sleep 0.3
$D capture clipboard $x $y $w $h >/dev/null
check "a clipboard capture shows the Copied toast" '$D screenshot "$OUT/toast.png" myCapture 25 >/dev/null'
$D testwindow hide >/dev/null; sleep 1.5
$D thumbnail restore >/dev/null
check "restore brings it back" '[[ $(thumbs) -eq 1 ]]'

focus() { $D testwindow show >/dev/null; $D focus >/dev/null; $D testwindow hide >/dev/null; }  # needs a window to take focus
# Opened while another app is in front: dialogs and Settings must take focus, not open behind it.
focus
$D thumbnail saveas >/dev/null; sleep 1
check "save as comes to the front" '$D front | grep "dev.maciek.mycapture " >/dev/null'
# The save panel takes no keys posted to the app, so Esc goes system-wide: only while myCapture is in front.
$D front | grep -q "dev.maciek.mycapture " && $D globalkey esc >/dev/null
check "esc cancels save as" '! $D windows myCapture | grep "layer=8 onscreen=1" >/dev/null'
check "a cancelled save as keeps the thumbnail" '[[ $(thumbs) -eq 1 ]]'

focus
$D settings >/dev/null; sleep 1.5
check "settings opens" '$D windows myCapture | grep "layer=0 onscreen=1 frame=.*,480," >/dev/null'
check "settings comes to the front" '$D front | grep "dev.maciek.mycapture " >/dev/null'
check "settings opens centered" '$D centered | grep "^yes" >/dev/null'
$D screenshot "$OUT/settings.png" myCapture 0 >/dev/null

# README image: a synthetic desktop with the test window and two thumbnails, the newest one hovered. Only our own
# windows are captured (with transparent surroundings); the background is drawn here.
while [[ $(thumbs) -gt 0 ]]; do $D thumbnail close >/dev/null; sleep 0.3; done
$D testwindow show >/dev/null; sleep 0.5
$D capture area $x $y $((w * 3 / 5)) $((h * 3 / 5)) >/dev/null; sleep 2.5
$D capture area $x $y $w $h >/dev/null; sleep 2.5
$D screenshot "$WORK/window.png" myCaptureDriver >/dev/null
tscale=$($D screenshot "$WORK/thumbs.png" myCapture 25 | sed -E 's/.*scale=([0-9]+).*/\1/')
$D testwindow hide >/dev/null
wwidth=$(sips -g pixelWidth "$WORK/window.png" | awk '/pixelWidth/ {print $2}')
# Drawn at 2×: the window 480 pt wide near the center; the thumbnails where the app puts them (box 40 pt from the
# left, 100 pt from the bottom; the panel image has a 32 pt margin around the box).
ffmpeg -loglevel error -y \
    -f lavfi -i "gradients=s=2200x1240:c0=0xA5F3FC:c1=0x818CF8:x0=0:y0=0:x1=2200:y1=1240:nb_colors=2:d=1" \
    -i "$WORK/window.png" -i "$WORK/thumbs.png" \
    -filter_complex "[1]scale=iw*960/$wwidth:-1[w];[2]scale=iw*2/$tscale:-1[t];[0][w]overlay=900:220[a];[a][t]overlay=16:H-h-136" \
    -frames:v 1 "$OUT/readme.png" && check "readme image" '[[ -s "$OUT/readme.png" ]]'

echo "screenshots: $OUT"
exit $fail
