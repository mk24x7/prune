import SwiftUI

@main
struct PruneApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 600, minHeight: 500)
        }
        .defaultSize(width: 720, height: 640)
        .windowStyle(.hiddenTitleBar)
    }
}
