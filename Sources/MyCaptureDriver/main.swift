// UI test driver for myCapture. Runs as its own signed app so Screen Recording and Accessibility
// are granted to it alone, not to the terminal. One long-lived process (`serve <dir>`) executes
// request files, so commands don't launch new processes that disturb keyboard focus.
// Fixed verbs only; see scripts/drive.sh.
//
//   setup                         request both permissions
//   status                        print permission state
//   windows <owner>               list the owner's windows
//   screenshot <png> [owner] [layer]  capture only the owner's on-screen windows (default myCapture), optionally one layer
//   windowshot <png> <window id>  one window alone (ids from `windows`), also when covered
//   key <combo>                   to the myCapture process only, e.g. esc, return
//   type <text>                   to the myCapture process only
//   globalkey <combo>             system-wide; only while the user is hands-off
//   globalclick <x> <y> [right] [cmd] [shift] [window=<id>]   system-wide click; only while the user is hands-off.
//                                 With window=<id> it refuses unless that window is topmost at the point.
//   windowat <x> <y>              the topmost window at a point: id and owner
//   globalmove <x> <y>            system-wide pointer move (hover); only while the user is hands-off
//   globaldrag <x1> <y1> <x2> <y2> [window=<id>]  system-wide drag; only while the user is hands-off
//   testwindow show|hide          a window with known content to capture; prints its frame (top-left coordinates)
//   capture <area|window|clipboard> <x> <y> <w> <h>
//                                 ask a myCapture launched with -uiTest YES to capture that rect without user input
//   thumbnail <close|restore|save>  act on the newest thumbnail of a myCapture launched with -uiTest YES
//   thumbnail editor              open the editor on the newest thumbnail
//   thumbnail add <png>           a copy of any image as a new capture: thumbnail and history entry (for screenshots)
//   editor <open png|drag x1 y1 x2 y2|save|close|activate|report>  act on the open editor (drag in image pixels); report writes editor.json
//   history <toggle|restore|report>  open or close Capture History, restore its selection; report writes history.json
//   settings [pane]               open the Settings window of a myCapture launched with -uiTest YES, on that pane
//   click <x> <y>                 to the myCapture process only; global top-left coordinates
//   front                         frontmost app
//   clear <x> <y> <w> <h>         exit 1 when another app's window covers any part of the rect (a capture would show it)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
    "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "0": kVK_ANSI_0,
    "esc": kVK_Escape, "return": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
    "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
    "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
]

/// Target for key/type: myCapture only, so test keystrokes can never reach the user's apps.
func appPID() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "dev.maciek.mycapture").first?.processIdentifier
}

func deliver(_ event: CGEvent?, to pid: pid_t?) {
    if let pid { event?.postToPid(pid) } else { event?.post(tap: .cghidEventTap) }
}

func postKey(_ combo: String, to pid: pid_t?) -> Bool {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    guard let keyName = parts.last, let code = keyCodes[keyName] else { return false }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
        switch modifier {
        case "cmd": flags.insert(.maskCommand)
        case "ctrl": flags.insert(.maskControl)
        case "opt", "alt": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        default: return false
        }
    }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
        event?.flags = flags
        deliver(event, to: pid)
        usleep(15_000)
    }
    return true
}

func typeText(_ text: String, to pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for unit in text.utf16 {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            var char = unit
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            event?.flags = []  // don't inherit modifiers from an earlier combo
            deliver(event, to: pid)
            usleep(8_000)
        }
    }
}

func windowList(owner: String) -> String {
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter { $0[kCGWindowOwnerName as String] as? String == owner }.map { window in
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return "id=\(window[kCGWindowNumber as String] ?? "?") layer=\(window[kCGWindowLayer as String] ?? "?") "
            + "onscreen=\(window[kCGWindowIsOnscreen as String] ?? false) "
            + "frame=\(bounds["X"] ?? 0),\(bounds["Y"] ?? 0),\(bounds["Width"] ?? 0),\(bounds["Height"] ?? 0)"
    }.joined(separator: "\n")
}

var busy = false

