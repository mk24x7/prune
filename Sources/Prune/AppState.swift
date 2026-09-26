import Foundation
import SwiftUI
import PruneCore

@MainActor
final class AppState: ObservableObject {
    let definitions: Definitions

    @Published var phase: AppPhase = .idle

    // Config
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var scanRootDisplay: String = "~"
    @Published var includeHidden: Bool = false
    /// Types enabled for scanning; persisted so the choice survives relaunches.
    @Published var selectedCategories: Set<String> {
        didSet { persistCategories() }
    }
    @Published var rootError: String?

    // Scanning
    @Published var scanProgress: String = ""
    @Published var foundCount: Int = 0
    @Published var sizingProgress: (completed: Int, total: Int)?

    // Results
    @Published var entries: [ArtifactEntry] = []
    @Published var selectedPaths: Set<URL> = []
    @Published var sortField: SortField = .size
    @Published var sortAscending: Bool = false
    @Published var filterCategory: String? = nil
    /// Free-text filter from the toolbar search field (project name or path).
    @Published var searchText: String = ""
    /// Types that were enabled when the current results were scanned.
    @Published var scannedCategories: Set<String> = []
    /// Set to ask the results screen to show the deletion confirmation.
    @Published var pendingDeleteMode: DeleteMode?
    @Published var deniedCount: Int = 0
    @Published var deniedDirectories: [URL] = []
    /// Minimum age filter captured from `@AppStorage("minAgeDays")` when the scan starts.
    @Published var minAgeDays: Int = 0

    // Deleting
    @Published var deletionItems: [DeletionItem] = []
    @Published var deletionCurrent: Int = 0
    @Published var deletionTotal: Int = 0

    // Deletion results
    @Published var deleteMode: DeleteMode = .trash
    /// Mode of the batch currently running (differs from `deleteMode` during a permanent fallback).
    @Published var batchMode: DeleteMode = .trash
    @Published var outcomes: [DeletionOutcome] = []
    @Published var measuredFreedBytes: Int64 = 0
    @Published var trashUnsupportedEntries: [ArtifactEntry] = []
    @Published var pendingPermanentFallback: Bool = false

    private var scanTask: Task<Void, Never>?

    /// Maximum number of concurrent `du` processes while sizing.
    nonisolated static let sizingConcurrency = 6

    static let minAgeDaysKey = "minAgeDays"
    static let selectedCategoriesKey = "selectedCategories"
    /// Every type id known when the selection was last saved, so types added in
    /// a later version start with their default instead of appearing disabled.
    static let knownCategoriesKey = "knownCategories"

    init(definitions: Definitions) {
        self.definitions = definitions
        self.selectedCategories = Self.restoreCategories(definitions: definitions)
    }

    private static func restoreCategories(definitions: Definitions) -> Set<String> {
        let defaults = UserDefaults.standard
        guard let saved = defaults.stringArray(forKey: selectedCategoriesKey) else {
            return definitions.defaultEnabledIds
        }
        let current = Set(definitions.types.map(\.id))
        let known = Set(defaults.stringArray(forKey: knownCategoriesKey) ?? [])
        let added = definitions.defaultEnabledIds.subtracting(known)
        return Set(saved).intersection(current).union(added)
    }

    /// False in snapshot mode so a demo selection never overwrites the user's.
    var persistsCategories = true

    private func persistCategories() {
        guard persistsCategories else { return }
        let defaults = UserDefaults.standard
        defaults.set(selectedCategories.sorted(), forKey: Self.selectedCategoriesKey)
        defaults.set(definitions.types.map(\.id), forKey: Self.knownCategoriesKey)
    }

    var isBusy: Bool { phase == .scanning || phase == .deleting }

    var canScan: Bool { !isBusy && !selectedCategories.isEmpty }

    func type(for entry: ArtifactEntry) -> ArtifactType? {
        definitions.type(id: entry.typeId)
    }

    var selectedEntries: [ArtifactEntry] {
        entries.filter { selectedPaths.contains($0.url) }
    }

    var selectedTotalSize: Int64 {
        selectedEntries.reduce(0) { $0 + $1.countedBytes }
    }

    /// Entries that pass the minimum age filter.
    var visibleEntries: [ArtifactEntry] {
        guard minAgeDays > 0 else { return entries }
        let cutoff = Date().addingTimeInterval(-Double(minAgeDays) * 86400)
        return entries.filter { $0.lastModified <= cutoff }
    }

    var totalSize: Int64 {
        visibleEntries.reduce(0) { $0 + $1.countedBytes }
    }

