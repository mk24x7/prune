import SwiftUI
import AppKit
import PruneCore

/// Summary detail: outcome, measured and estimated figures, per-type table,
/// failures, and the Rescan / Quit actions.
struct SummaryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                outcomeCard
                figuresCard
                if !state.categoryBreakdown.isEmpty {
                    breakdownCard
                }
                if !state.failures.isEmpty {
                    failuresCard
                }
                HStack(spacing: Theme.Spacing.m) {
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .controlSize(.large)
                    Button(action: { state.startScan() }) {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!state.canScan)
                    .help("Scan again with the current settings (Return)")
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
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

    // MARK: Cards

    private var outcomeCard: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                Circle()
                    .fill(outcome.color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: outcome.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(outcome.color)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                ForEach(detailLines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(outcome.color.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(outcome.color.opacity(0.35), lineWidth: 1)
        )
    }

    private var figuresCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Figures").sectionHeaderStyle()
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                if state.permanentCount > 0 {
                    StatView(value: Formatter.formatSize(state.measuredFreedBytes),
                             label: "freed (measured)", color: .green)
                    StatView(value: Formatter.formatSize(state.permanentEstimatedBytes),
                             label: "deleted (estimated)")
                }
                if state.trashedCount > 0 {
                    StatView(value: Formatter.formatSize(state.trashedEstimatedBytes),
                             label: "in Trash (estimated)")
                }
                StatView(value: "\(state.deletedCount) of \(state.deletedCount + state.failedCount)",
                         label: "items removed")
                if state.failedCount > 0 {
                    StatView(value: "\(state.failedCount)", label: "failed", color: .red)
                }
                Spacer(minLength: 0)
            }
            if state.trashedCount > 0 {
                Text("Items in the Trash still use disk space until you empty the Trash.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Removed by type").sectionHeaderStyle()
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: 6) {
                GridRow {
                    Text("Type")
                    Text("Items").gridColumnAlignment(.trailing)
                    Text("Size").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundColor(Theme.tertiary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(state.categoryBreakdown, id: \.typeId) { item in
                    let type = state.definitions.type(id: item.typeId)
                    GridRow {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: type?.icon ?? "questionmark.folder")
                                .foregroundColor(Palette.color(type?.color))
                                .frame(width: 16)
                            Text(type?.displayName ?? item.typeId)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.count)")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        Text(Formatter.formatSize(item.bytes))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .font(.callout)
                }
            }
        }
        .cardStyle()
    }

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(state.deletedCount == 0 ? "Not deleted" : "Failed to delete")
                .sectionHeaderStyle()
                .foregroundColor(.red)
            ForEach(state.failures.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.failures[i].path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(state.failures[i].error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textSelection(.enabled)
            }
        }
        .cardStyle()
    }

    // MARK: Outcome

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
