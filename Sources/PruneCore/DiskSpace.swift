import Foundation

/// Measures space actually returned to the file system by grouping the
/// affected paths by volume and diffing each volume's available capacity.
public enum DiskSpace {
    public struct Snapshot: Sendable, Equatable {
        /// Volume root path -> available bytes.
        public let available: [String: Int64]
    }

    /// Available capacity of every volume that holds one of `urls`.
    public static func snapshot(for urls: [URL]) -> Snapshot {
        var volumes: [String: URL] = [:]
        for url in urls {
            guard let volume = volumeURL(containing: url) else { continue }
            volumes[volume.path] = volume
        }
        return snapshot(volumes: Array(volumes.values))
    }

    /// Re-measure the same volumes as `before`.
    public static func snapshot(matching before: Snapshot) -> Snapshot {
        snapshot(volumes: before.available.keys.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    /// Sum over volumes of (after - before), each clamped at zero so unrelated
    /// writes on one volume cannot make the total negative.
    public static func freedBytes(before: Snapshot, after: Snapshot) -> Int64 {
        before.available.reduce(Int64(0)) { total, pair in
            guard let now = after.available[pair.key] else { return total }
            return total + max(0, now - pair.value)
        }
    }

    private static func snapshot(volumes: [URL]) -> Snapshot {
        var available: [String: Int64] = [:]
        for volume in volumes {
            // A fresh URL instance avoids Foundation's cached resource values.
            var fresh = URL(fileURLWithPath: volume.path, isDirectory: true)
            fresh.removeAllCachedResourceValues()
            if let capacity = try? fresh.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity {
                available[volume.path] = Int64(capacity)
            }
        }
        return Snapshot(available: available)
    }

    /// Volume root for `url`, walking up to the nearest existing ancestor.
    static func volumeURL(containing url: URL) -> URL? {
        var current = url.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.path),
               let volume = try? current.resourceValues(forKeys: [.volumeURLKey]).volume {
                return volume
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
