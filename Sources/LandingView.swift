import SwiftUI

struct LandingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: "folder.badge.minus")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            VStack(spacing: 4) {
                Text("Prune")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Find and remove unused node_modules to free disk space")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

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

                Toggle("Include hidden directories", isOn: $state.includeHidden)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280)

            Button(action: { state.startScan() }) {
                Text("Scan for node_modules")
                    .frame(maxWidth: 280)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
        .padding(.horizontal, 40)
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
