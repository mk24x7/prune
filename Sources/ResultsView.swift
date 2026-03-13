import SwiftUI

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
                            count: state.entries.count,
                            isSelected: state.filterCategory == nil,
                            onTap: { state.filterCategory = nil }
                        )

                        ForEach(state.categoriesWithResults) { category in
                            FilterChip(
                                label: category.rawValue,
                                count: state.entries.filter { $0.category == category }.count,
                                isSelected: state.filterCategory == category,
                                onTap: { state.filterCategory = category }
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
                            isSelected: state.selectedPaths.contains(entry.url),
                            onToggle: { state.toggleSelection(entry) }
                        )
                        Divider().padding(.leading, 36)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(state.entries.count) items -- \(Formatter.formatSize(state.totalSize)) total")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Scan Again") {
                    state.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete Selected (\(state.selectedPaths.count))") {
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
            Button("Delete \(state.selectedPaths.count) items (\(Formatter.formatSize(state.selectedTotalSize)))", role: .destructive) {
                state.startDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        let count = state.selectedPaths.count
        let size = Formatter.formatSize(state.selectedTotalSize)
        let categories = Set(state.selectedEntries.map(\.category))
        let categoryNames = categories.map(\.rawValue).sorted().joined(separator: ", ")
        let hints = categories.map(\.reinstallHint).joined(separator: ", ")
        return "This will delete \(count) items totaling \(size) across: \(categoryNames). You can restore them later (\(hints))."
    }
}

struct ResultRowView: View {
    let entry: ArtifactEntry
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
                        CategoryBadge(category: entry.category)
                        Text(entry.projectName)
                            .font(.system(.body, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        SizeBadge(bytes: entry.sizeBytes, formatted: entry.formattedSize)
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
    let category: ArtifactCategory

    private var color: Color {
        switch category {
        case .nodeModules: return .green
        case .swiftPM: return .orange
        case .cocoapods: return .red
        case .rust: return .brown
        case .pythonVenv, .pythonCache: return .yellow
        case .gradleBuild, .gradleCache, .gradleGlobalCache: return .teal
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport, .xcodeCache: return .blue
        case .homebrewCache: return .purple
        }
    }

    var body: some View {
        Text(category.rawValue)
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

    private var bgColor: Color {
        switch Formatter.sizeSeverity(bytes) {
        case .large: return Color.red.opacity(0.15)
        case .medium: return Color.orange.opacity(0.15)
        case .small: return Color.green.opacity(0.15)
        }
    }

    private var textColor: Color {
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
