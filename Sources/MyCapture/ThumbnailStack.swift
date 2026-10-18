import AppKit
import Carbon.HIToolbox
import MyCaptureCore
import MyKit
import SwiftUI

/// What a thumbnail can do. The app model owns the captures; the stack only shows them.
/// Copy and Save return true when they worked, so the thumbnail can show a checkmark and close.
struct ThumbnailActions {
    var copy: (Capture) -> Bool
    var save: (Capture) -> Bool
    var saveAs: (Capture) -> Void
    var close: (Capture) -> Void
    var annotate: (Capture) -> Void
    var preview: (Capture) -> Void
    /// Set by the stack: makes the keys of the hovered thumbnail, or nil when the pointer leaves it.
    var hoverKeys: (Capture.ID, (() -> HoverKeys)?) -> Void = { _, _ in }
}

/// The floating thumbnails: a fixed landscape box, bottom-left of the display the mouse is on,
/// newest on top. They never take focus, so typing in the user's app goes on.
final class ThumbnailStack {
    static let sideMargin: CGFloat = 40
    static let bottomMargin: CGFloat = 100
    static let gap: CGFloat = 10

    private var panels: [Capture.ID: ThumbnailPanel] = [:]
    private var order: [Capture.ID] = []
    /// What `show` got last, to rebuild the panels for another box size.
    private var captures: [Capture] = []
    private var capturing = false
    private let actions: ThumbnailActions
    private var screen: NSScreen?
    private var followTimer: Timer?
    /// Global keys of the hovered thumbnail. Released when it closes: a closing window gets no "mouse left" event.
    private var hovered: (id: Capture.ID, keys: HoverKeys)?

    init(actions: ThumbnailActions) {
        self.actions = actions
    }

    /// The box for a display: 210 × 150 on displays taller than 900 pt, else 168 × 120.
    static func boxSize(on screen: NSScreen) -> CGSize {
        screen.frame.height > 900 ? CGSize(width: 210, height: 150) : CGSize(width: 168, height: 120)
    }

    /// How many thumbnails fit above each other on the display the mouse is on.
    var limit: Int {
        let screen = Self.mouseScreen()
        let box = Self.boxSize(on: screen)
        return max(Int((screen.visibleFrame.height - Self.bottomMargin) / (box.height + Self.gap)), 1)
    }

    /// Shows exactly these captures, oldest first.
    func show(_ captures: [Capture]) {
        self.captures = captures
        let ids = Set(captures.map(\.id))
        if let hovered, !ids.contains(hovered.id) { self.hovered = nil }
        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        let screen = Self.mouseScreen()
        for capture in captures where panels[capture.id] == nil {
            guard let image = NSImage(contentsOf: capture.file) else { continue }
            var panelActions = actions
            panelActions.hoverKeys = { [weak self] id, keys in self?.setHoverKeys(id, keys) }
            let panel = ThumbnailPanel(capture: capture, image: image, box: Self.boxSize(on: screen), actions: panelActions)
            apply(capturing, to: panel)
            panels[capture.id] = panel
        }
        order = captures.map(\.id).filter { panels[$0] != nil }
        if TestHover.enabled { TestHover.shared.id = order.last }
        layout(on: screen)
        followMouse(order.isEmpty == false)
    }

    /// Shows the capture's file again after it changed (an annotation was saved).
    func reload(_ id: Capture.ID) {
        guard let panel = panels[id] else { return }
        if hovered?.id == id { hovered = nil }
        panel.orderOut(nil)
        panels[id] = nil
        show(captures)
    }

    /// During a capture the thumbnails stay on screen above the freeze, but out of the captured image.
    func setCapturing(_ capturing: Bool) {
        self.capturing = capturing
        // Space and Esc must reach the capture tool.
        if capturing { hovered = nil }
        panels.values.forEach { apply(capturing, to: $0) }
    }

