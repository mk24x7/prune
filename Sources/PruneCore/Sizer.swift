import Foundation

public enum Sizer {
    /// Allocated size of a directory tree via `/usr/bin/du -sk`.
    ///
    /// du exits non-zero when it cannot read part of the tree but still prints
    /// the total of what it could read, so stdout is parsed regardless of the
    /// exit status. Returns nil (size unknown) only when du cannot be launched,
    /// is terminated (including by task cancellation), or prints nothing usable.
    public static func diskSize(at url: URL) async -> Int64? {
        if Task.isCancelled { return nil }
        let box = DuProcess(path: url.path)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int64?, Never>) in
                box.start { continuation.resume(returning: $0) }
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Allocated (on-disk) size of a single regular file, matching what du
    /// reports. Sparse files such as Docker.raw have a far larger apparent size
    /// (64 GB) than the space they occupy, so the apparent size is never used.
    public static func fileSize(at url: URL) -> Int64? {
        if let allocated = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
            return Int64(allocated)
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Int64(info.st_blocks) * 512
    }

    /// Human-facing project name for an artifact, driven by the type's `nameFrom`.
    public static func projectName(for url: URL, type: ArtifactType) -> String {
        let parent = url.deletingLastPathComponent()
        let parentName = parent.lastPathComponent

        switch type.nameFrom {
        case .packageJson:
            return readJSONName(at: parent.appendingPathComponent("package.json")) ?? parentName
        case .cargoToml:
            return readTomlPackageName(at: parent.appendingPathComponent("Cargo.toml")) ?? parentName
        case .packageSwift:
            return readSwiftPackageName(at: parent.appendingPathComponent("Package.swift")) ?? parentName
        case .gradleSettings:
            return readGradleProjectName(in: parent) ?? parentName
        case .derivedData:
            // DerivedData folders are named "<Project>-<hash>".
            let name = url.lastPathComponent
            if let dash = name.range(of: "-", options: .backwards), dash.lowerBound != name.startIndex {
                return String(name[name.startIndex..<dash.lowerBound])
            }
            return name
        case .dirname:
            return url.lastPathComponent
        case .parentDirname:
            return parentName
        }
    }

    /// max(mtime of the item, mtimes of its direct children). Files use their own mtime.
    public static func lastModified(of url: URL, isFile: Bool) -> Date {
        let fm = FileManager.default
        var newest = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        if !isFile, let children = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        ) {
            for child in children {
                guard let date = try? child.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate else { continue }
                if newest == nil || date > newest! { newest = date }
            }
        }
        return newest ?? Date()
    }

    /// Measure and describe one artifact.
    public static func buildEntry(for url: URL, type: ArtifactType) async -> ArtifactEntry {
        let isFile = type.entriesAreFiles
        let size: Int64? = isFile ? fileSize(at: url) : await diskSize(at: url)
        return ArtifactEntry(
            url: url,
            typeId: type.id,
            projectName: projectName(for: url, type: type),
            sizeBytes: size ?? 0,
            sizeUnknown: size == nil,
            lastModified: lastModified(of: url, isFile: isFile)
        )
    }

    // MARK: - Manifest readers (nil means "fall back")

    static func readJSONName(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String
        else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func readTomlPackageName(at url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inPackage = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inPackage = trimmed == "[package]"
                continue
            }
            guard inPackage, trimmed.hasPrefix("name") else { continue }
            let rest = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("=") else { continue }
            let value = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
            let body = value.dropFirst()
            guard let end = body.firstIndex(of: quote) else { return nil }
            let name = String(body[body.startIndex..<end])
            return name.isEmpty ? nil : name
        }
        return nil
    }

    static func readSwiftPackageName(at url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return firstCapture(#"Package\s*\(\s*name\s*:\s*"([^"]+)""#, in: content)
    }

    static func readGradleProjectName(in dir: URL) -> String? {
        for filename in ["settings.gradle", "settings.gradle.kts"] {
            guard let content = try? String(contentsOf: dir.appendingPathComponent(filename), encoding: .utf8)
            else { continue }
            if let name = firstCapture(#"rootProject\.name\s*=\s*['"]([^'"]+)['"]"#, in: content) {
                return name
            }
        }
        return nil
    }

    private static func firstCapture(_ pattern: String, in content: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content)
        else { return nil }
        let value = String(content[range])
        return value.isEmpty ? nil : value
    }
}

/// Owns one `du -sk` process and makes launch, completion and cancellation
/// race-free: `terminate()` must never be sent to a process that has not been
/// launched, and the completion must fire exactly once.
private final class DuProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let pipe = Pipe()
    private var launched = false
    private var cancelled = false

    init(path: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
    }

    func start(completion: @escaping @Sendable (Int64?) -> Void) {
        let pipe = self.pipe
        process.terminationHandler = { process in
            // du prints a single short line, so reading after exit cannot block on a full pipe.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if process.terminationReason == .uncaughtSignal {
                completion(nil)
                return
            }
            completion(Self.parse(data))
        }

        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            completion(nil)
            return
        }
        do {
            try process.run()
            launched = true
        } catch {
            completion(nil)
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if launched && process.isRunning {
            process.terminate()
        }
    }

    static func parse(_ data: Data) -> Int64? {
        guard let output = String(data: data, encoding: .utf8),
              let field = output.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first,
              let kilobytes = Int64(field)
        else { return nil }
        return kilobytes * 1024
    }
}
