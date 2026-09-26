import Foundation

enum Deleter {
    struct Result {
        var deleted: [URL] = []
        var failed: [(url: URL, error: String)] = []
    }

    /// Delete directories sequentially to avoid I/O spikes.
    /// Safety: only deletes directories whose last path component is in `allowedNames`,
    /// or whose full URL is in `allowedSystemPaths`.
    static func delete(
        urls: [URL],
        allowedNames: Set<String>,
        allowedSystemPaths: Set<URL>,
        onProgress: (Int, Int, URL) -> Void
    ) -> Result {
        var result = Result()
        let fm = FileManager.default

        for (index, url) in urls.enumerated() {
            let name = url.lastPathComponent
            let isAllowedByName = allowedNames.contains(name)
            let isAllowedByPath = allowedSystemPaths.contains(url)

            guard isAllowedByName || isAllowedByPath else {
                result.failed.append((
                    url: url,
                    error: "Refusing to delete: '\(name)' is not a recognized artifact directory"
                ))
                continue
            }

            onProgress(index + 1, urls.count, url)

            do {
                try fm.removeItem(at: url)
                result.deleted.append(url)
            } catch {
                result.failed.append((url: url, error: error.localizedDescription))
            }
        }

        return result
    }
}
