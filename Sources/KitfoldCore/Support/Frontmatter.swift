import Foundation

/// A deliberately small YAML-frontmatter reader. SKILL.md / profile files only use
/// top-level scalars, block scalars (`|`, `>`), and simple lists. Nested maps are kept
/// as raw text so nothing is lost, but we never need to interpret them.
public struct Frontmatter: Sendable, Hashable {
    public enum Value: Sendable, Hashable {
        case string(String)
        case list([String])
        case raw(String)

        public var stringValue: String? {
            switch self {
            case .string(let s): return s
            case .list(let l): return l.joined(separator: ", ")
            case .raw(let r): return r
            }
        }
        public var listValue: [String] {
            switch self {
            case .list(let l): return l
            case .string(let s):
                return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .raw: return []
            }
        }
    }

    public var fields: [String: Value]
    public var keyOrder: [String]
    /// Text after the closing `---`.
    public var body: String
    /// Whether a frontmatter block was present at all.
    public var present: Bool
    public var parseError: String?

    public subscript(key: String) -> String? { fields[key]?.stringValue }
    public func list(_ key: String) -> [String] { fields[key]?.listValue ?? [] }

    public static func parse(_ text: String) -> Frontmatter {
        var lines = text.components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("\u{FEFF}") { lines[0] = String(first.dropFirst()) }
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return Frontmatter(fields: [:], keyOrder: [], body: text, present: false, parseError: nil)
        }
        var end: Int?
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            end = i
            break
        }
        guard let close = end else {
            return Frontmatter(
                fields: [:], keyOrder: [], body: text, present: true,
                parseError: "Frontmatter is not closed with ---")
        }
        let header = Array(lines[1..<close])
        let body = lines[(close + 1)...].joined(separator: "\n")
        var (fields, order, error) = parseHeader(header)
        if fields.isEmpty && error == nil && !header.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            error = "Frontmatter has no readable keys"
        }
        return Frontmatter(fields: fields, keyOrder: order, body: body, present: true, parseError: error)
    }

    private static func indent(of line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    private static func parseHeader(_ lines: [String]) -> ([String: Value], [String], String?) {
        var fields: [String: Value] = [:]
        var order: [String] = []
        var i = 0
        var error: String?
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || indent(of: line) > 0 {
                i += 1
                continue
            }
            guard let colon = findKeyColon(line) else {
                error = error ?? "Unreadable frontmatter line: \(trimmed.prefix(60))"
                i += 1
                continue
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            rest = stripComment(rest)
            // Gather indented continuation lines.
            var j = i + 1
            var block: [String] = []
            while j < lines.count {
                let l = lines[j]
                if l.trimmingCharacters(in: .whitespaces).isEmpty || indent(of: l) > 0
                    || l.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
                {
                    block.append(l)
                    j += 1
                } else {
                    break
                }
            }
            while let last = block.last, last.trimmingCharacters(in: .whitespaces).isEmpty { block.removeLast() }
            let value: Value
            if rest.hasPrefix("|") || rest.hasPrefix(">") {
                let folded = rest.hasPrefix(">")
                let minIndent = block.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(indent(of:)).min() ?? 0
                let content = block.map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : "" }
                value = .string(folded ? foldLines(content) : content.joined(separator: "\n"))
            } else if rest.isEmpty {
                let items = block.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !items.isEmpty && items.allSatisfy({ $0.hasPrefix("- ") || $0 == "-" }) {
                    value = .list(items.map { unquote(String($0.dropFirst(1)).trimmingCharacters(in: .whitespaces)) })
                } else if items.isEmpty {
                    value = .string("")
                } else {
                    value = .raw(block.joined(separator: "\n"))
                }
            } else if rest.hasPrefix("[") && rest.hasSuffix("]") {
                let inner = rest.dropFirst().dropLast()
                value = .list(
                    splitFlowList(String(inner)).map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                        .filter { !$0.isEmpty })
            } else {
                // Plain scalar, possibly continued on indented lines (YAML plain multi-line scalar).
                var s = unquote(rest)
                if !block.isEmpty && !(rest.hasPrefix("\"") || rest.hasPrefix("'")) {
                    s += " " + block.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                    s = s.trimmingCharacters(in: .whitespaces)
                } else if !block.isEmpty, rest.hasPrefix("\""), !rest.dropFirst().contains("\"") {
                    // Multi-line double-quoted string.
                    let joined = ([rest] + block.map { $0.trimmingCharacters(in: .whitespaces) }).joined(separator: " ")
                    s = unquote(joined)
                }
                value = .string(s)
            }
            if fields[key] == nil { order.append(key) }
            fields[key] = value
            i = j
        }
        return (fields, order, error)
    }

    private static func findKeyColon(_ line: String) -> String.Index? {
        var inQuote: Character?
        for idx in line.indices {
            let c = line[idx]
            if let q = inQuote {
                if c == q { inQuote = nil }
                continue
            }
            if c == "\"" || c == "'" { inQuote = c; continue }
            if c == ":" {
                let next = line.index(after: idx)
                if next == line.endIndex || line[next] == " " || line[next] == "\t" { return idx }
            }
        }
        return nil
    }

    private static func stripComment(_ s: String) -> String {
        guard !s.hasPrefix("\""), !s.hasPrefix("'") else { return s }
        if let r = s.range(of: " #") { return String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return s
    }

    private static func foldLines(_ lines: [String]) -> String {
        var out = ""
        for l in lines {
            if l.isEmpty { out += "\n" } else { out += (out.isEmpty || out.hasSuffix("\n") ? "" : " ") + l }
        }
        return out
    }

    private static func splitFlowList(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var quote: Character?
        for c in s {
            if let q = quote {
                cur.append(c)
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
                cur.append(c)
            } else if c == "," {
                parts.append(cur)
                cur = ""
            } else {
                cur.append(c)
            }
        }
        parts.append(cur)
        return parts
    }

    static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, let f = t.first, let l = t.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") {
            t = String(t.dropFirst().dropLast())
            if f == "\"" {
                // One pass, so an escaped backslash before `n` or `"` isn't decoded twice.
                var out = ""
                var escaping = false
                for c in t {
                    if escaping {
                        switch c {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        case "\"", "\\", "/": out.append(c)
                        default: out.append("\\"); out.append(c)
                        }
                        escaping = false
                    } else if c == "\\" {
                        escaping = true
                    } else {
                        out.append(c)
                    }
                }
                if escaping { out.append("\\") }
                t = out
            } else {
                t = t.replacingOccurrences(of: "''", with: "'")
            }
        }
        return t
    }

    /// Serialize simple fields back into a frontmatter block followed by body.
    public static func render(fields: [(String, Value)], body: String) -> String {
        var out = "---\n"
        for (k, v) in fields {
            switch v {
            case .string(let s):
                if s.contains("\n") {
                    out +=
                        "\(k): |\n" + s.split(separator: "\n", omittingEmptySubsequences: false).map { "  \($0)" }.joined(separator: "\n")
                        + "\n"
                } else {
                    out += "\(k): \(quoteIfNeeded(s))\n"
                }
            case .list(let l):
                if l.isEmpty { out += "\(k): []\n" } else { out += "\(k):\n" + l.map { "  - \(quoteIfNeeded($0))\n" }.joined() }
            case .raw(let r):
                out += "\(k):\n\(r)\n"
            }
        }
        out += "---\n"
        let trimmedBody = body.hasPrefix("\n") ? String(body.dropFirst()) : body
        return out + "\n" + trimmedBody
    }

    static func quoteIfNeeded(_ s: String) -> String {
        let special: Set<Character> = [":", "#", "[", "]", "{", "}", ",", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`"]
        if s.isEmpty || s.contains(where: { special.contains($0) }) || s.first == " " || s.last == " " || s.first == "-" {
            return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return s
    }
}
