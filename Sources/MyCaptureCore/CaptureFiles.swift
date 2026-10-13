import Foundation

/// Where captures live: a temp folder for new captures, the screenshots folder for saved ones.
public struct CaptureFiles: Sendable {
    public var tempFolder: URL
    public var namer: FileNamer

    public init(tempFolder: URL, namer: FileNamer = FileNamer()) {
        self.tempFolder = tempFolder
        self.namer = namer
    }

    /// `~/Library/Caches/dev.maciek.mycapture/captures`.
    public static var defaultTempFolder: URL {
        URL.cachesDirectory.appending(path: "dev.maciek.mycapture/captures")
    }

    /// `~/Downloads/Screenshots`.
    public static var defaultSaveFolder: URL {
        URL.downloadsDirectory.appending(path: "Screenshots")
    }

    /// A new temp file for the capture tool to write, in a folder of its own: `<temp>/<uuid>/capture.png`.
    public func newTempFile() throws -> URL {
        let folder = tempFolder.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "capture.png")
    }

    /// Renames the capture's temp file to its template name, so a drag drops a well-named file.
    public func applyName(to capture: inout Capture) throws {
        let target = capture.file.deletingLastPathComponent()
            .appending(path: namer.fileName(date: capture.date, app: capture.app, title: capture.title))
        guard target != capture.file else { return }
        try FileManager.default.moveItem(at: capture.file, to: target)
        capture.file = target
    }

    /// Copies the capture into `folder` under its template name; a name in use gets " 2", " 3"….
    /// The copy keeps the file's attributes, so Finder still treats it as a screenshot.
    @discardableResult
    public func save(_ capture: Capture, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = uniqueURL(in: folder, base: namer.baseName(date: capture.date, app: capture.app, title: capture.title))
        try FileManager.default.copyItem(at: capture.file, to: target)
        return target
    }

    func uniqueURL(in folder: URL, base: String) -> URL {
        var candidate = folder.appending(path: base + ".png")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(base) \(number).png")
            number += 1
        }
        return candidate
    }

    /// Deletes the temp folders of captures not in `keep`.
    public func purge(keeping keep: [Capture]) {
        let used = Set(keep.map { $0.file.deletingLastPathComponent().lastPathComponent })
        let items = (try? FileManager.default.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: nil)) ?? []
        for item in items where !used.contains(item.lastPathComponent) && UUID(uuidString: item.lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
