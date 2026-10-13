import Foundation

/// Which captures show as thumbnails, and which closed ones Restore can bring back.
public struct ThumbnailList: Codable, Equatable, Sendable {
    public static let maxClosed = 10

    /// Oldest first; the newest shows on top of the stack.
    public private(set) var visible: [Capture] = []
    /// Most recently closed last.
    public private(set) var closed: [Capture] = []

    public init() {}

    /// Adds a capture. When more than `limit` show (as many as fit on the screen), the oldest closes.
    public mutating func add(_ capture: Capture, limit: Int = .max) {
        visible.append(capture)
        while visible.count > max(limit, 1) {
            close(visible[0].id)
        }
    }

    public mutating func close(_ id: Capture.ID) {
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return }
        closed.append(visible.remove(at: index))
        if closed.count > Self.maxClosed { closed.removeFirst(closed.count - Self.maxClosed) }
    }

    /// Brings back the most recently closed capture. Nil when there is none.
    @discardableResult
    public mutating func restoreLast(limit: Int = .max) -> Capture? {
        guard let capture = closed.popLast() else { return nil }
        add(capture, limit: limit)
        return capture
    }

    /// Every capture whose temp file must stay.
    public var all: [Capture] { visible + closed }

    /// What survives a relaunch: the visible thumbnails only. Closed ones go.
    public var forRelaunch: ThumbnailList {
        var list = ThumbnailList()
        list.visible = visible
        return list
    }
}
