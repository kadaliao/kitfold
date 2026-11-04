import Foundation

/// Where Kitfold writes an agent's own "hide this skill" setting for one scope.
public struct NativeTarget: Sendable, Hashable {
    public var agent: AgentID
    public var scope: Scope
    public var mechanism: SkillDisableMechanism
    /// Absolute path of the settings file Kitfold edits.
    public var file: String
    /// An explicit "on" entry can beat a broader rule (Claude `"on"`, OpenCode `"allow"`).
    public var canForceOn: Bool
}

/// One entry Kitfold wants in a settings file.
public struct NativeEntry: Hashable, Sendable, Comparable {
    /// See `NativeSettings.claudeKey` and friends.
    public var key: String
    public var value: String
    /// The skill it's about (for summaries and the ledger).
    public var skill: String
    public var hides: Bool { ["off", "deny", "false", "disabled"].contains(value) }
    public static func < (a: NativeEntry, b: NativeEntry) -> Bool { (a.key, a.value) < (b.key, b.value) }
}

/// Reading targets and writing entries for each agent's native skill switch. Edits change only
/// the entry involved; every other byte of the file is kept.
public enum NativeSettings {
    // MARK: files

    /// Files an agent reads for `scope`, lowest precedence first.
    public static func files(_ adapter: AgentAdapter, _ scope: Scope, _ env: KitfoldEnvironment) -> [String] {
        let dir = adapter.configDir(env)
        switch adapter.descriptor.skillDisable {
        case .none: return []
        case .claudeSettings:
            var files = [dir + "/settings.json"]
            if let p = scope.projectPath { files += [p + "/.claude/settings.json", p + "/.claude/settings.local.json"] }
            return files
        case .codexConfig:
            // Codex honors [[skills.config]] only in $CODEX_HOME/config.toml.
            return [dir + "/config.toml"]
        case .openCodePermission:
            var files = [dir + "/opencode.json", dir + "/opencode.jsonc"]
            if let p = scope.projectPath {
                files += [p + "/opencode.json", p + "/opencode.jsonc", p + "/.opencode/opencode.json", p + "/.opencode/opencode.jsonc"]
            }
            return files
        case .geminiSettings:
            var files = [dir + "/settings.json"]
            if let p = scope.projectPath { files.append(p + "/.gemini/settings.json") }
            return files
        }
    }

    /// The file Kitfold edits for (agent, scope), or nil when the agent can't hide a skill there.
    public static func target(_ adapter: AgentAdapter, _ scope: Scope, _ env: KitfoldEnvironment) -> NativeTarget? {
        let dir = adapter.configDir(env)
        let m = adapter.descriptor.skillDisable
        func make(_ file: String, forceOn: Bool) -> NativeTarget {
            NativeTarget(agent: adapter.id, scope: scope, mechanism: m, file: file, canForceOn: forceOn)
        }
        switch (m, scope) {
        case (.none, _): return nil
        case (.claudeSettings, .global): return make(dir + "/settings.json", forceOn: false)
        // Personal and git-ignored by Claude Code; beats the shared project file and the user file.
        case (.claudeSettings, .project(let p)): return make(p + "/.claude/settings.local.json", forceOn: true)
        case (.codexConfig, .global): return make(dir + "/config.toml", forceOn: false)
        case (.codexConfig, .project): return nil
        case (.openCodePermission, _):
            // The last file OpenCode reads wins; Kitfold's own project file sits next to its skills.
            let candidates = files(adapter, scope, env).filter { scope.isGlobal || !FS.isInside($0, dir) }
            let fallback = scope.projectPath.map { $0 + "/.opencode/opencode.json" } ?? dir + "/opencode.json"
            return make(candidates.last(where: FS.exists) ?? fallback, forceOn: true)
        case (.geminiSettings, .global): return make(dir + "/settings.json", forceOn: false)
        case (.geminiSettings, .project(let p)): return make(p + "/.gemini/settings.json", forceOn: false)
        }
    }

    public static func ledgerKey(file: String, key: String) -> String { file + "#" + key }

    // MARK: entry keys

    static func claudeKey(_ name: String) -> String { "skillOverrides/" + name }
    static func openCodeKey(_ pattern: String) -> String { "permission.skill/" + pattern }
    static func geminiKey(_ name: String) -> String { "skills.disabled/" + name.lowercased() }
    static func codexKey(path: String) -> String { "skills.config/path:" + path }
    static func codexKey(name: String) -> String { "skills.config/name:" + name }

