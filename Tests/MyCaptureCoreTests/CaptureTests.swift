import CoreGraphics
import Foundation
import Testing

@testable import MyCaptureCore

struct CaptureCommandTests {
    let output = URL(filePath: "/tmp/x/a b.png")

    @Test func areaStartsInSelectionMode() {
        #expect(CaptureCommand.interactive(.area, output: output, sound: true).arguments == ["-i", "/tmp/x/a b.png"])
    }

    @Test func windowStartsInWindowModeAndSoundCanBeOff() {
        #expect(CaptureCommand.interactive(.window, output: output, sound: false).arguments == ["-i", "-W", "-x", "/tmp/x/a b.png"])
    }

    @Test func rectCaptureNeedsNoInput() {
        let command = CaptureCommand.rect(CGRect(x: 200.4, y: 300, width: 480, height: 299.6), output: output)
        #expect(command.arguments == ["-x", "-R", "200,300,481,300", "/tmp/x/a b.png"])
    }
}

struct CaptureFilesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "mycapture-tests-\(UUID().uuidString)")

    func makeCapture(_ files: CaptureFiles) throws -> Capture {
        let file = try files.newTempFile()
        try Data("png".utf8).write(to: file)
        try ScreenCaptureAttributes.write("window", ScreenCaptureAttributes.typeKey, to: file)
        try ScreenCaptureAttributes.write([10, 20, 300, 200], ScreenCaptureAttributes.rectKey, to: file)
        let info = try #require(ScreenCaptureAttributes.read(file))
        return Capture(file: file, date: Date(timeIntervalSince1970: 1_791_826_003), kind: info.kind, rect: info.rect, app: "Safari", title: "Docs")
    }

    @Test func readsTypeAndRectFromTheCaptureToolsAttributes() throws {
        let capture = try makeCapture(CaptureFiles(tempFolder: root.appending(path: "temp")))
        #expect(capture.kind == .window)
        #expect(capture.rect == CGRect(x: 10, y: 20, width: 300, height: 200))
    }

    @Test func savesUnderTheTemplateNameWithoutOverwriting() throws {
        let files = CaptureFiles(tempFolder: root.appending(path: "temp"), namer: FileNamer(timeZone: TimeZone(identifier: "UTC")!))
        let capture = try makeCapture(files)
        let folder = root.appending(path: "Screenshots")
        let first = try files.save(capture, to: folder)
        let second = try files.save(capture, to: folder)
        #expect(first.lastPathComponent == "26-10-12 17.26.43 Safari - Docs.png")
        #expect(second.lastPathComponent == "26-10-12 17.26.43 Safari - Docs 2.png")
        // The copy keeps the attributes, so Finder still treats it as a screenshot.
        #expect(ScreenCaptureAttributes.read(first)?.kind == .window)
    }

    @Test func renamesTheTempFileToItsTemplateName() throws {
        let files = CaptureFiles(tempFolder: root.appending(path: "temp"), namer: FileNamer(timeZone: TimeZone(identifier: "UTC")!))
        var capture = try makeCapture(files)
        try files.applyName(to: &capture)
        #expect(capture.file.lastPathComponent == "26-10-12 17.26.43 Safari - Docs.png")
        #expect(FileManager.default.fileExists(atPath: capture.file.path(percentEncoded: false)))
    }

    @Test func purgeKeepsOnlyFilesInUse() throws {
        let files = CaptureFiles(tempFolder: root.appending(path: "temp"))
        let kept = try makeCapture(files)
        let dropped = try makeCapture(files)
        files.purge(keeping: [kept])
        #expect(FileManager.default.fileExists(atPath: kept.file.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: dropped.file.path(percentEncoded: false)))
    }
}
