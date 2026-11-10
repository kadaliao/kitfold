import Foundation

/// Which agents a rule targets.
public enum AgentSelector: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Every agent Kitfold manages, including ones added later.
    case all
    case agent(AgentID)

    public var description: String {
        switch self {
        case .all: return "*"
        case .agent(let a): return a.rawValue
        }
    }
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = s == "*" ? .all : .agent(AgentID(s))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

public enum RuleState: String, Hashable, Sendable, Codable {
    case on, off
}

/// One explicit user intent: "resource R is on/off for agent(s) A in scope S".
/// Kitfold only acts on explicit intents. Anything without a rule is left exactly as found,
/// which is what makes the first launch a zero-change, read-only experience.
public struct AssignmentRule: Hashable, Sendable, Codable {
    public var resource: ResourceRef
    public var scope: Scope
    public var agent: AgentSelector
    public var state: RuleState

    public init(_ resource: ResourceRef, scope: Scope, agent: AgentSelector, state: RuleState) {
        self.resource = resource; self.scope = scope; self.agent = agent; self.state = state
    }
}

public struct ProjectConfig: Hashable, Sendable, Codable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    public init(path: String, name: String? = nil) {
        self.path = FS.standardize(path)
        self.name = name ?? (path as NSString).lastPathComponent
    }
}

/// A folder that holds skills (each `<name>/SKILL.md`). The Kitfold library is always the
/// first source; others are registered folders such as `~/.agents/skills` or a cloned Git repo.
public struct SkillSourceConfig: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var label: String
    public var path: String  // may contain ~
    /// Another tool that owns this folder ("skills CLI", "Magpie"…). Informational; shown as a warning on edits.
    public var managedBy: String?
    public var gitURL: String?
    public var enabled: Bool

    public init(id: String, label: String, path: String, managedBy: String? = nil, gitURL: String? = nil, enabled: Bool = true) {
        self.id = id; self.label = label; self.path = path; self.managedBy = managedBy; self.gitURL = gitURL; self.enabled = enabled
    }
}

extension SkillSourceConfig {
    /// Labels Kitfold gives the sources it finds on first launch. kitfold.json keeps them in English;
    /// they're shown in the app's language until the user renames them.
    static let firstRunLabels = ["agents": "Shared (~/.agents/skills)", "magpie": "Magpie library"]

    public var displayLabel: String {
        guard Self.firstRunLabels[id] == label else { return label }
        switch id {
        case "agents": return L("Shared (~/.agents/skills)")
        case "magpie": return L("Magpie library")
        default: return label
        }
    }
}

/// An agent the user describes in kitfold.json, for one Kitfold doesn't know or finds in the wrong place:
///
///     "customAgents": [{ "id": "my-agent", "name": "My Agent", "skills": "~/.my-agent/skills",
///                        "projectSkills": ".my-agent/skills", "instructions": "~/.my-agent/AGENTS.md" }]
public struct CustomAgent: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    /// Its global skills folder (tilde allowed). Kitfold links skills here for it.
    public var skills: String
    /// Its skills folder inside a project, relative to the project root.
    public var projectSkills: String?
    /// A global instruction file only this agent reads, where Kitfold may write profiles (tilde allowed).
    public var instructions: String?
    /// The same inside a project, relative to the project root.
    public var projectInstructions: String?

    public init(
        id: String, name: String, skills: String, projectSkills: String? = nil, instructions: String? = nil,
        projectInstructions: String? = nil
    ) {
        self.id = id; self.name = name; self.skills = skills; self.projectSkills = projectSkills
        self.instructions = instructions; self.projectInstructions = projectInstructions
    }

    public var descriptor: AgentDescriptor {
        let folder = FS.standardize(skills)
        let home = (folder as NSString).deletingLastPathComponent
        func absolute(_ p: String) -> (PathBase, String) {
            p.hasPrefix("~/") ? (.home, String(p.dropFirst(2))) : (.absolute, p)
        }
        let (base, path) = absolute(folder)
        var roots = [SkillRootSpec(base, path, scope: .global, role: .primary, note: AgentSpec.Notes.ownFolder)]
        if let p = projectSkills, !p.isEmpty {
            roots.append(SkillRootSpec(.project, p, scope: .project, role: .primary, note: AgentSpec.Notes.ownProjectFolder))
        }
        var files: [InstructionFileSpec] = []
        if let f = instructions, !f.isEmpty {
            let (b, p) = absolute(FS.standardize(f))
            files.append(InstructionFileSpec(b, p, scope: .global, role: .primary))
        }
        if let f = projectInstructions, !f.isEmpty { files.append(InstructionFileSpec(.project, f, scope: .project, role: .primary)) }
        return AgentDescriptor(
            id: AgentID(id), name: name, vendor: "", binaryNames: [], binaryDirs: [], configDir: home, configDirEnv: nil,
            skillRoots: roots, instructionFiles: files, skillDisable: .none, bundledProvider: nil, globalSkillsWin: false,
            nestedSkillDepth: 0, policyCoversBundled: false, instructionByteLimit: nil, docsURL: "",
            monogram: AgentSpec.monogram(for: name), tint: AgentSpec.tint(for: id), notes: [AgentSpec.Notes.custom], source: .custom,
            markers: [folder])
    }
}

