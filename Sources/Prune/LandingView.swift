import SwiftUI
import AppKit
import PruneCore

/// Idle detail: what will be scanned and a large Scan button.
struct LandingView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(AppState.minAgeDaysKey) private var minAgeDays: Int = 0

    private var enabledTypes: [ArtifactType] {
        state.definitions.types.filter { state.selectedCategories.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Prune")
                        .font(.system(size: 26, weight: .bold))
                    Text("Find build artifacts and caches that can be rebuilt, and move them to the Trash.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text(summary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)

                Button(action: { state.startScan() }) {
                    Label("Scan", systemImage: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!state.canScan)
                .help("Start scanning (Return)")

                if state.selectedCategories.isEmpty {
                    Text("Enable at least one type in the sidebar to scan.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                enabledCard
                    .frame(maxWidth: 560)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    private var summary: String {
        var text = "\(enabledTypes.count.counted("type")) enabled, scanning \(state.scanRootDisplay)"
        var extras: [String] = []
        if state.includeHidden { extras.append("hidden folders included") }
        if minAgeDays > 0 { extras.append("older than \(minAgeDays) days") }
        if !extras.isEmpty { text += "\n" + extras.joined(separator: ", ") }
        return text
    }

    /// Short reminder of the safety model and anything unusual in the selection.
    private var enabledCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Before you scan").sectionHeaderStyle()
            Label("Nothing is removed without a confirmation that lists every type.", systemImage: "checkmark.shield")
            Label("Items go to the Trash by default, so they can be put back.", systemImage: "trash")
            Label("Removals are logged to ~/Library/Logs/Prune/deletions.jsonl.", systemImage: "doc.text")
            let irreplaceable = enabledTypes.filter { !$0.regenerable }
            if !irreplaceable.isEmpty {
                Label {
                    Text("Enabled types that cannot be regenerated: ")
                        + Text(irreplaceable.map(\.displayName).joined(separator: ", ")).fontWeight(.semibold)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
            }
        }
        .font(.callout)
        .foregroundColor(.secondary)
        .cardStyle()
    }
}