// One case per verb.
// swiftlint:disable:next cyclomatic_complexity function_body_length
@MainActor func run(_ verb: String, _ args: [String]) async -> (String, Int32) {
    switch verb {
    case "setup":
        _ = CGRequestScreenCaptureAccess()
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        fallthrough
    case "status":
        return ("screen recording: \(CGPreflightScreenCaptureAccess()) accessibility: \(AXIsProcessTrusted())", 0)
    case "windows":
        return (windowList(owner: args.first ?? "myCapture"), 0)
    case "clear":
        let numbers = args.compactMap { Double($0) }
        guard numbers.count == 4 else { return ("usage: clear x y w h", 2) }
        let owner = coveringOwner(CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        return owner.map { ("covered by \($0)", 1) } ?? ("clear", 0)
    case "screenshot":
        guard let path = args.first else { return ("missing path", 2) }
        return await screenshot(path: path, owner: args.count > 1 ? args[1] : "myCapture", layer: args.count > 2 ? Int(args[2]) : nil)
    case "windowshot":
        guard args.count == 2, let id = CGWindowID(args[1]) else { return ("usage: windowshot <png> <window id>", 2) }
        return await windowShot(path: args[0], windowID: id)
    case "key":
        guard let pid = appPID() else { return ("myCapture is not running", 1) }
        guard let combo = args.first, postKey(combo, to: pid) else { return ("unknown key combo", 2) }
        return ("ok", 0)
    case "globalkey":
        guard let combo = args.first, postKey(combo, to: nil) else { return ("unknown key combo", 2) }
        return ("ok", 0)
    case "type":
        guard let pid = appPID() else { return ("myCapture is not running", 1) }
        typeText(args.joined(separator: " "), to: pid)
        return ("ok", 0)
    case "windowat":
        guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]) else { return ("usage: windowat x y", 2) }
        return windowAt(CGPoint(x: x, y: y)).map { ("id=\($0.id) owner=\($0.owner)", 0) } ?? ("none", 1)
    case "globalmove":
        guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]) else { return ("usage: globalmove x y", 2) }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?
            .post(tap: .cghidEventTap)
        return ("ok", 0)
    case "globaldrag":
        if let refusal = refuseUnlessWindow(args, at: args.count >= 2 ? (Double(args[0]), Double(args[1])) : (nil, nil)) { return refusal }
        let numbers = args.filter { !$0.hasPrefix("window=") }.compactMap { Double($0) }
        guard numbers.count == 4 else { return ("usage: globaldrag x1 y1 x2 y2", 2) }
        let start = CGPoint(x: numbers[0], y: numbers[1])
        let end = CGPoint(x: numbers[2], y: numbers[3])
        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        post(.leftMouseDown, start)
        for step in 1...20 {
            let fraction = Double(step) / 20
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction))
        }
        post(.leftMouseUp, end)
        return ("ok", 0)
    case "globalclick":
        if let refusal = refuseUnlessWindow(args, at: args.count >= 2 ? (Double(args[0]), Double(args[1])) : (nil, nil)) { return refusal }
        guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else { return ("usage: globalclick x y [right] [cmd] [shift]", 2) }
        let options = Set(args.dropFirst(2))
        let right = options.contains("right")
        var flags: CGEventFlags = []
        if options.contains("cmd") { flags.insert(.maskCommand) }
        if options.contains("shift") { flags.insert(.maskShift) }
        let types: [CGEventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            let event = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: right ? .right : .left)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
        return ("ok", 0)
    case "testwindow":
        if args.first == "hide" {
            testWindow?.orderOut(nil)
            return ("ok", 0)
        }
        return (showTestWindow(), 0)
    case "thumbnail":
        guard let action = args.first, ["close", "restore", "save", "saveas", "editor", "add"].contains(action),
            action != "add" || args.count == 2
        else {
            return ("usage: thumbnail <close|restore|save|saveas|editor|add png>", 2)
        }
        DistributedNotificationCenter.default().postNotificationName(
            .init("dev.maciek.mycapture.test.thumbnail"), object: nil, userInfo: ["action": action, "file": args.last ?? ""],
            deliverImmediately: true)
        return ("ok", 0)
    case "editor":
        guard let action = args.first, ["open", "drag", "save", "close", "activate", "report"].contains(action) else {
            return ("usage: editor <open png|drag x1 y1 x2 y2|save|close|activate|report>", 2)
        }
        DistributedNotificationCenter.default().postNotificationName(
            .init("dev.maciek.mycapture.test.editor"), object: nil, userInfo: ["args": args.joined(separator: " ")],
            deliverImmediately: true)
        return ("ok", 0)
    case "history":
        guard let action = args.first, ["toggle", "restore", "report"].contains(action) else {
            return ("usage: history <toggle|restore|report>", 2)
        }
        DistributedNotificationCenter.default().postNotificationName(
            .init("dev.maciek.mycapture.test.history"), object: nil, userInfo: ["action": action], deliverImmediately: true)
        return ("ok", 0)
    case "settings":
        DistributedNotificationCenter.default().postNotificationName(
            .init("dev.maciek.mycapture.test.settings"), object: nil, userInfo: args.first.map { ["pane": $0] },
            deliverImmediately: true)
        return ("ok", 0)
    case "capture":
        guard args.count == 5, ["area", "window", "clipboard"].contains(args[0]), args.dropFirst().allSatisfy({ Double($0) != nil })
        else { return ("usage: capture <area|window|clipboard> x y w h", 2) }
        DistributedNotificationCenter.default().postNotificationName(
            .init("dev.maciek.mycapture.test.capture"), object: nil,
            userInfo: ["mode": args[0], "rect": args.dropFirst().joined(separator: ",")], deliverImmediately: true)
        return ("ok", 0)
    case "click":
        guard let pid = appPID() else { return ("myCapture is not running", 1) }
        guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]) else { return ("usage: click x y", 2) }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            deliver(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left), to: pid)
            usleep(30_000)
        }
        return ("ok", 0)
    case "focus":
        // The driver takes focus, so a check can see whether myCapture takes it back. The forced call, by selector:
        // NSApp.activate() cannot take focus from the active app on macOS 26, and the old call is deprecated.
        typealias Activate = @convention(c) (AnyObject, Selector, Bool) -> Void
        let selector = NSSelectorFromString("activateIgnoringOtherApps:")
        unsafeBitCast(NSApp.method(for: selector), to: Activate.self)(NSApp, selector, true)
        try? await Task.sleep(for: .milliseconds(300))
        let app = NSWorkspace.shared.frontmostApplication
        return ("\(app?.bundleIdentifier ?? "nil")", 0)
    case "centered":
        // Is myCapture's normal-level window (Settings) centered left to right on the display it is on?
        let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        guard
            let window = all.first(where: {
                $0[kCGWindowOwnerName as String] as? String == "myCapture" && $0[kCGWindowLayer as String] as? Int == 0
            }),
            let bounds = window[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return ("no window", 1) }
        let screens = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
            .map(CGDisplayBounds)
        guard let screen = screens.first(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { return ("off screen", 1) }
        let centered = abs(frame.midX - screen.midX) <= 2
        return ("\(centered ? "yes" : "no") window=\(frame) display=\(screen)", centered ? 0 : 1)
    case "front":
        let app = NSWorkspace.shared.frontmostApplication
        return ("\(app?.bundleIdentifier ?? "nil") pid=\(app?.processIdentifier ?? 0)", 0)
    default:
        return ("unknown verb \(verb)", 2)
    }
}

