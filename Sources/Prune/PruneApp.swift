import SwiftUI
import AppKit
import PruneCore

@main
struct PruneApp: App {
    @StateObject private var appState: AppState

    init() {
        let definitions: Definitions
        do {
            definitions = try Definitions.load()
        } catch {
            PruneApp.failLaunch(error)
        }
        _appState = StateObject(wrappedValue: AppState(definitions: definitions))
    }

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

    /// The artifact definitions are required for every screen, so a broken or
    /// missing artifacts.json is reported once and the app quits.
    private static func failLaunch(_ error: Error) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Prune cannot start"
        alert.informativeText = "The bundled artifact definitions could not be loaded.\n\n"
            + error.localizedDescription
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        exit(EXIT_FAILURE)
    }
}