    private func apply(_ capturing: Bool, to panel: ThumbnailPanel) {
        panel.sharingType = capturing ? .none : .readOnly
        panel.level = capturing ? FreezeOverlay.overlayLevel : .statusBar
    }

    private func setHoverKeys(_ id: Capture.ID, _ makeKeys: (() -> HoverKeys)?) {
        if let makeKeys {
            // Release the old keys first: the system refuses a key that is still registered.
            hovered = nil
            hovered = (id, makeKeys())
        } else if hovered?.id == id {
            hovered = nil
        }
    }

    /// The screen point (global top-left) at the center of a capture's thumbnail, for toasts.
    func center(of capture: Capture) -> CGPoint? {
        guard let frame = panels[capture.id]?.boxFrame else { return nil }
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: frame.midX, y: height - frame.midY)
    }

    private func layout(on screen: NSScreen) {
        self.screen = screen
        let box = Self.boxSize(on: screen)
        var y = screen.frame.minY + Self.bottomMargin
        // Newest on top: the oldest sits lowest.
        for id in order {
            guard let panel = panels[id] else { continue }
            panel.place(box: CGRect(x: screen.frame.minX + Self.sideMargin, y: y, width: box.width, height: box.height))
            y += box.height + Self.gap
        }
    }

    /// Thumbnails move to the display the mouse is on, checked every second.
    private func followMouse(_ active: Bool) {
        guard active else {
            followTimer?.invalidate()
            followTimer = nil
            return
        }
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let screen = Self.mouseScreen()
                guard screen != self.screen else { return }
                if let old = self.screen, Self.boxSize(on: old) != Self.boxSize(on: screen) {
                    // The panels draw a fixed box: build them again in the other size.
                    self.hovered = nil
                    self.panels.values.forEach { $0.orderOut(nil) }
                    self.panels = [:]
                    self.show(self.captures)
                } else {
                    self.layout(on: screen)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private static func mouseScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// One thumbnail window. It is larger than the box by `margin`, so the drop shadow has room.
final class ThumbnailPanel: OverlayPanel {
    static let margin: CGFloat = 32

    private(set) var boxFrame: CGRect = .zero
    private var drag: DragSource?

    init(capture: Capture, image: NSImage, box: CGSize, actions: ThumbnailActions) {
        super.init()
        let view = ThumbnailView(capture: capture, image: image, box: box, actions: actions)
            .padding(Self.margin)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        contentView = host
        let drag = DragSource(window: self)
        // A press on the image itself, where the mouse area gets it: not on the margin or a button.
        drag.items = { [weak self] point in
            guard self?.contentView?.hitTest(point) is MouseAreaView else { return [] }
            return [DragItem(writer: capture.file as NSURL, image: image)]
        }
        // After a drop the thumbnail closes; with ⌥ held it stays.
        drag.onEnd = { dropped in
            if dropped, !NSEvent.modifierFlags.contains(.option) { actions.close(capture) }
        }
        self.drag = drag
    }

    func place(box: CGRect) {
        boxFrame = box
        let frame = box.insetBy(dx: -Self.margin, dy: -Self.margin)
        if isVisible {
            // animator(): `animate: true` blocks the main thread for each panel in turn.
            animator().setFrame(frame, display: true)
        } else {
            setFrame(frame, display: false)
            orderFrontRegardless()
        }
    }
}

/// `-thumbnailHover YES` in test runs: the newest thumbnail shows its hover look without a pointer, for screenshots.
@Observable
final class TestHover {
    static let shared = TestHover()
    static let enabled = AppModel.uiTest && UserDefaults.standard.bool(forKey: "thumbnailHover")
    var id: Capture.ID?
}

@Observable
final class ThumbnailState {
    var hovering = false
    /// The button that just worked (Copy or Save): it shows a checkmark before the thumbnail closes.
    var done: String?
}

/// A capture: the image fills a rounded box. On hover, dark glass covers the image, with
/// Copy and Save in the center, Close at the top-left and Annotate at the bottom-left, in light frosted buttons.
struct ThumbnailView: View {
    /// Corner buttons sit this far in from the box edge.
    static let cornerInset: CGFloat = 6
    /// Between Copy and Save.
    static let buttonGap: CGFloat = 10
    /// The curtain sits 1 pt inside the box's corner.
    static let curtainRadius: CGFloat = .radiusThumbnail - 1

    let capture: Capture
    let image: NSImage
    let box: CGSize
    let actions: ThumbnailActions
    @State private var state = ThumbnailState()

    var body: some View {
        ZStack {
            Checkerboard()
            Image(nsImage: image).resizable().scaledToFill().frame(width: box.width, height: box.height).clipped()
            if hovering || state.done != nil {
                Color.clear.curtainSurface(cornerRadius: Self.curtainRadius).transition(.opacity)
            }
            MouseArea(onHover: hover, onDoubleClick: { actions.annotate(capture) }, menu: contextMenu)
            if hovering || state.done != nil {
                controls.transition(.opacity)
            }
        }
        .frame(width: box.width, height: box.height)
        .clipShape(.rect(cornerRadius: .radiusThumbnail))
        .overlay(RoundedRectangle(cornerRadius: .radiusThumbnail).strokeBorder(.gray.opacity(0.4)))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 15)
        .animation(.quick, value: hovering)
        .animation(.quick, value: state.done)
    }

    private var hovering: Bool { state.hovering || TestHover.shared.id == capture.id }

    private var controls: some View {
        ZStack {
            VStack(spacing: Self.buttonGap) {
                Button(action: copy) { title("Copy") }
                    .help("Copy to the clipboard (⌘C); ⌥-click keeps the thumbnail")
                Button(action: save) { title("Save") }
                    .help("Save to the screenshots folder (⌘S); ⌥-click to choose where")
            }
            .buttonStyle(.overlay)
            VStack {
                Button {
                    actions.close(capture)
                } label: {
                    ControlGlyph.close
                }
                .accessibilityLabel("Close")
                .help("Close (Esc)")
                Spacer()
                Button {
                    actions.annotate(capture)
                } label: {
                    ControlGlyph.pencil
                }
                .accessibilityLabel("Annotate")
                .help("Annotate")
            }
            .buttonStyle(.overlayIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Self.cornerInset)
        }
    }

    /// A button title; after it worked, a checkmark before it.
    private func title(_ text: String) -> some View {
        HStack(spacing: .space1) {
            if state.done == text { Image(systemName: "checkmark") }
            Text(text)
        }
    }

    /// Copy closes the thumbnail after a short checkmark; with ⌥ held it stays.
    private func copy() {
        let keepOpen = NSEvent.modifierFlags.contains(.option)
        guard actions.copy(capture) else { return }
        finish("Copy", close: !keepOpen)
    }

    /// Save closes the thumbnail after a short checkmark; with ⌥ held it asks where to save instead.
    private func save() {
        if NSEvent.modifierFlags.contains(.option) {
            actions.saveAs(capture)
        } else if actions.save(capture) {
            finish("Save", close: true)
        }
    }

    private func finish(_ button: String, close: Bool) {
        state.done = button
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            if close { actions.close(capture) } else { state.done = nil }
        }
    }

    private func hover(_ inside: Bool) {
        state.hovering = inside
        // While the pointer rests on a thumbnail, these keys act on it without clicking.
        actions.hoverKeys(
            capture.id,
            inside
                ? {
                    HoverKeys(
                        preview: { actions.preview(capture) }, close: { actions.close(capture) }, copy: { copy() }, save: { save() })
                }
                : nil)
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureMenuItem("Annotate") { actions.annotate(capture) })
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("Copy") { copy() })
        menu.addItem(closureMenuItem("Save") { save() })
        menu.addItem(closureMenuItem("Save As…") { actions.saveAs(capture) })
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("Close") { actions.close(capture) })
        return menu
    }
}
