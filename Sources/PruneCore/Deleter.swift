import Foundation

public enum DeleteMode: String, Sendable, Codable {
    case trash, permanent
}

public enum DeletionFailure: Error, Equatable, Sendable, LocalizedError {
    /// The Verifier refused the item; nothing was touched.
    case verification(String)
    /// The volume (or item) cannot be moved to the Trash.
    case trashUnsupported(String)
    /// Permission denied even after making the tree writable.
    case permission(String)
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .verification(let reason): return "Safety check failed: \(reason)"
        case .trashUnsupported(let reason): return "Could not move to Trash: \(reason)"
        case .permission(let reason): return "Permission denied: \(reason)"
        case .other(let reason): return reason
        }
    }
}

public struct DeletionOutcome: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case trashed(URL)
        case deleted
        /// Nothing to do; `alreadyGone` counts as success.
        case skipped(String)
        case failed(DeletionFailure)
    }

    public static let alreadyGone = "already gone"

    public let entry: ArtifactEntry
    public let status: Status

    public init(entry: ArtifactEntry, status: Status) {
        self.entry = entry
        self.status = status
    }

    public var url: URL { entry.url }

    /// The item is no longer at its original location.
    public var isSuccess: Bool {
        switch status {
        case .trashed, .deleted: return true
        case .skipped(let reason): return reason == Self.alreadyGone
        case .failed: return false
        }
    }

    public var failure: DeletionFailure? {
        if case .failed(let failure) = status { return failure }
        return nil
    }

    public var isTrashUnsupported: Bool {
        if case .failed(.trashUnsupported) = status { return true }
        return false
    }
}

public enum DeletionEvent: Sendable {
    case started(index: Int, total: Int, entry: ArtifactEntry)
    case finished(index: Int, total: Int, outcome: DeletionOutcome)
}

/// Deletes verified artifacts one at a time, either into the Trash or permanently.
public struct Deleter {
    /// Moves an item to the Trash and returns where it ended up.
    public typealias TrashFunction = (URL) throws -> URL?

    public let mode: DeleteMode
    public let scanRoot: URL
    public let definitions: Definitions
    public let log: DeletionLog?
    private let fm: FileManager
    private let env: [String: String]
    private let home: URL
    private let trash: TrashFunction

    public init(
        mode: DeleteMode,
        scanRoot: URL,
        definitions: Definitions,
        log: DeletionLog?,
        fm: FileManager = .default,
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        trash: TrashFunction? = nil
    ) {
        self.mode = mode
        self.scanRoot = scanRoot
        self.definitions = definitions
        self.log = log
        self.fm = fm
        self.env = env
        self.home = home
        self.trash = trash ?? { url in
            var resulting: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        }
    }

    public func delete(
        _ entries: [ArtifactEntry],
        progress: (DeletionEvent) -> Void = { _ in }
    ) async -> [DeletionOutcome] {
        var outcomes: [DeletionOutcome] = []
        outcomes.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            progress(.started(index: index, total: entries.count, entry: entry))
            let outcome = deleteOne(entry)
            log?.record(outcome, mode: mode)
            outcomes.append(outcome)
            progress(.finished(index: index, total: entries.count, outcome: outcome))
            await Task.yield()
        }
        return outcomes
    }

    func deleteOne(_ entry: ArtifactEntry) -> DeletionOutcome {
        // A project artifact nested in a system cache deleted earlier in the
        // same batch is simply gone; that is success, not failure.
        if FileKind.of(entry.url) == .missing {
            return DeletionOutcome(entry: entry, status: .skipped(DeletionOutcome.alreadyGone))
        }
        guard let type = definitions.type(id: entry.typeId) else {
            return DeletionOutcome(entry: entry, status: .failed(.verification("unknown artifact type \(entry.typeId)")))
        }
        do {
            try Verifier.verify(entry: entry, type: type, scanRoot: scanRoot, definitions: definitions,
                                env: env, home: home, fm: fm)
        } catch let failure as DeletionFailure {
            return DeletionOutcome(entry: entry, status: .failed(failure))
        } catch {
            return DeletionOutcome(entry: entry, status: .failed(.verification(error.localizedDescription)))
        }

        switch mode {
        case .trash:
            do {
                let destination = try trash(entry.url)
                return DeletionOutcome(entry: entry, status: .trashed(destination ?? entry.url))
            } catch {
                if error.isNoSuchFileError {
                    return DeletionOutcome(entry: entry, status: .skipped(DeletionOutcome.alreadyGone))
                }
                return DeletionOutcome(entry: entry, status: .failed(.trashUnsupported(error.localizedDescription)))
            }
        case .permanent:
            return removePermanently(entry)
        }
    }

    private func removePermanently(_ entry: ArtifactEntry) -> DeletionOutcome {
        do {
            try fm.removeItem(at: entry.url)
            return DeletionOutcome(entry: entry, status: .deleted)
        } catch {
            if error.isNoSuchFileError {
                return DeletionOutcome(entry: entry, status: .skipped(DeletionOutcome.alreadyGone))
            }
            guard error.isPermissionError else {
                return DeletionOutcome(entry: entry, status: .failed(.other(error.localizedDescription)))
            }
        }
        // Read-only trees (the Go module cache is 0444/0555) need the owner
        // write bit before their contents can be unlinked. Retry once.
        Self.makeWritable(entry.url, fm: fm)
        do {
            try fm.removeItem(at: entry.url)
            return DeletionOutcome(entry: entry, status: .deleted)
        } catch {
            if error.isNoSuchFileError || FileKind.of(entry.url) == .missing {
                return DeletionOutcome(entry: entry, status: .skipped(DeletionOutcome.alreadyGone))
            }
            let failure: DeletionFailure = error.isPermissionError
                ? .permission(error.localizedDescription) : .other(error.localizedDescription)
            return DeletionOutcome(entry: entry, status: .failed(failure))
        }
    }

    /// Add the owner write bit to every directory and file below `url`
    /// (directories also get owner read and search so they can be walked).
    /// Symlinks are skipped because chmod(2) would follow them.
    static func makeWritable(_ url: URL, fm: FileManager) {
        func addOwnerBits(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0 else { return }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: _ = chmod(path, (info.st_mode & 0o7777) | S_IRWXU)
            case S_IFREG: _ = chmod(path, (info.st_mode & 0o7777) | S_IWUSR)
            default: break
            }
        }
        addOwnerBits(url.path)
        guard FileKind.of(url) == .directory, let walker = fm.enumerator(atPath: url.path) else { return }
        // The enumerator lists a directory only when it descends into it, which
        // happens after the directory itself has been returned (and fixed) here.
        while let relative = walker.nextObject() as? String {
            addOwnerBits(url.appendingPathComponent(relative).path)
        }
    }
}
