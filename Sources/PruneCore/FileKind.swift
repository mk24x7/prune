import Foundation

/// What `lstat` says a path is. Symlinks are never followed, so a symlink to a
/// directory reports `.symlink`, not `.directory`.
public enum FileKind: Equatable, Sendable {
    case missing, directory, regularFile, symlink, other

    public static func of(_ url: URL) -> FileKind {
        of(path: url.path)
    }

    public static func of(path: String) -> FileKind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFREG: return .regularFile
        case S_IFLNK: return .symlink
        default: return .other
        }
    }
}

extension Error {
    /// True for EACCES / EPERM style failures, however Foundation wraps them.
    var isPermissionError: Bool {
        let ns = self as NSError
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError {
            return true
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EACCES) || ns.code == Int(EPERM) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return underlying.isPermissionError
        }
        return false
    }

    /// True for ENOENT style failures, however Foundation wraps them.
    var isNoSuchFileError: Bool {
        let ns = self as NSError
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError {
            return true
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return underlying.isNoSuchFileError
        }
        return false
    }
}
