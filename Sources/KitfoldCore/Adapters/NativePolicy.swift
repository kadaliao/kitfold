import Foundation

/// Whether an agent's own settings switch a skill off.
public enum NativeSkillState: Hashable, Sendable {
    case enabled
    /// Hidden by the agent's settings; `source` is the file that says so.
    case disabled(source: String)
    /// Loaded in a reduced form (Claude `name-only`, `user-invocable-only`, OpenCode `ask`).
    case limited(mode: String, source: String)

    public var isDisabled: Bool { if case .disabled = self { return true }; return false }
}

/// Reads each agent's native "disable a skill" settings — only the keys involved, nothing else.
/// Config files can hold secrets (env blocks, tokens); values other than these keys are
/// never stored, logged or shown.
public struct NativePolicy: Sendable {
    var byName: [String: NativeSkillState] = [:]
    var byPath: [String: NativeSkillState] = [:]
    /// OpenCode wildcard rules; the last matching rule wins.
    var patterns: [(pattern: String, state: NativeSkillState)] = []
    var caseInsensitive = false
    var allDisabled: NativeSkillState?

    public static let empty = NativePolicy()

    public func state(name: String, skillFile: String?) -> NativeSkillState {
        if let all = allDisabled { return all }
        if let f = skillFile, let s = byPath[f] { return s }
        let key = caseInsensitive ? name.lowercased() : name
        if let s = byName[key] { return s }
        var result: NativeSkillState = .enabled
        for (pattern, state) in patterns where NativePolicy.wildcard(pattern, matches: name) { result = state }
        return result
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

    public static func load(adapter: AgentAdapter, scope: Scope, env: KitfoldEnvironment) -> NativePolicy {
        let dir = adapter.configDir(env)
        switch adapter.descriptor.skillDisable {
        case .none: return .empty
        case .claudeSettings:
            var files = [dir + "/settings.json"]
            if let p = scope.projectPath { files += [p + "/.claude/settings.json", p + "/.claude/settings.local.json"] }
            return claude(files, env: env)
        case .codexConfig:
            return codex(dir + "/config.toml", env: env)
        case .openCodePermission:
            var files = [dir + "/opencode.json", dir + "/opencode.jsonc"]
            if let p = scope.projectPath {
                files += [p + "/opencode.json", p + "/opencode.jsonc", p + "/.opencode/opencode.json", p + "/.opencode/opencode.jsonc"]
            }
            return openCode(files, env: env)
        case .geminiSettings:
            var files = [dir + "/settings.json"]
            if let p = scope.projectPath { files.append(p + "/.gemini/settings.json") }
            return gemini(files, env: env)
        }
    }

    static func claude(_ files: [String], env: KitfoldEnvironment) -> NativePolicy {
        var p = NativePolicy()
        for f in files {
            guard let obj = JSONC.object(at: f), let overrides = obj["skillOverrides"] as? [String: Any] else { continue }
            for (name, v) in overrides {
                switch v as? String {
                case "off": p.byName[name] = .disabled(source: env.abbreviate(f))
                case "name-only", "user-invocable-only": p.byName[name] = .limited(mode: v as! String, source: env.abbreviate(f))
                case "on": p.byName[name] = .enabled
                default: break
                }
            }
        }
        return p
    }

    static func codex(_ file: String, env: KitfoldEnvironment) -> NativePolicy {
        var p = NativePolicy()
        guard let text = FS.read(file) else { return p }
        let src = env.abbreviate(file)
        for entry in MiniTOML.arrayTables(named: "skills.config", in: text) {
            let enabled = entry["enabled"].map { $0 == "true" } ?? true
            let state: NativeSkillState = enabled ? .enabled : .disabled(source: src)
            if let path = entry["path"] {
                let abs = env.expand(path)
                p.byPath[FS.realPath(abs) ?? abs] = state
            } else if let name = entry["name"] {
                p.byName[name] = state
            }
        }
        return p
    }

    static func openCode(_ files: [String], env: KitfoldEnvironment) -> NativePolicy {
        var p = NativePolicy()
        for f in files {
            guard let obj = JSONC.object(at: f), let perm = obj["permission"] else { continue }
            let src = env.abbreviate(f)
            func state(_ action: String) -> NativeSkillState? {
                switch action {
                case "deny": return .disabled(source: src)
                case "ask": return .limited(mode: "ask", source: src)
                case "allow": return .enabled
                default: return nil
                }
            }
            if let s = perm as? String, let st = state(s) { p.patterns.append(("*", st)); continue }
            guard let dict = perm as? [String: Any], let skill = dict["skill"] else { continue }
            if let s = skill as? String, let st = state(s) { p.patterns.append(("*", st)) }
            if let rules = skill as? [String: Any] {
                // JSON object order isn't preserved by JSONSerialization; put "*" first so specific rules win.
                for (pattern, v) in rules.sorted(by: { ($0.key == "*" ? 0 : 1, $0.key) < ($1.key == "*" ? 0 : 1, $1.key) }) {
                    if let s = v as? String, let st = state(s) { p.patterns.append((pattern, st)) }
                }
            }
        }
        return p
    }

    static func gemini(_ files: [String], env: KitfoldEnvironment) -> NativePolicy {
        var p = NativePolicy()
        p.caseInsensitive = true
        for f in files {
            guard let obj = JSONC.object(at: f), let skills = obj["skills"] as? [String: Any] else { continue }
            if (skills["enabled"] as? Bool) == false { p.allDisabled = .disabled(source: env.abbreviate(f)) }
            for name in (skills["disabled"] as? [String]) ?? [] {
                p.byName[name.lowercased()] = .disabled(source: env.abbreviate(f))
            }
        }
        return p
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
                current = (line == "[[\(name)]]") ? [:] : nil
                continue
            }
            guard current != nil, let (k, v) = keyValue(line) else { continue }
            current?[k] = v
        }
        if let c = current { out.append(c) }
        return out
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
        } else if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        return (key, value)
    }
}
