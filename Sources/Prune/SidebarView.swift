import SwiftUI
import AppKit
import PruneCore

/// Sidebar row identity: everything, or one artifact type.
enum SidebarItem: Hashable {
    case all
    case type(String)
}

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { state.filterCategory.map(SidebarItem.type) ?? .all },
            set: { item in
                if case .type(let id) = item {
                    state.filterCategory = id
                } else {
                    state.filterCategory = nil
                }
            }
        )
    }

    var body: some View {
        let stats = state.typeStats
        let hasResults = state.phase == .results
        List(selection: selection) {
            Section {
                AllResultsRow(
                    count: hasResults ? state.visibleEntries.count : nil,
                    bytes: hasResults ? state.totalSize : nil
                )
                .tag(SidebarItem.all)
            }

            TypeSection(title: "Project Artifacts", types: state.definitions.projectTypes,
                        stats: stats, hasResults: hasResults)
            TypeSection(title: "System Caches", types: state.definitions.systemTypes,
                        stats: stats, hasResults: hasResults)
            if !state.definitions.filesTypes.isEmpty {
                TypeSection(title: "Other", types: state.definitions.filesTypes,
                            stats: stats, hasResults: hasResults)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ScanLocationPanel()
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.m)
                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
                .background(.bar)
        }
    }
}

/// Folder picker, hidden-folder toggle and minimum age.
struct ScanLocationPanel: View {
    @EnvironmentObject var state: AppState
    @AppStorage(AppState.minAgeDaysKey) private var minAgeDays: Int = 0

    static let ageChoices: [(days: Int, label: String)] = [
        (0, "Any age"), (7, "7 days"), (30, "30 days"), (90, "90 days"), (180, "180 days"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Scan location").sectionHeaderStyle()

            Button(action: browse) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(state.scanRootDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Theme.Spacing.xs)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("\(state.scanRoot.path)\nClick to choose another folder")
            .accessibilityLabel("Scan location \(state.scanRootDisplay). Choose folder")

            HStack(spacing: Theme.Spacing.s) {
                Toggle("Include hidden", isOn: $state.includeHidden)
                    .toggleStyle(.checkbox)
                    .help("Also look inside folders whose names start with a dot")
                Spacer(minLength: Theme.Spacing.xs)
                Picker("Minimum age", selection: $minAgeDays) {
                    ForEach(Self.ageChoices, id: \.days) { choice in
                        Text(choice.label).tag(choice.days)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("Only show artifacts whose folder and direct contents were last modified at least this long ago. Applies when a scan starts.")
                .accessibilityLabel("Minimum age")
            }
            .font(.system(size: 11))
            .controlSize(.small)

            if state.phase == .results, minAgeDays != state.minAgeDays {
                Text("Rescan to apply the new minimum age")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .disabled(state.isBusy)
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

struct AllResultsRow: View {
    let count: Int?
    let bytes: Int64?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text("All results")
                .fontWeight(.medium)
            Spacer(minLength: Theme.Spacing.xs)
            if let count, let bytes {
                TrailingStat(count: count, bytes: bytes)
            }
        }
    }
}

/// One group of artifact types with All / None links.
struct TypeSection: View {
    @EnvironmentObject var state: AppState
    let title: String
    let types: [ArtifactType]
    let stats: [String: (count: Int, bytes: Int64)]
    let hasResults: Bool

    var body: some View {
        Section {
            ForEach(types) { type in
                TypeRow(
                    type: type,
                    isEnabled: state.selectedCategories.contains(type.id),
                    stat: hasResults && state.scannedCategories.contains(type.id)
                        ? (stats[type.id] ?? (count: 0, bytes: 0)) : nil
                )
                .tag(SidebarItem.type(type.id))
            }
        } header: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .textCase(.uppercase)
                Spacer()
                let enabled = types.filter { state.selectedCategories.contains($0.id) }.count
                Text("\(enabled)/\(types.count)")
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
                Button("All") { setAll(true) }
                    .buttonStyle(.link)
                    .help("Enable every type in \(title)")
                Button("None") { setAll(false) }
                    .buttonStyle(.link)
                    .help("Disable every type in \(title)")
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.trailing, Theme.Spacing.s)
            .disabled(state.isBusy)
        }
    }

    private func setAll(_ on: Bool) {
        let ids = Set(types.map(\.id))
        if on {
            state.selectedCategories.formUnion(ids)
        } else {
            state.selectedCategories.subtract(ids)
        }
    }
}

struct TypeRow: View {
    @EnvironmentObject var state: AppState
    let type: ArtifactType
    let isEnabled: Bool
    let stat: (count: Int, bytes: Int64)?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { _ in state.toggleCategory(type.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)
            .disabled(state.isBusy)
            .accessibilityLabel("Scan \(type.displayName)")

            Image(systemName: type.icon)
                .font(.system(size: 12))
                .foregroundColor(Palette.color(type.color))
                .frame(width: 18)
                .opacity(isEnabled ? 1 : 0.5)

            Text(type.displayName)
                .lineLimit(1)
                .foregroundColor(isEnabled ? .primary : .secondary)

            if !type.regenerable {
                NotRegenerableTag(compact: true)
            }

            Spacer(minLength: Theme.Spacing.xs)

            if let stat {
                TrailingStat(count: stat.count, bytes: stat.bytes)
            }
        }
        .help(type.description + ". " + type.reinstallHint)
    }
}

/// "12  1.4 GB" trailing text for sidebar rows; dimmed when empty.
struct TrailingStat: View {
    let count: Int
    let bytes: Int64

    var body: some View {
        if count == 0 {
            Text("0")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(Theme.tertiary)
                .accessibilityLabel("no results")
        } else {
            HStack(spacing: 6) {
                Text("\(count)")
                    .foregroundColor(.secondary)
                Text(Formatter.formatSize(bytes))
                    .foregroundColor(.primary)
            }
            .font(.system(size: 11).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count.counted("result")), \(Formatter.formatSize(bytes))")
        }
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Theme.Spacing.s) {
                Text("\(state.selectedCategories.count) of \(state.definitions.types.count) types enabled")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Prune v\(AppVersion.short)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
        }
    }
}
