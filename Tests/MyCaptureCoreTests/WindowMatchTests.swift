import CoreGraphics
import Testing

@testable import MyCaptureCore

struct WindowMatchTests {
    // Front to back, as the system lists them.
    let windows = [
        WindowInfo(app: "Control Center", title: nil, frame: CGRect(x: 0, y: 0, width: 3000, height: 30), layer: 25),
        WindowInfo(app: "myCapture", title: "Thumbnail", frame: CGRect(x: 0, y: 0, width: 400, height: 400), processID: 42),
        WindowInfo(app: "Safari", title: "Docs", frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
        WindowInfo(app: "Finder", title: "Downloads", frame: CGRect(x: 0, y: 0, width: 1200, height: 900)),
    ]

    @Test func areaUsesTheFrontWindowUnderItsCenter() {
        let source = WindowMatch.source(of: .selection, rect: CGRect(x: 150, y: 150, width: 100, height: 100), in: windows, excluding: 42)
        #expect(source?.app == "Safari")
    }

    @Test func areaOutsideFrontWindowsFallsToTheOneBehind() {
        let source = WindowMatch.source(of: .selection, rect: CGRect(x: 1000, y: 800, width: 50, height: 50), in: windows, excluding: 42)
        #expect(source?.app == "Finder")
    }

    @Test func windowCaptureUsesTheLargestOverlapAndSkipsOurOwnWindows() {
        let source = WindowMatch.source(of: .window, rect: CGRect(x: 90, y: 90, width: 820, height: 620), in: windows, excluding: 42)
        #expect(source?.title == "Docs")
    }

    @Test func nothingUnderTheRectGivesNoSource() {
        let source = WindowMatch.source(of: .window, rect: CGRect(x: 5000, y: 5000, width: 10, height: 10), in: windows, excluding: 42)
        #expect(source == nil)
    }
}
