import CoreGraphics

/// A window from the system window list, front to back.
public struct WindowInfo: Equatable, Sendable {
    public var app: String
    public var title: String?
    /// Global top-left coordinates, in points.
    public var frame: CGRect
    public var layer: Int
    public var processID: Int32

    public init(app: String, title: String?, frame: CGRect, layer: Int = 0, processID: Int32 = 0) {
        self.app = app
        self.title = title
        self.frame = frame
        self.layer = layer
        self.processID = processID
    }
}

/// Which app and window a capture shows, for its file name.
public enum WindowMatch {
    /// Window capture: the normal window whose frame matches the captured rect best (overlap ÷ union; a big window
    /// behind it also covers the rect, so plain overlap would pick it).
    /// Area capture: the frontmost normal window under the center of the rect.
    /// Normal windows are layer 0 and not ours.
    public static func source(of kind: Capture.Kind, rect: CGRect, in windows: [WindowInfo], excluding ownProcess: Int32)
        -> WindowInfo?
    {
        let candidates = windows.filter { $0.layer == 0 && $0.processID != ownProcess && !$0.frame.isEmpty }
        switch kind {
        case .window:
            let best = candidates.max { match($0.frame, rect) < match($1.frame, rect) }
            return best.flatMap { match($0.frame, rect) > 0 ? $0 : nil }
        case .selection:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            return candidates.first { $0.frame.contains(center) }
        }
    }

    static func match(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let common = first.intersection(second)
        guard !common.isNull else { return 0 }
        let overlap = common.width * common.height
        return overlap / (first.width * first.height + second.width * second.height - overlap)
    }
}
