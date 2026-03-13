import Foundation

struct NodeModuleEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let projectName: String
    let sizeBytes: Int64
    let formattedSize: String
    let shortPath: String
    let age: String
    let lastModified: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: NodeModuleEntry, rhs: NodeModuleEntry) -> Bool {
        lhs.url == rhs.url
    }
}

struct DeletionItem: Identifiable {
    let id = UUID()
    let entry: NodeModuleEntry
    var status: DeletionStatus = .pending
    var error: String?
}

enum DeletionStatus {
    case pending, inProgress, done, failed
}

enum AppPhase {
    case idle, scanning, results, deleting, summary
}

enum SortField: String, CaseIterable {
    case size = "Size"
    case name = "Name"
    case age = "Age"
    case path = "Path"
}
