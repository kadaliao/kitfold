import CryptoKit
import Foundation

public enum Hashing {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ text: String) -> String { sha256(Data(text.utf8)) }

    /// Short content fingerprint used in managed-block markers and UI.
    public static func short(_ text: String) -> String { String(sha256(text).prefix(12)) }

    static let ignoredNames: Set<String> = [".DS_Store", ".git", "node_modules", "__pycache__", ".venv"]

    /// Deterministic hash of a directory tree: relative paths + file bytes, sorted.
    /// Symlinks inside the tree are hashed by their link text, not followed.
    public static func directoryHash(_ url: URL, maxFiles: Int = 2000) -> String? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else {
            return nil
        }
        var entries: [(String, URL, Bool)] = []
        let base = url.standardizedFileURL.path
        while let item = walker.nextObject() as? URL {
            if ignoredNames.contains(item.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let rel = String(item.standardizedFileURL.path.dropFirst(base.count))
            if vals?.isSymbolicLink == true {
                entries.append((rel, item, true))
            } else if vals?.isRegularFile == true {
                entries.append((rel, item, false))
            }
            if entries.count > maxFiles { break }
        }
        entries.sort { $0.0 < $1.0 }
        var hasher = SHA256()
        for (rel, file, isLink) in entries {
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            if isLink {
                let dest = (try? fm.destinationOfSymbolicLink(atPath: file.path)) ?? ""
                hasher.update(data: Data(("link:" + dest).utf8))
            } else if let d = try? Data(contentsOf: file) {
                hasher.update(data: d)
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
