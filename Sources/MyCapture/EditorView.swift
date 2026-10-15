import AppKit
import MyCaptureCore
import MyKit
import SwiftUI

/// The editor window's content. Top bar, in the title bar: the tools, the style of the
/// current tool, Save As… on the right. Bottom bar: the file to drag out in the center, Copy on the right.
struct EditorView: View {
    /// Bar heights and insets of the editor chrome.
    enum Metrics {
        static let barHeight: CGFloat = 49
        /// The top bar with the window's top rim.
        static let topBarHeight: CGFloat = 50
        /// Under the bottom bar: a 1 pt inset plus the window's bottom edge.
        static let bottomInset: CGFloat = 2
        /// Both bars with their lines: 103 pt.
        static let chrome: CGFloat = topBarHeight + 1 + 1 + barHeight + bottomInset
        /// First item after the traffic lights; the bars' outer insets.
        static let leading: CGFloat = 96
        static let inset: CGFloat = 13
        static let gap: CGFloat = 6
        /// Between the tool group and the style buttons.
        static let groupGap: CGFloat = 12
        static let toolbarItemHeight: CGFloat = 30
        /// The system puts the last toolbar item 8 pt from the window edge; the main button sits at `inset`.
        static let mainButtonTrailing: CGFloat = inset - 8
    }

    @Bindable var model: EditorModel
    let commands: EditorCommands
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        EditorCanvas(model: model, commands: commands, revision: model.revision)
            // The bars' edges: a light line under the top bar, a faint one over the bottom bar; one gray in light mode.
            .overlay(alignment: .top) { Rectangle().fill(.chrome(scheme == .dark ? 0.29 : 0.1)).frame(height: 1) }
            // The canvas starts right under the 50 pt top bar, not under the taller system title bar.
            .padding(.top, Metrics.topBarHeight)
            .ignoresSafeArea(.container, edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .background { HeaderMaterial().ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .navigation) { tools }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .primaryAction) {
                    Button(model.optionHeld ? "Save" : "Save As…", action: commands.saveOrSaveAs)
                        .buttonStyle(.pill(selected: true))
                        .help(model.optionHeld ? "Save to the screenshots folder (⌘S)" : "Save As… (⇧⌘S); hold ⌥ to save to the screenshots folder")
                        .padding(.trailing, Metrics.mainButtonTrailing)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }

    /// 30 pt tall like the title bar's own items, so the bar keeps the system's height.
    private var tools: some View {
        HStack(spacing: Metrics.gap) {
            SegmentGroup(
                selection: Binding(get: { model.editor.tool }, set: { tool in model.change { $0.tool = tool } }),
                items: AnnotationEditor.Tool.allCases.map {
                    .init($0, title: $0.title, glyph: $0.glyph, help: "\($0.title) (\($0.key))")
                })
            if showsStyle {
                colorMenu.padding(.leading, Metrics.groupGap - Metrics.gap)
                widthMenu
            }
        }
        .frame(height: Metrics.toolbarItemHeight)
    }

    /// The style controls show for a drawing tool and for a selected markup.
    private var showsStyle: Bool {
        model.editor.tool != .move || model.editor.selection != nil
    }

    private var colorMenu: some View {
        Menu {
            ForEach(MarkupColor.palette, id: \.name) { entry in
                Button {
                    model.setColor(entry)
                } label: {
                    Label {
                        Text(entry.name)
                    } icon: {
                        Swatch(color: entry.color)
                    }
                }
            }
        } label: {
            StyleButtonLabel { SwatchDot(color: model.editor.color) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Color")
        .help("Color")
    }

    private var widthMenu: some View {
        Menu {
            ForEach(EditorModel.widths, id: \.self) { width in
                Toggle("\(width.formatted()) pt", isOn: Binding(get: { model.width == width }, set: { _ in model.setWidth(width) }))
            }
        } label: {
            StyleButtonLabel { ControlGlyph.line }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Line Width")
        .help("Line width")
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.chrome(scheme == .dark ? 0.04 : 0.1)).frame(height: 1)
            ZStack {
                DragOutButton(
                    title: "Drag Me", file: model.capture.file, prepare: commands.prepareDrag,
                    click: commands.close)
                HStack(spacing: Metrics.gap) {
                    Spacer()
                    Button(action: commands.copy) { ControlGlyph.copy }
                        .buttonStyle(.pillIcon)
                        .accessibilityLabel("Copy")
                        .help("Copy (⇧⌘C)")
                }
            }
            .padding(.horizontal, Metrics.inset)
            .frame(height: Metrics.barHeight)
            .padding(.bottom, Metrics.bottomInset)
        }
    }
}

/// The bars' background: the header material, as in a window's title bar.
private struct HeaderMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A style button's face: its content and a small chevron, in a 40 pt capsule.
private struct StyleButtonLabel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: .space1) {
            content
            ControlGlyph.chevron.opacity(0.55)
        }
        .pill()
    }
}

