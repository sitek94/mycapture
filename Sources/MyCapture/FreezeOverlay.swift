import AppKit
import ScreenCaptureKit
import os

/// The frozen screen during an area capture, when Settings turn it on: one window per display showing a snapshot
/// taken just before `screencapture` starts, so menus and tooltips stay in the capture. On top, a crosshair and a
/// magnifier of the snapshot that never appear in captures (`sharingType = .none`; `screencapture` leaves such
/// windows out).
final class FreezeOverlay {
    private var windows: [NSWindow] = []
    private var guides: [GuideView] = []
    private var timer: Timer?
    /// The mouse and ⌘ at the last redraw: the full-screen guides redraw only when one of them changes.
    private var lastGuideState: (mouse: CGPoint, command: Bool)?
    private let log = Logger(subsystem: "dev.maciek.mycapture", category: "freeze")

    /// The first ScreenCaptureKit capture after launch is slow (~200 ms); later ones take 20–40 ms.
    static func warmUp() {
        Task {
            guard let content = try? await SCShareableContent.current, let display = content.displays.first else { return }
            let config = SCStreamConfiguration()
            config.width = 64
            config.height = 64
            _ = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
        }
    }

    /// `frozen` false: only the crosshair and magnifier; the screen stays live.
    func show(frozen: Bool) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Our own windows (thumbnails) stay out of the frozen image, so they stay out of the capture.
            let ownApps = content.applications.filter { $0.processID == getpid() }
            for display in content.displays {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(CGFloat(display.width) * CGFloat(filter.pointPixelScale))
                config.height = Int(CGFloat(display.height) * CGFloat(filter.pointPixelScale))
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                add(image, on: screen, frozen: frozen)
            }
        } catch {
            log.error("freeze failed, capturing live: \(error.localizedDescription, privacy: .public)")
            hide()
            return
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Space switches the capture tool to window mode: its camera cursor appears. Window captures show
                // live windows, so the freeze and the crosshair go away at once.
                if Self.windowModeCursorVisible() {
                    self.hide()
                    return
                }
                let state = (mouse: NSEvent.mouseLocation, command: NSEvent.modifierFlags.contains(.command))
                guard state.mouse != self.lastGuideState?.mouse || state.command != self.lastGuideState?.command else { return }
                self.lastGuideState = state
                self.guides.forEach { $0.needsDisplay = true }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guides = []
    }

    /// The capture tool's window-mode (camera) cursor has its hotspot at (14, 11) (measured on macOS 26).
    private static func windowModeCursorVisible() -> Bool {
        NSCursor.currentSystem?.hotSpot == CGPoint(x: 14, y: 11)
    }

    private func add(_ image: CGImage, on screen: NSScreen, frozen: Bool) {
        if frozen {
            let window = Self.window(on: screen, level: Self.level)
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = NSImage(cgImage: image, size: screen.frame.size)
            imageView.imageScaling = .scaleAxesIndependently
            window.contentView = imageView
            window.orderFrontRegardless()
            windows.append(window)
        }

        let overlay = Self.window(on: screen, level: Self.overlayLevel)
        overlay.sharingType = .none
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        let guide = GuideView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image, screen: screen)
        overlay.contentView = guide
        overlay.orderFrontRegardless()

        windows.append(overlay)
        guides.append(guide)
    }

    /// Below `screencapture`'s own selection UI, above everything else.
    private static let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 2)
    /// The crosshair, and the thumbnails during a capture: above the freeze, below Apple's selection UI.
    static let overlayLevel = NSWindow.Level(rawValue: level.rawValue + 1)

    private static func window(on screen: NSScreen, level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = level
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // No zoom-in and zoom-out: the frozen image must replace the live screen with no visible change.
        window.animationBehavior = .none
        window.setFrame(screen.frame, display: false)
        return window
    }
}

/// While ⌘ is held: a crosshair across the display and a magnifier of the frozen image
/// next to the cursor.
final class GuideView: NSView {
    /// 19 × 19 frozen pixels, each drawn 7 pt wide.
    static let loupePixels = 19
    static let loupePixelSize: CGFloat = 7
    static let loupeOffset: CGFloat = 20

    private let image: CGImage
    private let screen: NSScreen

    init(frame: NSRect, image: CGImage, screen: NSScreen) {
        self.image = image
        self.screen = screen
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let mouse = NSEvent.mouseLocation
        guard NSEvent.modifierFlags.contains(.command), screen.frame.contains(mouse),
            let context = NSGraphicsContext.current?.cgContext
        else { return }
        let point = CGPoint(x: (mouse.x - screen.frame.minX).rounded(.down) + 0.5, y: (mouse.y - screen.frame.minY).rounded(.down) + 0.5)
        drawCrosshair(at: point, in: context)
        drawLoupe(at: point, in: context)
    }

    /// A 1 pt dark line on a 3 pt light halo: visible on any background.
    private func drawCrosshair(at point: CGPoint, in context: CGContext) {
        let lines = [
            CGPoint(x: 0, y: point.y), CGPoint(x: bounds.width, y: point.y),
            CGPoint(x: point.x, y: 0), CGPoint(x: point.x, y: bounds.height),
        ]
        for (color, width) in [(NSColor.white.withAlphaComponent(0.15), 3.0), (NSColor.black.withAlphaComponent(0.4), 1.0)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.strokeLineSegments(between: lines)
        }
    }

    /// The frozen pixels around the cursor, sharp, in a rounded square beside it; the center pixel is marked.
    private func drawLoupe(at point: CGPoint, in context: CGContext) {
        let size = CGFloat(Self.loupePixels) * Self.loupePixelSize
        var origin = CGPoint(x: point.x + Self.loupeOffset, y: point.y - Self.loupeOffset - size)
        if origin.x + size > bounds.width { origin.x = point.x - Self.loupeOffset - size }
        if origin.y < 0 { origin.y = point.y + Self.loupeOffset }
        let loupe = CGRect(origin: origin, size: CGSize(width: size, height: size))
        let scale = CGFloat(image.width) / bounds.width
        let half = CGFloat(Self.loupePixels / 2)
        // Image rows run top to bottom; the view runs bottom to top.
        let center = CGPoint(x: (point.x * scale).rounded(.down), y: ((bounds.height - point.y) * scale).rounded(.down))
        let source = CGRect(x: center.x - half, y: center.y - half, width: CGFloat(Self.loupePixels), height: CGFloat(Self.loupePixels))
        guard let crop = image.cropping(to: source) else { return }
        let shape = CGPath(roundedRect: loupe, cornerWidth: .radiusInner, cornerHeight: .radiusInner, transform: nil)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.interpolationQuality = .none
        context.draw(crop, in: loupe)
        // Mark the center row and column.
        let cell = Self.loupePixelSize
        let middle = CGRect(x: loupe.minX + half * cell, y: loupe.minY + half * cell, width: cell, height: cell)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1)
        context.stroke(middle.insetBy(dx: -0.5, dy: -0.5))
        context.restoreGState()
        // A white ring inside a dark outline, with a soft shadow: visible on dark and light screens alike.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(
            CGPath(roundedRect: loupe.insetBy(dx: -1.5, dy: -1.5), cornerWidth: .radiusInner + 1.5, cornerHeight: .radiusInner + 1.5, transform: nil))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
        context.addPath(
            CGPath(roundedRect: loupe.insetBy(dx: -0.5, dy: -0.5), cornerWidth: .radiusInner + 0.5, cornerHeight: .radiusInner + 0.5, transform: nil))
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokePath()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
