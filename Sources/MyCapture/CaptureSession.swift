import AppKit
import MyCaptureCore
import os

/// Runs one capture with Apple's `screencapture` (selection, window picker, shadow), then reads what it captured.
struct CaptureSession {
    let files: CaptureFiles
    var freezeScreen: Bool
    private let log = Logger(subsystem: "dev.maciek.mycapture", category: "capture")

    init(files: CaptureFiles, freezeScreen: Bool) {
        self.files = files
        self.freezeScreen = freezeScreen
    }

    /// Nil when the user pressed Esc, or the capture made no file.
    /// `testRect` (global top-left points) captures that rect with no user input; only for test runs.
    func run(_ mode: CaptureMode, sound: Bool, testRect: CGRect? = nil) async throws -> Capture? {
        let output = try files.newTempFile()
        let command = testRect.map { CaptureCommand.rect($0, output: output) } ?? .interactive(mode, output: output, sound: sound)
        // Area captures get the ⌘ crosshair, and the frozen screen when Settings turn it on.
        let freeze = FreezeOverlay()
        if mode == .area { await freeze.show(frozen: freezeScreen) }
        defer { freeze.hide() }
        try await Self.launch(command)
        guard FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) else {
            log.notice("no capture (cancelled)")
            try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
            return nil
        }
        // The tool can set its attributes a moment after it exits.
        var info = ScreenCaptureAttributes.read(output)
        for _ in 0..<20 where info == nil {
            try? await Task.sleep(for: .milliseconds(50))
            info = ScreenCaptureAttributes.read(output)
        }
        // A selection smaller than 5 × 5 pt is a slip, not a capture.
        if let rect = info?.rect, rect.width < 5 || rect.height < 5 {
            log.notice("selection too small, treated as cancel")
            try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
            return nil
        }
        let kind = info?.kind ?? (mode == .window ? .window : .selection)
        var capture = Capture(file: output, date: .now, kind: kind, rect: info?.rect ?? testRect)
        if let rect = capture.rect,
            let source = WindowMatch.source(of: kind, rect: rect, in: Self.windows(), excluding: getpid())
        {
            capture.app = source.app
            capture.title = source.title
        }
        return capture
    }

    private static func launch(_ command: CaptureCommand) async throws {
        let process = Process()
        process.executableURL = CaptureCommand.executable
        process.arguments = command.arguments
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// On-screen windows, front to back. Titles need the Screen Recording permission.
    private static func windows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return WindowInfo(
                app: entry[kCGWindowOwnerName as String] as? String ?? "",
                title: entry[kCGWindowName as String] as? String,
                frame: frame,
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                processID: entry[kCGWindowOwnerPID as String] as? Int32 ?? 0
            )
        }
    }
}
