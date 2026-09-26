import SwiftUI
import AppKit
import PruneCore

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var keyMonitor: Any?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .navigationTitle("Prune")
        .navigationSubtitle(subtitle)
        .searchable(text: $state.searchText, placement: .toolbar, prompt: "Filter by name or path")
        .toolbar { toolbarContent }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .alert(
            "Cannot scan this folder",
            isPresented: Binding(
                get: { state.rootError != nil },
                set: { if !$0 { state.rootError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.rootError = nil }
        } message: {
            Text(state.rootError ?? "")
        }
    }

    private var subtitle: String {
        switch state.phase {
        case .idle:
            return state.scanRootDisplay
        case .scanning:
            return "Scanning \(state.scanRootDisplay)"
        case .results:
            return "\(state.visibleEntries.count.counted("item")), \(Formatter.formatSize(state.totalSize)) in \(state.scanRootDisplay)"
        case .deleting:
            return state.batchMode == .trash ? "Moving to Trash" : "Deleting"
        case .summary:
            return "Done"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $state.sortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .pickerStyle(.inline)
                Picker("Order", selection: $state.sortAscending) {
                    Text("Descending").tag(false)
                    Text("Ascending").tag(true)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort results (currently by \(state.sortField.rawValue.lowercased()), \(state.sortAscending ? "ascending" : "descending"))")
            .accessibilityLabel("Sort results")
            .disabled(state.phase != .results)

            if state.phase == .scanning {
                Button(action: { state.cancelScan() }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop the scan")
                .accessibilityLabel("Stop scan")
            } else {
                Button(action: { state.startScan() }) {
                    Label(state.phase == .idle ? "Scan" : "Rescan",
                          systemImage: state.phase == .idle ? "magnifyingglass" : "arrow.clockwise")
                }
                .help(state.phase == .idle ? "Scan for artifacts" : "Scan again with the current settings (Command-R)")
                .accessibilityLabel(state.phase == .idle ? "Scan" : "Rescan")
                .disabled(!state.canScan)
            }
        }
    }

    // MARK: Keyboard

    /// Handles Delete (confirm deletion) and Command-A (select all visible) on
    /// the results screen, but never while a text field such as the search
    /// field is being edited, and never behind a sheet or alert.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let state = self.state
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread.
            let box = EventBox(event: event)
            let consumed = MainActor.assumeIsolated {
                Self.handleKey(box.event, state: state)
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    @MainActor
    private static func handleKey(_ event: NSEvent, state: AppState) -> Bool {
        guard state.phase == .results,
              NSApp.modalWindow == nil,
              let window = event.window,
              window.attachedSheet == nil,
              window.sheetParent == nil,
              !(window.firstResponder is NSText)
        else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let deleteKeys: Set<UInt16> = [51, 117] // Delete (backspace), Forward Delete
        if deleteKeys.contains(event.keyCode), flags.isEmpty || flags == .command {
            state.requestDeletion(.trash)
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "a" {
            state.selectAll()
            return true
        }
        return false
    }
}

/// Carries an NSEvent into a main-actor closure; local event monitors are
/// always invoked on the main thread, so no cross-thread access happens.
private struct EventBox: @unchecked Sendable {
    let event: NSEvent
}

/// Picks the detail screen for the current phase.
struct DetailView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
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
}