    /// The entry that hides `name` (Codex: the SKILL.md at `skillFile`).
    static func hideEntry(_ m: SkillDisableMechanism, name: String, skillFile: String) -> NativeEntry? {
        switch m {
        case .none: return nil
        case .claudeSettings: return NativeEntry(key: claudeKey(name), value: "off", skill: name)
        case .codexConfig: return NativeEntry(key: codexKey(path: skillFile), value: "false", skill: name)
        case .openCodePermission: return NativeEntry(key: openCodeKey(name), value: "deny", skill: name)
        case .geminiSettings: return NativeEntry(key: geminiKey(name), value: "disabled", skill: name)
        }
    }

    /// An explicit "load it" entry that beats a broader or lower-precedence rule.
    static func showEntry(_ m: SkillDisableMechanism, name: String) -> NativeEntry? {
        switch m {
        case .claudeSettings: return NativeEntry(key: claudeKey(name), value: "on", skill: name)
        case .openCodePermission: return NativeEntry(key: openCodeKey(name), value: "allow", skill: name)
        default: return nil
        }
    }

    // MARK: editing

    /// Set or replace one entry.
    static func set(_ entry: NativeEntry, in text: String?, _ m: SkillDisableMechanism) throws -> String {
        let text = text ?? ""
        switch m {
        case .none, .codexConfig: return text
        case .claudeSettings:
            return try JSONEdit.set(text, path: ["skillOverrides", name(entry.key)], literal: JSONEdit.quote(entry.value))
        case .openCodePermission:
            return try JSONEdit.set(text, path: ["permission", "skill", name(entry.key)], literal: JSONEdit.quote(entry.value))
        case .geminiSettings:
            return try JSONEdit.append(text, path: ["skills", "disabled"], literal: JSONEdit.quote(entry.skill))
        }
    }

    /// Remove one entry (and objects it leaves empty).
    static func remove(key: String, from text: String, _ m: SkillDisableMechanism, env: KitfoldEnvironment) throws -> String {
        switch m {
        case .none: return text
        case .codexConfig: return CodexConfig.removeEntries(matching: key, from: text, env: env)
        case .claudeSettings: return try JSONEdit.remove(text, path: ["skillOverrides", name(key)])
        case .openCodePermission: return try JSONEdit.remove(text, path: ["permission", "skill", name(key)])
        case .geminiSettings:
            let lower = name(key)
            var out = try JSONEdit.removeElements(text, path: ["skills", "disabled"]) { $0.stringValue?.lowercased() == lower }
            // Drop a list (and a `skills` object) the removal emptied.
            let root = try JSONEdit.parse(out)
            if let skills = JSONEdit.object(at: ["skills"], in: root), let list = skills.member("disabled")?.value,
                list.kind == .array, list.elements.isEmpty
            {
                out = try JSONEdit.remove(out, path: ["skills", "disabled"])
            }
            return out
        }
    }

    static func name(_ key: String) -> String {
        guard let slash = key.firstIndex(of: "/") else { return key }
        return String(key[key.index(after: slash)...])
    }

    /// True when a settings file holds nothing but an empty object (safe to delete if Kitfold created it).
    static func isEmptyDocument(_ text: String, _ m: SkillDisableMechanism) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        return m == .codexConfig ? t.isEmpty : t == "{}"
    }

    // MARK: describing (never shows anything but the entries involved)

    /// One line for the review sheet, e.g. `+ skillOverrides › "pdf": "off"`.
    public static func describe(_ key: String, value: String, added: Bool, env: KitfoldEnvironment) -> String {
        let sign = added ? "+" : "−"
        let n = name(key)
        if key.hasPrefix("skillOverrides/") { return "\(sign) skillOverrides › \(JSONEdit.quote(n)): \(JSONEdit.quote(value))" }
        if key.hasPrefix("permission.skill/") { return "\(sign) permission.skill › \(JSONEdit.quote(n)): \(JSONEdit.quote(value))" }
        if key.hasPrefix("skills.disabled/") { return "\(sign) skills.disabled › \(JSONEdit.quote(n))" }
        if key.hasPrefix("skills.config/path:") {
            return
                "\(sign) [[skills.config]] path = \"\(env.abbreviate(String(key.dropFirst("skills.config/path:".count))))\", enabled = \(value)"
        }
        if key.hasPrefix("skills.config/name:") {
            return "\(sign) [[skills.config]] name = \"\(key.dropFirst("skills.config/name:".count))\", enabled = \(value)"
        }
        return "\(sign) \(key) = \(value)"
    }

    /// Semantic difference between two versions of a settings file: only skill entries, nothing else.
    public static func semanticDiff(
        _ adapter: AgentAdapter, file: String, before: String?, after: String?, env: KitfoldEnvironment
    )
        -> [String]
    {
        func entries(_ text: String?) -> [String: String] {
            var p = NativePolicy()
            guard let text, (try? p.read(text, file: file, mechanism: adapter.descriptor.skillDisable, env: env)) != nil else { return [:] }
            var out: [String: String] = [:]
            for r in p.rules { out[r.key] = r.value }
            return out
        }
        let a = entries(before), b = entries(after)
        var lines: [String] = []
        for k in Set(a.keys).union(b.keys).sorted() where a[k] != b[k] {
            if let old = a[k] { lines.append(describe(k, value: old, added: false, env: env)) }
            if let new = b[k] { lines.append(describe(k, value: new, added: true, env: env)) }
        }
        return lines
    }
}

