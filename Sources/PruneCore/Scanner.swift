import Foundation

public struct ScanResult: Sendable {
    public var found: [(url: URL, typeId: String)]
    /// First `Scanner.deniedDirectoryCap` directories that could not be read.
    public var deniedDirectories: [URL]
    /// Total number of directories that could not be read.
    public var deniedCount: Int
    /// Number of directories whose contents were listed.
    public var scannedCount: Int

    public init(found: [(url: URL, typeId: String)] = [], deniedDirectories: [URL] = [],
                deniedCount: Int = 0, scannedCount: Int = 0) {
        self.found = found
        self.deniedDirectories = deniedDirectories
        self.deniedCount = deniedCount
        self.scannedCount = scannedCount
    }
}

public struct Scanner: Sendable {
    public static let deniedDirectoryCap = 50

    public init() {}

    /// Walk `root` looking for project artifacts of the given types.
    ///
    /// Rules (shared with the CLI via artifacts.json):
    /// - `rules.skipUnderHome` names are skipped only directly under `home`;
    ///   `rules.skipAnywhere` names are skipped at any depth.
    /// - Directories whose name ends in one of `rules.skipPackageExtensions`
    ///   (.app, .xcodeproj, ...) are never entered.
    /// - A directory whose name is a target and whose type matches (sibling
    ///   check) is recorded and not descended into. If no type matches, the
    ///   directory is treated like any other and recursion continues.
    /// - Root is depth 0; artifacts are found at depth up to `rules.maxDepth` inclusive.
    /// - Symlinks are never followed or reported.
    /// - Hidden directories are skipped unless `includeHidden`, except target names.
    /// - Paths in `extraSkipPaths` (resolved system cache paths) are never entered.
    /// - Cancellation is checked continuously; partial results are returned.
    public func scan(
        root: URL,
        types: [ArtifactType],
        rules: ScanRules,
        includeHidden: Bool,
        home: URL,
        extraSkipPaths: Set<URL>,
        onProgress: (String) -> Void,
        onFound: (URL, String, Int) -> Void
    ) -> ScanResult {
        var result = ScanResult()
        let fm = FileManager.default
        let projectTypes = types.filter { $0.kind == .project }
        guard !projectTypes.isEmpty else { return result }

        var typesByTarget: [String: [ArtifactType]] = [:]
        for type in projectTypes {
            for target in type.targets ?? [] {
                typesByTarget[target, default: []].append(type)
            }
        }
        let skipAnywhere = Set(rules.skipAnywhere)
        let skipUnderHome = Set(rules.skipUnderHome)
        let packageSuffixes = rules.skipPackageExtensions.map { $0.lowercased() }
        let homePath = home.standardizedFileURL.path
        let skipPaths = Set(extraSkipPaths.map { $0.standardizedFileURL.path })

        var stack: [(URL, Int)] = [(root, 0)]
        var lastProgress = Date.timeIntervalSinceReferenceDate

        while let (dirURL, depth) = stack.popLast() {
            if Task.isCancelled { return result }
            // Root is depth 0; a directory is listed only while its depth is
            // below maxDepth, so artifacts are found at depth <= maxDepth.
            if depth >= rules.maxDepth { continue }

            let now = Date.timeIntervalSinceReferenceDate
            if now - lastProgress > 0.1 {
                onProgress(dirURL.path)
                lastProgress = now
            }

            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [])
            } catch {
                if error.isPermissionError {
                    result.deniedCount += 1
                    if result.deniedDirectories.count < Self.deniedDirectoryCap {
                        result.deniedDirectories.append(dirURL)
                    }
                }
                continue
            }
            result.scannedCount += 1
            let dirIsHome = dirURL.standardizedFileURL.path == homePath

            for (index, itemURL) in contents.enumerated() {
                if index & 63 == 63, Task.isCancelled { return result }

                // Only real directories are interesting; symlinks never are.
                guard FileKind.of(itemURL) == .directory else { continue }
                let name = itemURL.lastPathComponent
                if !skipPaths.isEmpty, skipPaths.contains(itemURL.standardizedFileURL.path) { continue }

                if let candidates = typesByTarget[name] {
                    if let match = candidates.first(where: { Self.siblingsSatisfied($0, parent: dirURL, fm: fm) }) {
                        result.found.append((url: itemURL, typeId: match.id))
                        onFound(itemURL, match.id, result.found.count)
                        continue
                    }
                    // No type matched: fall through and treat it as a normal directory.
                }

                if skipAnywhere.contains(name) { continue }
                if dirIsHome && skipUnderHome.contains(name) { continue }
                let lowered = name.lowercased()
                if packageSuffixes.contains(where: { lowered.hasSuffix($0) }) { continue }
                if !includeHidden && name.hasPrefix(".") && typesByTarget[name] == nil { continue }

                stack.append((itemURL, depth + 1))
            }
        }
        return result
    }

    static func siblingsSatisfied(_ type: ArtifactType, parent: URL, fm: FileManager) -> Bool {
        let siblings = type.siblings ?? []
        if siblings.isEmpty { return true }
        return siblings.contains { fm.fileExists(atPath: parent.appendingPathComponent($0).path) }
    }

    /// Find system and files kind artifacts at their resolved locations.
    /// - system: the resolved path must exist (a regular file when `isFile`);
    ///   with `expand` every subdirectory, hidden ones included, is an entry,
    ///   otherwise the path itself is a single entry.
    /// - files: every regular file directly inside the resolved path whose
    ///   extension (case-insensitive) is listed in `extensions`.
    public func checkSystemArtifacts(
        types: [ArtifactType],
        definitions: Definitions,
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [(url: URL, typeId: String)] {
        let fm = FileManager.default
        var results: [(url: URL, typeId: String)] = []

        for type in types where type.kind != .project {
            guard let url = definitions.resolvedSystemURL(for: type, env: env, home: home) else { continue }

            switch type.kind {
            case .project:
                continue
            case .system:
                if type.isFile == true {
                    if FileKind.of(url) == .regularFile { results.append((url: url, typeId: type.id)) }
                    continue
                }
                if type.expand == true {
                    // The container itself may be a symlink (e.g. a relocated
                    // cache); its children must be real directories.
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard let children = try? fm.contentsOfDirectory(
                        at: url, includingPropertiesForKeys: nil, options: []
                    ) else {
                        if FileKind.of(url) == .directory { results.append((url: url, typeId: type.id)) }
                        continue
                    }
                    for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    where FileKind.of(child) == .directory {
                        results.append((url: child, typeId: type.id))
                    }
                } else if FileKind.of(url) == .directory {
                    results.append((url: url, typeId: type.id))
                }
            case .files:
                let extensions = Set((type.extensions ?? []).map { $0.lowercased() })
                guard let children = try? fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: []
                ) else { continue }
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where FileKind.of(child) == .regularFile
                    && extensions.contains("." + child.pathExtension.lowercased()) {
                    results.append((url: child, typeId: type.id))
                }
            }
        }
        return results
    }
}
