import CoreGraphics
import Foundation

/// One annotation on a capture. Geometry is in image pixels, top-left origin, so it does not depend on the zoom
/// of the editor window.
public struct Markup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var shape: Shape
    public var color: MarkupColor
    /// Line width in image pixels.
    public var width: Double

    public enum Shape: Codable, Equatable, Sendable {
        case arrow(start: CGPoint, end: CGPoint)
    }

    /// A point the user can drag to change the shape.
    public enum Handle: Equatable, Sendable {
        case start, end
    }

    public init(id: UUID = UUID(), shape: Shape, color: MarkupColor, width: Double) {
        self.id = id
        self.shape = shape
        self.color = color
        self.width = width
    }

    public var handles: [(Handle, CGPoint)] {
        switch shape {
        case .arrow(let start, let end): [(.start, start), (.end, end)]
        }
    }

    /// True when `point` is on the shape, with `tolerance` extra pixels around the line.
    public func contains(_ point: CGPoint, tolerance: Double) -> Bool {
        switch shape {
        case .arrow(let start, let end):
            Geometry.distance(from: point, toSegment: start, end) <= max(width, ArrowPath.headWidth(for: width)) / 2 + tolerance
        }
    }

    public func moved(by delta: CGVector) -> Markup {
        var copy = self
        switch shape {
        case .arrow(let start, let end):
            copy.shape = .arrow(start: start + delta, end: end + delta)
        }
        return copy
    }

    public func moving(_ handle: Handle, to point: CGPoint) -> Markup {
        var copy = self
        switch shape {
        case .arrow(let start, let end):
            copy.shape = handle == .start ? .arrow(start: point, end: end) : .arrow(start: start, end: point)
        }
        return copy
    }
}

/// An sRGB color with alpha, stored with the markup so a file opens the same anywhere.
public struct MarkupColor: Codable, Equatable, Hashable, Sendable {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    // swiftlint:disable raw_color
    // Drawing data saved with each markup, not UI colors, so they are raw values.
    /// The editor's color choices, with names for menus and accessibility. Red first: the default.
    public static let palette: [(name: String, color: MarkupColor)] = [
        ("Red", MarkupColor(red: 0.95, green: 0.23, blue: 0.21)),
        ("Orange", MarkupColor(red: 0.98, green: 0.55, blue: 0.10)),
        ("Yellow", MarkupColor(red: 0.99, green: 0.82, blue: 0.13)),
        ("Green", MarkupColor(red: 0.20, green: 0.75, blue: 0.35)),
        ("Blue", MarkupColor(red: 0.16, green: 0.47, blue: 0.96)),
        ("Purple", MarkupColor(red: 0.62, green: 0.32, blue: 0.90)),
        ("Pink", MarkupColor(red: 0.96, green: 0.33, blue: 0.62)),
        ("Black", MarkupColor(red: 0.08, green: 0.08, blue: 0.09)),
        ("White", MarkupColor(red: 1, green: 1, blue: 1)),
    ]
    // swiftlint:enable raw_color
}

enum Geometry {
    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        // How far along the segment the nearest point is, from 0 (start) to 1 (end).
        let fraction = min(max(((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared, 0), 1)
        return hypot(point.x - (start.x + fraction * deltaX), point.y - (start.y + fraction * deltaY))
    }

    /// `end`, moved so the line from `start` points at the nearest multiple of 45°. The length stays.
    static func snapped45(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return end }
        let step = Double.pi / 4
        let angle = (atan2(end.y - start.y, end.x - start.x) / step).rounded() * step
        return CGPoint(x: start.x + length * cos(angle), y: start.y + length * sin(angle))
    }
}

func + (point: CGPoint, delta: CGVector) -> CGPoint {
    CGPoint(x: point.x + delta.dx, y: point.y + delta.dy)
}
