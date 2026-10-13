import Foundation

/// File names for captures: `yy-MM-dd HH.mm.ss <app> - <title>`, for example `26-10-12 19.26.43 Safari - Pull requests`.
public struct FileNamer: Sendable {
    /// Longest window title kept in a name; longer titles are cut.
    public static let maxTitleLength = 60
    /// Longest base name in UTF-8 bytes: APFS allows 255 per name, and " 99.png" must still fit.
    public static let maxBaseBytes = 240

    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public func baseName(date: Date, app: String?, title: String?) -> String {
        var name = timestamp(date)
        if let app = Self.clean(app) {
            name += " " + app
            if let title = Self.clean(title) {
                name += " - " + String(title.prefix(Self.maxTitleLength)).trimmingCharacters(in: .whitespaces)
            }
        }
        // Emoji and CJK take up to 4 bytes per character: cut whole characters until the name fits.
        while name.utf8.count > Self.maxBaseBytes { name.removeLast() }
        return name.trimmingCharacters(in: .whitespaces)
    }

    public func fileName(date: Date, app: String?, title: String?) -> String {
        baseName(date: date, app: app, title: title) + ".png"
    }

    private func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%02d-%02d-%02d %02d.%02d.%02d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Characters a file name cannot hold (`/`, and `:` which Finder shows as `/`) become `-`; line breaks become spaces.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned =
            text
            .replacing(/[\/:]/, with: "-")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }
}
