import CoreGraphics
import Foundation

/// What a capture shortcut captures.
public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    case area
    case window
}

/// What happens to a capture right after it is taken.
public enum CaptureDestination: String, Codable, Sendable {
    /// The floating thumbnail; nothing is saved until Save or a drag.
    case thumbnail
    /// The clipboard only, with a "Copied" toast.
    case clipboard
}

/// The arguments for Apple's `/usr/sbin/screencapture`, which does the selection, the window picker and the shadow.
public struct CaptureCommand: Equatable, Sendable {
    public static let executable = URL(filePath: "/usr/sbin/screencapture")

    public var arguments: [String]

    /// Interactive capture into `output`. Area starts in selection mode, window in window mode;
    /// `Space` switches between them, as in `⇧⌘4`.
    public static func interactive(_ mode: CaptureMode, output: URL, sound: Bool) -> CaptureCommand {
        var arguments = ["-i"]
        if mode == .window { arguments.append("-W") }
        if !sound { arguments.append("-x") }
        arguments.append(output.path(percentEncoded: false))
        return CaptureCommand(arguments: arguments)
    }

    /// A capture of a fixed rect (global top-left coordinates, points) with no user input, for test runs.
    public static func rect(_ rect: CGRect, output: URL) -> CaptureCommand {
        let whole = rect.integral
        let value = "\(Int(whole.minX)),\(Int(whole.minY)),\(Int(whole.width)),\(Int(whole.height))"
        return CaptureCommand(arguments: ["-x", "-R", value, output.path(percentEncoded: false)])
    }
}
