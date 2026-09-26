import SwiftUI
import PruneCore

/// Results detail: header card, the result rows and the action footer.
struct ResultsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let rows = state.sortedEntries
        VStack(spacing: 0) {
            ResultsHeader(shownCount: rows.count)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)

            if state.entries.isEmpty {
                NothingFoundView()
            } else if rows.isEmpty {
                NoMatchesView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().padding(.leading, 44)
                            }
                            ResultRowView(
                                entry: entry,
                                type: state.type(for: entry),
                                isSelected: state.selectedPaths.contains(entry.url)
                            )
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .cardStyle(padding: 0)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.l)
                }
            }

            ResultsFooter(rows: rows)
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { state.pendingDeleteMode != nil },
                set: { if !$0 { state.pendingDeleteMode = nil } }
            ),
            titleVisibility: .visible,
            presenting: state.pendingDeleteMode
        ) { mode in
            let count = state.selectedEntries.count.counted("item")
            let size = Formatter.formatSize(state.selectedTotalSize)
            if mode == .trash {
                Button("Move \(count) to Trash (\(size))", role: .destructive) {
                    state.startDeletion(mode: .trash)
                }
                .keyboardShortcut(.defaultAction)
                Button("Delete Permanently", role: .destructive) {
                    state.startDeletion(mode: .permanent)
                }
            } else {
                Button("Delete \(count) Permanently (\(size))", role: .destructive) {
                    state.startDeletion(mode: .permanent)
                }
                .keyboardShortcut(.defaultAction)
                Button("Move to Trash Instead") {
                    state.startDeletion(mode: .trash)
                }
            }
            Button("Cancel", role: .cancel) { state.pendingDeleteMode = nil }
        } message: { _ in
            Text(confirmationMessage)
        }
    }

    private var dialogTitle: String {
        state.pendingDeleteMode == .permanent ? "Delete Permanently?" : "Move to Trash?"
    }

    private var confirmationMessage: String {
        let selected = state.selectedEntries
        let size = Formatter.formatSize(state.selectedTotalSize)
        var counts: [String: Int] = [:]
        for entry in selected { counts[entry.typeId, default: 0] += 1 }
        let types = state.definitions.types.filter { counts[$0.id] != nil }
        let breakdown = types.map { "\($0.displayName): \(counts[$0.id] ?? 0)" }.joined(separator: "\n")

        var message = ""
        let irreplaceable = types.filter { !$0.regenerable }
        if !irreplaceable.isEmpty {
            let names = irreplaceable.map(\.displayName).joined(separator: ", ")
            message += "WARNING: \(names) cannot be regenerated.\n\n"
        }
        message += "\(selected.count.counted("item")) totaling \(size):\n\(breakdown)"
        let hidden = state.hiddenSelectedCount
        if hidden > 0 {
            message += "\n\n\(hidden) of the selected \(hidden == 1 ? "item is" : "items are") hidden by the current filter or search."
        }
        let unknown = selected.filter(\.sizeUnknown).count
        if unknown > 0 {
            message += "\n\n\(unknown) \(unknown == 1 ? "item has" : "items have") an unknown size and \(unknown == 1 ? "is" : "are") not counted in the total."
        }
        let hints = types.filter(\.regenerable).map { "\($0.displayName): \($0.reinstallHint)" }
        if !hints.isEmpty {
            message += "\n\nTo restore later:\n" + hints.joined(separator: "\n")
        }
        message += "\n\nMoving to Trash lets you put items back until you empty the Trash. Deleting permanently frees the space immediately."
        return message
    }
}