/// Codex `config.toml`: reads `[[skills.config]]` entries and keeps Kitfold's own entries in a
/// marked section at the end of the file.
enum CodexConfig {
    static let begin = "# kitfold:begin (managed by Kitfold: skills hidden from Codex)"
    static let end = "# kitfold:end"

    struct Entry {
        var fields: [String: String]
        /// Line range of the table (header through its last key).
        var lines: ClosedRange<Int>
        var inKitfoldBlock: Bool
    }

    static func blockRange(_ lines: [String]) -> ClosedRange<Int>? {
        guard let s = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == begin }),
            let e = lines[s...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == end })
        else { return nil }
        return s...e
    }

    static func entries(in text: String) -> [Entry] {
        let lines = text.components(separatedBy: "\n")
        let block = blockRange(lines)
        var out: [Entry] = []
        var current: Entry?
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if let c = current { out.append(c) }
                current =
                    MiniTOML.header(line) == "[[skills.config]]"
                    ? Entry(fields: [:], lines: i...i, inKitfoldBlock: block?.contains(i) ?? false) : nil
                continue
            }
            guard var c = current, let (k, v) = MiniTOML.keyValue(line) else { continue }
            c.fields[k] = v
            c.lines = c.lines.lowerBound...i
            current = c
        }
        if let c = current { out.append(c) }
        return out
    }

    /// Something in the file would make an appended `[[skills.config]]` invalid TOML
    /// (`skills.config` written as an inline array, a plain table, or `skills` as an inline table).
    static func conflictsWithArrayTables(_ text: String) -> Bool {
        var table = ""
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("[") {
                table = MiniTOML.header(line)
                if table == "[skills.config]" { return true }
                continue
            }
            guard let (k, _) = MiniTOML.keyValue(line) else { continue }
            if table == "" && (k == "skills" || k == "skills.config") { return true }
            if table == "[skills]" && k == "config" { return true }
        }
        return false
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Replace Kitfold's section with these SKILL.md paths (removed when empty). Nothing outside it changes.
    static func withBlock(_ text: String?, paths: [String], env: KitfoldEnvironment) -> String {
        var lines = (text ?? "").components(separatedBy: "\n")
        if text == nil || text == "" { lines = [] }
        var insertAt = lines.count
        if let r = blockRange(lines) {
            lines.removeSubrange(r)
            insertAt = r.lowerBound
        } else if lines.last == "" {
            insertAt = lines.count - 1  // before the final newline
        }
        guard !paths.isEmpty else { return lines.joined(separator: "\n") }
        var block = [begin]
        for p in paths.sorted() { block += ["[[skills.config]]", "path = " + quote(p), "enabled = false"] }
        block.append(end)
        lines.insert(contentsOf: block, at: insertAt)
        if lines.last != "" { lines.append("") }
        return lines.joined(separator: "\n")
    }

    /// Remove the user's own entries for `key` (outside Kitfold's section).
    static func removeEntries(matching key: String, from text: String, env: KitfoldEnvironment) -> String {
        var lines = text.components(separatedBy: "\n")
        let doomed = entries(in: text).filter { e in
            guard !e.inKitfoldBlock else { return false }
            if let p = e.fields["path"], key.hasPrefix("skills.config/path:") {
                let abs = env.expand(p)
                return NativeSettings.codexKey(path: FS.realPath(abs) ?? abs) == key
            }
            if let n = e.fields["name"], key == NativeSettings.codexKey(name: n) { return true }
            return false
        }
        for e in doomed.reversed() {
            var r = e.lines
            // Take one blank separator line with it.
            if r.upperBound + 1 < lines.count, lines[r.upperBound + 1].trimmingCharacters(in: .whitespaces).isEmpty,
                r.lowerBound == 0 || lines[r.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty
            {
                r = r.lowerBound...(r.upperBound + 1)
            }
            lines.removeSubrange(r)
        }
        return lines.joined(separator: "\n")
    }
}
