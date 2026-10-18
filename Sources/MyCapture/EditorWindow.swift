import AppKit
import ImageIO
import MyCaptureCore
import MyKit
import SwiftUI

/// What the editor needs from the app.
struct EditorActions {
    /// After the capture file changed: the thumbnail shows the new image.
    var saved: (Capture) -> Void
    /// Copies the capture file and image; true when it worked.
    var copy: (Capture) -> Bool
    /// Saves a copy to the screenshots folder and closes the thumbnail; true when saved.
    var save: (Capture) -> Bool
    /// Asks where to save a copy; true when saved.
    var saveAs: (Capture) -> Bool
    var closed: (Capture) -> Void
}

/// The editor's state for one capture: the pixels, the markups and the style for new ones.
@Observable
final class EditorModel {
    /// Line widths offered, in points; the saved width is in image pixels (points × the capture's scale).
    static let widths: [Double] = [2, 3, 4, 6, 9, 14]

    private(set) var editor: AnnotationEditor
    /// Bumped on every change, so the canvas redraws.
    private(set) var revision = 0
    /// ⌥ is down while the window is key: Save As… shows as Save.
    var optionHeld = false
    let capture: Capture
    let image: CGImage
    let properties: [CFString: Any]
    /// Image pixels per point: 2 for a Retina capture.
    let scale: Double
    /// The Drag Me button in the window content, from its top-left.
    @ObservationIgnored var dragOutFrame: CGRect = .zero

    init?(capture: Capture) {
        let store = AnnotationStore(file: capture.file)
        guard let loaded = store.loadImage() else { return nil }
        self.capture = capture
        image = loaded.image
        properties = loaded.properties
        scale = max((loaded.properties[kCGImagePropertyDPIWidth] as? Double ?? 72) / 72, 1)
        let defaults = UserDefaults.standard
        let colorName = defaults.string(forKey: "markupColor")
        let color = MarkupColor.palette.first { $0.name == colorName }?.color ?? MarkupColor.palette[0].color
        let width = defaults.object(forKey: "markupWidth") as? Double ?? 4
        editor = AnnotationEditor(markups: store.loadMarkups(), color: color, width: width * scale)
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    /// The width for new markups, in points.
    var width: Double { editor.width / scale }

    func change(_ body: (inout AnnotationEditor) -> Void) {
        body(&editor)
        revision += 1
    }

    func setColor(_ entry: (name: String, color: MarkupColor)) {
        UserDefaults.standard.set(entry.name, forKey: "markupColor")
        change { $0.setColor(entry.color) }
    }

    func setWidth(_ points: Double) {
        UserDefaults.standard.set(points, forKey: "markupWidth")
        change { $0.setWidth(points * scale) }
    }

    func save() throws {
        try AnnotationStore(file: capture.file).save(editor.markups, image: image, properties: properties)
        change { $0.markSaved() }
    }
}

/// The annotation editor: one window per capture, with a Dock icon while it is open.
final class EditorWindow: NSWindowController, NSWindowDelegate {
    let model: EditorModel
    private let actions: EditorActions
    private var drag: DragSource?

    init?(capture: Capture, actions: EditorActions) {
        guard let model = EditorModel(capture: capture) else { return nil }
        self.model = model
        self.actions = actions
        let window = EditorPanel()
        super.init(window: window)
        let host = NSHostingController(rootView: EditorView(model: model, commands: commands))
        host.sceneBridgingOptions = [.toolbars]
        window.contentViewController = host
        // The title is hidden, as the tools fill the title bar; it still names the window in the Window menu and Mission Control.
        window.title = capture.file.deletingPathExtension().lastPathComponent
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // The bars' material shows through the title bar, as one surface.
        window.titlebarAppearsTransparent = true
        window.contentMinSize = CGSize(width: 990, height: 400)
        window.delegate = self
        window.editor = self
        let drag = DragSource(window: window)
        drag.items = { [weak self] point in self?.dragItems(at: point) ?? [] }
        self.drag = drag
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var commands: EditorCommands {
        EditorCommands(
            copy: { [weak self] in self?.copyCapture() },
            save: { [weak self] in self?.save() },
            saveAs: { [weak self] in self?.saveAs() },
            saveOrSaveAs: { [weak self] in self?.saveOrSaveAs() },
            close: { [weak self] in self?.window?.performClose(nil) })
    }

    /// A press on Drag Me drags the file, with the changes saved into it first.
    private func dragItems(at point: CGPoint) -> [DragItem] {
        guard let drag, model.dragOutFrame.contains(drag.contentPoint(point)) else { return [] }
        if model.editor.isModified { saveInPlace() }
        let file = model.capture.file
        return [DragItem(writer: file as NSURL, image: NSImage(contentsOf: file) ?? NSImage())]
    }

    /// The first show centers the window and gives the app a Dock icon; later ones only bring it to the front.
    func show() {
        guard let window else { return }
        if window.isVisible {
            AppWindows.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            AppWindows.show(window, size: Self.initialSize(for: model))
        }
    }

    /// The image at 100 % (one image point per screen point), made smaller to fit the screen; at least 990 x 500.
    private static func initialSize(for model: EditorModel) -> CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let image = CGSize(width: model.imageSize.width / model.scale, height: model.imageSize.height / model.scale)
        let padding = EditorCanvas.padding * 2
        let chrome = EditorView.Metrics.chrome
        let fit = min(1, (screen.width * 0.95 - padding) / image.width, ((screen.height - chrome) * 0.95 - padding) / image.height)
        return CGSize(width: max(image.width * fit + padding, 990), height: max(image.height * fit + padding + chrome, 500))
    }

