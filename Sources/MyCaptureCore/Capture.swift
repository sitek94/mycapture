import CoreGraphics
import Foundation

/// One capture: the image file plus what is known about it, so later actions (save, copy, annotate) can use it.
public struct Capture: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// The image in the temp folder. Saving copies it out; the temp file stays for restore.
    public var file: URL
    public var date: Date
    public var kind: Kind
    /// Global top-left coordinates, in points.
    public var rect: CGRect?
    public var app: String?
    public var title: String?

    /// What the capture tool says it captured.
    public enum Kind: String, Codable, Sendable {
        case selection, window
    }

    public init(id: UUID = UUID(), file: URL, date: Date, kind: Kind, rect: CGRect?, app: String? = nil, title: String? = nil) {
        self.id = id
        self.file = file
        self.date = date
        self.kind = kind
        self.rect = rect
        self.app = app
        self.title = title
    }
}

/// The attributes Apple's capture tool writes on its output: the capture type and the global rect.
public enum ScreenCaptureAttributes {
    public static let typeKey = "com.apple.metadata:kMDItemScreenCaptureType"
    public static let rectKey = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"

    public static func read(_ file: URL) -> (kind: Capture.Kind, rect: CGRect?)? {
        guard let type = value(typeKey, of: file) as? String else { return nil }
        let kind: Capture.Kind = type == "window" ? .window : .selection
        let numbers = (value(rectKey, of: file) as? [NSNumber])?.map(\.doubleValue)
        let rect = numbers.flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        return (kind, rect)
    }

    static func value(_ name: String, of file: URL) -> Any? {
        let path = file.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    /// Writes a value as a binary plist, the way the capture tool does. Used by tests.
    static func write(_ value: Any, _ name: String, to file: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(file.path(percentEncoded: false), name, $0.baseAddress, data.count, 0, 0) }
        if result != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}
