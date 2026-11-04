import Foundation

/// Regions of an instruction file (CLAUDE.md, AGENTS.md, GEMINI.md…) that Kitfold owns —
/// one block per Profile. Everything outside the markers belongs to the user and is never touched.
///
///     <!-- kitfold:begin profile=backend hash=3f2a9c01b7de -->
///     …profile text…
///     <!-- kitfold:end profile=backend -->
///
/// The hash covers the body as Kitfold last wrote it, so edits made outside Kitfold are detectable
/// from the file alone, per profile (no database needed).
public enum ManagedBlock {
    public static let beginPrefix = "<!-- kitfold:begin"
    public static let endPrefix = "<!-- kitfold:end"

    public struct Found: Sendable, Hashable, Identifiable {
        public var id: String { profile }
        public var profile: String
        public var recordedHash: String
        public var body: String
        /// Line range (inclusive) of the whole block in the file.
        public var startLine: Int
        public var endLine: Int
        public var isModifiedOutsideKitfold: Bool { Hashing.short(body) != recordedHash }
    }

    static func attribute(_ name: String, in line: String) -> String? {
        for token in line.split(separator: " ") where token.hasPrefix(name + "=") {
            return String(token.dropFirst(name.count + 1))
        }
        return nil
    }

    public static func findAll(in text: String) -> [Found] {
        let lines = text.components(separatedBy: "\n")
        var out: [Found] = []
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(beginPrefix) else { i += 1; continue }
            let profile = attribute("profile", in: t) ?? ""
            guard
                let end = lines[(i + 1)...].firstIndex(where: {
                    let s = $0.trimmingCharacters(in: .whitespaces)
                    return s.hasPrefix(endPrefix) || s.hasPrefix(beginPrefix)
                }), lines[end].trimmingCharacters(in: .whitespaces).hasPrefix(endPrefix)
            else {
                i += 1
                continue
            }
            let body = lines[(i + 1)..<end].joined(separator: "\n")
            out.append(
                Found(
                    profile: profile, recordedHash: attribute("hash", in: t) ?? "",
                    body: normalize(body), startLine: i, endLine: end))
            i = end + 1
        }
        return out
    }

    static func normalize(_ s: String) -> String { s.trimmingCharacters(in: .newlines) }

    public static func render(profile: String, body: String) -> String {
        let b = normalize(body)
        return ["\(beginPrefix) profile=\(profile) hash=\(Hashing.short(b)) -->", b, "\(endPrefix) profile=\(profile) -->"]
            .joined(separator: "\n")
    }

    /// Returns `text` with Kitfold's blocks replaced by `blocks` (in order). New blocks go where the
    /// first old block was, or at the top of the file. An empty list removes all Kitfold blocks.
    public static func apply(_ blocks: [(profile: String, body: String)], to text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let found = findAll(in: text)
        var insertAt = 0
        if let first = found.first {
            insertAt = first.startLine
            for f in found.reversed() {
                var end = f.endLine
                // Swallow one blank separator line after each block.
                if end + 1 < lines.count, lines[end + 1].trimmingCharacters(in: .whitespaces).isEmpty { end += 1 }
                lines.removeSubrange(f.startLine...end)
            }
        }
        if !blocks.isEmpty {
            var chunk: [String] = []
            for b in blocks {
                chunk += render(profile: b.profile, body: b.body).components(separatedBy: "\n")
                chunk.append("")
            }
            let restIsEmpty = lines[insertAt...].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            if restIsEmpty { lines.removeSubrange(insertAt...) }
            if insertAt > 0, !(lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty) { chunk.insert("", at: 0) }
            lines.insert(contentsOf: chunk, at: insertAt)
        }
        var result = lines.joined(separator: "\n")
        if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result = "" }
        return result
    }

    /// The user's own content (file minus Kitfold's blocks).
    public static func userContent(of text: String) -> String { apply([], to: text) }

    /// Managed blocks written by other tools (e.g. `<!-- magpie:begin … -->`). Kitfold leaves them alone.
    public static func foreignBlocks(in text: String) -> [String] {
        var tools: [String] = []
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("SKILLS_TABLE_START"), !tools.contains("openskills") { tools.append("openskills") }
            guard t.hasPrefix("<!--"), let r = t.range(of: ":begin") else { continue }
            let name = t[t.index(t.startIndex, offsetBy: 4)..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name != "kitfold", !name.contains(" "), !tools.contains(name) { tools.append(name) }
        }
        return tools
    }
}
