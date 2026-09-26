import SwiftUI
import PruneCore

/// Deleting detail: overall progress card and a per-item status list.
struct DeletingView: View {
    @EnvironmentObject var state: AppState

    private var progress: Double {
        guard state.deletionTotal > 0 else { return 0 }
        return Double(state.deletionCurrent) / Double(state.deletionTotal)
    }

    private var currentItem: DeletionItem? {
        state.deletionItems.first { $0.status == .inProgress }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            progressCard
            itemsCard
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.batchMode == .trash ? "Moving to Trash" : "Deleting permanently")
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(state.deletionCurrent) of \(state.deletionTotal)")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(currentItem.map { "Now: \($0.entry.shortPath) (\($0.entry.formattedSize))" } ?? " ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .cardStyle()
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Items")
                .sectionHeaderStyle()
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.s)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.deletionItems) { item in
                        DeletionRow(item: item, type: state.type(for: item.entry))
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .cardStyle(padding: 0)
    }
}

struct DeletionRow: View {
    let item: DeletionItem
    let type: ArtifactType?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            statusIcon
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(item.entry.projectName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    TypeBadge(type: type, fallback: item.entry.typeId)
                }
                if let error = item.error, item.status == .failed {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                } else {
                    Text(item.entry.shortPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            Text(item.entry.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            statusLabel
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 8, height: 8)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .pending:
            Text("waiting").font(.caption).foregroundColor(Theme.tertiary)
        case .inProgress:
            Text("...").font(.caption).foregroundColor(.accentColor)
        case .done:
            Text("done").font(.caption).foregroundColor(.green)
        case .failed:
            Text("failed").font(.caption).foregroundColor(.red)
        }
    }
}
