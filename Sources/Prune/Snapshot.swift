import AppKit
import SwiftUI
import PruneCore

/// Hidden snapshot mode used to regenerate the README screenshot without
/// screen recording permission:
///
///     PRUNE_SNAPSHOT_DIR=/tmp/prune-shots dist/Prune.app/Contents/MacOS/Prune
///
/// It scans PRUNE_SNAPSHOT_ROOT (default ~/Demo) for project artifacts only,
/// so no real cache paths from the machine appear, then renders the sidebar
/// and detail views offscreen at 2x into landing.png and results.png and quits.
/// It never deletes anything and never changes the saved type selection.
enum Snapshot {
    static let size = NSSize(width: 1040, height: 680)
    static let scale: CGFloat = 2

    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["PRUNE_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["PRUNE_SNAPSHOT_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Demo", isDirectory: true)
    }

    @MainActor
    static func run(state: AppState) async {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        state.persistsCategories = false
        state.selectedCategories = Set(state.definitions.projectTypes.map(\.id))
        state.includeHidden = false
        state.setScanRoot(root)

        await render(state: state, to: dir.appendingPathComponent("landing.png"))

        state.startScan(minAgeOverride: 0)
        let deadline = Date().addingTimeInterval(180)
        while state.phase == .scanning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if state.phase == .results {
            // Show the selection state: the three largest results.
            for entry in state.sortedEntries.prefix(3) { state.toggleSelection(entry) }
            await render(state: state, to: dir.appendingPathComponent("results.png"))
        } else {
            FileHandle.standardError.write(Data("snapshot: scan did not finish (\(state.rootError ?? "timeout"))\n".utf8))
        }
        NSApp.terminate(nil)
    }

    /// Hosts the sidebar and detail side by side in a borderless window and
    /// captures it. The real window's glass sidebar and toolbar do not render
    /// through cacheDisplay, so they are replaced by solid backgrounds here.
    @MainActor
    private static func render(state: AppState, to url: URL) async {
        let content = HStack(spacing: 0) {
            SidebarView()
                .frame(width: 290)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .frame(width: size.width, height: size.height)
        .environmentObject(state)

        let window = KeyableWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        host.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }
}

/// Borderless windows cannot become key by default, which renders prominent
/// buttons in their inactive grey; the snapshot should show the active look.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
