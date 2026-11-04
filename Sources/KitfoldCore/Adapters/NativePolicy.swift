import Foundation

/// Whether an agent's own settings switch a skill off.
public enum NativeSkillState: Hashable, Sendable {
    case enabled
    /// Hidden by the agent's settings; `source` is the file that says so.
    case disabled(source: String, byKitfold: Bool)
    /// Loaded in a reduced form (Claude `name-only`, `user-invocable-only`, OpenCode `ask`).
    case limited(mode: String, source: String)

    public var isDisabled: Bool { if case .disabled = self { return true }; return false }
}

/// One entry in an agent's settings that decides whether a skill loads.
public struct NativeRule: Hashable, Sendable {
    public enum Match: Hashable, Sendable {
        case name(String)
        /// Codex: the real path of a SKILL.md file.
        case path(String)
        /// OpenCode: a wildcard pattern (an exact name is a pattern without wildcards).
        case pattern(String)
        /// Every skill (Gemini `skills.enabled: false`, OpenCode `permission: "deny"`).
        case all
    }
    public var match: Match
    public var state: NativeSkillState
    /// Absolute path of the settings file.
    public var file: String
    /// Which entry in the file, e.g. `skillOverrides/pdf` (see `NativeSettings`).
    public var key: String
    /// The entry's value as written (`off`, `deny`, `false`…).
    public var value: String
    /// Codex: inside Kitfold's managed section of config.toml.
    public var inKitfoldBlock = false

    /// Key of this entry in Kitfold's deployment ledger.
    public var ledgerKey: String { NativeSettings.ledgerKey(file: file, key: key) }

    /// Written by Kitfold and unchanged since.
    func isOwned(by ledger: [String: String]) -> Bool { inKitfoldBlock || ledger[ledgerKey] == value }
}

/// Reads each agent's native "disable a skill" settings — only the keys involved, nothing else.
/// Config files can hold secrets (env blocks, tokens); values other than these keys are
/// never stored, logged or shown.
public struct NativePolicy: Sendable {
    /// In the order the agent applies them; for each kind of match the last one wins.
    public internal(set) var rules: [NativeRule] = []
    var caseInsensitive = false
    /// Files that exist but couldn't be parsed.
    public internal(set) var unreadable: [String] = []

    public static let empty = NativePolicy()

    public func state(name: String, skillFile: String?) -> NativeSkillState {
        rule(name: name, skillFile: skillFile)?.state ?? .enabled
    }

    /// The entry that decides `name`'s state, if any.
    public func rule(name: String, skillFile: String?) -> NativeRule? {
        if let all = rules.last(where: { $0.match == .all && $0.state.isDisabled }) { return all }
        if let f = skillFile, let r = rules.last(where: { $0.match == .path(f) }) { return r }
        let key = caseInsensitive ? name.lowercased() : name
        if let r = rules.last(where: { $0.match == .name(key) }) { return r }
        return rules.last { rule in
            switch rule.match {
            case .pattern(let p): return NativePolicy.wildcard(p, matches: name)
            case .all: return true
            default: return false
            }
        }
    }

    /// The same policy without the entries `drop` selects (e.g. the ones Kitfold wrote).
    func removing(_ drop: (NativeRule) -> Bool) -> NativePolicy {
        var p = self
        p.rules.removeAll(where: drop)
        return p
    }

    static func wildcard(_ pattern: String, matches s: String) -> Bool {
        if pattern == "*" { return true }
        let regex =
            "^"
            + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
        return s.range(of: regex, options: .regularExpression) != nil
    }

    // MARK: per agent

