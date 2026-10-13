import Foundation
import Testing

@testable import MyCaptureCore

struct FileNamerTests {
    let namer = FileNamer(timeZone: TimeZone(identifier: "Europe/Warsaw")!)
    // 2026-10-12 19:26:43 in Warsaw (UTC+2).
    let date = Date(timeIntervalSince1970: 1791826003)

    @Test func dateAppAndTitle() {
        #expect(namer.fileName(date: date, app: "Safari", title: "Pull requests") == "26-10-12 19.26.43 Safari - Pull requests.png")
    }

    @Test func longNamesFitTheFileSystemLimit() {
        // 4-byte emoji in a long app name and title: the name must stay under 255 bytes with " 99.png".
        let emoji = String(repeating: "🧪", count: 100)
        let base = namer.baseName(date: date, app: emoji, title: emoji)
        #expect(base.utf8.count <= FileNamer.maxBaseBytes)
        #expect((base + " 99.png").utf8.count <= 255)
        #expect(base.hasPrefix("26-10-12 19.26.43 🧪"))
    }

    @Test func noTitleLeavesOutTheDash() {
        #expect(namer.baseName(date: date, app: "Finder", title: nil) == "26-10-12 19.26.43 Finder")
        #expect(namer.baseName(date: date, app: "Finder", title: "  ") == "26-10-12 19.26.43 Finder")
    }

    @Test func noAppGivesTheDateOnly() {
        #expect(namer.baseName(date: date, app: nil, title: "Ignored") == "26-10-12 19.26.43")
    }

    @Test func replacesCharactersAFileNameCannotHold() {
        #expect(namer.baseName(date: date, app: "Safari", title: "a/b: c\nd") == "26-10-12 19.26.43 Safari - a-b- c d")
    }

    @Test func cutsLongTitles() {
        let title = String(repeating: "x", count: 200)
        let name = namer.baseName(date: date, app: "Safari", title: title)
        #expect(name.hasSuffix(" - " + String(repeating: "x", count: FileNamer.maxTitleLength)))
    }
}
