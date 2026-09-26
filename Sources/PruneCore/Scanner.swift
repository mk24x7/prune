import Foundation

actor Scanner {
    private static let baseSkipDirs: Set<String> = [
        "Library", ".Trash", "Applications", "Pictures", "Movies", "Music",
        ".Spotlight-V100", ".fseventsd",
        ".npm", ".cache", ".yarn", ".pnpm-store", ".bun",
        ".git", ".docker", ".ollama", ".conda", ".anaconda",
        ".cocoapods", ".cargo", ".rustup",
        ".oh-my-zsh", ".zsh_sessions",
        ".vscode", ".cursor", ".windsurf",
        ".local", ".config", "Wallpapers",
    ]

    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    /// Scan a directory tree for artifacts matching the given definitions.
    func scan(
        root: URL,
        definitions: [ArtifactDefinition],
        includeHidden: Bool = false,
        onProgress: @Sendable (String) -> Void,
        onFound: @Sendable (URL, ArtifactCategory, Int) -> Void
    ) -> [(url: URL, category: ArtifactCategory)] {
        cancelled = false
        var results: [(url: URL, category: ArtifactCategory)] = []
        let fm = FileManager.default

        // Build lookup structures
        let targetNames = ArtifactRegistry.allTargetNames(for: definitions)

        // Adjust skip list: remove any entries that are target directories
        // (e.g. .gradle should not be skipped if Gradle scanning is enabled)
        let skipDirs = Self.baseSkipDirs.subtracting(targetNames)

        var stack: [(URL, Int)] = [(root, 0)]
        let maxDepth = 8
        var lastProgressTime = Date.timeIntervalSinceReferenceDate

        while !stack.isEmpty {
            if cancelled { return results }

            let (dirURL, depth) = stack.removeLast()
            if depth > maxDepth { continue }

            let now = Date.timeIntervalSinceReferenceDate
            if now - lastProgressTime > 0.1 {
                onProgress(dirURL.path)
                lastProgressTime = now
            }

            guard let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for itemURL in contents {
                if cancelled { return results }

                let name = itemURL.lastPathComponent

                // Check if this directory name matches any artifact target
                if targetNames.contains(name) {
                    guard let values = try? itemURL.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    ) else { continue }

                    if values.isDirectory == true && values.isSymbolicLink != true {
                        // Check which definition matches (including sibling detection)
                        if let def = ArtifactRegistry.matchDefinition(
                            dirName: name,
                            parentURL: dirURL,
                            definitions: definitions,
                            fm: fm
                        ) {
                            results.append((url: itemURL, category: def.category))
                            onFound(itemURL, def.category, results.count)
                        }
                    }
                    // Don't recurse into matched directories regardless of match
                    continue
                }

                // Only recurse into directories
                guard let values = try? itemURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                ) else { continue }

                guard values.isDirectory == true else { continue }
                guard values.isSymbolicLink != true else { continue }

                // Skip known unproductive directories
                if skipDirs.contains(name) { continue }

                // Skip hidden dirs unless opted in (but never skip artifact targets)
                if !includeHidden && name.hasPrefix(".") && !targetNames.contains(name) { continue }

                stack.append((itemURL, depth + 1))
            }
        }

        return results
    }

    /// Check system-level artifact paths for existence.
    /// Returns entries for each path that exists.
    /// For paths with expandSubdirectories, returns individual subdirectory entries.
    nonisolated func checkSystemArtifacts(
        categories: Set<ArtifactCategory>
    ) -> [(url: URL, category: ArtifactCategory)] {
        let fm = FileManager.default
        var results: [(url: URL, category: ArtifactCategory)] = []

        for sysArtifact in ArtifactRegistry.systemArtifacts(for: categories) {
            guard fm.fileExists(atPath: sysArtifact.url.path) else { continue }

            if sysArtifact.expandSubdirectories {
                // List subdirectories as individual entries
                guard let contents = try? fm.contentsOfDirectory(
                    at: sysArtifact.url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    // If we can't list, add the whole directory
                    results.append((url: sysArtifact.url, category: sysArtifact.category))
                    continue
                }

                for item in contents {
                    guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                          values.isDirectory == true else { continue }
                    results.append((url: item, category: sysArtifact.category))
                }
            } else {
                results.append((url: sysArtifact.url, category: sysArtifact.category))
            }
        }

        return results
    }
}
