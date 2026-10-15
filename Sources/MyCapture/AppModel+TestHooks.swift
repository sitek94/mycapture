import AppKit
import MyCaptureCore
import MyKit

// Test runs only (`-uiTest YES`): the driver's requests, as distributed notifications.
extension AppModel {
    /// Test runs act on the newest thumbnail: close, restore, save (into the `-saveFolder` launch argument) or Save As;
    /// `add` takes a copy of the image `file` as a new capture from Finder: a thumbnail and a history entry.
    func testThumbnailAction(_ action: String?, file: String?) {
        switch action {
        case "add":
            guard let file, let copy = try? files.newTempFile() else { return }
            try? FileManager.default.copyItem(at: URL(filePath: file), to: copy)
            let capture = Capture(file: copy, date: .now, kind: .selection, rect: nil, app: "Finder")
            history.add(capture)
            showThumbnail(capture)
        case "close": thumbnails.visible.last.map { closeThumbnail($0.id) }
        case "restore": restoreLast()
        case "save": _ = thumbnails.visible.last.map(saveAndClose)
        case "saveas": _ = thumbnails.visible.last.map(saveAs)
        case "editor": thumbnails.visible.last.map(annotate)
        default: break
        }
    }

    /// Test runs act on the editor: `open <png>` (a copy of any image), `drag x1 y1 x2 y2` (image pixels, through the canvas's mouse
    /// handlers), `save` (to the screenshots folder), `close`, `activate`, and `report`, which writes `editor.json` (file, markups, unsaved changes, selection).
    func testEditorAction(_ args: [String]) {
        if args.first == "open", args.count == 2 {
            guard let file = try? files.newTempFile() else { return }
            try? FileManager.default.copyItem(at: URL(filePath: args[1]), to: file)
            annotate(Capture(file: file, date: .now, kind: .selection, rect: nil))
            return
        }
        guard let editor = editors.values.first else {
            try? Data("{}".utf8).write(to: files.tempFolder.appending(path: "editor.json"))
            return
        }
        switch args.first {
        case "drag":
            let numbers = args.dropFirst().compactMap { Double($0) }
            guard numbers.count == 4 else { return }
            editor.testDrag(from: CGPoint(x: numbers[0], y: numbers[1]), to: CGPoint(x: numbers[2], y: numbers[3]))
        case "save": editor.save()
        case "close": editor.window?.performClose(nil)
        // Takes focus back, in case the user's own app took it during the run.
        case "activate": AppWindows.activate()
        case "report":
            let report: [String: Any] = [
                "file": editor.model.capture.file.path(percentEncoded: false), "markups": editor.model.editor.markups.count,
                "modified": editor.model.editor.isModified, "selected": editor.model.editor.selection != nil,
            ]
            try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys).write(to: files.tempFolder.appending(path: "editor.json"))
        default: break
        }
    }

    /// Test runs only: the driver's requests arrive as distributed notifications.
    func startTestHooks() {
        onTestRequest("settings") { [weak self] in self?.showSettings(pane: $0["pane"]) }
        onTestRequest("thumbnail") { [weak self] in self?.testThumbnailAction($0["action"], file: $0["file"]) }
        onTestRequest("editor") { [weak self] in
            self?.testEditorAction(($0["args"] ?? "").split(separator: " ").map(String.init))
        }
        onTestRequest("history") { [weak self] in self?.testHistoryAction($0["action"]) }
        onTestRequest("capture") { [weak self] info in
            let mode = info["mode"] ?? "area"
            let numbers = (info["rect"] ?? "").split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 4 else { return }
            let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            self?.capture(mode == "window" ? .window : .area, to: mode == "clipboard" ? .clipboard : .thumbnail, testRect: rect)
        }
    }

    /// The driver sends only strings.
    private func onTestRequest(_ name: String, _ handle: @escaping @MainActor @Sendable ([String: String]) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("dev.maciek.mycapture.test.\(name)"), object: nil, queue: .main
        ) { note in
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { handle(info) }
        }
    }

    /// Test runs: `toggle` the history panel, `restore` its selection, `report` writes `history.json` (count, open).
    func testHistoryAction(_ action: String?) {
        switch action {
        case "toggle": history.toggle()
        case "restore": history.selected.map(history.restore)
        case "report":
            let report: [String: Any] = ["count": history.entries.count, "open": history.isOpen]
            try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys).write(to: files.tempFolder.appending(path: "history.json"))
        default: break
        }
    }
}
