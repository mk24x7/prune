import Foundation

/// Append-only JSON Lines record of every deletion attempt, shared in shape
/// with the CLI: `~/Library/Logs/Prune/deletions.jsonl` (or `$PRUNE_LOG_DIR`).
/// One line per item plus one `"event": "run"` line per batch. The file is
/// renamed with a timestamp suffix once it reaches 5 MB.
public final class DeletionLog: @unchecked Sendable {
    public static let fileName = "deletions.jsonl"
    public static let rotateBytes: Int64 = 5 * 1024 * 1024

    public let directory: URL
    public let tool: String
    public let version: String
    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(directory: URL? = nil, tool: String = "app", version: String,
                env: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.directory = directory ?? Self.defaultDirectory(env: env, home: home)
        self.tool = tool
        self.version = version
    }

    public static func defaultDirectory(env: [String: String] = ProcessInfo.processInfo.environment,
                                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let override = env["PRUNE_LOG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Library/Logs/Prune", isDirectory: true)
    }

    struct ItemLine: Encodable {
        let ts: String
        let tool: String
        let version: String
        let mode: String
        let typeId: String
        let path: String
        let estimatedBytes: Int64?
        let result: String
        let trashedTo: String?
        let error: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ts, forKey: .ts)
            try c.encode(tool, forKey: .tool)
            try c.encode(version, forKey: .version)
            try c.encode(mode, forKey: .mode)
            try c.encode(typeId, forKey: .typeId)
            try c.encode(path, forKey: .path)
            // Unknown sizes are logged as null rather than a misleading 0.
            try c.encode(estimatedBytes, forKey: .estimatedBytes)
            try c.encode(result, forKey: .result)
            try c.encodeIfPresent(trashedTo, forKey: .trashedTo)
            try c.encodeIfPresent(error, forKey: .error)
        }

        enum CodingKeys: String, CodingKey {
            case ts, tool, version, mode, typeId, path, estimatedBytes, result, trashedTo, error
        }
    }

    struct RunLine: Encodable {
        let event = "run"
        let ts: String
        let scanRoot: String
        let selected: Int
        let ok: Int
        let failed: Int
        let estimatedBytes: Int64
        let measuredFreedBytes: Int64
    }

    public func record(_ outcome: DeletionOutcome, mode: DeleteMode) {
        let result: String
        var trashedTo: String?
        var error: String?
        switch outcome.status {
        case .trashed(let destination):
            result = "trashed"
            trashedTo = destination.path
        case .deleted:
            result = "deleted"
        case .skipped(let reason):
            result = reason == DeletionOutcome.alreadyGone ? "gone" : "skipped"
            error = reason == DeletionOutcome.alreadyGone ? nil : reason
        case .failed(let failure):
            result = "failed"
            error = failure.localizedDescription
        }
        let entry = outcome.entry
        append(ItemLine(
            ts: Self.timestamp(), tool: tool, version: version, mode: mode.rawValue,
            typeId: entry.typeId, path: entry.url.path,
            estimatedBytes: entry.sizeUnknown ? nil : entry.sizeBytes,
            result: result, trashedTo: trashedTo, error: error))
    }

    public func recordRun(scanRoot: URL, selected: Int, ok: Int, failed: Int,
                          estimatedBytes: Int64, measuredFreedBytes: Int64) {
        append(RunLine(ts: Self.timestamp(), scanRoot: scanRoot.path, selected: selected, ok: ok,
                       failed: failed, estimatedBytes: estimatedBytes, measuredFreedBytes: measuredFreedBytes))
    }

    private func append<T: Encodable>(_ line: T) {
        guard var data = try? encoder.encode(line) else { return }
        data.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded(fm)
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never block a deletion; failures are ignored.
        }
    }

    private func rotateIfNeeded(_ fm: FileManager) {
        guard let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber,
              size.int64Value >= Self.rotateBytes else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var target = directory.appendingPathComponent("deletions-\(formatter.string(from: Date())).jsonl")
        var counter = 1
        while fm.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("deletions-\(formatter.string(from: Date()))-\(counter).jsonl")
            counter += 1
        }
        try? fm.moveItem(at: fileURL, to: target)
    }

    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
