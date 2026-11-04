import Foundation

/// Line-based diff (LCS) used for change previews and profile version comparison.
public enum LineDiff {
    public enum Op: Sendable, Hashable {
        case same(String)
        case added(String)
        case removed(String)
    }

    public struct Hunk: Sendable, Hashable, Identifiable {
        public var id: Int { oldStart * 100_000 + newStart }
        public var oldStart: Int
        public var newStart: Int
        public var lines: [Op]
    }

    public static func diff(_ a: String, _ b: String) -> [Op] {
        diff(lines: split(a), split(b))
    }

    static func split(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var parts = s.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    public static func diff(lines a: [String], _ b: [String]) -> [Op] {
        // Trim common prefix/suffix first; keeps the DP table small for typical edits.
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
            a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
        {
            suffix += 1
        }
        let x = Array(a[prefix..<(a.count - suffix)])
        let y = Array(b[prefix..<(b.count - suffix)])
        var ops: [Op] = a[0..<prefix].map { Op.same($0) }

        let n = x.count, m = y.count
        if n * m > 4_000_000 {
            // Too large for a table; fall back to remove-all/add-all for the middle.
            ops.append(contentsOf: x.map { Op.removed($0) })
            ops.append(contentsOf: y.map { Op.added($0) })
        } else if n > 0 || m > 0 {
            var table = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
            if n > 0 && m > 0 {
                for i in stride(from: n - 1, through: 0, by: -1) {
                    for j in stride(from: m - 1, through: 0, by: -1) {
                        table[i][j] = x[i] == y[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                    }
                }
            }
            var i = 0, j = 0
            while i < n || j < m {
                if i < n, j < m, x[i] == y[j] {
                    ops.append(.same(x[i])); i += 1; j += 1
                } else if j < m, i == n || table[i][j + 1] >= table[i + 1][j] {
                    ops.append(.added(y[j])); j += 1
                } else {
                    ops.append(.removed(x[i])); i += 1
                }
            }
        }
        ops.append(contentsOf: a[(a.count - suffix)...].map { Op.same($0) })
        return ops
    }

    /// Group a full diff into hunks with `context` unchanged lines around each change.
    public static func hunks(_ ops: [Op], context: Int = 3) -> [Hunk] {
        var result: [Hunk] = []
        var oldLine = 1, newLine = 1
        var current: Hunk?
        var trailingSame = 0
        var recentSame: [(Op, Int, Int)] = []
        for op in ops {
            switch op {
            case .same:
                if var h = current {
                    if trailingSame < context {
                        h.lines.append(op)
                        current = h
                        trailingSame += 1
                    } else {
                        result.append(h)
                        current = nil
                    }
                }
                recentSame.append((op, oldLine, newLine))
                if recentSame.count > context { recentSame.removeFirst() }
                oldLine += 1; newLine += 1
            case .added, .removed:
                if current == nil {
                    let start = recentSame.first
                    current = Hunk(
                        oldStart: start?.1 ?? oldLine, newStart: start?.2 ?? newLine,
                        lines: recentSame.map { $0.0 })
                }
                current?.lines.append(op)
                trailingSame = 0
                recentSame.removeAll()
                if case .added = op { newLine += 1 } else { oldLine += 1 }
            }
        }
        if let h = current { result.append(h) }
        return result
    }

    public static func stats(_ ops: [Op]) -> (added: Int, removed: Int) {
        var a = 0, r = 0
        for op in ops {
            if case .added = op { a += 1 }
            if case .removed = op { r += 1 }
        }
        return (a, r)
    }

    public static func unified(_ old: String, _ new: String, oldName: String = "a", newName: String = "b") -> String {
        let ops = diff(old, new)
        var out = "--- \(oldName)\n+++ \(newName)\n"
        for h in hunks(ops) {
            out += "@@ -\(h.oldStart) +\(h.newStart) @@\n"
            for l in h.lines {
                switch l {
                case .same(let s): out += " \(s)\n"
                case .added(let s): out += "+\(s)\n"
                case .removed(let s): out += "-\(s)\n"
                }
            }
        }
        return out
    }
}
