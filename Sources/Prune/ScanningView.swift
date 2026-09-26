import SwiftUI
import PruneCore

/// Scanning detail: current folder, found count and sizing progress.
struct ScanningView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(state.sizingProgress == nil ? "Scanning" : "Calculating sizes")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Text(state.foundCount.counted("item") + " found")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                if let sizing = state.sizingProgress {
                    ProgressView(value: Double(sizing.completed), total: Double(max(sizing.total, 1)))
                        .progressViewStyle(.linear)
                    Text("\(sizing.completed) of \(sizing.total) sized")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(state.scanProgress.isEmpty ? state.scanRootDisplay : state.scanProgress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(state.scanProgress)
                }

                HStack {
                    Text("\(state.scannedCategories.count.counted("type")) in \(state.scanRootDisplay)")
                        .font(.caption)
                        .foregroundColor(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Cancel") { state.cancelScan() }
                        .keyboardShortcut(.cancelAction)
                        .help("Stop the scan (Escape)")
                }
            }
            .cardStyle(padding: Theme.Spacing.xl)
            .frame(maxWidth: 560)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