    // MARK: Actions

    /// Copies the capture, then closes; with ⌥ held the editor stays.
    func copyCapture() {
        if model.editor.isModified, !saveInPlace() { return }
        guard actions.copy(model.capture) else {
            warn("Could not copy the capture")
            return
        }
        if NSEvent.modifierFlags.contains(.option) {
            ToastPanel.show("Copied", at: toastPoint)
        } else {
            window?.close()
        }
    }

    /// The main button: Save As…, or Save while ⌥ is held.
    func saveOrSaveAs() {
        if NSEvent.modifierFlags.contains(.option) { save() } else { saveAs() }
    }

    /// Saves a copy to the screenshots folder, then closes.
    func save() {
        if model.editor.isModified, !saveInPlace() { return }
        if actions.save(model.capture) { window?.close() }
    }

    /// Saves a copy where the user picks, then closes.
    func saveAs() {
        if model.editor.isModified, !saveInPlace() { return }
        if actions.saveAs(model.capture) { window?.close() }
    }

    /// Writes the markups into the capture, so the thumbnail, Copy and a drag show them.
    @discardableResult
    func saveInPlace() -> Bool {
        do {
            try model.save()
            actions.saved(model.capture)
            return true
        } catch {
            warn("Could not save: \(error.localizedDescription)")
            return false
        }
    }

    /// Test runs: a drag through the canvas's own mouse handlers.
    func testDrag(from start: CGPoint, to end: CGPoint) {
        let canvas = window?.contentView.flatMap { CanvasView.find(in: $0) }
        canvas?.simulateDrag(from: start, to: end)
    }

    // MARK: Window

    /// Every close keeps the changes, without a question: the markups stay editable, so nothing is lost.
    /// The window stays open only when the save fails.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !model.editor.isModified || saveInPlace()
    }

    func windowDidResignKey(_ notification: Notification) {
        model.optionHeld = false
    }

    func windowWillClose(_ notification: Notification) {
        actions.closed(model.capture)
    }

    private var toastPoint: CGPoint {
        let frame = window?.frame ?? .zero
        return CGPoint(x: frame.midX, y: (NSScreen.screens.first?.frame.height ?? 0) - frame.midY)
    }

    private func warn(_ text: String) {
        ToastPanel.show(text, systemImage: "exclamationmark.triangle.fill", at: toastPoint, warning: true)
    }
}

/// The editor's window commands, for the toolbar, the keys and the canvas menu.
struct EditorCommands {
    var copy: () -> Void
    var save: () -> Void
    var saveAs: () -> Void
    /// The main button: Save As…, or Save with ⌥ held.
    var saveOrSaveAs: () -> Void
    var close: () -> Void
}

/// The editor window. ⌘ keys reach it before the app's menu, which has no File menu in a menu bar app.
final class EditorPanel: NSWindow {
    weak var editor: EditorWindow?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        isReleasedWhenClosed = false
        toolbarStyle = .unified
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor, let key = EditorKey(event) else { return super.performKeyEquivalent(with: event) }
        let model = editor.model
        switch key {
        case .undo: model.change { $0.undo() }
        case .redo: model.change { $0.redo() }
        case .save: editor.save()
        case .saveAs: editor.saveAs()
        case .close, .quit: performClose(nil)
        case .copy: editor.copyCapture()
        }
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        editor?.model.optionHeld = event.modifierFlags.contains(.option)
        super.flagsChanged(with: event)
    }
}

/// The ⌘ keys of the editor. The canvas menu shows the same keys.
/// ⌘ Q closes the editor only: quitting the app would also stop its global shortcuts.
enum EditorKey {
    case undo, redo, save, saveAs, close, quit, copy

    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags.subtracting(.capsLock), key) {
        case ([.command], "z"): self = .undo
        case ([.command, .shift], "z"): self = .redo
        case ([.command], "s"): self = .save
        case ([.command, .shift], "s"): self = .saveAs
        case ([.command], "w"): self = .close
        case ([.command], "q"): self = .quit
        case ([.command, .shift], "c"): self = .copy
        default: return nil
        }
    }
}
