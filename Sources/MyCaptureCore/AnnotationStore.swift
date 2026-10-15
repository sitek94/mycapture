import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps a capture editable after it is annotated. The capture's folder gets `original.png` (the pixels before the
/// first edit) and `markups.json`; the capture file itself always holds the rendered result, so drag, copy and save
/// keep working on it. Purging the capture's folder removes all three.
public struct AnnotationStore: Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    var folder: URL { file.deletingLastPathComponent() }
    var originalFile: URL { folder.appending(path: "original.png") }
    var markupsFile: URL { folder.appending(path: "markups.json") }

    /// The pixels to draw on: the original if the capture was annotated before.
    public func loadImage() -> (image: CGImage, properties: [CFString: Any])? {
        let source = FileManager.default.fileExists(atPath: originalFile.path(percentEncoded: false)) ? originalFile : file
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        return (image, properties)
    }

    public func loadMarkups() -> [Markup] {
        guard let data = try? Data(contentsOf: markupsFile), let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return []
        }
        return saved.markups
    }

    /// Writes the rendered image into the capture file and keeps the original and the markups beside it.
    /// The capture file is overwritten in place, so its attributes (the screenshot marks) stay.
    public func save(_ markups: [Markup], image: CGImage, properties: [CFString: Any]) throws {
        if !FileManager.default.fileExists(atPath: originalFile.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: file, to: originalFile)
        }
        guard let rendered = MarkupRenderer.render(image, markups: markups) else { throw CocoaError(.fileWriteUnknown) }
        let data = try Self.png(rendered, properties: properties)
        try JSONEncoder().encode(Saved(version: 1, markups: markups)).write(to: markupsFile, options: .atomic)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
    }

    /// PNG data with the source's resolution, so a Retina capture still opens at its point size.
    static func png(_ image: CGImage, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var kept: [CFString: Any] = [:]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] { kept[key] = properties[key] }
        CGImageDestinationAddImage(destination, image, kept as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    private struct Saved: Codable {
        var version: Int
        var markups: [Markup]
    }
}