/// Totals, selection and the denied-folders notice.
struct ResultsHeader: View {
    @EnvironmentObject var state: AppState
    let shownCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                StatView(
                    value: Formatter.formatSize(state.totalSize),
                    label: "\(state.visibleEntries.count.counted("item")) found"
                )
                StatView(
                    value: Formatter.formatSize(state.selectedTotalSize),
                    label: "\(state.selectedEntries.count) selected",
                    color: state.selectedPaths.isEmpty ? .secondary : .accentColor
                )
                Spacer(minLength: Theme.Spacing.s)
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    if let id = state.filterCategory {
                        HStack(spacing: Theme.Spacing.xs) {
                            TypeBadge(type: state.definitions.type(id: id), fallback: id)
                            Button(action: { state.filterCategory = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Show all results")
                            .accessibilityLabel("Clear type filter")
                        }
                    }
                    if state.filterCategory != nil || state.isSearching {
                        Text("Showing \(shownCount) of \(state.visibleEntries.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(scopeLine)
                .font(.caption)
                .foregroundColor(Theme.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if state.deniedCount > 0 {
                Divider()
                DeniedNotice(count: state.deniedCount, examples: state.deniedDirectories)
            }
        }
        .cardStyle()
    }

    private var scopeLine: String {
        var text = "Scanned \(state.scanRootDisplay)"
        if state.minAgeDays > 0 {
            let hidden = state.entries.count - state.visibleEntries.count
            text += ", older than \(state.minAgeDays) days"
            if hidden > 0 { text += " (\(hidden) newer hidden)" }
        }
        let unknown = state.visibleEntries.filter(\.sizeUnknown).count
        if unknown > 0 {
            text += ", \(unknown) with unknown size"
        }
        return text
    }
}

struct ResultRowView: View {
    @EnvironmentObject var state: AppState
    let entry: ArtifactEntry
    let type: ArtifactType?
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: { state.toggleSelection(entry) }) {
            HStack(spacing: Theme.Spacing.m) {
                CheckboxGlyph(mark: isSelected ? .on : .off)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(entry.projectName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        TypeBadge(type: type, fallback: entry.typeId)
                        if type?.regenerable == false {
                            NotRegenerableTag()
                        }
                    }
                    Text(entry.shortPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: Theme.Spacing.s)

                Text(entry.age)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)

                SizeBadge(bytes: entry.sizeBytes, formatted: entry.formattedSize, unknown: entry.sizeUnknown)
                    .frame(minWidth: 76, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.08) : (hovering ? Theme.hover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.url.path)
        .accessibilityLabel("\(entry.projectName), \(type?.displayName ?? entry.typeId), \(entry.formattedSize), \(entry.age)")
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint("Toggles selection")
        .contextMenu {
            Button("Reveal in Finder") { FileActions.reveal(entry.url) }
            Button("Copy Path") { FileActions.copyPath(entry.url) }
            Divider()
            Button("Select All \(type?.displayName ?? entry.typeId)") { state.selectAll(ofType: entry.typeId) }
        }
    }
}

/// Select all, selection summary and the delete actions.
struct ResultsFooter: View {
    @EnvironmentObject var state: AppState
    let rows: [ArtifactEntry]

    private var selectedInView: Int {
        rows.filter { state.selectedPaths.contains($0.url) }.count
    }

    private var mark: CheckboxGlyph.Mark {
        let count = selectedInView
        if count == 0 { return .off }
        return count == rows.count ? .on : .mixed
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Theme.Spacing.m) {
                Button(action: {
                    if mark == .on { state.deselectAll() } else { state.selectAll() }
                }) {
                    HStack(spacing: 6) {
                        CheckboxGlyph(mark: mark)
                        Text("Select all (\(rows.count))")
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(rows.isEmpty)
                .help("Select or deselect every visible result (Command-A selects all)")
                .accessibilityLabel(mark == .on ? "Deselect all visible results" : "Select all visible results")

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(state.selectedPaths.isEmpty
                         ? "Nothing selected"
                         : "\(state.selectedEntries.count) selected, \(Formatter.formatSize(state.selectedTotalSize))")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(state.selectedPaths.isEmpty ? .secondary : .primary)
                    let hidden = state.hiddenSelectedCount
                    if hidden > 0 {
                        Text("\(hidden) hidden by filter")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Menu {
                    Button("Delete Permanently...") { state.requestDeletion(.permanent) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(state.selectedPaths.isEmpty)
                .help("More delete options")
                .accessibilityLabel("More delete options")

                Button(action: { state.requestDeletion(.trash) }) {
                    Label("Move to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.selectedPaths.isEmpty)
                .help("Move the selected items to the Trash (Delete)")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .background(.bar)
    }
}

struct NothingFoundView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.green)
            }
            Text("Nothing to prune")
                .font(.system(size: 20, weight: .bold))
            Text("No artifacts of the \(state.scannedCategories.count.counted("enabled type")) were found in \(state.scanRootDisplay).")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoMatchesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("No results match")
                .font(.headline)
            HStack(spacing: Theme.Spacing.s) {
                if state.filterCategory != nil {
                    Button("Show All Types") { state.filterCategory = nil }
                }
                if state.isSearching {
                    Button("Clear Search") { state.searchText = "" }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
