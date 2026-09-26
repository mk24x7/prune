import Foundation
import XCTest

/// One node in a TempTree spec.
enum TreeNode {
    /// Regular file with the given UTF-8 contents.
    case file(String)
    /// Regular file filled with `count` bytes of non-sparse data.
    case bytes(Int)
    /// Empty directory (parents are created implicitly for every node).
    case dir
    /// Symbolic link whose target is the given string (relative or absolute).
    case symlink(String)
}

/// A throwaway directory tree built from a spec map of relative path -> node
/// under a fresh `mkdtemp` directory. The root is canonicalised with realpath
/// (so /var vs /private/var never differs) and removed, permissions and all,
/// when the object is released.
final class TempTree {
    let root: URL

    init(_ spec: [String: TreeNode] = [:], file: StaticString = #filePath, line: UInt = #line) throws {
        var template = Array((NSTemporaryDirectory() as NSString)
            .appendingPathComponent("prune-test-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let raw = String(cString: made)
        guard let real = realpath(raw, nil) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        root = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        free(real)
        try add(spec)
    }

    deinit {
        TempTree.forceRemove(root)
    }

    func url(_ relative: String) -> URL {
        relative.isEmpty ? root : root.appendingPathComponent(relative)
    }

    func path(_ relative: String) -> String {
        url(relative).path
    }

    /// Path of `url` relative to the root, for readable assertions.
    func relative(_ url: URL) -> String {
        // Note: standardizedFileURL maps /private/var to /var, so compare both spellings.
        for full in [url.path, url.standardizedFileURL.path] {
            for base in [root.path + "/", root.standardizedFileURL.path + "/"] where full.hasPrefix(base) {
                return String(full.dropFirst(base.count))
            }
        }
        return url.path
    }

    func add(_ spec: [String: TreeNode]) throws {
        let fm = FileManager.default
        // Sort so parents are created before children and results are deterministic.
        for (relative, node) in spec.sorted(by: { $0.key < $1.key }) {
            let target = url(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch node {
            case .file(let contents):
                try Data(contents.utf8).write(to: target)
            case .bytes(let count):
                // Non-zero bytes so APFS cannot store the file sparsely.
                try Data(repeating: 0xA5, count: count).write(to: target)
            case .dir:
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            case .symlink(let destination):
                try fm.createSymbolicLink(atPath: target.path, withDestinationPath: destination)
            }
        }
    }

    func chmod(_ relative: String, _ mode: mode_t) {
        _ = Darwin.chmod(path(relative), mode)
    }

    func touch(_ relative: String, date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path(relative))
    }

    static func forceRemove(_ url: URL) {
        let fm = FileManager.default
        // Restore owner rwx everywhere first so 000 and 0555 fixtures can be removed.
        _ = Darwin.chmod(url.path, 0o755)
        if let walker = fm.enumerator(atPath: url.path) {
            while let relative = walker.nextObject() as? String {
                let full = url.appendingPathComponent(relative).path
                var info = stat()
                if lstat(full, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK {
                    _ = Darwin.chmod(full, (info.st_mode & S_IFMT) == S_IFDIR ? 0o755 : 0o644)
                }
            }
        }
        try? fm.removeItem(at: url)
    }
}

var isRunningAsRoot: Bool { getuid() == 0 }
