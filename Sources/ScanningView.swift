import SwiftUI

struct ScanningView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.5)

            VStack(spacing: 6) {
                if let sizing = state.sizingProgress {
                    Text("Calculating sizes...")
                        .font(.headline)
                    Text("\(sizing.completed) / \(sizing.total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Scanning...")
                        .font(.headline)
                    Text(state.scanProgress)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300)
                }

                Text("Found \(state.foundCount) \(state.foundCount == 1 ? "directory" : "directories")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Cancel") {
                state.cancelScan()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
