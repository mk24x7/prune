import Foundation

/// Last line of defence before anything is removed. Every check re-reads the
/// file system at delete time, so a tree that changed since the scan (a
/// directory swapped for a symlink, a project manifest removed) is refused.
public enum Verifier {
    public static func verify(
        entry: ArtifactEntry,
        type: ArtifactType,
        scanRoot: URL,
        definitions: Definitions,
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fm: FileManager = .default
    ) throws {
        func reject(_ reason: String) -> DeletionFailure { .verification(reason) }

        guard entry.typeId == type.id else {
            throw reject("entry type \(entry.typeId) does not match \(type.id)")
        }
        let url = entry.url.standardizedFileURL
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count > 2 else {
            throw reject("refusing to delete a path this close to the root: \(url.path)")
        }
        let real = realPath(url)
        let homeReal = realPath(home)
        if url.path == "/" || real == "/" || url.path == home.standardizedFileURL.path || real == homeReal {
            throw reject("refusing to delete / or the home folder")
        }

        switch FileKind.of(url) {
        case .symlink:
            throw reject("\(url.lastPathComponent) is a symbolic link")
        case .missing:
            throw reject("\(url.path) no longer exists")
        case .directory:
            if type.entriesAreFiles { throw reject("\(url.lastPathComponent) is a directory, expected a file") }
        case .regularFile:
            if !type.entriesAreFiles { throw reject("\(url.lastPathComponent) is a file, expected a directory") }
        case .other:
            throw reject("\(url.lastPathComponent) is not a regular file or directory")
        }

        let parent = url.deletingLastPathComponent().standardizedFileURL
        switch type.kind {
        case .project:
            guard (type.targets ?? []).contains(url.lastPathComponent) else {
                throw reject("\(url.lastPathComponent) is not a \(type.displayName) folder name")
            }
            let rootReal = realPath(scanRoot)
            let prefix = rootReal == "/" ? "/" : rootReal + "/"
            guard real.hasPrefix(prefix) else {
                throw reject("\(url.path) is outside the scanned folder \(scanRoot.path)")
            }
            let siblings = type.siblings ?? []
            if !siblings.isEmpty,
               !siblings.contains(where: { fm.fileExists(atPath: parent.appendingPathComponent($0).path) }) {
                throw reject("no \(siblings.joined(separator: " / ")) next to \(url.lastPathComponent) any more")
            }

        case .system:
            guard let resolved = definitions.resolvedSystemURL(for: type, env: env, home: home) else {
                throw reject("\(type.id) has no resolvable path")
            }
            let isResolved = samePath(url, resolved)
            let isExpandedChild = type.expand == true && samePath(parent, resolved)
            guard isResolved || isExpandedChild else {
                throw reject("\(url.path) is not the \(type.displayName) location")
            }

        case .files:
            guard let resolved = definitions.resolvedSystemURL(for: type, env: env, home: home) else {
                throw reject("\(type.id) has no resolvable path")
            }
            guard samePath(parent, resolved) else {
                throw reject("\(url.path) is not directly inside \(resolved.path)")
            }
            let ext = "." + url.pathExtension.lowercased()
            guard (type.extensions ?? []).contains(where: { $0.lowercased() == ext }) else {
                throw reject("\(url.lastPathComponent) does not have a \(type.displayName) extension")
            }
        }
    }

    static func samePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path || realPath(a) == realPath(b)
    }

    /// realpath(3), or the standardized path when the item does not exist.
    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
