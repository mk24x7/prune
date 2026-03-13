import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var state: AppState
    @State private var showConfirm = false

    private var allSelected: Bool {
        !state.entries.isEmpty && state.selectedPaths.count == state.entries.count
    }

    private var someSelected: Bool {
        !state.selectedPaths.isEmpty && state.selectedPaths.count < state.entries.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Select all
                Button(action: {
                    if allSelected { state.deselectAll() } else { state.selectAll() }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "checkmark.square.fill" :
                                someSelected ? "minus.square.fill" : "square")
                            .foregroundColor(allSelected || someSelected ? .blue : .secondary)
                        Text("Select all (\(state.entries.count))")
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

                // Sort
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
                    ForEach(state.sortedEntries) { entry in
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
                Text("\(state.entries.count) directories -- \(Formatter.formatSize(state.totalSize)) total")
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
            Button("Delete \(state.selectedPaths.count) directories (\(Formatter.formatSize(state.selectedTotalSize)))", role: .destructive) {
                state.startDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(state.selectedPaths.count) node_modules directories totaling \(Formatter.formatSize(state.selectedTotalSize)). You can reinstall them later with npm install.")
        }
    }
}

struct ResultRowView: View {
    let entry: NodeModuleEntry
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
