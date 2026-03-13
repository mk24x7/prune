import Foundation

actor Scanner {
    private static let skipDirs: Set<String> = [
        "Library", ".Trash", "Applications", "Pictures", "Movies", "Music",
        ".Spotlight-V100", ".fseventsd",
        ".npm", ".cache", ".yarn", ".pnpm-store", ".bun",
        ".git", ".docker", ".ollama", ".conda", ".anaconda",
        ".cocoapods", ".gradle", ".cargo", ".rustup",
        ".oh-my-zsh", ".zsh_sessions",
        ".vscode", ".cursor", ".windsurf",
        ".local", ".config", "Wallpapers",
    ]

    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    func scan(
        root: URL,
        includeHidden: Bool = false,
        onProgress: @Sendable (String) -> Void,
        onFound: @Sendable (URL, Int) -> Void
    ) -> [URL] {
        cancelled = false
        var results: [URL] = []
        let fm = FileManager.default

        // Stack-based DFS like the Node.js version
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

                // Found node_modules
                if name == "node_modules" {
                    guard let values = try? itemURL.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    ) else { continue }

                    if values.isDirectory == true && values.isSymbolicLink != true {
                        results.append(itemURL)
                        onFound(itemURL, results.count)
                    }
                    continue
                }

                // Only recurse into directories
                guard let values = try? itemURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                ) else { continue }

                guard values.isDirectory == true else { continue }
                guard values.isSymbolicLink != true else { continue }

                // Skip known unproductive directories
                if Self.skipDirs.contains(name) { continue }

                // Skip hidden dirs unless opted in
                if !includeHidden && name.hasPrefix(".") { continue }

                stack.append((itemURL, depth + 1))
            }
        }

        return results
    }
}
