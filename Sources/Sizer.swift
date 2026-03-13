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

    /// Extract project name for a given artifact URL based on its category.
    static func projectName(for url: URL, category: ArtifactCategory) -> String {
        let parentDir = url.deletingLastPathComponent()
        let fallback = parentDir.lastPathComponent

        switch category {
        case .nodeModules:
            return readJSONName(at: parentDir.appendingPathComponent("package.json"), fallback: fallback)

        case .rust:
            return readTomlName(at: parentDir.appendingPathComponent("Cargo.toml"), fallback: fallback)

        case .swiftPM:
            // Try to extract name from Package.swift, fall back to directory name
            return readSwiftPackageName(at: parentDir.appendingPathComponent("Package.swift"), fallback: fallback)

        case .cocoapods:
            return fallback

        case .gradleBuild, .gradleCache:
            return readGradleProjectName(in: parentDir, fallback: fallback)

        case .pythonVenv, .pythonCache:
            return fallback

        case .xcodeDerivedData:
            // DerivedData subdirs are like "ProjectName-hashstring"
            let name = url.lastPathComponent
            if let dashRange = name.range(of: "-", options: .backwards) {
                return String(name[name.startIndex..<dashRange.lowerBound])
            }
            return name

        case .xcodeArchives:
            return url.lastPathComponent

        case .xcodeDeviceSupport:
            return url.lastPathComponent

        case .xcodeCache, .gradleGlobalCache, .homebrewCache:
            return url.lastPathComponent
        }
    }

    /// Build a full ArtifactEntry with size, name, and metadata.
    static func buildEntry(for url: URL, category: ArtifactCategory) -> ArtifactEntry {
        let sizeBytes = diskSize(at: url)
        let name = projectName(for: url, category: category)
        let lastModified = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.modificationDate] as? Date) ?? Date()

        return ArtifactEntry(
            url: url,
            projectName: name,
            sizeBytes: sizeBytes,
            formattedSize: Formatter.formatSize(sizeBytes),
            shortPath: Formatter.shortenPath(url.path),
            age: Formatter.formatAge(lastModified),
            lastModified: lastModified,
            category: category
        )
    }

    // MARK: - Private Helpers

    private static func readJSONName(at url: URL, fallback: String) -> String {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty
        else { return fallback }
        return name
    }

    private static func readTomlName(at url: URL, fallback: String) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        // Simple parse: look for name = "value" under [package]
        var inPackage = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[package]" {
                inPackage = true
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inPackage = false
                continue
            }
            if inPackage && (trimmed.hasPrefix("name =") || trimmed.hasPrefix("name=")) {
                // name = "my-crate"
                if let eqIndex = trimmed.firstIndex(of: "=") {
                    var value = String(trimmed[trimmed.index(after: eqIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty { return value }
                }
            }
        }
        return fallback
    }

    private static func readSwiftPackageName(at url: URL, fallback: String) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        // Look for: name: "PackageName"
        let pattern = #"name:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content)
        else { return fallback }
        return String(content[range])
    }

    private static func readGradleProjectName(in dir: URL, fallback: String) -> String {
        // Try settings.gradle or settings.gradle.kts for rootProject.name
        for filename in ["settings.gradle", "settings.gradle.kts"] {
            let settingsURL = dir.appendingPathComponent(filename)
            guard let content = try? String(contentsOf: settingsURL, encoding: .utf8) else { continue }
            // rootProject.name = "my-project" or rootProject.name = 'my-project'
            let pattern = #"rootProject\.name\s*=\s*['"]([^'"]+)['"]"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let range = Range(match.range(at: 1), in: content)
            else { continue }
            return String(content[range])
        }
        return fallback
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