    /// `read` supplies file contents (the planner passes contents a plan is about to write);
    /// `ledger` marks entries Kitfold wrote, so the UI can tell them apart.
    public static func load(
        adapter: AgentAdapter, scope: Scope, env: KitfoldEnvironment, ledger: [String: String] = [:],
        read: (String) -> String? = FS.read
    ) -> NativePolicy {
        var p = NativePolicy()
        for f in NativeSettings.files(adapter, scope, env) {
            guard let text = read(f) else { continue }
            do { try p.read(text, file: f, mechanism: adapter.descriptor.skillDisable, env: env) } catch { p.unreadable.append(f) }
        }
        for i in p.rules.indices where p.rules[i].isOwned(by: ledger) {
            if case .disabled(let s, _) = p.rules[i].state { p.rules[i].state = .disabled(source: s, byKitfold: true) }
        }
        return p
    }

    /// Add the rules found in one file's text.
    mutating func read(_ text: String, file: String, mechanism: SkillDisableMechanism, env: KitfoldEnvironment) throws {
        switch mechanism {
        case .none: break
        case .claudeSettings: try NativePolicy.claude(text, file: file, env: env, into: &self)
        case .codexConfig: NativePolicy.codex(text, file: file, env: env, into: &self)
        case .openCodePermission: try NativePolicy.openCode(text, file: file, env: env, into: &self)
        case .geminiSettings:
            caseInsensitive = true
            try NativePolicy.gemini(text, file: file, env: env, into: &self)
        }
    }

    static func claude(_ text: String, file: String, env: KitfoldEnvironment, into p: inout NativePolicy) throws {
        let root = try JSONEdit.parse(text)
        guard let overrides = JSONEdit.object(at: ["skillOverrides"], in: root) else { return }
        let src = env.abbreviate(file)
        for m in overrides.members {
            guard let v = m.value.stringValue else { continue }
            let state: NativeSkillState
            switch v {
            case "off": state = .disabled(source: src, byKitfold: false)
            case "name-only", "user-invocable-only": state = .limited(mode: v, source: src)
            case "on": state = .enabled
            default: continue
            }
            p.rules.append(NativeRule(match: .name(m.key), state: state, file: file, key: NativeSettings.claudeKey(m.key), value: v))
        }
    }

    static func codex(_ text: String, file: String, env: KitfoldEnvironment, into p: inout NativePolicy) {
        let src = env.abbreviate(file)
        for entry in CodexConfig.entries(in: text) {
            let enabled = entry.fields["enabled"].map { $0 == "true" } ?? true
            let state: NativeSkillState = enabled ? .enabled : .disabled(source: src, byKitfold: false)
            let value = enabled ? "true" : "false"
            if let path = entry.fields["path"] {
                let abs = env.expand(path)
                let real = FS.realPath(abs) ?? abs
                p.rules.append(
                    NativeRule(
                        match: .path(real), state: state, file: file, key: NativeSettings.codexKey(path: real), value: value,
                        inKitfoldBlock: entry.inKitfoldBlock))
            } else if let name = entry.fields["name"] {
                p.rules.append(
                    NativeRule(
                        match: .name(name), state: state, file: file, key: NativeSettings.codexKey(name: name), value: value,
                        inKitfoldBlock: entry.inKitfoldBlock))
            }
        }
    }

    static func openCode(_ text: String, file: String, env: KitfoldEnvironment, into p: inout NativePolicy) throws {
        let root = try JSONEdit.parse(text)
        guard let perm = root.member("permission")?.value else { return }
        let src = env.abbreviate(file)
        func state(_ action: String) -> NativeSkillState? {
            switch action {
            case "deny": return .disabled(source: src, byKitfold: false)
            case "ask": return .limited(mode: "ask", source: src)
            case "allow": return .enabled
            default: return nil
            }
        }
        if let s = perm.stringValue, let st = state(s) {
            p.rules.append(NativeRule(match: .pattern("*"), state: st, file: file, key: "permission", value: s))
            return
        }
        guard let skill = perm.member("skill")?.value else { return }
        if let s = skill.stringValue, let st = state(s) {
            p.rules.append(NativeRule(match: .pattern("*"), state: st, file: file, key: "permission.skill", value: s))
        }
        // Document order matters: the last matching rule wins.
        for m in skill.members {
            guard let s = m.value.stringValue, let st = state(s) else { continue }
            p.rules.append(NativeRule(match: .pattern(m.key), state: st, file: file, key: NativeSettings.openCodeKey(m.key), value: s))
        }
    }

