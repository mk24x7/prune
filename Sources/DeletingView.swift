import SwiftUI

struct DeletingView: View {
    @EnvironmentObject var state: AppState

    var progress: Double {
        guard state.deletionTotal > 0 else { return 0 }
        return Double(state.deletionCurrent) / Double(state.deletionTotal)
    }

    var currentItem: DeletionItem? {
        state.deletionItems.first { $0.status == .inProgress }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Deleting... \(state.deletionCurrent) of \(state.deletionTotal)")
                .font(.headline)

            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)

                HStack {
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 300)
            }

            if let item = currentItem {
                Text("Currently: \(item.entry.projectName) (\(item.entry.formattedSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer().frame(height: 16)

            // Item list
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.deletionItems) { item in
                        HStack(spacing: 8) {
                            statusIcon(for: item.status)
                                .frame(width: 14)
                            Text(item.entry.projectName)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(item.entry.formattedSize)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            statusLabel(for: item.status)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 200)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusIcon(for status: DeletionStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
        case .inProgress:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private func statusLabel(for status: DeletionStatus) -> some View {
        switch status {
        case .pending:
            Text("")
                .font(.system(size: 10))
        case .inProgress:
            Text("...")
                .font(.system(size: 10))
                .foregroundColor(.blue)
        case .done:
            Text("done")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .failed:
            Text("failed")
                .font(.system(size: 10))
                .foregroundColor(.red)
        }
    }
}
