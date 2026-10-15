# myCapture agent index

myCapture is a personal screenshot tool for macOS 26 (Swift 6, SwiftUI + AppKit, myKit). Keep the feature set small.

`scripts/check.sh` is the gate: format, lint (including myKit's design-token rules), build with warnings as errors, tests. CI runs the same script. Always go through `xcrun`: a `swift` elsewhere on `PATH` may be an older toolchain.

This file is a map, not the docs. Open the page that owns the task:

- The build plan, while v1 is in progress: `PLAN.md` (local only, never committed)
- Shared traps (focus, permissions, shortcuts, icon, building): [myKit gotchas](https://github.com/sitek94/mykit/blob/main/docs/gotchas.md)

## Rules

- UI work runs in safe mode on test windows only. System-wide keys and clicks only with the user's go-ahead and hands off the Mac. Never capture or view the user's real screen content.
- Bug fixes get a regression test where the logic allows.
- New version: bump `VERSION` in `scripts/bundle.sh`, list user-visible changes under a new heading in `CHANGELOG.md`, tag `vX.Y.Z`.
- No code, assets or text from other apps in this repo.
