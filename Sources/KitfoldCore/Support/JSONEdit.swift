import Foundation

/// Reads JSON (with comments and trailing commas) while remembering where every value sits, so
/// Kitfold can change one key of an agent's settings file and leave every other byte as it was.
///
/// Only the edits Kitfold needs exist: set a key, remove a key, add or remove an array element.
/// New entries copy the indentation of their neighbours.
enum JSONEdit {
    enum Failure: Error, Equatable {
        case syntax(offset: Int)
        /// A key on the way to the edit holds something other than an object (or array).
        case wrongType(path: [String])
    }

    /// A parsed value and its byte range in the document.
    struct Node {
        enum Kind: Equatable { case object, array, string, number, bool, null }
        var kind: Kind
        var start: Int
        var end: Int
        var members: [Member] = []
        var elements: [Element] = []
        /// Decoded text for strings; raw text for numbers, booleans and null.
        var text = ""

        func member(_ key: String) -> Member? { members.last { $0.key == key } }
        var stringValue: String? { kind == .string ? text : nil }
        var boolValue: Bool? { kind == .bool ? text == "true" : nil }
    }

    struct Member {
        var key: String
        var keyStart: Int
        var value: Node
        /// Offset of the comma that follows the value, if any.
        var comma: Int?
    }

    struct Element {
        var value: Node
        var comma: Int?
    }

    // MARK: reading

    static func parse(_ text: String) throws -> Node {
        var p = Parser(bytes: Array(text.utf8))
        p.skipTrivia()
        let root = try p.value(depth: 0)
        p.skipTrivia()
        guard p.i == p.bytes.count else { throw Failure.syntax(offset: p.i) }
        return root
    }

    /// The object at `path` below the root (nil if a key is missing or isn't an object).
    static func object(at path: [String], in root: Node) -> Node? {
        var node = root
        for key in path {
            guard node.kind == .object, let m = node.member(key) else { return nil }
            node = m.value
        }
        return node
    }

    // MARK: editing

