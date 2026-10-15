import Foundation
import Testing

@testable import MyCaptureCore

struct ThumbnailListTests {
    func capture(_ number: Int) -> Capture {
        Capture(file: URL(filePath: "/tmp/\(number).png"), date: .now, kind: .selection, rect: nil)
    }

    @Test func showsAsManyAsFitAndClosesTheOldest() {
        var list = ThumbnailList()
        let captures = (1...6).map(capture)
        captures.forEach { list.add($0, limit: 5) }
        #expect(list.visible == Array(captures[1...]))
        #expect(list.closed == [captures[0]])
    }

    @Test func addingAShownOrClosedCaptureMovesItToTheTop() {
        var list = ThumbnailList()
        let (first, second) = (capture(1), capture(2))
        list.add(first)
        list.add(second)
        list.add(first)
        #expect(list.visible == [second, first])
        list.close(second.id)
        list.add(second)
        #expect(list.visible == [first, second])
        #expect(list.closed.isEmpty)
    }

    @Test func restoreBringsBackTheMostRecentlyClosed() {
        var list = ThumbnailList()
        let (first, second) = (capture(1), capture(2))
        list.add(first)
        list.add(second)
        list.close(first.id)
        list.close(second.id)
        #expect(list.restoreLast() == second)
        #expect(list.visible == [second])
        #expect(list.closed == [first])
    }

    @Test func keepsTheLastTenClosed() {
        var list = ThumbnailList()
        let captures = (1...12).map(capture)
        for item in captures {
            list.add(item)
            list.close(item.id)
        }
        #expect(list.closed == Array(captures[2...]))
        #expect(list.restoreLast() == captures[11])
    }

    @Test func onlyVisibleThumbnailsSurviveARelaunch() throws {
        var list = ThumbnailList()
        let (shown, gone) = (capture(1), capture(2))
        list.add(gone)
        list.close(gone.id)
        list.add(shown)
        let decoded = try JSONDecoder().decode(ThumbnailList.self, from: JSONEncoder().encode(list.forRelaunch))
        #expect(decoded.visible == [shown])
        #expect(decoded.closed.isEmpty)
    }
}
