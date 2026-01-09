import Foundation

enum AtlasDateFormatters {
    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()
}
