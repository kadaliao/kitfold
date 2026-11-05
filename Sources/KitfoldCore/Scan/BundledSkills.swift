import Foundation

/// Agent-specific discovery of plugin / extension skills. These are read-only to Kitfold:
/// the agent's own plugin system owns them. Only *enabled* plugins are reported, because
/// only those reach the agent's context.
public enum BundledProvider: String, Sendable, Hashable, Codable {
    case claudePlugins
    case codexPlugins
    case geminiExtensions
}

enum BundledSkills {
    static func observe(adapter: AgentAdapter, scope: Scope, env: KitfoldEnvironment) -> [ObservedSkill] {
        guard scope.isGlobal, let provider = adapter.descriptor.bundledProvider else { return [] }
        let dir = adapter.configDir(env)
        let dirs: [(label: String, dir: String)]
        switch provider {
        case .claudePlugins: dirs = claudePluginDirs(configDir: dir)
        case .codexPlugins: dirs = codexPluginDirs(configDir: dir)
        case .geminiExtensions: dirs = geminiExtensionDirs(configDir: dir)
        }
        var out: [ObservedSkill] = []
        for (label, dir) in dirs {
            let skillsDir = dir + "/skills"
            guard FS.isDirectoryFollowing(skillsDir) else { continue }
            let spec = SkillRootSpec(.absolute, skillsDir, scope: .global, role: .bundled, note: label)
            let root = ResolvedSkillRoot(path: skillsDir, spec: spec, agent: adapter.id, scope: scope)
            out += Scanner(env: env, adapters: []).observe(root: root)
        }
        return out
    }

    /// `plugins/installed_plugins.json` → installPath, filtered by `enabledPlugins` in settings.json.
    /// Only those two keys are read.
    static func claudePluginDirs(configDir: String) -> [(String, String)] {
        guard let data = FileManager.default.contents(atPath: configDir + "/plugins/installed_plugins.json"),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let plugins = root["plugins"] as? [String: Any]
        else { return [] }
        var enabled: [String: Bool] = [:]
        if let obj = JSONC.object(at: configDir + "/settings.json"), let ep = obj["enabledPlugins"] as? [String: Any] {
            for (k, v) in ep { enabled[k] = (v as? Bool) ?? false }
        }
        var out: [(String, String)] = []
        for (key, value) in plugins.sorted(by: { $0.key < $1.key }) where enabled[key] == true {
            let installs = (value as? [[String: Any]]) ?? []
            let user = installs.first { ($0["scope"] as? String) == "user" } ?? installs.first
            if let path = user?["installPath"] as? String { out.append((L("Plugin \(key)"), path)) }
        }
        return out
    }

    /// `[plugins."name@marketplace"]` tables in config.toml → newest cached version of each enabled plugin.
    static func codexPluginDirs(configDir: String) -> [(String, String)] {
        guard let text = FS.read(configDir + "/config.toml") else { return [] }
        var out: [(String, String)] = []
        for (key, fields) in MiniTOML.tables(prefix: "plugins", in: text).sorted(by: { $0.key < $1.key }) {
            guard fields["enabled"] != "false" else { continue }
            let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let base = configDir + "/plugins/cache/\(parts[1])/\(parts[0])"
            let versions = FS.children(base).map { base + "/" + $0 }.filter(FS.isDirectoryFollowing)
            if let newest = versions.max(by: { (FS.modificationDate($0) ?? .distantPast) < (FS.modificationDate($1) ?? .distantPast) }) {
                out.append((L("Plugin \(key)"), newest))
            }
        }
        return out
    }

    /// `extensions/<name>/` with `gemini-extension.json`, minus those disabled in extension-enablement.json.
    static func geminiExtensionDirs(configDir: String) -> [(String, String)] {
        let base = configDir + "/extensions"
        var disabled = Set<String>()
        if let obj = JSONC.object(at: base + "/extension-enablement.json") {
            for (name, v) in obj {
                if let o = v as? [String: Any], let overrides = o["overrides"] as? [String],
                    overrides.contains(where: { $0.hasPrefix("!") })
                {
                    disabled.insert(name)
                }
            }
        }
        return FS.children(base).compactMap { name -> (String, String)? in
            let dir = base + "/" + name
            guard FS.exists(dir + "/gemini-extension.json"), !disabled.contains(name) else { return nil }
            return (L("Extension \(name)"), dir)
        }
    }
}
