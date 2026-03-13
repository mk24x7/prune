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
            guard url.lastPathComponent == "node_modules" else {
                result.failed.append((url: url, error: "Refusing to delete: path does not end in node_modules"))
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
