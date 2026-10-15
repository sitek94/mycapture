import AppKit
import Carbon.HIToolbox
import MyKit
import SwiftUI

/// Global keys that act on the hovered thumbnail: Space preview, Esc close, ⌘C copy, ⌘S save, ⌘W close.
/// They exist only while the pointer is on a thumbnail, and are unregistered when it leaves.
@MainActor
final class HoverKeys {
    private static let defaults = UserDefaults(suiteName: "dev.maciek.mycapture.hoverkeys")!
    private let shortcuts: [GlobalShortcut]

    init(preview: @escaping () -> Void, close: @escaping () -> Void, copy: @escaping () -> Void, save: @escaping () -> Void) {
        struct Key {
            let name: String
            let code: Int
            let modifiers: NSEvent.ModifierFlags
            let action: () -> Void
        }
        let keys = [
            Key(name: "preview", code: kVK_Space, modifiers: [], action: preview),
            Key(name: "close", code: kVK_Escape, modifiers: [], action: close),
            Key(name: "copy", code: kVK_ANSI_C, modifiers: .command, action: copy),
            Key(name: "save", code: kVK_ANSI_S, modifiers: .command, action: save),
            Key(name: "closeWindow", code: kVK_ANSI_W, modifiers: .command, action: close),
        ]
        shortcuts = keys.map { key in
            GlobalShortcut(
                name: key.name, default: Shortcut(keyCode: key.code, modifiers: key.modifiers), defaults: Self.defaults,
                action: key.action)
        }
    }
}

/// A light and dark checkerboard under transparent areas of a capture.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0..<Int(size.height / square) + 1 {
                for column in 0..<Int(size.width / square) + 1 where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.25)))
                }
            }
        }
    }
}

/// A menu item that runs a closure. The item keeps its target alive through `representedObject`.
@MainActor
func closureMenuItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let target = MenuTarget(handler: handler)
    let item = NSMenuItem(title: title, action: #selector(MenuTarget.run), keyEquivalent: "")
    item.target = target
    item.representedObject = target
    return item
}

final class MenuTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

/// Mouse handling the SwiftUI layer cannot do in a window that never becomes key: hover, file drag,
/// click, double-click and the right-click menu.
struct MouseArea: NSViewRepresentable {
    let file: URL
    let image: NSImage
    let onHover: (Bool) -> Void
    let onDoubleClick: () -> Void
    /// After a drop; true when ⌥ was held, so the thumbnail stays.
    let onDropped: (Bool) -> Void
    let menu: () -> NSMenu
    var onClick: () -> Void = {}

    func makeNSView(context: Context) -> MouseAreaView {
        MouseAreaView(area: self)
    }

    func updateNSView(_ view: MouseAreaView, context: Context) {
        view.area = self
    }
}

final class MouseAreaView: NSView, NSDraggingSource {
    var area: MouseArea
    private var downEvent: NSEvent?

    init(area: MouseArea) {
        self.area = area
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { area.onHover(true) }
    override func mouseExited(with event: NSEvent) { area.onHover(false) }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 1 { area.onClick() }
        if event.clickCount == 2 { area.onDoubleClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(area.menu(), with: event, for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        let moved = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
        guard moved > 3 else { return }
        downEvent = nil
        let item = NSDraggingItem(pasteboardWriter: area.file as NSURL)
        item.setDraggingFrame(bounds, contents: area.image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        area.onDropped(NSEvent.modifierFlags.contains(.option))
    }
}