    /// Types that have results, in definition order.
    var categoriesWithResults: [ArtifactType] {
        let ids = Set(visibleEntries.map(\.typeId))
        return definitions.types.filter { ids.contains($0.id) }
    }

    /// Selected entries that the current category filter hides from the list.
    var hiddenSelectedCount: Int {
        let shown = Set(sortedEntries.map(\.url))
        return selectedEntries.filter { !shown.contains($0.url) }.count
    }

    /// Result count and counted size per type, over the age-filtered entries.
    var typeStats: [String: (count: Int, bytes: Int64)] {
        var stats: [String: (count: Int, bytes: Int64)] = [:]
        for entry in visibleEntries {
            let existing = stats[entry.typeId] ?? (count: 0, bytes: 0)
            stats[entry.typeId] = (count: existing.count + 1, bytes: existing.bytes + entry.countedBytes)
        }
        return stats
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !trimmedSearch.isEmpty }

    /// Entries filtered by minimum age, the category filter and the search
    /// text, then sorted.
    var sortedEntries: [ArtifactEntry] {
        var filtered = visibleEntries
        if let id = filterCategory {
            filtered = filtered.filter { $0.typeId == id }
        }
        let query = trimmedSearch
        if !query.isEmpty {
            filtered = filtered.filter {
                $0.projectName.localizedCaseInsensitiveContains(query)
                    || $0.shortPath.localizedCaseInsensitiveContains(query)
            }
        }

        return filtered.sorted { a, b in
            let cmp: Bool
            switch sortField {
            case .size: cmp = a.countedBytes < b.countedBytes
            case .name: cmp = a.projectName.localizedCaseInsensitiveCompare(b.projectName) == .orderedAscending
            case .age: cmp = a.lastModified < b.lastModified
            case .path: cmp = a.shortPath < b.shortPath
            }
            return sortAscending ? cmp : !cmp
        }
    }

    /// Per-type size breakdown: selected entries before deletion, deleted entries in the summary.
    var categoryBreakdown: [(typeId: String, count: Int, bytes: Int64)] {
        var map: [String: (count: Int, bytes: Int64)] = [:]
        let doneURLs = Set(outcomes.filter(\.isSuccess).map(\.url))
        for entry in entries {
            let include = phase == .summary ? doneURLs.contains(entry.url) : selectedPaths.contains(entry.url)
            guard include else { continue }
            let existing = map[entry.typeId] ?? (count: 0, bytes: 0)
            map[entry.typeId] = (count: existing.count + 1, bytes: existing.bytes + entry.countedBytes)
        }
        return map.map { (typeId: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            .sorted { $0.bytes > $1.bytes }
    }

    func setScanRoot(_ url: URL) {
        scanRoot = url
        scanRootDisplay = Formatter.shortenPath(url.path)
    }

    func toggleCategory(_ id: String) {
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }
    }

    func selectAllCategories() {
        selectedCategories = Set(definitions.types.map(\.id))
    }

    func deselectAllCategories() {
        selectedCategories = []
    }

    /// Starts a scan of `scanRoot`. `minAgeOverride` replaces the stored
    /// minimum age for this scan only (snapshot mode).
    func startScan(minAgeOverride: Int? = nil) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scanRoot.path, isDirectory: &isDir), isDir.boolValue else {
            rootError = "\(scanRoot.path) is not an existing folder. Choose another folder to scan."
            phase = .idle
            return
        }

        phase = .scanning
        scannedCategories = selectedCategories
        pendingDeleteMode = nil
        // A rescan from the summary starts from a clean deletion state.
        deletionItems = []
        outcomes = []
        measuredFreedBytes = 0
        trashUnsupportedEntries = []
        pendingPermanentFallback = false
        scanProgress = ""
        foundCount = 0
        sizingProgress = nil
        entries = []
        selectedPaths = []
        filterCategory = nil
        deniedCount = 0
        deniedDirectories = []
        minAgeDays = max(0, minAgeOverride ?? UserDefaults.standard.integer(forKey: Self.minAgeDaysKey))

        let definitions = self.definitions
        let root = scanRoot
        let includeHidden = self.includeHidden
        let selected = selectedCategories
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = Scanner()
            let projectTypes = definitions.projectTypes.filter { selected.contains($0.id) }
            let otherTypes = definitions.types.filter { $0.kind != .project && selected.contains($0.id) }
            // Never descend into system caches during the project walk, whether
            // or not they are selected, so nothing is found twice.
            let systemPaths = Set(definitions.systemTypes.compactMap {
                definitions.resolvedSystemURL(for: $0, env: env, home: home)
            })

