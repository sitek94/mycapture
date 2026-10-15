import Foundation
import Testing

@testable import MyCaptureCore

struct CaptureHistoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func capture(_ name: String, hoursAgo: Double = 0) -> Capture {
        Capture(file: URL(filePath: "/tmp/\(name).png"), date: now.addingTimeInterval(-hoursAgo * 3600), kind: .selection, rect: nil)
    }

    @Test func newestFirstAndAnUpdateMovesToTheFront() {
        var history = CaptureHistory()
        var first = capture("first")
        let second = capture("second")
        history.add(first)
        history.add(second)
        #expect(history.entries.map(\.file.lastPathComponent) == ["second.png", "first.png"])
        first.title = "Renamed"
        history.add(first)
        #expect(history.entries.map(\.title) == ["Renamed", nil])
    }

    @Test func pruneDropsOldEntriesAndMissingFiles() {
        var history = CaptureHistory()
        history.add(capture("old", hoursAgo: 80))
        history.add(capture("gone", hoursAgo: 1))
        history.add(capture("new", hoursAgo: 1))
        history.prune(keeping: .threeDays, now: now) { $0.lastPathComponent != "gone.png" }
        #expect(history.entries.map(\.file.lastPathComponent) == ["new.png"])
    }

    @Test func neverKeepsNothing() {
        var history = CaptureHistory()
        history.add(capture("new"))
        history.prune(keeping: .never, now: now.addingTimeInterval(1)) { _ in true }
        #expect(history.entries.isEmpty)
    }
}
