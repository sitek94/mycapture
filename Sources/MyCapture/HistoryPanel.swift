import AppKit
import Carbon.HIToolbox
import MyCaptureCore
import MyKit
import SwiftUI

/// What the history panel can do with a capture. The app model owns the captures and the thumbnails.
struct HistoryActions {
    /// Shows the capture as a thumbnail again.
    var restore: (Capture) -> Void
    var copy: (Capture) -> Bool
    var annotate: (Capture) -> Void
    var preview: (Capture) -> Void
    /// After entries were removed: their files may go.
    var removed: () -> Void
}

/// Capture History: every capture of the last days, newest first, in a strip at the top of the screen. Opening it
/// again closes it.
@Observable
final class HistoryController {
    /// Within this time a reopened panel keeps the selection.
    static let keepState: TimeInterval = 90

    private(set) var history = CaptureHistory()
    var retention = HistoryRetention(rawValue: UserDefaults.standard.string(forKey: "historyRetention") ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(retention.rawValue, forKey: "historyRetention")
            prune()
        }
    }
    var selection: Capture.ID?
    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let actions: HistoryActions
    @ObservationIgnored private var panel: StripPanel?
    @ObservationIgnored private var closedAt: Date?

    /// - Parameter persist: false in test runs, which share the app's defaults.
    init(persist: Bool, actions: HistoryActions) {
        self.persist = persist
        self.actions = actions
        if persist, let data = UserDefaults.standard.data(forKey: "history"),
            let saved = try? JSONDecoder().decode(CaptureHistory.self, from: data)
        {
            history = saved
        }
        prune()
    }

    var entries: [Capture] { history.entries }
    var isOpen: Bool { panel?.isVisible == true }

    func add(_ capture: Capture) {
        guard retention != .never else { return }
        change { $0.add(capture) }
    }

    func remove(_ id: Capture.ID) {
        let index = entries.firstIndex { $0.id == id }
        change { $0.remove(id) }
        // The next one takes the place of the removed one.
        if let index, selection == id { selection = entries.indices.contains(index) ? entries[index].id : entries.last?.id }
        actions.removed()
    }

    func clear() {
        change { $0.clear() }
        actions.removed()
    }

    func prune() {
        change { $0.prune(keeping: retention) { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } }
    }

    private func change(_ body: (inout CaptureHistory) -> Void) {
        body(&history)
        guard persist else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history")
    }

    // MARK: Panel

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        prune()
        if closedAt.map({ Date.now.timeIntervalSince($0) > Self.keepState }) ?? true || !entries.contains(where: { $0.id == selection }) {
            selection = entries.first?.id
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.show(on: Self.mouseScreen())
    }

    func close() {
        panel?.dismiss("closed")
    }

    private func makePanel() -> StripPanel {
        let panel = StripPanel(options: FloatingPanel.Options(closesOnOutsideClick: !AppModel.uiTest))
        panel.setContent { HistoryStrip(controller: self) }
        panel.keys = { [weak self] key in self?.handle(key) ?? false }
        panel.onClose = { [weak self] _ in self?.closedAt = .now }
        return panel
    }

    // MARK: Actions

    var selected: Capture? { entries.first { $0.id == selection } }

    func restore(_ capture: Capture) {
        close()
        actions.restore(capture)
    }

    func copy(_ capture: Capture) {
        guard actions.copy(capture) else { return }
        close()
        ToastPanel.show("Copied", at: toastPoint)
    }

    func annotate(_ capture: Capture) {
        close()
        actions.annotate(capture)
    }

    func preview(_ capture: Capture) {
        actions.preview(capture)
    }

    /// The keys of the panel. True when the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        let code = Int(event.keyCode)
        if event.modifierFlags.contains(.command) { return handleCommand(code) }
        switch code {
        case kVK_LeftArrow: move(by: -1)
        case kVK_RightArrow: move(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: selected.map(restore)
        case kVK_Space: selected.map(preview)
        case kVK_Delete, kVK_ForwardDelete: selection.map(remove)
        default: return false
        }
        return true
    }

    private func handleCommand(_ code: Int) -> Bool {
        switch code {
        case kVK_ANSI_C: selected.map(copy)
        case kVK_ANSI_E: selected.map(annotate)
        case kVK_ANSI_W, kVK_ANSI_Q: close()
        default: return false
        }
        return true
    }

    private func move(by step: Int) {
        guard let index = entries.firstIndex(where: { $0.id == selection }) else {
            selection = entries.first?.id
            return
        }
        if entries.indices.contains(index + step) { selection = entries[index + step].id }
    }

    private static func mouseScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private var toastPoint: CGPoint {
        let strip = panel?.frame ?? .zero
        return CGPoint(x: strip.midX, y: (NSScreen.screens.first?.frame.height ?? 0) - strip.midY)
    }
}

