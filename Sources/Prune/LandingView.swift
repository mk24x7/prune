import SwiftUI

struct LandingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 8)

                // Header
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

                VStack(spacing: 4) {
                    Text("Prune")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Scan and clean up developer artifacts to free disk space")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Scan directory picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan directory")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: browse) {
                        HStack {
                            Text(state.scanRootDisplay)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Toggle("Include hidden directories", isOn: $state.includeHidden)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 480)

                Divider()
                    .frame(maxWidth: 480)

                // Category selection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("What to scan")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("All") { state.selectAllCategories() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)

                        Text("/")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("None") { state.deselectAllCategories() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                    }

                    // Project-level artifacts
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PROJECT ARTIFACTS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            .padding(.bottom, 2)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ], spacing: 6) {
                            ForEach(ArtifactCategory.projectLevel) { category in
                                CategoryToggle(
                                    category: category,
                                    isSelected: state.selectedCategories.contains(category),
                                    onToggle: { state.toggleCategory(category) }
                                )
                            }
                        }
                    }

                    // System-level artifacts
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SYSTEM CACHES")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            .padding(.bottom, 2)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ], spacing: 6) {
                            ForEach(ArtifactCategory.systemLevel) { category in
                                CategoryToggle(
                                    category: category,
                                    isSelected: state.selectedCategories.contains(category),
                                    onToggle: { state.toggleCategory(category) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 480)

                // Scan button
                Button(action: { state.startScan() }) {
                    Text("Scan (\(state.selectedCategories.count) selected)")
                        .frame(maxWidth: 280)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(state.selectedCategories.isEmpty)

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: state.phase)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = state.scanRoot
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            state.setScanRoot(url)
        }
    }
}

struct CategoryToggle: View {
    let category: ArtifactCategory
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 12))

                Image(systemName: category.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 14)

                Text(category.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