/// Request: <dir>/req/<id>.json = ["verb", "arg", ...]; response: <dir>/res/<id>.txt, first line is the exit code.
@MainActor func serve(_ dir: URL) {
    let req = dir.appending(path: "req"), res = dir.appending(path: "res")
    try? FileManager.default.createDirectory(at: req, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
            guard !busy,
                let name = (try? FileManager.default.contentsOfDirectory(atPath: req.path))?
                    .filter({ $0.hasSuffix(".json") }).sorted().first
            else { return }
            let file = req.appending(path: name)
            let command = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))) ?? []
            try? FileManager.default.removeItem(at: file)
            busy = true
            Task { @MainActor in
                let (output, code) = await run(command.first ?? "", Array(command.dropFirst()))
                let out = res.appending(path: name.replacingOccurrences(of: ".json", with: ".txt"))
                try? "\(code)\n\(output)".write(to: out, atomically: true, encoding: .utf8)
                busy = false
            }
        }
    }
}

var testWindow: NSWindow?

// The mock stands in for another app's content, so the myKit design tokens do not apply.
// swiftlint:disable raw_spacing raw_radius system_font raw_color
/// Synthetic content that looks like a real app in screenshots (README, smoke): a small report with a bar chart.
struct TestWindowContent: View {
    private let bars: [(day: String, value: Double)] = [("Mon", 0.45), ("Tue", 0.7), ("Wed", 0.55), ("Thu", 0.9), ("Fri", 0.65)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("myCapture test window").font(.title2.weight(.semibold))
            Text("Captures this week").font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(bars, id: \.day) { bar in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6).fill(Color.teal.gradient).frame(width: 52, height: 150 * bar.value)
                        Text(bar.day).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 480, height: 300, alignment: .topLeading)
        .background(.background)
    }
}
// swiftlint:enable raw_spacing raw_radius system_font raw_color

/// A window with known, synthetic content, so captures never show the user's screen.
@MainActor func showTestWindow() -> String {
    if testWindow == nil {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 300, width: 480, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "myCaptureDriver test window"
        window.isReleasedWhenClosed = false
        // Normal level: the source lookup for file names considers normal windows only.
        window.contentView = NSHostingView(rootView: TestWindowContent())
        testWindow = window
    }
    testWindow?.orderFrontRegardless()
    guard let window = testWindow, let screen = NSScreen.screens.first else { return "no window" }
    let frame = window.frame
    return "frame=\(Int(frame.minX)),\(Int(screen.frame.height - frame.maxY)),\(Int(frame.width)),\(Int(frame.height)) id=\(window.windowNumber)"
}

let args = Array(CommandLine.arguments.dropFirst())
let app = NSApplication.shared
switch (args.first, args.count) {
case ("serve", 2):
    app.setActivationPolicy(.accessory)
    serve(URL(filePath: args[1]))
default:
    FileHandle.standardError.write(Data("usage: myCaptureDriver serve <dir>\n".utf8))
    exit(2)
}
app.run()

/// For `window=<id>` in a global click or drag: an error unless that window is the topmost one at the point.
@MainActor func refuseUnlessWindow(_ args: [String], at point: (Double?, Double?)) -> (String, Int32)? {
    guard let expected = args.first(where: { $0.hasPrefix("window=") }).flatMap({ CGWindowID($0.dropFirst(7)) }) else { return nil }
    guard let x = point.0, let y = point.1 else { return ("missing point", 2) }
    let top = windowAt(CGPoint(x: x, y: y))
    guard top?.id == expected else { return ("refused: topmost at \(Int(x)),\(Int(y)) is \(top.map { "\($0.id) \($0.owner)" } ?? "none")", 1) }
    return nil
}
