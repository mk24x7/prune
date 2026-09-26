import SwiftUI
import PruneCore

struct ResultsView: View {
    @EnvironmentObject var state: AppState
    @State private var showConfirm = false

    private var displayEntries: [ArtifactEntry] {
        state.sortedEntries
    }

    private var allSelected: Bool {
        !displayEntries.isEmpty && displayEntries.allSatisfy { state.selectedPaths.contains($0.url) }
    }

    private var someSelected: Bool {
        let selectedInView = displayEntries.filter { state.selectedPaths.contains($0.url) }
        return !selectedInView.isEmpty && selectedInView.count < displayEntries.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter bar
            if state.categoriesWithResults.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(
                            label: "All",
                            count: state.visibleEntries.count,
                            isSelected: state.filterCategory == nil,
                            onTap: { state.filterCategory = nil }
                        )

                        ForEach(state.categoriesWithResults) { type in
                            FilterChip(
                                label: type.displayName,
                                count: state.visibleEntries.filter { $0.typeId == type.id }.count,
                                isSelected: state.filterCategory == type.id,
                                onTap: { state.filterCategory = type.id }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(.ultraThinMaterial)

                Divider()
            }

            // Toolbar
            HStack {
                Button(action: {
                    if allSelected { state.deselectAll() } else { state.selectAll() }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "checkmark.square.fill" :
                                someSelected ? "minus.square.fill" : "square")
                            .foregroundColor(allSelected || someSelected ? .blue : .secondary)
                        Text("Select all (\(displayEntries.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !state.selectedPaths.isEmpty {
                    Text("\(state.selectedPaths.count) selected -- \(Formatter.formatSize(state.selectedTotalSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Menu {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Button(action: { state.toggleSort(field) }) {
                            HStack {
                                Text(field.rawValue)
                                if state.sortField == field {
                                    Image(systemName: state.sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Sort: \(state.sortField.rawValue)")
                            .font(.caption)
                        Image(systemName: state.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayEntries) { entry in
                        ResultRowView(
                            entry: entry,
                            type: state.type(for: entry),
                            isSelected: state.selectedPaths.contains(entry.url),
                            onToggle: { state.toggleSelection(entry) }
                        )
                        Divider().padding(.leading, 36)
                    }
                }
            }

            Divider()

            if state.deniedCount > 0 {
                DeniedNotice(count: state.deniedCount, examples: state.deniedDirectories)
                Divider()
            }

            // Footer
            HStack {
                Text(footerSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Scan Again") {
                    state.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(deleteButtonLabel) {
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(state.selectedPaths.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Confirm Deletion",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(
                "Move \(state.selectedEntries.count) \(state.selectedEntries.count == 1 ? "item" : "items") to Trash (\(Formatter.formatSize(state.selectedTotalSize)))",
                role: .destructive
            ) {
                state.startDeletion(mode: .trash)
            }
            .keyboardShortcut(.defaultAction)
            Button("Delete Permanently", role: .destructive) {
                state.startDeletion(mode: .permanent)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var footerSummary: String {
        var text = "\(state.visibleEntries.count) items -- \(Formatter.formatSize(state.totalSize)) total"
        if state.minAgeDays > 0 {
            let hidden = state.entries.count - state.visibleEntries.count
            text += " (older than \(state.minAgeDays) days"
            text += hidden > 0 ? ", \(hidden) newer hidden)" : ")"
        }
        return text
    }

    private var deleteButtonLabel: String {
        let hidden = state.hiddenSelectedCount
        let base = "Delete Selected (\(state.selectedEntries.count))"
        return hidden > 0 ? base + ", \(hidden) hidden by filter" : base
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
        message += "\(selected.count) \(selected.count == 1 ? "item" : "items") totaling \(size):\n\(breakdown)"
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

/// Shown when the scan hit folders it was not allowed to read.
struct DeniedNotice: View {
    let count: Int
    let examples: [URL]

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("\(count) \(count == 1 ? "folder" : "folders") could not be read")
                .font(.caption)
                .foregroundColor(.secondary)
                .help(examples.prefix(10).map { Formatter.shortenPath($0.path) }.joined(separator: "\n"))
            Spacer()
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(Self.privacySettingsURL)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

struct ResultRowView: View {
    let entry: ArtifactEntry
    let type: ArtifactType?
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 14))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        CategoryBadge(type: type, fallback: entry.typeId)
                        Text(entry.projectName)
                            .font(.system(.body, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        SizeBadge(bytes: entry.sizeBytes, formatted: entry.formattedSize, unknown: entry.sizeUnknown)
                    }
                    HStack {
                        Text(entry.shortPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(entry.age)
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

struct CategoryBadge: View {
    let type: ArtifactType?
    let fallback: String

    private var color: Color { Palette.color(type?.color) }

    var body: some View {
        Text(type?.displayName ?? fallback)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }
}

struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .foregroundColor(isSelected ? .blue : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SizeBadge: View {
    let bytes: Int64
    let formatted: String
    var unknown: Bool = false

    private var bgColor: Color {
        if unknown { return Color.gray.opacity(0.15) }
        switch Formatter.sizeSeverity(bytes) {
        case .large: return Color.red.opacity(0.15)
        case .medium: return Color.orange.opacity(0.15)
        case .small: return Color.green.opacity(0.15)
        }
    }

    private var textColor: Color {
        if unknown { return .secondary }
        switch Formatter.sizeSeverity(bytes) {
        case .large: return Color(red: 0.95, green: 0.3, blue: 0.3)
        case .medium: return Color(red: 0.95, green: 0.7, blue: 0.2)
        case .small: return Color(red: 0.2, green: 0.8, blue: 0.5)
        }
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor)
            .cornerRadius(4)
    }
}
