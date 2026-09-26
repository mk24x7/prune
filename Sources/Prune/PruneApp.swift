import SwiftUI
import AppKit
import PruneCore

@main
struct PruneApp: App {
    @StateObject private var appState: AppState
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .dark

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
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { AppearancePreference.current.apply() }
                .task {
                    if Snapshot.directory != nil {
                        await Snapshot.run(state: appState)
                    }
                }
        }
        .defaultSize(width: 1040, height: 680)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button(appState.phase == .idle ? "Scan" : "Rescan") { appState.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!appState.canScan)
                Button("Stop Scan") { appState.cancelScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(appState.phase != .scanning)
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: Binding(
                    get: { appearance },
                    set: { newValue in
                        appearance = newValue
                        newValue.apply()
                    }
                )) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Divider()
            }
        }
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
