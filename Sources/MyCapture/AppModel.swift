import AppKit
import Carbon.HIToolbox
import MyCaptureCore
import MyKit
import Observation
import SwiftUI
import os

@Observable
final class AppModel {
    /// `-uiTest YES` on launch: captures run on a distributed notification from the test driver, with a fixed rect
    /// and no user input, into the `-tempDir` folder. Only in a test build (`UITEST=1 scripts/bundle.sh`): in a normal
    /// build any local process could post the notification and capture the screen with this app's permission.
    #if UITEST
        static let uiTest = UserDefaults.standard.bool(forKey: "uiTest")
    #else
        static let uiTest = false
    #endif

    var playSound = UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(playSound, forKey: "playSound") }
    }
    /// Off by default, as in CleanShot X: a live screen lets you pick a moment of a video while you drag.
    var freezeScreen = UserDefaults.standard.bool(forKey: "freezeScreen") {
        didSet { UserDefaults.standard.set(freezeScreen, forKey: "freezeScreen") }
    }
    var saveFolder = UserDefaults.standard.url(forKey: "saveFolder") ?? CaptureFiles.defaultSaveFolder {
        didSet { UserDefaults.standard.set(saveFolder, forKey: "saveFolder") }
    }
    private(set) var screenRecordingAllowed = CGPreflightScreenCaptureAccess()
    /// The thumbnails on screen and the closed captures Restore can bring back. Saved on every change.
    private(set) var thumbnails = ThumbnailList() {
        didSet {
            stack.show(thumbnails.visible)
            purgeTemp()
            // Test runs share the app's defaults; they must not touch the real thumbnails.
            guard !Self.uiTest else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(thumbnails.forRelaunch), forKey: "thumbnails")
        }
    }
    private(set) var capturing = false

    // Defaults match the CleanShot X setup this app replaces: ⌃⇧⌘ + a letter.
    @ObservationIgnored private(set) lazy var areaShortcut = GlobalShortcut(name: "areaThumbnail", default: Self.shortcut(kVK_ANSI_A)) {
        [weak self] in self?.capture(.area, to: .thumbnail)
    }
    @ObservationIgnored private(set) lazy var clipboardShortcut = GlobalShortcut(name: "areaClipboard", default: Self.shortcut(kVK_ANSI_Q)) {
        [weak self] in self?.capture(.area, to: .clipboard)
    }
    @ObservationIgnored private(set) lazy var windowShortcut = GlobalShortcut(name: "windowThumbnail", default: Self.shortcut(kVK_ANSI_W)) {
        [weak self] in self?.capture(.window, to: .thumbnail)
    }
    @ObservationIgnored private(set) lazy var restoreShortcut = GlobalShortcut(name: "restore", default: Self.shortcut(kVK_ANSI_H)) {
        [weak self] in self?.restoreLast()
    }
    @ObservationIgnored let files: CaptureFiles
    @ObservationIgnored private let log = Logger(subsystem: "dev.maciek.mycapture", category: "app")
    /// The last clipboard capture: its file stays, so a pasted file reference keeps working.
    @ObservationIgnored private var clipboardCapture: Capture?
    @ObservationIgnored private let quickLook = QuickLookPreview()
    @ObservationIgnored private lazy var stack = ThumbnailStack(
        actions: ThumbnailActions(
            copy: { [weak self] in self?.copy($0) ?? false },
            save: { [weak self] in self?.save($0) ?? false },
            saveAs: { [weak self] in self?.saveAs($0) },
            close: { [weak self] in self?.thumbnails.close($0.id) },
            open: {
                NSWorkspace.shared.open([$0.file], withApplicationAt: URL(filePath: "/System/Applications/Preview.app"), configuration: .init())
            },
            preview: { [weak self] in self?.quickLook.toggle($0.file) }
        ))
    @ObservationIgnored private lazy var settingsWindow = SettingsWindow(title: "myCapture Settings", tint: .brand) {
        [unowned self] in
        SettingsSections(app: self)
    }

    init() {
        let tempDir = Self.uiTest ? UserDefaults.standard.string(forKey: "tempDir").map { URL(filePath: $0) } : nil
        files = CaptureFiles(tempFolder: tempDir ?? CaptureFiles.defaultTempFolder)
    }

    func start() {
        ToastPanel.tint = .brand
        if Self.uiTest {
            DistributedNotificationCenter.default().addObserver(
                forName: .init("dev.maciek.mycapture.test.settings"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.showSettings() }
            }
            DistributedNotificationCenter.default().addObserver(
                forName: .init("dev.maciek.mycapture.test.thumbnail"), object: nil, queue: .main
            ) { [weak self] note in
                let action = note.userInfo?["action"] as? String
                MainActor.assumeIsolated { self?.testThumbnailAction(action) }
            }
        }
        FreezeOverlay.warmUp()
        // Permission changes happen in System Settings; refresh what the menu and Settings show.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        // Registers the global shortcuts.
        _ = (areaShortcut, clipboardShortcut, windowShortcut, restoreShortcut)
        // Thumbnails on screen at quit come back, if their files are still there.
        let data = Self.uiTest ? nil : UserDefaults.standard.data(forKey: "thumbnails")
        if let data {
            // A list this version cannot read (an older format) keeps its files rather than deleting them.
            if let saved = try? JSONDecoder().decode(ThumbnailList.self, from: data) {
                var list = ThumbnailList()
                saved.visible.filter { FileManager.default.fileExists(atPath: $0.file.path(percentEncoded: false)) }.forEach { list.add($0) }
                thumbnails = list
            }
        } else {
            files.purge(keeping: [])
        }
        if Self.uiTest {
            DistributedNotificationCenter.default().addObserver(
                forName: .init("dev.maciek.mycapture.test.capture"), object: nil, queue: .main
            ) { [weak self] note in
                let mode = note.userInfo?["mode"] as? String ?? "area"
                let numbers = (note.userInfo?["rect"] as? String ?? "").split(separator: ",").compactMap { Double($0) }
                guard numbers.count == 4 else { return }
                let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                MainActor.assumeIsolated {
                    self?.capture(mode == "window" ? .window : .area, to: mode == "clipboard" ? .clipboard : .thumbnail, testRect: rect)
                }
            }
        }
    }

    // MARK: Capture

    func capture(_ mode: CaptureMode, to destination: CaptureDestination, testRect: CGRect? = nil) {
        guard !capturing else { return }
        screenRecordingAllowed = CGPreflightScreenCaptureAccess()
        guard screenRecordingAllowed else {
            CGRequestScreenCaptureAccess()
            // A click on the warning opens the System Settings pane.
            ToastPanel.show(
                "Allow Screen Recording", systemImage: "exclamationmark.triangle.fill", at: Self.mouseLocation(), warning: true,
                action: { SystemSettingsPane.screenRecording.open() })
            return
        }
        capturing = true
        stack.setCapturing(true)
        Task {
            defer {
                capturing = false
                stack.setCapturing(false)
                purgeTemp()
            }
            do {
                let session = CaptureSession(files: files, freezeScreen: freezeScreen)
                guard var capture = try await session.run(mode, sound: playSound, testRect: testRect) else { return }
                // A capture under its temp name is better than a lost one.
                do {
                    try files.applyName(to: &capture)
                } catch {
                    log.error("rename failed: \(error.localizedDescription, privacy: .public)")
                }
                if Self.uiTest { writeTestReport(capture) }
                switch destination {
                case .thumbnail:
                    thumbnails.add(capture, limit: stack.limit)
                case .clipboard:
                    clipboardCapture = capture
                    let point = capture.rect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? Self.mouseLocation()
                    if copy(capture) {
                        ToastPanel.show("Copied", at: point)
                    } else {
                        warn("Could not copy the capture", at: point)
                    }
                }
            } catch {
                log.error("capture failed: \(error.localizedDescription, privacy: .public)")
                warn("Capture failed: \(error.localizedDescription)", at: Self.mouseLocation())
            }
        }
    }

    /// The clipboard gets the file and the image, as in CleanShot X: Finder and chat apps paste a file,
    /// image editors paste the picture.
    @discardableResult
    func copy(_ capture: Capture) -> Bool {
        guard let data = try? Data(contentsOf: capture.file), let image = NSImage(data: data) else { return false }
        let item = NSPasteboardItem()
        item.setString(capture.file.absoluteString, forType: .fileURL)
        item.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    func restoreLast() {
        // A restored thumbnail during a capture would show in it.
        guard !capturing else { return }
        if thumbnails.restoreLast(limit: stack.limit) == nil {
            ToastPanel.show("Nothing to restore", systemImage: "clock.arrow.circlepath", at: Self.mouseLocation())
        }
    }

    /// Saves to the screenshots folder; the thumbnail shows a checkmark and closes.
    private func save(_ capture: Capture) -> Bool {
        do {
            try files.save(capture, to: saveFolder)
            return true
        } catch {
            warn("Could not save: \(error.localizedDescription)", at: stack.center(of: capture) ?? Self.mouseLocation())
            return false
        }
    }

    /// ⌥-click on Save: asks where to save, then closes the thumbnail.
    private func saveAs(_ capture: Capture) {
        AppWindows.activate()
        let panel = NSSavePanel()
        panel.directoryURL = saveFolder
        panel.nameFieldStringValue = capture.file.lastPathComponent
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Copy first, then swap: a failed copy must not delete the file already there.
            let copy = capture.file.deletingLastPathComponent().appending(path: "save-as.png")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: capture.file, to: copy)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: copy)
            } else {
                try FileManager.default.moveItem(at: copy, to: url)
            }
            thumbnails.close(capture.id)
        } catch {
            warn("Could not save: \(error.localizedDescription)", at: Self.mouseLocation())
        }
    }

    /// Never during a capture: the folder `screencapture` writes into is not in any list yet.
    private func purgeTemp() {
        guard !capturing else { return }
        files.purge(keeping: thumbnails.all + (clipboardCapture.map { [$0] } ?? []))
    }

    // MARK: Menu actions

    func showSettings() {
        settingsWindow.show()
    }

    func openSaveFolder() {
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(saveFolder)
    }

    func chooseSaveFolder() {
        AppWindows.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveFolder = url
    }

    func refreshPermissions() {
        screenRecordingAllowed = CGPreflightScreenCaptureAccess()
    }

    /// Test runs act on the newest thumbnail: close, restore, save (into the `-saveFolder` launch argument) or Save As.
    private func testThumbnailAction(_ action: String?) {
        switch action {
        case "close": thumbnails.visible.last.map { thumbnails.close($0.id) }
        case "restore": restoreLast()
        case "save":
            // As the Save button does: save, then close the thumbnail.
            if let capture = thumbnails.visible.last, save(capture) { thumbnails.close(capture.id) }
        case "saveas": thumbnails.visible.last.map(saveAs)
        default: break
        }
    }

    /// Test runs read the last capture record from `last-capture.json` in the temp folder.
    private func writeTestReport(_ capture: Capture) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(capture).write(to: files.tempFolder.appending(path: "last-capture.json"))
    }

    private func warn(_ text: String, at point: CGPoint) {
        ToastPanel.show(text, systemImage: "exclamationmark.triangle.fill", at: point, warning: true)
    }

    private static func shortcut(_ keyCode: Int) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: [.control, .shift, .command])
    }

    /// The mouse in global top-left coordinates.
    private static func mouseLocation() -> CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }
}
