import Foundation

enum Sizer {
    /// Calculate disk size using `du -sk` (fast, handles large dirs well).
    static func diskSize(at url: URL) -> Int64 {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return 0
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return 0 }
        let sizeStr = output.split(separator: "\t").first ?? "0"
        return (Int64(sizeStr) ?? 0) * 1024
    }

    /// Extract project name from the parent directory's package.json.
    static func projectName(for nodeModulesURL: URL) -> String {
        let projectDir = nodeModulesURL.deletingLastPathComponent()
        let fallback = projectDir.lastPathComponent
        let pkgURL = projectDir.appendingPathComponent("package.json")

        guard let data = try? Data(contentsOf: pkgURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty
        else { return fallback }

        return name
    }

    /// Build a full NodeModuleEntry with size, name, and metadata.
    static func buildEntry(for url: URL) -> NodeModuleEntry {
        let sizeBytes = diskSize(at: url)
        let projectName = projectName(for: url)
        let lastModified = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.modificationDate] as? Date) ?? Date()

        return NodeModuleEntry(
            url: url,
            projectName: projectName,
            sizeBytes: sizeBytes,
            formattedSize: Formatter.formatSize(sizeBytes),
            shortPath: Formatter.shortenPath(url.path),
            age: Formatter.formatAge(lastModified),
            lastModified: lastModified
        )
    }
}

enum Formatter {
    static func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    static func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func formatAge(_ date: Date) -> String {
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

    static func sizeSeverity(_ bytes: Int64) -> SizeSeverity {
        if bytes > 500 * 1_048_576 { return .large }
        if bytes > 100 * 1_048_576 { return .medium }
        return .small
    }
}

enum SizeSeverity {
    case small, medium, large
}