public struct AgentSettings: Hashable, Sendable, Codable {
    /// nil = automatic (managed when detected).
    public var enabled: Bool?
    public var configDir: String?
    public init(enabled: Bool? = nil, configDir: String? = nil) { self.enabled = enabled; self.configDir = configDir }
}

public struct Preferences: Hashable, Sendable, Codable {
    /// Add Kitfold's project-level symlinks / personal files to `.git/info/exclude`.
    public var gitExcludeProjectFiles: Bool = true
    /// Keep this many days of backups.
    public var backupRetentionDays: Int = 30
    public init() {}

    enum CodingKeys: String, CodingKey { case gitExcludeProjectFiles, backupRetentionDays }

    // Missing keys fall back to defaults, so new settings never break an older file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gitExcludeProjectFiles = try c.decodeIfPresent(Bool.self, forKey: .gitExcludeProjectFiles) ?? true
        backupRetentionDays = try c.decodeIfPresent(Int.self, forKey: .backupRetentionDays) ?? 30
    }
}

/// `~/.kitfold/kitfold.json` — the user's declared intent. Human-readable, diffable,
/// safe to keep in a dotfiles repo. Runtime state (what Kitfold deployed, history) lives in
/// `state.sqlite` instead.
public struct KitfoldConfig: Hashable, Sendable, Codable {
    public var version: Int = 1
    public var sources: [SkillSourceConfig] = []
    public var projects: [ProjectConfig] = []
    public var rules: [AssignmentRule] = []
    public var agents: [String: AgentSettings] = [:]
    public var customAgents: [CustomAgent] = []
    public var preferences = Preferences()

    public init() {}