/// The strip's content: cards in a row, the settings menu at the top-right.
struct HistoryStrip: View {
    static let cell = CGSize(width: 255, height: 210)
    /// The first and last card's distance from the strip's sides.
    static let sideInset: CGFloat = 20
    /// The cards' top, from the strip's top.
    static let cellTop: CGFloat = 34
    static let menuTop: CGFloat = 14
    static let menuTrailing: CGFloat = 18
    /// The empty message sits this far below the center.
    static let emptyOffset: CGFloat = 15

    let controller: HistoryController

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if controller.entries.isEmpty {
                Text(controller.retention == .never ? "History is off. Turn it on in Keep History." : "No captures yet.")
                    .font(.textTitle)
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: Self.emptyOffset)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(controller.entries) { capture in
                                HistoryCard(capture: capture, selected: controller.selection == capture.id, controller: controller)
                                    .frame(width: Self.cell.width, height: Self.cell.height)
                                    .id(capture.id)
                            }
                        }
                        .padding(.horizontal, Self.sideInset)
                    }
                    .scrollIndicators(.never)
                    .padding(.top, Self.cellTop)
                    .onChange(of: controller.selection) { _, id in
                        withAnimation(.quick) { proxy.scrollTo(id) }
                    }
                }
            }
            settingsMenu
                .padding(.top, Self.menuTop)
                .padding(.trailing, Self.menuTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelSurface()
        // The panel's hidden title bar would push the content down.
        .ignoresSafeArea()
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Keep History", selection: Binding(get: { controller.retention }, set: { controller.retention = $0 })) {
                ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button("Clear History", role: .destructive) { controller.clear() }
        } label: {
            Image(systemName: "ellipsis").accessibilityLabel("History Settings")
        }
        .menuStyle(.button)
        .buttonStyle(.ghost)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("History settings")
    }
}

/// One capture in the strip: the image with the app it came from; under it the time, or Restore on the selected card.
/// The pointer selects a card (not in test runs, where it could rest anywhere).
struct HistoryCard: View {
    static let image = CGSize(width: 185, height: 130)
    static let imageTop: CGFloat = 25
    static let iconSize: CGFloat = 40
    /// The app icon's corner from the image's bottom-right corner.
    static let iconOutset: CGFloat = 15
    static let restoreBottom: CGFloat = 15
    static let timeBottom: CGFloat = 20
    static let timeHeight: CGFloat = 20

    let capture: Capture
    let selected: Bool
    let controller: HistoryController
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .top) {
            thumbnail.padding(.top, Self.imageTop)
            VStack {
                Spacer()
                if selected {
                    Button("⏎ Restore") { controller.restore(capture) }
                        .buttonStyle(.smallPrimary)
                        .padding(.bottom, Self.restoreBottom)
                } else {
                    Text(capture.date, format: .relative(presentation: .named))
                        .font(.textBody)
                        .foregroundStyle(.primary.opacity(0.5))
                        .lineLimit(1)
                        .frame(height: Self.timeHeight)
                        .padding(.bottom, Self.timeBottom)
                }
            }
        }
        .onHover { inside in
            if inside, !AppModel.uiTest { controller.selection = capture.id }
        }
        .task(id: capture.file) {
            image = NSImage(contentsOf: capture.file)
        }
    }

    private var thumbnail: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
            MouseArea(
                file: capture.file, image: image ?? NSImage(),
                onHover: { _ in },
                onDoubleClick: { controller.annotate(capture) },
                onDropped: { _ in },
                menu: menu,
                onClick: { controller.selection = capture.id })
        }
        .frame(width: Self.image.width, height: Self.image.height)
        .clipShape(.rect(cornerRadius: .radiusCard))
        .overlay(RoundedRectangle(cornerRadius: .radiusCard).strokeBorder(.gray.opacity(0.2)))
        .shadow(color: .black.opacity(0.3), radius: 13, y: 5)
        .selectionRing(selected)
        .overlay(alignment: .bottomTrailing) {
            appIcon.map {
                Image(nsImage: $0)
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    .offset(x: Self.iconOutset, y: Self.iconOutset)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The icon of the app the capture came from, while that app runs.
    private var appIcon: NSImage? {
        guard let app = capture.app else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == app }?.icon
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureMenuItem("Restore") { controller.restore(capture) })
        menu.addItem(closureMenuItem("Annotate") { controller.annotate(capture) })
        menu.addItem(closureMenuItem("Copy") { controller.copy(capture) })
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("Remove from History") { controller.remove(capture.id) })
        return menu
    }
}
