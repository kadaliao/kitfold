import Darwin
import Foundation

/// Thin, explicit wrapper around the file system. Every path is an absolute string.
/// Nothing here follows a symlink unless the name says so.
public enum FS {
    public enum Kind: Sendable, Hashable {
        case missing
        case file
        case directory
        case symlink(target: String)  // raw link text
    }

    public static func kind(_ path: String) -> Kind {
        var st = stat()
        guard lstat(path, &st) == 0 else { return .missing }
        switch st.st_mode & S_IFMT {
        case S_IFLNK:
            return .symlink(target: (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) ?? "")
        case S_IFDIR: return .directory
        default: return .file
        }
    }

    public static func exists(_ path: String) -> Bool { kind(path) != .missing }

    /// True if the path (following links) is a directory.
    public static func isDirectoryFollowing(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Resolve a path completely (all symlinks); nil if it doesn't resolve to an existing item.
    public static func realPath(_ path: String) -> String? {
        guard let r = Darwin.realpath(path, nil) else { return nil }
        defer { free(r) }
        return String(cString: r)
    }

    /// Absolute target of a symlink at `path` (one hop), resolved against the link's directory.
    public static func linkDestination(_ path: String) -> String? {
        guard case .symlink(let raw) = kind(path) else { return nil }
        return absolute(raw, relativeTo: (path as NSString).deletingLastPathComponent)
    }

    public static func absolute(_ p: String, relativeTo base: String) -> String {
        if p.hasPrefix("/") { return standardize(p) }
        return standardize((base as NSString).appendingPathComponent(p))
    }

    /// Purely lexical: collapses `//`, `.` and `..`. Unlike NSString.standardizingPath it never
    /// rewrites `/private/var` to `/var`, so it stays consistent with `realPath`.
    public static func standardize(_ p: String) -> String {
        guard !p.isEmpty else { return p }
        let absolute = p.hasPrefix("/")
        var parts: [Substring] = []
        for comp in p.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." {
                if let last = parts.last, last != ".." { parts.removeLast() } else if !absolute { parts.append(comp) }
                continue
            }
            parts.append(comp)
        }
        let joined = parts.joined(separator: "/")
        if absolute { return "/" + joined }
        return joined.isEmpty ? "." : joined
    }

    public static func expandTilde(_ p: String, home: String) -> String {
        if p == "~" { return home }
        if p.hasPrefix("~/") { return home + String(p.dropFirst(1)) }
        return p
    }

    public static func abbreviate(_ p: String, home: String) -> String {
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + String(p.dropFirst(home.count)) }
        // macOS spells some folders two ways (/var and /private/var, /tmp and /private/tmp).
        if home.hasPrefix("/private/") { return abbreviate(p, home: String(home.dropFirst("/private".count))) }
        return p
    }

    public static func children(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    }

    public static func read(_ path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Atomic write (temp file + rename), creating parent directories.
    /// `permissions` applies to new files; an existing file keeps its own mode (an atomic write
    /// would otherwise reset a 0600 file to the umask default).
    public static func write(_ text: String, to path: String, permissions newFileMode: Int? = nil) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // If the target is a symlink (e.g. a dotfile manager links CLAUDE.md), write through to
        // the real file so we don't replace the link with a plain file.
        var target = path
        if case .symlink = kind(path), let real = realPath(path) { target = real }
        let existingMode = (try? FileManager.default.attributesOfItem(atPath: target))?[.posixPermissions] as? Int
        try Data(text.utf8).write(to: URL(fileURLWithPath: target), options: .atomic)
        if let mode = existingMode ?? newFileMode {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: target)
        }
    }

    /// For copies of user files (backups, history): owner-only, inside an owner-only folder.
    public static func writePrivate(_ text: String, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try write(text, to: path, permissions: 0o600)
    }

    public static func createSymlink(at path: String, to target: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    /// Remove only a symlink (never what it points to).
    public static func removeSymlink(at path: String) throws {
        guard case .symlink = kind(path) else {
            throw KitfoldError.precondition(L("Refusing to remove \(path): not a symlink"))
        }
        guard unlink(path) == 0 else { throw KitfoldError.io(L("unlink failed for \(path): \(String(cString: strerror(errno)))")) }
    }

    /// Relative path from directory `from` to `to` (both absolute, standardized).
    public static func relativePath(from: String, to: String) -> String {
        let a = standardize(from).split(separator: "/").map(String.init)
        let b = standardize(to).split(separator: "/").map(String.init)
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        let ups = Array(repeating: "..", count: a.count - i)
        let rest = Array(b[i...])
        let parts = ups + rest
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    /// Is `path` equal to or inside `dir`? Compares standardized strings, plus resolved forms.
    public static func isInside(_ path: String, _ dir: String) -> Bool {
        let p = standardize(path), d = standardize(dir)
        if p == d || p.hasPrefix(d.hasSuffix("/") ? d : d + "/") { return true }
        if let rp = realPath(path), let rd = realPath(dir) {
            return rp == rd || rp.hasPrefix(rd + "/")
        }
        return false
    }

    /// Walk up from `start` to the nearest directory containing `.git` (or stop at `/`).
    public static func gitRoot(from start: String) -> String? {
        var cur = standardize(start)
        while true {
            if exists((cur as NSString).appendingPathComponent(".git")) { return cur }
            let parent = (cur as NSString).deletingLastPathComponent
            if parent == cur || parent.isEmpty { return nil }
            cur = parent
        }
    }
}

public enum KitfoldError: Error, CustomStringConvertible, LocalizedError {
    case precondition(String)
    case io(String)
    case invalid(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .precondition(let s): return L("Precondition failed: \(s)")
        case .io(let s): return L("I/O error: \(s)")
        case .invalid(let s): return L("Invalid: \(s)")
        case .notFound(let s): return L("Not found: \(s)")
        }
    }
    public var errorDescription: String? { description }
}
