import AppKit
import ScreenCaptureKit

func screenshot(path: String, owner: String, layer: Int? = nil) async -> (String, Int32) {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let mine = content.windows.filter {
            $0.owningApplication?.applicationName == owner && $0.isOnScreen && $0.frame.height > 30 && (layer == nil || $0.windowLayer == layer)
        }
        guard let first = mine.first,
            let display = content.displays.first(where: { $0.frame.intersects(first.frame) }) ?? content.displays.first
        else { return ("no on-screen windows for \(owner)", 1) }
        let filter = SCContentFilter(display: display, including: mine)
        let union = mine.map(\.frame).reduce(first.frame) { $0.union($1) }
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = union.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int(union.width * scale)
        config.height = Int(union.height * scale)
        config.showsCursor = false
        // Transparent around the windows, so a script can place them on a synthetic background.
        config.backgroundColor = .clear
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        return ("saved \(path) \(image.width)x\(image.height) from \(mine.count) window(s) scale=\(Int(scale))", 0)
    } catch {
        return ("screenshot failed: \(error.localizedDescription)", 1)
    }
}

/// One window alone, also when other windows cover it, with its shadow.
func windowShot(path: String, windowID: CGWindowID) async -> (String, Int32) {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return ("no window \(windowID)", 1) }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        config.backgroundColor = .clear
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        return ("saved \(path) \(image.width)x\(image.height) scale=\(Int(scale))", 0)
    } catch {
        return ("screenshot failed: \(error.localizedDescription)", 1)
    }
}

/// The first app, front to back, whose on-screen window overlaps the rect above the driver's test window.
/// The rect is in global top-left coordinates, as CGWindowList bounds are. The menu bar and the Dock do not count, nor
/// Notification Center: while a notification shows, its host window spans the whole screen, but notifications sit at
/// the top-right, away from the test window.
@MainActor func coveringOwner(_ rect: CGRect) -> String? {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in all {
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
        guard alpha > 0, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds), frame.intersects(rect)
        else { continue }
        // Below the test window nothing shows in the capture.
        if owner == "myCaptureDriver" { return nil }
        if ["myCapture", "Window Server", "Dock", "Control Center", "Notification Center"].contains(owner) { continue }
        return owner
    }
    return nil
}

/// The topmost on-screen window at a point (global top-left coordinates): its id and owner. The menu bar is skipped.
@MainActor func windowAt(_ point: CGPoint) -> (id: CGWindowID, owner: String)? {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in all {
        let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        guard alpha > 0, !["Window Server"].contains(owner), let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point),
            let id = info[kCGWindowNumber as String] as? CGWindowID
        else { continue }
        return (id, owner)
    }
    return nil
}
