import AppKit
import Carbon.HIToolbox
import MyCaptureCore
import MyKit
import SwiftUI

/// The drawing area. Markups are stored in image pixels; the view fits the image into its bounds and converts.
struct EditorCanvas: NSViewRepresentable {
    /// Space around the image, in points.
    static let padding: CGFloat = .space6

    let model: EditorModel
    let commands: EditorCommands
    /// Read here so SwiftUI calls `updateNSView` after each change.
    let revision: Int

    func makeNSView(context: Context) -> CanvasView {
        CanvasView(model: model, commands: commands)
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.needsDisplay = true
        // The cursor follows the tool.
        view.window?.invalidateCursorRects(for: view)
    }
}

final class CanvasView: NSView {
    /// Screen sizes in points; divided by the zoom they become image pixels.
    static let tolerance: CGFloat = 6
    static let handleSize: CGFloat = 14
    static let minimumDrag: CGFloat = 4
    static let selectionHalo: CGFloat = 3

    private let model: EditorModel
    private let commands: EditorCommands

    init(model: EditorModel, commands: EditorCommands) {
        self.model = model
        self.commands = commands
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: model.editor.tool == .move ? .arrow : .crosshair)
    }

    // MARK: Geometry

    /// View points per image pixel: the image fits the view, and is never larger than 100 % (its point size).
    private var zoom: CGFloat {
        let size = model.imageSize
        let available = bounds.insetBy(dx: EditorCanvas.padding, dy: EditorCanvas.padding).size
        return max(min(available.width / size.width, available.height / size.height, 1 / model.scale), 0.01)
    }

    private var imageRect: CGRect {
        let size = CGSize(width: model.imageSize.width * zoom, height: model.imageSize.height * zoom)
        return CGRect(
            x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        return CGPoint(x: (point.x - rect.minX) / zoom, y: (point.y - rect.minY) / zoom)
    }

    private var metrics: AnnotationEditor.Metrics {
        AnnotationEditor.Metrics(
            tolerance: Self.tolerance / zoom, handleRadius: Self.handleSize / zoom, minimumSize: Self.minimumDrag / zoom)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        CanvasStyle.background.setFill()
        bounds.fill()
        let rect = imageRect
        // A small shadow under the image lifts it off the canvas. CG blur 6 renders as an NSShadow blur radius of 3 (measured).
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(rect)
        context.restoreGState()
        Checkerboard.draw(in: context, rect: rect)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: zoom, y: zoom)
        // CGImage draws with a bottom-left origin.
        context.saveGState()
        context.translateBy(x: 0, y: model.imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(model.image, in: CGRect(origin: .zero, size: model.imageSize))
        context.restoreGState()
        // Only what is on the image is saved: show the same.
        context.clip(to: CGRect(origin: .zero, size: model.imageSize))
        if let selected = model.editor.selected { drawHalo(selected, in: context) }
        MarkupRenderer.draw(model.editor.markups, in: context, deviceScale: zoom * (window?.backingScaleFactor ?? 2))
        context.restoreGState()
        if let selected = model.editor.selected { drawHandles(selected, in: rect) }
    }

    /// A soft outline in the accent color around the selected markup.
    private func drawHalo(_ markup: Markup, in context: CGContext) {
        guard case .arrow(let start, let end) = markup.shape else { return }
        let path = ArrowPath.path(from: start, to: end, width: markup.width)
        context.saveGState()
        context.addPath(path.copy(strokingWithWidth: Self.selectionHalo * 2 / zoom, lineCap: .round, lineJoin: .round, miterLimit: 1))
        context.setFillColor(CanvasStyle.halo.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    /// Round handles at the points a drag can move.
    private func drawHandles(_ markup: Markup, in rect: CGRect) {
        for (_, point) in markup.handles {
            let center = CGPoint(x: rect.minX + point.x * zoom, y: rect.minY + point.y * zoom)
            let size = Self.handleSize
            let circle = NSBezierPath(ovalIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = .shadowColor.withAlphaComponent(0.4)
            shadow.set()
            CanvasStyle.handle.setFill()
            circle.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke()
            circle.lineWidth = 2
            circle.stroke()
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        model.change { $0.mouseDown(at: imagePoint(event), metrics: metrics, duplicate: event.modifierFlags.contains(.option)) }
    }

    override func mouseDragged(with event: NSEvent) {
        model.change { $0.mouseDragged(to: imagePoint(event), constrain: event.modifierFlags.contains(.shift)) }
    }

    override func mouseUp(with event: NSEvent) {
        model.change { $0.mouseUp(metrics: metrics) }
    }

    /// Test runs: mouse down, drag and up between two image points, as real events to the handlers above.
    func simulateDrag(from start: CGPoint, to end: CGPoint) {
        let rect = imageRect
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent? {
            let local = CGPoint(x: rect.minX + point.x * zoom, y: rect.minY + point.y * zoom)
            return NSEvent.mouseEvent(
                with: type, location: convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window?.windowNumber ?? 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        event(.leftMouseDown, start).map(mouseDown)
        event(.leftMouseDragged, end).map(mouseDragged)
        event(.leftMouseUp, end).map(mouseUp)
    }

    static func find(in view: NSView) -> CanvasView? {
        if let canvas = view as? CanvasView { return canvas }
        return view.subviews.lazy.compactMap { find(in: $0) }.first
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let editor = model.editor
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Undo", key: "z", enabled: editor.canUndo) { [model] in model.change { $0.undo() } })
        menu.addItem(item("Redo", key: "z", modifiers: [.command, .shift], enabled: editor.canRedo) { [model] in model.change { $0.redo() } })
        menu.addItem(.separator())
        menu.addItem(
            item("Delete", key: "\u{8}", modifiers: [], enabled: editor.selection != nil) { [model] in model.change { $0.deleteSelection() } })
        menu.addItem(.separator())
        menu.addItem(item("Copy", key: "c", modifiers: [.command, .shift], action: commands.copy))
        menu.addItem(item("Save", key: "s", action: commands.save))
        menu.addItem(item("Save As…", key: "s", modifiers: [.command, .shift], action: commands.saveAs))
        menu.addItem(item("Close", key: "w", action: commands.close))
        return menu
    }

    private func item(
        _ title: String, key: String, modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true, action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = closureMenuItem(title, handler: action)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = enabled
        return item
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        guard flags.isEmpty else { return super.keyDown(with: event) }
        let step = (event.modifierFlags.contains(.shift) ? 10 : 1) * model.scale
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete: model.change { $0.deleteSelection() }
        case kVK_LeftArrow: model.change { $0.nudgeSelection(by: CGVector(dx: -step, dy: 0)) }
        case kVK_RightArrow: model.change { $0.nudgeSelection(by: CGVector(dx: step, dy: 0)) }
        case kVK_UpArrow: model.change { $0.nudgeSelection(by: CGVector(dx: 0, dy: -step)) }
        case kVK_DownArrow: model.change { $0.nudgeSelection(by: CGVector(dx: 0, dy: step)) }
        case kVK_ANSI_A: model.change { $0.tool = .arrow }
        case kVK_ANSI_V: model.change { $0.tool = .move }
        case kVK_Escape: cancelOperation(nil)
        default: super.keyDown(with: event)
        }
    }

    /// Esc: the first one deselects, the next closes the editor (keeping the changes).
    override func cancelOperation(_ sender: Any?) {
        if model.editor.selection != nil {
            model.change { $0.deselect() }
        } else {
            commands.close()
        }
    }
}

extension Checkerboard {
    /// The same pattern as the SwiftUI view, for AppKit drawing.
    static func draw(in context: CGContext, rect: CGRect) {
        let square: CGFloat = 8
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.setFillColor(NSColor.gray.withAlphaComponent(0.25).cgColor)
        for row in 0..<Int(rect.height / square) + 1 {
            for column in 0..<Int(rect.width / square) + 1 where (row + column).isMultiple(of: 2) {
                context.fill(CGRect(x: rect.minX + CGFloat(column) * square, y: rect.minY + CGFloat(row) * square, width: square, height: square))
            }
        }
        context.restoreGState()
    }
}

/// Colors drawn on the canvas, not UI chrome: a fixed blue for selection, so it reads the same on any image and
/// with any system accent.
enum CanvasStyle {
    /// Around the image: a dark gray in dark mode, white in light mode.
    static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.14, green: 0.16, blue: 0.17, alpha: 1) : .white
    }
    static let handle = NSColor(srgbRed: 0, green: 0.52, blue: 1, alpha: 1)
    static let halo = NSColor(srgbRed: 0.3, green: 0.66, blue: 1, alpha: 0.6)
}
