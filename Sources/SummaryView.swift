import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.green)
            }

            VStack(spacing: 6) {
                Text("\(Formatter.formatSize(state.freedBytes)) freed")
                    .font(.system(size: 28, weight: .bold))

                Text("Deleted \(state.deletedCount) of \(state.deletedCount + state.failedCount) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Per-category breakdown
            if state.categoryBreakdown.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.categoryBreakdown, id: \.category) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.category.icon)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 14)
                            Text(item.category.rawValue)
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
                    Text("Failed to delete:")
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
    }
}