            var found: [(url: URL, typeId: String)] = []
            var denied = ScanResult()
            if !projectTypes.isEmpty {
                let result = scanner.scan(
                    root: root,
                    types: projectTypes,
                    rules: definitions.scan,
                    includeHidden: includeHidden,
                    home: home,
                    extraSkipPaths: systemPaths,
                    onProgress: { dir in
                        let short = Formatter.shortenPath(dir)
                        Task { @MainActor [weak self] in self?.scanProgress = short }
                    },
                    onFound: { _, _, count in
                        Task { @MainActor [weak self] in self?.foundCount = count }
                    }
                )
                found = result.found
                denied = result
            }
            if Task.isCancelled { return }

            found.append(contentsOf: scanner.checkSystemArtifacts(
                types: otherTypes, definitions: definitions, env: env, home: home))
            var seen = Set<URL>()
            found = found.filter { seen.insert($0.url.standardizedFileURL).inserted }
            let total = found.count
            let deniedCount = denied.deniedCount
            let deniedDirectories = denied.deniedDirectories
            await MainActor.run { [weak self] in
                self?.foundCount = total
                self?.sizingProgress = (completed: 0, total: total)
            }

            let built = await Self.sizeEntries(found, definitions: definitions) { completed in
                Task { @MainActor [weak self] in
                    guard let self, self.phase == .scanning else { return }
                    self.sizingProgress = (completed: completed, total: total)
                }
            }
            if Task.isCancelled { return }

