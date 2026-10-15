import CoreGraphics
import Foundation

/// The arrow outline: a shaft that widens from the tail toward a swept-back head, filled as one shape.
/// Every size follows the line width, so thick arrows keep the same proportions.
public enum ArrowPath {
    /// Head length for a line width; a short arrow gets a smaller head (see `path`).
    static func headLength(for width: Double) -> Double { width * 3.2 + 10 }
    static func headWidth(for width: Double) -> Double { headLength(for: width) * 1.1 }

    public static func path(from start: CGPoint, to end: CGPoint, width: Double) -> CGPath {
        let length = hypot(end.x - start.x, end.y - start.y)
        let path = CGMutablePath()
        guard length > 0 else { return path }
        // The head takes at most 60 % of a short arrow.
        let scale = min(1, length * 0.6 / headLength(for: width))
        let head = headLength(for: width) * scale
        let halfHead = headWidth(for: width) / 2 * scale
        let halfShaft = width / 2 * max(scale, 0.5)
        let halfTail = halfShaft * 0.3
        let base = length - head
        // Drawn along +x from the origin, then turned and moved onto the line.
        let outline = [
            CGPoint(x: 0, y: halfTail),
            CGPoint(x: base, y: halfShaft),
            CGPoint(x: base - head * 0.18, y: halfHead),
            CGPoint(x: length, y: 0),
            CGPoint(x: base - head * 0.18, y: -halfHead),
            CGPoint(x: base, y: -halfShaft),
            CGPoint(x: 0, y: -halfTail),
        ]
        let angle = atan2(end.y - start.y, end.x - start.x)
        path.addLines(between: outline, transform: CGAffineTransform(translationX: start.x, y: start.y).rotated(by: angle))
        path.closeSubpath()
        // A thin round stroke softens the corners of the tip and the barbs.
        let rounded = path.copy(strokingWithWidth: max(width * 0.25, 1), lineCap: .round, lineJoin: .round, miterLimit: 1)
        return path.union(rounded)
    }
}
