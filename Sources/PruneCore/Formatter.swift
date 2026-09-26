import Foundation

public enum Formatter {
    public static func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    public static func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    public static func formatAge(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        let days = seconds / 86400
        let weeks = days / 7
        let months = days / 30
        let years = days / 365

        if years > 0 { return "\(years) year\(years > 1 ? "s" : "") ago" }
        if months > 0 { return "\(months) month\(months > 1 ? "s" : "") ago" }
        if weeks > 0 { return "\(weeks) week\(weeks > 1 ? "s" : "") ago" }
        if days > 0 { return "\(days) day\(days > 1 ? "s" : "") ago" }
        return "today"
    }

    public static func sizeSeverity(_ bytes: Int64) -> SizeSeverity {
        if bytes > 500 * 1_048_576 { return .large }
        if bytes > 100 * 1_048_576 { return .medium }
        return .small
    }
}

public enum SizeSeverity {
    case small, medium, large
}
