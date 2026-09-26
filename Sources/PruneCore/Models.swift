import Foundation

// MARK: - Artifact Entry

public struct ArtifactEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let typeId: String
    public let projectName: String
    /// Allocated size in bytes. Meaningless when `sizeUnknown` is true.
    public let sizeBytes: Int64
    /// True when the size could not be measured (du failed to launch or was
    /// terminated). Unknown sizes render as "?" and are excluded from totals.
    public let sizeUnknown: Bool
    public let lastModified: Date

    public init(url: URL, typeId: String, projectName: String, sizeBytes: Int64,
                sizeUnknown: Bool = false, lastModified: Date) {
        self.url = url
        self.typeId = typeId
        self.projectName = projectName
        self.sizeBytes = sizeBytes
        self.sizeUnknown = sizeUnknown
        self.lastModified = lastModified
    }

    public var id: URL { url }

    /// Size that counts towards totals: zero when unknown.
    public var countedBytes: Int64 { sizeUnknown ? 0 : sizeBytes }

    public var formattedSize: String {
        sizeUnknown ? "?" : Formatter.formatSize(sizeBytes)
    }

    public var shortPath: String { Formatter.shortenPath(url.path) }

    public var age: String { Formatter.formatAge(lastModified) }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: ArtifactEntry, rhs: ArtifactEntry) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Deletion

public struct DeletionItem: Identifiable {
    public let id = UUID()
    public let entry: ArtifactEntry
    public var status: DeletionStatus = .pending
    public var error: String?

    public init(entry: ArtifactEntry) {
        self.entry = entry
    }
}

public enum DeletionStatus {
    case pending, inProgress, done, failed
}

// MARK: - App State

public enum AppPhase {
    case idle, scanning, results, deleting, summary
}

public enum SortField: String, CaseIterable {
    case size = "Size"
    case name = "Name"
    case age = "Age"
    case path = "Path"
}