    static func gemini(_ text: String, file: String, env: KitfoldEnvironment, into p: inout NativePolicy) throws {
        let root = try JSONEdit.parse(text)
        guard let skills = JSONEdit.object(at: ["skills"], in: root) else { return }
        let src = env.abbreviate(file)
        if skills.member("enabled")?.value.boolValue == false {
            p.rules.append(
                NativeRule(match: .all, state: .disabled(source: src, byKitfold: false), file: file, key: "skills.enabled", value: "false"))
        }
        for e in skills.member("disabled")?.value.elements ?? [] {
            guard let name = e.value.stringValue else { continue }
            p.rules.append(
                NativeRule(
                    match: .name(name.lowercased()), state: .disabled(source: src, byKitfold: false), file: file,
                    key: NativeSettings.geminiKey(name), value: "disabled"))
        }
    }
}

/// JSON with comments and trailing commas (OpenCode, Gemini).
enum JSONC {
    static func object(at path: String) -> [String: Any]? {
        guard let text = FS.read(path) else { return nil }
        let clean = strip(text)
        return (try? JSONSerialization.jsonObject(with: Data(clean.utf8))) as? [String: Any]
    }

    static func strip(_ s: String) -> String {
        var out = ""
        var chars = Array(s)
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            if c == "," {
                // Drop trailing commas before } or ].
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" { i += 1; continue }
            }
            out.append(c)
            i += 1
        }
        chars.removeAll()
        return out
    }
}

/// Just enough TOML to read `[[array.tables]]` and `[table."quoted"]` with scalar values.
enum MiniTOML {
    static func arrayTables(named name: String, in text: String) -> [[String: String]] {
        var out: [[String: String]] = []
        var current: [String: String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if let c = current { out.append(c) }
                current = (header(line) == "[[\(name)]]") ? [:] : nil
                continue
            }
            guard current != nil, let (k, v) = keyValue(line) else { continue }
            current?[k] = v
        }
        if let c = current { out.append(c) }
        return out
    }

    /// A table header without a trailing comment or spaces inside the brackets.
    static func header(_ line: String) -> String {
        var l = line
        if let hash = l.firstIndex(of: "#"), let close = l.lastIndex(of: "]"), hash > close { l = String(l[..<hash]) }
        return l.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\t", with: "")
    }

    /// `[prefix."key"]` tables → key → (field → value).
    static func tables(prefix: String, in text: String) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        var currentKey: String?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                currentKey = nil
                let header = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                if header.hasPrefix(prefix + ".") {
                    let k = String(header.dropFirst(prefix.count + 1))
                    if k.hasPrefix("\""), k.hasSuffix("\""), k.count >= 2 {
                        currentKey = String(k.dropFirst().dropLast())
                    } else if !k.contains(".") {
                        currentKey = k
                    }
                    if let ck = currentKey, out[ck] == nil { out[ck] = [:] }
                }
                continue
            }
            if let ck = currentKey, let (k, v) = keyValue(line) { out[ck]?[k] = v }
        }
        return out
    }

    static func keyValue(_ line: String) -> (String, String)? {
        guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return nil }
        let key = Frontmatter.unquote(String(line[..<eq]).trimmingCharacters(in: .whitespaces))
        var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            let q = value.first!
            if let end = value.dropFirst().firstIndex(of: q) { value = String(value[value.index(after: value.startIndex)..<end]) }
            if q == "\"" { value = value.replacingOccurrences(of: "\\\\", with: "\\") }
        } else if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        return (key, value)
    }
}