extension AnnotationEditor.Tool {
    var title: String {
        switch self {
        case .move: "Move"
        case .arrow: "Arrow"
        }
    }

    var glyph: ControlGlyph {
        switch self {
        case .move: .cursor
        case .arrow: .arrow
        }
    }

    /// The key that picks the tool in the canvas.
    var key: String {
        switch self {
        case .move: "V"
        case .arrow: "A"
        }
    }
}

/// The color button's dot: the markup color in a thin white ring.
private struct SwatchDot: View {
    static let size: CGFloat = 15

    let color: MarkupColor

    var body: some View {
        Circle()
            .fill(Color(cgColor: color.cgColor))
            .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1))
            .frame(width: Self.size, height: Self.size)
    }
}

/// A filled circle in a markup color, for menus.
struct Swatch: View {
    let color: MarkupColor

    var body: some View {
        Image(nsImage: Self.image(color))
    }

    /// Menus show images, not views: draw the swatch once per color.
    private static func image(_ color: MarkupColor) -> NSImage {
        let size: CGFloat = 14
        let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor(cgColor: color.cgColor)?.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
        return image
    }
}

/// The capture as a file to drag into another app; a click closes the editor, keeping the changes.
struct DragOutButton: View {
    static let size = CGSize(width: 115, height: 31)

    let title: String
    let file: URL
    /// Runs before a drag starts, so the dragged file holds the current markups.
    let prepare: () -> Void
    let click: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearsActive) private var active
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: .space2) {
            grip
            Text(title).lineLimit(1)
            grip
        }
        .font(.textCallout.weight(.regular))
        .foregroundStyle(.primary.opacity(0.7))
        .frame(width: Self.size.width, height: Self.size.height)
        .background(fill, in: .capsule)
        .overlay {
            if scheme == .dark {
                // One device pixel: a 0.5 pt line on a 1x screen is half a pixel, which fades along the straight edges.
                // On 1x, half the opacity keeps the weight of a Retina half-point line.
                Capsule().strokeBorder(.chrome(min(0.1 * displayScale, 0.2)), lineWidth: 1 / displayScale)
            } else {
                Capsule().strokeBorder(.white, lineWidth: 1)
            }
        }
        .overlay(DragArea(file: file, prepare: prepare, click: click))
        .help("Drag into any app, or click to close")
    }

    /// Light mode: a white capsule, gone when the window is not key.
    private var fill: AnyShapeStyle {
        if scheme == .dark { return AnyShapeStyle(.chrome(0.08)) }
        return AnyShapeStyle(Color.white.opacity(active ? 0.99 : 0))
    }

    private var grip: some View {
        Image(systemName: "line.3.horizontal").imageScale(.small).foregroundStyle(.secondary)
    }
}

/// Click and file drag for `DragOutButton`, which SwiftUI gestures cannot give together.
private struct DragArea: NSViewRepresentable {
    let file: URL
    let prepare: () -> Void
    let click: () -> Void

    func makeNSView(context: Context) -> DragAreaView {
        DragAreaView(area: self)
    }

    func updateNSView(_ view: DragAreaView, context: Context) {
        view.area = self
    }
}

private final class DragAreaView: NSView, NSDraggingSource {
    var area: DragArea
    private var downEvent: NSEvent?

    init(area: DragArea) {
        self.area = area
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        guard downEvent != nil else { return }
        downEvent = nil
        area.click()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        let moved = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
        guard moved > 3 else { return }
        downEvent = nil
        area.prepare()
        let item = NSDraggingItem(pasteboardWriter: area.file as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(contentsOf: area.file))
        beginDraggingSession(with: [item], event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
