import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Title bar drag area
            TitleBarView()

            // Phase-based content
            switch state.phase {
            case .idle:
                LandingView()
            case .scanning:
                ScanningView()
            case .results:
                ResultsView()
            case .deleting:
                DeletingView()
            case .summary:
                SummaryView()
            }
        }
        .background(Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)))
    }
}

struct TitleBarView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Prune")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(height: 38)
        .background(Color.clear)
    }
}