    enum CodingKeys: String, CodingKey { case version, sources, projects, rules, agents, customAgents, preferences }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sources = try c.decodeIfPresent([SkillSourceConfig].self, forKey: .sources) ?? []
        projects = try c.decodeIfPresent([ProjectConfig].self, forKey: .projects) ?? []
        rules = try c.decodeIfPresent([AssignmentRule].self, forKey: .rules) ?? []
        agents = try c.decodeIfPresent([String: AgentSettings].self, forKey: .agents) ?? [:]
        customAgents = try c.decodeIfPresent([CustomAgent].self, forKey: .customAgents) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }

    /// `customAgents` is written only when there are some, so older files don't change shape.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(sources, forKey: .sources)
        try c.encode(projects, forKey: .projects)
        try c.encode(rules, forKey: .rules)
        try c.encode(agents, forKey: .agents)
        if !customAgents.isEmpty { try c.encode(customAgents, forKey: .customAgents) }
        try c.encode(preferences, forKey: .preferences)
    }

    // MARK: rule queries

    /// Explicit state for (resource, agent, scope): a specific-agent rule wins over `*`.
    public func state(_ resource: ResourceRef, agent: AgentID, scope: Scope) -> RuleState? {
        var wildcard: RuleState?
        for r in rules where r.resource == resource && r.scope == scope {
            switch r.agent {
            case .agent(let a) where a == agent: return r.state
            case .all: wildcard = r.state
            default: break
            }
        }
        return wildcard
    }

    public func rule(_ resource: ResourceRef, agent: AgentSelector, scope: Scope) -> AssignmentRule? {
        rules.first { $0.resource == resource && $0.scope == scope && $0.agent == agent }
    }

    /// Set (or clear with nil) the rule for exactly this selector.
    public mutating func setRule(_ resource: ResourceRef, agent: AgentSelector, scope: Scope, state: RuleState?) {
        rules.removeAll { $0.resource == resource && $0.scope == scope && $0.agent == agent }
        if let state { rules.append(AssignmentRule(resource, scope: scope, agent: agent, state: state)) }
        normalize()
    }

    /// "All agents" switch: one wildcard rule, specific rules cleared.
    public mutating func setAll(_ resource: ResourceRef, scope: Scope, state: RuleState?) {
        rules.removeAll { $0.resource == resource && $0.scope == scope }
        if let state { rules.append(AssignmentRule(resource, scope: scope, agent: .all, state: state)) }
        normalize()
    }

    public mutating func removeRules(for resource: ResourceRef) {
        rules.removeAll { $0.resource == resource }
    }

    public mutating func renameResource(_ from: ResourceRef, to: ResourceRef) {
        for i in rules.indices where rules[i].resource == from { rules[i].resource = to }
        normalize()
    }

    public func rules(for resource: ResourceRef) -> [AssignmentRule] { rules.filter { $0.resource == resource } }

    /// The rule edits `draft` made to `base`, replayed on top of this config. Keeps unapplied toggles
    /// when kitfold.json changes underneath them, and lets undo revert one apply's rules only.
    /// Where this config also changed a rule the draft edited, the draft wins; `overridden` counts those.
    public func replaying(rulesOf draft: KitfoldConfig, since base: KitfoldConfig) -> (config: KitfoldConfig, overridden: Int) {
        struct Key: Hashable {
            var resource: ResourceRef
            var scope: Scope
            var agent: AgentSelector
        }
        var out = self
        var overridden = 0
        for k in Set((draft.rules + base.rules).map { Key(resource: $0.resource, scope: $0.scope, agent: $0.agent) }) {
            let wanted = draft.rule(k.resource, agent: k.agent, scope: k.scope)?.state
            let was = base.rule(k.resource, agent: k.agent, scope: k.scope)?.state
            guard wanted != was else { continue }
            let now = rule(k.resource, agent: k.agent, scope: k.scope)?.state
            if now != was && now != wanted { overridden += 1 }
            out.setRule(k.resource, agent: k.agent, scope: k.scope, state: wanted)
        }
        return (out, overridden)
    }

    /// Drop specific rules that merely repeat the wildcard; keep a stable order for clean diffs.
    mutating func normalize() {
        var out: [AssignmentRule] = []
        for r in rules {
            if case .agent = r.agent,
                let w = rules.first(where: { $0.resource == r.resource && $0.scope == r.scope && $0.agent == .all }),
                w.state == r.state
            {
                continue
            }
            if !out.contains(where: { $0.resource == r.resource && $0.scope == r.scope && $0.agent == r.agent }) {
                out.append(r)
            }
        }
        out.sort {
            ($0.resource.kind.rawValue, $0.resource.id, $0.scope.description, $0.agent.description)
                < ($1.resource.kind.rawValue, $1.resource.id, $1.scope.description, $1.agent.description)
        }
        rules = out
    }

    /// Project paths must be absolute: expand `~`; projects and rules with a relative path are dropped
    /// (they would resolve against whatever the current directory happens to be).
    public mutating func resolvePaths(_ env: KitfoldEnvironment) {
        projects = projects.compactMap { p in
            var p = p
            p.path = env.expand(p.path)
            return p.path.hasPrefix("/") ? p : nil
        }
        rules = rules.compactMap { r in
            guard case .project(let path) = r.scope else { return r }
            var r = r
            r.scope = .project(env.expand(path))
            return r.scope.projectPath!.hasPrefix("/") ? r : nil
        }
    }

    public func isAgentEnabled(_ id: AgentID, detected: Bool) -> Bool {
        agents[id.rawValue]?.enabled ?? detected
    }

    // MARK: persistence

    public static func load(from path: String) throws -> KitfoldConfig? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try JSONDecoder().decode(KitfoldConfig.self, from: data)
    }

    public func save(to path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(self)
        try FS.write(String(decoding: data, as: UTF8.self) + "\n", to: path)
    }
}
