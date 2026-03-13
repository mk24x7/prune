import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle

    // Config
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var scanRootDisplay: String = "~"
    @Published var includeHidden: Bool = false

    // Scanning
    @Published var scanProgress: String = ""
    @Published var foundCount: Int = 0
    @Published var sizingProgress: (completed: Int, total: Int)?

    // Results
    @Published var entries: [NodeModuleEntry] = []
    @Published var selectedPaths: Set<URL> = []
    @Published var sortField: SortField = .size
    @Published var sortAscending: Bool = false

    // Deleting
    @Published var deletionItems: [DeletionItem] = []
    @Published var deletionCurrent: Int = 0
    @Published var deletionTotal: Int = 0

    // Summary
    @Published var deletedCount: Int = 0
    @Published var failedCount: Int = 0
    @Published var freedBytes: Int64 = 0
    @Published var failures: [(path: String, error: String)] = []

    private var scanner = Scanner()
    private var scanTask: Task<Void, Never>?

    var selectedEntries: [NodeModuleEntry] {
        entries.filter { selectedPaths.contains($0.url) }
    }

    var selectedTotalSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    var sortedEntries: [NodeModuleEntry] {
        entries.sorted { a, b in
            let cmp: Bool
            switch sortField {
            case .size: cmp = a.sizeBytes < b.sizeBytes
            case .name: cmp = a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
            case .age: cmp = a.lastModified < b.lastModified
            case .path: cmp = a.shortPath < b.shortPath
            }
            return sortAscending ? cmp : !cmp
        }
    }

    func setScanRoot(_ url: URL) {
        scanRoot = url
        scanRootDisplay = Formatter.shortenPath(url.path)
    }

    func startScan() {
        phase = .scanning
        scanProgress = ""
        foundCount = 0
        sizingProgress = nil
        entries = []
        selectedPaths = []

        scanTask = Task.detached { [weak self] in
            guard let self else { return }
            let scanner = await self.scanner
            let root = await self.scanRoot
            let includeHidden = await self.includeHidden

            let paths = await scanner.scan(
                root: root,
                includeHidden: includeHidden,
                onProgress: { dir in
                    Task { @MainActor [weak self] in
                        self?.scanProgress = Formatter.shortenPath(dir)
                    }
                },
                onFound: { _, count in
                    Task { @MainActor [weak self] in
                        self?.foundCount = count
                    }
                }
            )

            // Check if cancelled
            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                self?.sizingProgress = (completed: 0, total: paths.count)
            }

            // Calculate sizes (on background thread)
            var builtEntries: [NodeModuleEntry] = []
            for (index, url) in paths.enumerated() {
                if Task.isCancelled { return }
                let entry = Sizer.buildEntry(for: url)
                builtEntries.append(entry)
                await MainActor.run { [weak self] in
                    self?.sizingProgress = (completed: index + 1, total: paths.count)
                }
            }

            if Task.isCancelled { return }

            // Sort by size descending
            builtEntries.sort { $0.sizeBytes > $1.sizeBytes }

            await MainActor.run { [weak self] in
                self?.entries = builtEntries
                self?.sizingProgress = nil
                self?.phase = .results
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        Task {
            await scanner.cancel()
        }
        phase = .idle
        scanProgress = ""
        foundCount = 0
        sizingProgress = nil
    }

    func toggleSelection(_ entry: NodeModuleEntry) {
        if selectedPaths.contains(entry.url) {
            selectedPaths.remove(entry.url)
        } else {
            selectedPaths.insert(entry.url)
        }
    }

    func selectAll() {
        selectedPaths = Set(entries.map(\.url))
    }

    func deselectAll() {
        selectedPaths = []
    }

    func toggleSort(_ field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = false
        }
    }

    func startDeletion() {
        let selected = selectedEntries
        deletionItems = selected.map { DeletionItem(entry: $0) }
        deletionCurrent = 0
        deletionTotal = selected.count
        phase = .deleting

        Task.detached { [weak self] in
            guard let self else { return }
            let items = await self.deletionItems
            let urls = items.map(\.entry.url)

            let result = Deleter.delete(urls: urls) { current, total, url in
                Task { @MainActor [weak self] in
                    self?.deletionCurrent = current
                    self?.deletionTotal = total
                    if let idx = self?.deletionItems.firstIndex(where: { $0.entry.url == url }) {
                        self?.deletionItems[idx].status = .inProgress
                    }
                }
                // Small delay to let UI update
                Thread.sleep(forTimeInterval: 0.05)
            }

            // Mark completed items
            await MainActor.run { [weak self] in
                guard let self else { return }
                for url in result.deleted {
                    if let idx = self.deletionItems.firstIndex(where: { $0.entry.url == url }) {
                        self.deletionItems[idx].status = .done
                    }
                }
                for (url, error) in result.failed {
                    if let idx = self.deletionItems.firstIndex(where: { $0.entry.url == url }) {
                        self.deletionItems[idx].status = .failed
                        self.deletionItems[idx].error = error
                    }
                }

                self.freedBytes = result.deleted.compactMap { url in
                    self.entries.first { $0.url == url }?.sizeBytes
                }.reduce(0, +)

                self.deletedCount = result.deleted.count
                self.failedCount = result.failed.count
                self.failures = result.failed.map {
                    (path: Formatter.shortenPath($0.url.path), error: $0.error)
                }
                self.phase = .summary
            }
        }
    }

    func reset() {
        phase = .idle
        entries = []
        selectedPaths = []
        scanProgress = ""
        foundCount = 0
        sizingProgress = nil
        deletionItems = []
        deletedCount = 0
        failedCount = 0
        freedBytes = 0
        failures = []
    }
}