            let sorted = built.sorted { $0.countedBytes > $1.countedBytes }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, self.phase == .scanning else { return }
                self.entries = sorted
                self.deniedCount = deniedCount
                self.deniedDirectories = deniedDirectories
                self.sizingProgress = nil
                self.phase = .results
            }
        }
    }

    /// Size every found item with at most `sizingConcurrency` du processes in flight.
    nonisolated static func sizeEntries(
        _ items: [(url: URL, typeId: String)],
        definitions: Definitions,
        onCompleted: (Int) -> Void
    ) async -> [ArtifactEntry] {
        await withTaskGroup(of: ArtifactEntry?.self) { group in
            var pending = items.makeIterator()
            func addNext() -> Bool {
                guard let item = pending.next() else { return false }
                group.addTask {
                    guard let type = definitions.type(id: item.typeId) else { return nil }
                    return await Sizer.buildEntry(for: item.url, type: type)
                }
                return true
            }
            for _ in 0..<sizingConcurrency where !addNext() { break }

            var results: [ArtifactEntry] = []
            var completed = 0
            while let entry = await group.next() {
                if let entry { results.append(entry) }
                completed += 1
                onCompleted(completed)
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                _ = addNext()
            }
            return results
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
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
        // Only deselect entries visible in the current filter.
        selectedPaths.subtract(Set(sortedEntries.map(\.url)))
    }

    /// Select every age-filtered entry of a type, regardless of the list filter.
    func selectAll(ofType typeId: String) {
        selectedPaths.formUnion(visibleEntries.filter { $0.typeId == typeId }.map(\.url))
    }

    /// Open the deletion confirmation for the current selection.
    func requestDeletion(_ mode: DeleteMode) {
        guard phase == .results, !selectedPaths.isEmpty else { return }
        pendingDeleteMode = mode
    }

    func toggleSort(_ field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = false
        }
    }

    func startDeletion(mode: DeleteMode) {
        let selected = selectedEntries
        pendingDeleteMode = nil
        guard !selected.isEmpty else { return }
        deleteMode = mode
        outcomes = []
        measuredFreedBytes = 0
        trashUnsupportedEntries = []
        pendingPermanentFallback = false
        runDeletion(selected, mode: mode)
    }

    /// The user agreed to delete the items the Trash could not take.
    func confirmPermanentFallback() {
        let entries = trashUnsupportedEntries
        pendingPermanentFallback = false
        trashUnsupportedEntries = []
        guard !entries.isEmpty else { return }
        runDeletion(entries, mode: .permanent)
    }

    func declinePermanentFallback() {
        pendingPermanentFallback = false
    }

    private func runDeletion(_ batch: [ArtifactEntry], mode: DeleteMode) {
        // Re-runs (permanent fallback) keep the rows of the first pass visible.
        let batchURLs = Set(batch.map(\.url))
        if deletionItems.isEmpty || !batchURLs.isSubset(of: Set(deletionItems.map(\.entry.url))) {
            deletionItems = batch.map { DeletionItem(entry: $0) }
        } else {
            for index in deletionItems.indices where batchURLs.contains(deletionItems[index].entry.url) {
                deletionItems[index].status = .pending
                deletionItems[index].error = nil
            }
        }
        deletionCurrent = 0
        deletionTotal = batch.count
        batchMode = mode
        phase = .deleting

        let deleter = Deleter(
            mode: mode,
            scanRoot: scanRoot,
            definitions: definitions,
            log: DeletionLog(version: AppVersion.short)
        )
        let scanRoot = self.scanRoot

        Task { [weak self] in
            let urls = batch.map(\.url)
            let before = await Task.detached { DiskSpace.snapshot(for: urls) }.value
            let results = await Task.detached { () -> [DeletionOutcome] in
                await deleter.delete(batch) { event in
                    Task { @MainActor [weak self] in self?.apply(event) }
                }
            }.value
            let after = await Task.detached { DiskSpace.snapshot(matching: before) }.value
            let measured = DiskSpace.freedBytes(before: before, after: after)

            let ok = results.filter(\.isSuccess).count
            deleter.log?.recordRun(
                scanRoot: scanRoot, selected: batch.count, ok: ok, failed: results.count - ok,
                estimatedBytes: batch.reduce(0) { $0 + $1.countedBytes }, measuredFreedBytes: measured)

            self?.finishDeletion(results, measured: measured)
        }
    }

    private func apply(_ event: DeletionEvent) {
        switch event {
        case .started(let index, let total, let entry):
            deletionCurrent = index
            deletionTotal = total
            if let i = deletionItems.firstIndex(where: { $0.entry.url == entry.url }) {
                deletionItems[i].status = .inProgress
            }
        case .finished(let index, let total, let outcome):
            deletionCurrent = index + 1
            deletionTotal = total
            if let i = deletionItems.firstIndex(where: { $0.entry.url == outcome.url }) {
                deletionItems[i].status = outcome.isSuccess ? .done : .failed
                deletionItems[i].error = outcome.failure?.localizedDescription
            }
        }
    }

    private func finishDeletion(_ results: [DeletionOutcome], measured: Int64) {
        // Merge: a permanent fallback replaces the trashUnsupported outcomes of the first pass.
        let replaced = Set(results.map(\.url))
        outcomes = outcomes.filter { !replaced.contains($0.url) } + results
        measuredFreedBytes += measured
        for outcome in results {
            if let i = deletionItems.firstIndex(where: { $0.entry.url == outcome.url }) {
                deletionItems[i].status = outcome.isSuccess ? .done : .failed
                deletionItems[i].error = outcome.failure?.localizedDescription
            }
        }
        trashUnsupportedEntries = results.filter(\.isTrashUnsupported).map(\.entry)
        pendingPermanentFallback = !trashUnsupportedEntries.isEmpty
        phase = .summary
    }

    // MARK: - Summary figures

    var succeededOutcomes: [DeletionOutcome] { outcomes.filter(\.isSuccess) }
    var failedOutcomes: [DeletionOutcome] { outcomes.filter { !$0.isSuccess } }

    var deletedCount: Int { succeededOutcomes.count }
    var failedCount: Int { failedOutcomes.count }

    /// Sum of scan-time size estimates for everything that is gone.
    var estimatedFreedBytes: Int64 {
        succeededOutcomes.reduce(0) { $0 + $1.entry.countedBytes }
    }

    var trashedCount: Int {
        outcomes.filter { if case .trashed = $0.status { return true } else { return false } }.count
    }

    var trashedEstimatedBytes: Int64 {
        outcomes.reduce(0) { total, outcome in
            if case .trashed = outcome.status { return total + outcome.entry.countedBytes }
            return total
        }
    }

    var permanentCount: Int {
        outcomes.filter { $0.status == .deleted }.count
    }

    var permanentEstimatedBytes: Int64 {
        outcomes.filter { $0.status == .deleted }.reduce(0) { $0 + $1.entry.countedBytes }
    }

    var failures: [(path: String, error: String)] {
        failedOutcomes.map {
            (path: Formatter.shortenPath($0.url.path), error: $0.failure?.localizedDescription ?? "not deleted")
        }
    }

    func reset() {
        phase = .idle
        entries = []
        selectedPaths = []
        filterCategory = nil
        scannedCategories = []
        pendingDeleteMode = nil
        scanProgress = ""
        foundCount = 0
        sizingProgress = nil
        deniedCount = 0
        deniedDirectories = []
        deletionItems = []
        outcomes = []
        measuredFreedBytes = 0
        trashUnsupportedEntries = []
        pendingPermanentFallback = false
    }
}
