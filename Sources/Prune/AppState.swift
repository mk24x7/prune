import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle

    // Config
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var scanRootDisplay: String = "~"
    @Published var includeHidden: Bool = false
    @Published var selectedCategories: Set<ArtifactCategory> = Set(ArtifactCategory.allCases)

    // Scanning
    @Published var scanProgress: String = ""
    @Published var foundCount: Int = 0
    @Published var sizingProgress: (completed: Int, total: Int)?

    // Results
    @Published var entries: [ArtifactEntry] = []
    @Published var selectedPaths: Set<URL> = []
    @Published var sortField: SortField = .size
    @Published var sortAscending: Bool = false
    @Published var filterCategory: ArtifactCategory? = nil

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

    var selectedEntries: [ArtifactEntry] {
        entries.filter { selectedPaths.contains($0.url) }
    }

    var selectedTotalSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Categories that have results
    var categoriesWithResults: [ArtifactCategory] {
        let cats = Set(entries.map(\.category))
        return ArtifactCategory.allCases.filter { cats.contains($0) }
    }

    /// Entries filtered by selected category filter and sorted
    var sortedEntries: [ArtifactEntry] {
        let filtered: [ArtifactEntry]
        if let cat = filterCategory {
            filtered = entries.filter { $0.category == cat }
        } else {
            filtered = entries
        }

        return filtered.sorted { a, b in
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

    /// Per-category size breakdown for summary
    var categoryBreakdown: [(category: ArtifactCategory, count: Int, bytes: Int64)] {
        var map: [ArtifactCategory: (count: Int, bytes: Int64)] = [:]
        for entry in entries {
            if selectedPaths.contains(entry.url) || phase == .summary {
                let existing = map[entry.category] ?? (count: 0, bytes: 0)
                // In summary phase, only count deleted items
                if phase == .summary {
                    if deletionItems.first(where: { $0.entry.url == entry.url })?.status == .done {
                        map[entry.category] = (count: existing.count + 1, bytes: existing.bytes + entry.sizeBytes)
                    }
                } else {
                    map[entry.category] = (count: existing.count + 1, bytes: existing.bytes + entry.sizeBytes)
                }
            }
        }
        return map.map { (category: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            .sorted { $0.bytes > $1.bytes }
    }

    var hasProjectCategories: Bool {
        !selectedCategories.intersection(Set(ArtifactCategory.projectLevel)).isEmpty
    }

    var hasSystemCategories: Bool {
        !selectedCategories.intersection(Set(ArtifactCategory.systemLevel)).isEmpty
    }

    func setScanRoot(_ url: URL) {
        scanRoot = url
        scanRootDisplay = Formatter.shortenPath(url.path)
    }

    func toggleCategory(_ category: ArtifactCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    func selectAllCategories() {
        selectedCategories = Set(ArtifactCategory.allCases)
    }

    func deselectAllCategories() {
        selectedCategories = []
    }

    func startScan() {
        phase = .scanning
        scanProgress = ""
        foundCount = 0
        sizingProgress = nil
        entries = []
        selectedPaths = []
        filterCategory = nil

        scanTask = Task.detached { [weak self] in
            guard let self else { return }
            let scanner = await self.scanner
            let root = await self.scanRoot
            let includeHidden = await self.includeHidden
            let categories = await self.selectedCategories

            var allPaths: [(url: URL, category: ArtifactCategory)] = []

            // Phase 1: Scan for project-level artifacts
            let projectCategories = categories.intersection(Set(ArtifactCategory.projectLevel))
            if !projectCategories.isEmpty {
                let definitions = ArtifactRegistry.definitions(for: projectCategories)
                let projectPaths = await scanner.scan(
                    root: root,
                    definitions: definitions,
                    includeHidden: includeHidden,
                    onProgress: { dir in
                        Task { @MainActor [weak self] in
                            self?.scanProgress = Formatter.shortenPath(dir)
                        }
                    },
                    onFound: { _, _, count in
                        Task { @MainActor [weak self] in
                            self?.foundCount = count
                        }
                    }
                )
                allPaths.append(contentsOf: projectPaths)
            }

            // Phase 2: Check system-level artifacts
            let systemCategories = categories.intersection(Set(ArtifactCategory.systemLevel))
            if !systemCategories.isEmpty {
                let systemPaths = scanner.checkSystemArtifacts(categories: systemCategories)
                let prevCount = allPaths.count
                allPaths.append(contentsOf: systemPaths)
                await MainActor.run { [weak self] in
                    self?.foundCount = (self?.foundCount ?? 0) + (allPaths.count - prevCount)
                }
            }

            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                self?.sizingProgress = (completed: 0, total: allPaths.count)
            }

            // Phase 3: Calculate sizes
            var builtEntries: [ArtifactEntry] = []
            for (index, item) in allPaths.enumerated() {
                if Task.isCancelled { return }
                let entry = Sizer.buildEntry(for: item.url, category: item.category)
                builtEntries.append(entry)
                await MainActor.run { [weak self] in
                    self?.sizingProgress = (completed: index + 1, total: allPaths.count)
                }
            }

            if Task.isCancelled { return }

            builtEntries.sort { $0.sizeBytes > $1.sizeBytes }

            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
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

    func toggleSelection(_ entry: ArtifactEntry) {
        if selectedPaths.contains(entry.url) {
            selectedPaths.remove(entry.url)
        } else {
            selectedPaths.insert(entry.url)
        }
    }

    func selectAll() {
        selectedPaths.formUnion(sortedEntries.map(\.url))
    }

    func deselectAll() {
        // Only deselect entries visible in current filter
        let visibleURLs = Set(sortedEntries.map(\.url))
        selectedPaths.subtract(visibleURLs)
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

            // Derive allowed names from the actual entries being deleted, not mutable UI state
            let entryCategories = Set(items.map(\.entry.category))
            let allowedNames = ArtifactRegistry.allowedDeletionNames(for: entryCategories)
            let allowedSystemPaths = ArtifactRegistry.allowedSystemPaths(for: entryCategories)

            let result = Deleter.delete(
                urls: urls,
                allowedNames: allowedNames,
                allowedSystemPaths: allowedSystemPaths
            ) { current, total, url in
                Task { @MainActor [weak self] in
                    self?.deletionCurrent = current
                    self?.deletionTotal = total
                    if let idx = self?.deletionItems.firstIndex(where: { $0.entry.url == url }) {
                        self?.deletionItems[idx].status = .inProgress
                    }
                }
                Thread.sleep(forTimeInterval: 0.05)
            }

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
        filterCategory = nil
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
