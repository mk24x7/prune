import SwiftUI
import PruneCore

struct SummaryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Outcome icon
            ZStack {
                Circle()
                    .fill(outcome.color.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: outcome.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(outcome.color)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))

                ForEach(detailLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Per-category breakdown
            if state.categoryBreakdown.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.categoryBreakdown, id: \.typeId) { item in
                        let type = state.definitions.type(id: item.typeId)
                        HStack(spacing: 6) {
                            Image(systemName: type?.icon ?? "questionmark.folder")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 14)
                            Text(type?.displayName ?? item.typeId)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(item.count) items")
                                .font(.system(size: 10))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            Text(Formatter.formatSize(item.bytes))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: 360)
            }

            // Show failures if any
            if !state.failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.deletedCount == 0 ? "Not deleted:" : "Failed to delete:")
                        .font(.caption)
                        .foregroundColor(.red)
                    ForEach(state.failures.indices, id: \.self) { i in
                        Text("\(state.failures[i].path) -- \(state.failures[i].error)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: 400)
            }

            HStack(spacing: 12) {
                Button("Scan Again") {
                    state.reset()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "Move to Trash failed",
            isPresented: Binding(
                get: { state.pendingPermanentFallback },
                set: { if !$0 { state.declinePermanentFallback() } }
            )
        ) {
            Button("Delete Permanently", role: .destructive) { state.confirmPermanentFallback() }
            Button("Skip", role: .cancel) { state.declinePermanentFallback() }
        } message: {
            let count = state.trashUnsupportedEntries.count
            Text("\(count) \(count == 1 ? "item" : "items") could not be moved to Trash (the volume does not support it). Delete \(count == 1 ? "it" : "them") permanently?")
        }
    }

    private enum Outcome {
        case allOk, partial, none

        var icon: String {
            switch self {
            case .allOk: return "checkmark"
            case .partial: return "exclamationmark.triangle"
            case .none: return "xmark"
            }
        }

        var color: Color {
            switch self {
            case .allOk: return .green
            case .partial: return .orange
            case .none: return .red
            }
        }
    }

    private var outcome: Outcome {
        if state.deletedCount == 0 { return .none }
        return state.failedCount == 0 ? .allOk : .partial
    }

    private var title: String {
        switch outcome {
        case .none:
            return "Nothing was deleted"
        case .partial:
            return "Deleted \(state.deletedCount) of \(state.deletedCount + state.failedCount)"
        case .allOk:
            if state.permanentCount == 0 {
                return "\(Formatter.formatSize(state.trashedEstimatedBytes)) moved to Trash"
            }
            return "\(Formatter.formatSize(state.measuredFreedBytes)) freed"
        }
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if state.trashedCount > 0 {
            lines.append("Moved to Trash: \(Formatter.formatSize(state.trashedEstimatedBytes)) (estimated). Empty the Trash to reclaim the space.")
        }
        if state.permanentCount > 0 {
            lines.append("Freed \(Formatter.formatSize(state.measuredFreedBytes)) (measured; \(Formatter.formatSize(state.permanentEstimatedBytes)) estimated)")
        }
        let total = state.deletedCount + state.failedCount
        lines.append("\(state.deletedCount) of \(total) \(total == 1 ? "item" : "items") removed")
        return lines
    }
}