    /// Set `path` to `literal` (raw JSON text), creating missing objects on the way.
    static func set(_ text: String, path: [String], literal: String) throws -> String {
        precondition(!path.isEmpty)
        let doc = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}\n" : text
        let bytes = Array(doc.utf8)
        var node = try parse(doc)
        guard node.kind == .object else { throw Failure.wrongType(path: []) }
        let unit = indentUnit(bytes)
        for (depth, key) in path.enumerated() {
            let isLeaf = depth == path.count - 1
            if let m = node.member(key) {
                if isLeaf {
                    return splice(bytes, [(m.value.start..<m.value.end, literal)])
                }
                guard m.value.kind == .object else { throw Failure.wrongType(path: Array(path[...depth])) }
                node = m.value
                continue
            }
            // Missing: insert the rest of the path as nested objects.
            let inline = !contains(bytes, newlineIn: node.start..<node.end) && !node.members.isEmpty
            let indent = childIndent(bytes, container: node, unit: unit)
            let value = render(Array(path[(depth + 1)...]), literal: literal, indent: indent, unit: unit, inline: inline)
            return insert(bytes, into: node, item: quote(key) + ": " + value, unit: unit)
        }
        return doc
    }

    /// Remove `path`. With `prune`, objects left empty by the removal are removed too (never the root).
    static func remove(_ text: String, path: [String], prune: Bool = true) throws -> String {
        let root = try parse(text)
        var chain = [root]
        for key in path.dropLast() {
            guard let last = chain.last, last.kind == .object, let m = last.member(key), m.value.kind == .object else { return text }
            chain.append(m.value)
        }
        guard let parent = chain.last, let index = parent.members.lastIndex(where: { $0.key == path.last }) else { return text }
        if prune, parent.members.count == 1, path.count > 1 {
            return try remove(text, path: Array(path.dropLast()), prune: true)
        }
        let bytes = Array(text.utf8)
        let items = parent.members.map { Item(start: $0.keyStart, end: $0.value.end, comma: $0.comma) }
        return removeItem(bytes, container: parent, items: items, at: index)
    }

    /// Append `literal` to the array at `path`, creating it (and missing objects) if needed.
    static func append(_ text: String, path: [String], literal: String) throws -> String {
        let doc = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}\n" : text
        let root = try parse(doc)
        guard let parent = object(at: Array(path.dropLast()), in: root), let m = parent.member(path.last!) else {
            return try set(doc, path: path, literal: "[" + literal + "]")
        }
        guard m.value.kind == .array else { throw Failure.wrongType(path: path) }
        let bytes = Array(doc.utf8)
        return insert(bytes, into: m.value, item: literal, unit: indentUnit(bytes))
    }

    /// Remove every element of the array at `path` for which `matches` is true.
    static func removeElements(_ text: String, path: [String], where matches: (Node) -> Bool) throws -> String {
        var text = text
        while true {
            let root = try parse(text)
            guard let parent = object(at: Array(path.dropLast()), in: root), let m = parent.member(path.last!),
                m.value.kind == .array, let index = m.value.elements.lastIndex(where: { matches($0.value) })
            else { return text }
            let items = m.value.elements.map { Item(start: $0.value.start, end: $0.value.end, comma: $0.comma) }
            text = removeItem(Array(text.utf8), container: m.value, items: items, at: index)
        }
    }

    /// JSON string literal.
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    // MARK: internals

    struct Item {
        var start: Int
        var end: Int
        var comma: Int?
    }

    static let newline = UInt8(ascii: "\n")
    static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0D }

    static func splice(_ bytes: [UInt8], _ edits: [(Range<Int>, String)]) -> String {
        var out = bytes
        // Back to front; edits at the same offset keep the order they were listed in.
        let ordered = edits.enumerated().sorted { ($0.element.0.lowerBound, $0.offset) > ($1.element.0.lowerBound, $1.offset) }
        for (_, (range, text)) in ordered {
            out.replaceSubrange(range, with: Array(text.utf8))
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func contains(_ bytes: [UInt8], newlineIn range: Range<Int>) -> Bool {
        bytes[range].contains(newline)
    }

    static func lineStart(_ bytes: [UInt8], _ i: Int) -> Int {
        var j = i
        while j > 0, bytes[j - 1] != newline { j -= 1 }
        return j
    }

    /// Leading whitespace of the line containing `i`.
    static func lineIndent(_ bytes: [UInt8], _ i: Int) -> String {
        var j = lineStart(bytes, i)
        var out: [UInt8] = []
        while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09 {
            out.append(bytes[j])
            j += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func startsLine(_ bytes: [UInt8], _ i: Int) -> Bool {
        bytes[lineStart(bytes, i)..<i].allSatisfy { $0 == 0x20 || $0 == 0x09 }
    }

    /// The document's indentation step: the first indented line's leading whitespace, else two spaces.
    static func indentUnit(_ bytes: [UInt8]) -> String {
        var i = 0
        while i < bytes.count {
            if bytes[i] == newline {
                var j = i + 1
                var ws: [UInt8] = []
                while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09 {
                    ws.append(bytes[j])
                    j += 1
                }
                if !ws.isEmpty, j < bytes.count, bytes[j] != newline { return String(decoding: ws, as: UTF8.self) }
            }
            i += 1
        }
        return "  "
    }

    static func childIndent(_ bytes: [UInt8], container: Node, unit: String) -> String {
        let firstStart = container.kind == .object ? container.members.first?.keyStart : container.elements.first?.value.start
        if let s = firstStart, startsLine(bytes, s) { return lineIndent(bytes, s) }
        return lineIndent(bytes, container.start) + unit
    }

    /// Text for the value of a newly inserted key: nested objects down to the literal.
    static func render(_ rest: [String], literal: String, indent: String, unit: String, inline: Bool) -> String {
        guard let key = rest.first else { return literal }
        let inner = render(Array(rest.dropFirst()), literal: literal, indent: indent + unit, unit: unit, inline: inline)
        if inline { return "{" + quote(key) + ": " + inner + "}" }
        return "{\n" + indent + unit + quote(key) + ": " + inner + "\n" + indent + "}"
    }

    /// Insert `item` as the last member/element of `container`.
    static func insert(_ bytes: [UInt8], into container: Node, item: String, unit: String) -> String {
        let open = container.start, close = container.end - 1
        let items: [Item] =
            container.kind == .object
            ? container.members.map { Item(start: $0.keyStart, end: $0.value.end, comma: $0.comma) }
            : container.elements.map { Item(start: $0.value.start, end: $0.value.end, comma: $0.comma) }
        let outer = lineIndent(bytes, open)
        guard let last = items.last else {
            let inner = bytes[(open + 1)..<close]
            if inner.allSatisfy({ isSpace($0) || $0 == newline }) {
                if container.kind == .array { return splice(bytes, [((open + 1)..<close, item)]) }
                return splice(bytes, [((open + 1)..<close, "\n" + outer + unit + item + "\n" + outer)])
            }
            // Only comments inside: put the item first.
            return splice(bytes, [((open + 1)..<(open + 1), "\n" + outer + unit + item)])
        }
        if !contains(bytes, newlineIn: open..<close) {
            if let c = last.comma { return splice(bytes, [((c + 1)..<(c + 1), " " + item + ",")]) }
            return splice(bytes, [(last.end..<last.end, ", " + item)])
        }
        let indent = startsLine(bytes, last.start) ? lineIndent(bytes, last.start) : outer + unit
        let after = last.comma.map { $0 + 1 } ?? last.end
        // Insert at the end of the last item's line, so a trailing comment stays with its item.
        var eol = after
        while eol < bytes.count, bytes[eol] != newline { eol += 1 }
        let lineRest = (after < eol) ? Array(bytes[after..<eol]) : []
        let restIsTrivia = eol <= close && Parser.isOnlyTrivia(lineRest)
        if let c = last.comma {
            let at = restIsTrivia ? eol : c + 1
            return splice(bytes, [(at..<at, "\n" + indent + item + ",")])
        }
        if restIsTrivia {
            return splice(bytes, [(last.end..<last.end, ","), (eol..<eol, "\n" + indent + item)])
        }
        return splice(bytes, [(last.end..<last.end, ",\n" + indent + item)])
    }

    static func removeItem(_ bytes: [UInt8], container: Node, items: [Item], at index: Int) -> String {
        let item = items[index]
        let open = container.start, close = container.end - 1
        if items.count == 1 {
            let end = item.comma.map { $0 + 1 } ?? item.end
            let rest = Array(bytes[(open + 1)..<item.start]) + Array(bytes[end..<close])
            if rest.allSatisfy({ isSpace($0) || $0 == newline }) { return splice(bytes, [((open + 1)..<close, "")]) }
            return splice(bytes, [(item.start..<end, "")])
        }
        if let c = item.comma {
            var s = item.start, e = c + 1
            var eol = e
            while eol < bytes.count, isSpace(bytes[eol]) { eol += 1 }
            if startsLine(bytes, s), eol < bytes.count, bytes[eol] == newline {
                s = lineStart(bytes, s)
                e = eol + 1
            } else {
                e = eol
            }
            return splice(bytes, [(s..<e, "")])
        }
        // Last item without a trailing comma: drop the previous item's comma as well.
        guard let prevComma = items[index - 1].comma else { return splice(bytes, [(item.start..<item.end, "")]) }
        if startsLine(bytes, item.start) {
            let s = lineStart(bytes, item.start) - 1  // the newline before the item's line
            if s > prevComma { return splice(bytes, [(prevComma..<(prevComma + 1), ""), (s..<item.end, "")]) }
        }
        return splice(bytes, [(prevComma..<item.end, "")])
    }

    struct Parser {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }
        }

        static func isOnlyTrivia(_ b: [UInt8]) -> Bool {
            var p = Parser(bytes: b)
            p.skipTrivia()
            return p.i == b.count
        }

        mutating func skipTrivia() {
            while i < bytes.count {
                let c = bytes[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    i += 1
                } else if c == UInt8(ascii: "/"), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "/") {
                    while i < bytes.count, bytes[i] != 0x0A { i += 1 }
                } else if c == UInt8(ascii: "/"), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "*") {
                    i += 2
                    while i + 1 < bytes.count, !(bytes[i] == UInt8(ascii: "*") && bytes[i + 1] == UInt8(ascii: "/")) { i += 1 }
                    i = min(i + 2, bytes.count)
                } else {
                    return
                }
            }
        }

        mutating func value(depth: Int) throws -> Node {
            guard depth < 200, i < bytes.count else { throw Failure.syntax(offset: i) }
            switch bytes[i] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""):
                let start = i
                let s = try string()
                return Node(kind: .string, start: start, end: i, text: s)
            case UInt8(ascii: "t"): return try literal("true", .bool)
            case UInt8(ascii: "f"): return try literal("false", .bool)
            case UInt8(ascii: "n"): return try literal("null", .null)
            default: return try number()
            }
        }

        mutating func literal(_ word: String, _ kind: Node.Kind) throws -> Node {
            let w = Array(word.utf8)
            guard bytes.count - i >= w.count, Array(bytes[i..<(i + w.count)]) == w else { throw Failure.syntax(offset: i) }
            let start = i
            i += w.count
            return Node(kind: kind, start: start, end: i, text: word)
        }

        mutating func number() throws -> Node {
            let start = i
            while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
            guard i > start else { throw Failure.syntax(offset: i) }
            return Node(kind: .number, start: start, end: i, text: String(decoding: bytes[start..<i], as: UTF8.self))
        }

        mutating func object(depth: Int) throws -> Node {
            var node = Node(kind: .object, start: i, end: i)
            i += 1
            skipTrivia()
            while i < bytes.count, bytes[i] != UInt8(ascii: "}") {
                guard bytes[i] == UInt8(ascii: "\"") else { throw Failure.syntax(offset: i) }
                let keyStart = i
                let key = try string()
                skipTrivia()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw Failure.syntax(offset: i) }
                i += 1
                skipTrivia()
                let v = try value(depth: depth + 1)
                skipTrivia()
                var comma: Int?
                if i < bytes.count, bytes[i] == UInt8(ascii: ",") {
                    comma = i
                    i += 1
                    skipTrivia()
                } else if i < bytes.count, bytes[i] != UInt8(ascii: "}") {
                    throw Failure.syntax(offset: i)
                }
                node.members.append(Member(key: key, keyStart: keyStart, value: v, comma: comma))
            }
            guard i < bytes.count else { throw Failure.syntax(offset: i) }
            i += 1
            node.end = i
            return node
        }

        mutating func array(depth: Int) throws -> Node {
            var node = Node(kind: .array, start: i, end: i)
            i += 1
            skipTrivia()
            while i < bytes.count, bytes[i] != UInt8(ascii: "]") {
                let v = try value(depth: depth + 1)
                skipTrivia()
                var comma: Int?
                if i < bytes.count, bytes[i] == UInt8(ascii: ",") {
                    comma = i
                    i += 1
                    skipTrivia()
                } else if i < bytes.count, bytes[i] != UInt8(ascii: "]") {
                    throw Failure.syntax(offset: i)
                }
                node.elements.append(Element(value: v, comma: comma))
            }
            guard i < bytes.count else { throw Failure.syntax(offset: i) }
            i += 1
            node.end = i
            return node
        }

        mutating func string() throws -> String {
            let start = i
            i += 1
            var raw: [UInt8] = []
            var escaped = false
            while i < bytes.count {
                let c = bytes[i]
                if c == UInt8(ascii: "\\") {
                    escaped = true
                    raw.append(c)
                    if i + 1 < bytes.count { raw.append(bytes[i + 1]) }
                    i += 2
                    continue
                }
                if c == UInt8(ascii: "\"") {
                    i += 1
                    if !escaped { return String(decoding: raw, as: UTF8.self) }
                    let literal = Data(bytes[start..<i])
                    guard let s = try? JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed) as? String else {
                        throw Failure.syntax(offset: start)
                    }
                    return s
                }
                raw.append(c)
                i += 1
            }
            throw Failure.syntax(offset: start)
        }
    }
}
