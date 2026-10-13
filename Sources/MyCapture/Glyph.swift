import AppKit
import SwiftUI

// The myCapture glyph: viewfinder brackets around a camera. Our own drawing (SF Symbols may not be used in app
// icons), shared by the app icon (`scripts/make-glyph.swift`) and the menu bar icon. Plain SwiftUI, no app types:
// the script compiles this file on its own.

/// The four corner brackets, as strokes in a unit square scaled to the frame.
struct ViewfinderBrackets: Shape {
    /// Stroke width as a share of the side: the menu bar needs a heavier line than the icon.
    var weight: CGFloat = 0.11

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let inset = side * (0.06 + weight / 2)
        let arm = side * 0.24
        let box = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        for (corner, alongX, alongY) in [
            (CGPoint(x: box.minX, y: box.minY), 1.0, 1.0), (CGPoint(x: box.maxX, y: box.minY), -1.0, 1.0),
            (CGPoint(x: box.minX, y: box.maxY), 1.0, -1.0), (CGPoint(x: box.maxX, y: box.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + alongY * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + alongX * arm, y: corner.y))
        }
        return path.strokedPath(StrokeStyle(lineWidth: side * weight, lineCap: .round, lineJoin: .round))
    }
}

/// A camera body with a viewfinder bump; the lens is a hole, so the background shows through.
struct CameraBody: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        // A rect in shares of the side.
        func part(_ left: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: rect.minX + left * side, y: rect.minY + top * side, width: width * side, height: height * side)
        }
        // The body sits just below the middle, so the body with its bump looks centered between the brackets.
        var path = Path()
        path.addRoundedRect(in: part(0.23, 0.35, 0.54, 0.38), cornerSize: CGSize(width: side * 0.08, height: side * 0.08))
        path.addRoundedRect(in: part(0.38, 0.27, 0.24, 0.12), cornerSize: CGSize(width: side * 0.04, height: side * 0.04))
        path.addEllipse(in: part(0.37, 0.415, 0.26, 0.26))
        return path
    }
}

/// The whole glyph in one color, for the menu bar (a template image).
struct MenuBarGlyph: View {
    var body: some View {
        ZStack {
            ViewfinderBrackets(weight: 0.1)
            // Smaller than on the icon: at 18 pt the camera needs a clear gap to the brackets.
            CameraBody().fill(style: FillStyle(eoFill: true)).scaleEffect(0.85)
        }
    }
}

extension MenuBarGlyph {
    /// The menu bar icon: 18 pt, drawn once at 2× for Retina displays.
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: MenuBarGlyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.size = CGSize(width: 18, height: 18)
        return image
    }()
}
