import Foundation

enum Deleter {
    struct Result {
        var deleted: [URL] = []
        var failed: [(url: URL, error: String)] = []
    }

    /// Delete directories sequentially to avoid I/O spikes.
    static func delete(
        urls: [URL],
        onProgress: (Int, Int, URL) -> Void
    ) -> Result {
        var result = Result()
        let fm = FileManager.default

        for (index, url) in urls.enumerated() {
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
