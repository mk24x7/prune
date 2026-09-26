import SwiftUI
import PruneCore

struct LandingView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(AppState.minAgeDaysKey) private var minAgeDays: Int = 0

    private static let ageChoices: [(days: Int, label: String)] = [
        (0, "Any"), (7, "7 days"), (30, "30 days"), (90, "90 days"), (180, "180 days"),
    ]

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

                    HStack {
                        Toggle("Include hidden directories", isOn: $state.includeHidden)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Picker("Minimum age", selection: $minAgeDays) {
                            ForEach(Self.ageChoices, id: \.days) { choice in
                                Text(choice.label).tag(choice.days)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)
                        .fixedSize()
                        .help("Only show artifacts whose folder and direct contents were last modified at least this long ago")
                    }
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

                    CategoryGroup(title: "PROJECT ARTIFACTS", types: state.definitions.projectTypes)
                    CategoryGroup(title: "SYSTEM CACHES", types: state.definitions.systemTypes)
                    if !state.definitions.filesTypes.isEmpty {
                        CategoryGroup(title: "OTHER", types: state.definitions.filesTypes)
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

                Text("v\(AppVersion.short)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 40)
        }
        .alert(
            "Cannot scan this folder",
            isPresented: Binding(
                get: { state.rootError != nil },
                set: { if !$0 { state.rootError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.rootError = nil }
        } message: {
            Text(state.rootError ?? "")
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

struct CategoryGroup: View {
    @EnvironmentObject var state: AppState
    let title: String
    let types: [ArtifactType]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.bottom, 2)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 6) {
                ForEach(types) { type in
                    CategoryToggle(
                        type: type,
                        isSelected: state.selectedCategories.contains(type.id),
                        onToggle: { state.toggleCategory(type.id) }
                    )
                }
            }
        }
    }
}

struct CategoryToggle: View {
    let type: ArtifactType
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 12))

                Image(systemName: type.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 14)

                Text(type.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if !type.regenerable {
                    Text("not regenerable")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(3)
                        .lineLimit(1)
                        .fixedSize()
                }
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
        .help(type.description + ". " + type.reinstallHint)
    }
}
