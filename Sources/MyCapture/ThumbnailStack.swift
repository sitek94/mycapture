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
    var open: (Capture) -> Void
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

    init(capture: Capture, image: NSImage, box: CGSize, actions: ThumbnailActions) {
        super.init()
        let view = ThumbnailView(capture: capture, image: image, box: box, actions: actions)
            .padding(Self.margin)
            .tint(.brand)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        contentView = host
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
    /// A short checkmark after Copy or Save worked.
    var done = false
}

struct ThumbnailView: View {
    let capture: Capture
    let image: NSImage
    let box: CGSize
    let actions: ThumbnailActions
    @State private var state = ThumbnailState()

    var body: some View {
        ZStack {
            Checkerboard()
            Image(nsImage: image).resizable().scaledToFill().frame(width: box.width, height: box.height).clipped()
            // On hover the image blurs behind the controls, as in CleanShot X.
            if hovering || state.done {
                Rectangle().fill(.ultraThinMaterial)
            }
            MouseArea(
                file: capture.file, image: image,
                onHover: hover,
                onDoubleClick: { actions.open(capture) },
                onDropped: { keepOpen in if !keepOpen { actions.close(capture) } },
                menu: contextMenu
            )
            if state.done {
                Image(systemName: "checkmark.circle.fill")
                    // swiftlint:disable:next system_font
                    .font(.system(size: 40))  // a symbol used as a picture
                    .foregroundStyle(.white)
            } else if hovering {
                controls.transition(.opacity)
            }
        }
        .frame(width: box.width, height: box.height)
        .clipShape(.rect(cornerRadius: .radiusCard))
        .overlay(RoundedRectangle(cornerRadius: .radiusCard).strokeBorder(.gray.opacity(0.4)))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 15)
        .animation(.quick, value: hovering)
        .animation(.quick, value: state.done)
    }

    private var hovering: Bool { state.hovering || TestHover.shared.id == capture.id }

    /// CleanShot X's layout: Copy and Save as equal-width pills in the center, Close at the top-left. Always light, on
    /// a fill that does not adapt to the image, so they read the same on any capture.
    private var controls: some View {
        ZStack {
            VStack(spacing: .space2) {
                Button {
                    copy()
                } label: {
                    Text("Copy").frame(maxWidth: .infinity)
                }
                Button {
                    save()
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.pill)
            .fixedSize()
            VStack {
                HStack {
                    Button("Close", systemImage: "xmark") { actions.close(capture) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.pillIcon)
                        .help("Close")
                    Spacer()
                }
                Spacer()
            }
            .padding(.space2)
        }
        .environment(\.colorScheme, .light)
        .controlBackdrop(.image)
    }

    /// Copy closes the thumbnail after a short checkmark; with ⌥ held it stays.
    private func copy() {
        let keepOpen = NSEvent.modifierFlags.contains(.option)
        guard actions.copy(capture) else { return }
        finish(close: !keepOpen)
    }

    /// Save closes the thumbnail after a short checkmark; with ⌥ held it asks where to save instead.
    private func save() {
        if NSEvent.modifierFlags.contains(.option) {
            actions.saveAs(capture)
        } else if actions.save(capture) {
            finish(close: true)
        }
    }

    private func finish(close: Bool) {
        state.done = true
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            if close { actions.close(capture) } else { state.done = false }
        }
    }

    private func hover(_ inside: Bool) {
        state.hovering = inside
        // While the pointer rests on a thumbnail, these keys act on it without clicking, as in CleanShot X.
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
        menu.addItem(closureMenuItem("Copy") { copy() })
        menu.addItem(closureMenuItem("Save") { save() })
        menu.addItem(closureMenuItem("Save As…") { actions.saveAs(capture) })
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("Close") { actions.close(capture) })
        return menu
    }
}
