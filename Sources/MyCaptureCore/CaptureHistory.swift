import Foundation

/// Every capture, newest first, for the Capture History panel. Entries older than the retention go.
public struct CaptureHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [Capture] = []

    public init() {}

    /// Adds a capture at the front. A capture already in the list moves to the front with its new data.
    public mutating func add(_ capture: Capture) {
        entries.removeAll { $0.id == capture.id }
        entries.insert(capture, at: 0)
    }

    public mutating func remove(_ id: Capture.ID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func clear() {
        entries = []
    }

    /// Drops entries older than the retention, and entries whose file is gone.
    public mutating func prune(keeping retention: HistoryRetention, now: Date = .now, fileExists: (URL) -> Bool) {
        let oldest = now.addingTimeInterval(-retention.interval)
        entries.removeAll { $0.date < oldest || !fileExists($0.file) }
    }
}

/// How long captures stay in the history. "Never" keeps none.
public enum HistoryRetention: String, CaseIterable, Codable, Sendable {
    case never, day, threeDays, week, month

    public static let `default` = HistoryRetention.threeDays

    public var interval: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        return switch self {
        case .never: 0
        case .day: day
        case .threeDays: 3 * day
        case .week: 7 * day
        case .month: 30 * day
        }
    }

    public var title: String {
        switch self {
        case .never: "Never"
        case .day: "1 Day"
        case .threeDays: "3 Days"
        case .week: "1 Week"
        case .month: "1 Month"
        }
    }
}
