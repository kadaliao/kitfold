import Foundation

/// One entry found in one of an agent's skill directories.
public struct ObservedSkill: Identifiable, Hashable, Sendable {
    public var id: String { entryPath }
    public var agent: AgentID
    public var scope: Scope
    public var root: ResolvedSkillRoot
    /// `<root>/<entryName>` (may be a symlink).
    public var entryPath: String
    public var entryName: String
    /// Absolute destination if the entry is a symlink.
    public var linkTarget: String?
    /// Fully resolved directory; nil when the link is broken.
    public var realPath: String?
    public var skill: SkillEntry?
    /// The agent's own settings may switch the skill off.
    public var native: NativeSkillState = .enabled
    /// Found inside another skill's folder (Codex/OpenCode load nested SKILL.md files).
    public var nestedIn: String?
    /// The agent ignores this SKILL.md (missing frontmatter it requires).
    public var skipReason: String?

    public var name: String { skill?.name ?? entryName }
    public var isSymlink: Bool { linkTarget != nil }
    public var isBroken: Bool { realPath == nil }
    public var isReadable: Bool { skill != nil }
    /// Actually reaches the agent's context.
    public var isActive: Bool { isReadable && skipReason == nil && !native.isDisabled }
    public var skillFile: String? { realPath.map { $0 + "/SKILL.md" } }
}

public struct InstructionFileState: Identifiable, Hashable, Sendable {
    public var id: String { file.id }
    public var file: ResolvedInstructionFile
    public var exists: Bool
    /// Loaded right now, after fallback/override rules.
    public var isLoaded: Bool
    public var isSymlink: Bool
    public var realPath: String?
    public var byteCount: Int
    /// Kitfold's per-profile blocks in this file.
    public var blocks: [ManagedBlock.Found]
    public var foreignBlocks: [String]
    /// Other agents that load this same file in the same scope.
    public var sharedWith: [AgentID]
    public var driftedBlocks: [ManagedBlock.Found] { blocks.filter(\.isModifiedOutsideKitfold) }
}

public struct AgentScopeState: Sendable {
    public var skills: [ObservedSkill]
    public var instructions: [InstructionFileState]
    public var policy: NativePolicy

    public init(skills: [ObservedSkill] = [], instructions: [InstructionFileState] = [], policy: NativePolicy = .empty) {
        self.skills = skills; self.instructions = instructions; self.policy = policy
    }

    /// Skills the agent will actually load in this scope alone, first root wins on a name clash.
    public var effectiveSkills: [ObservedSkill] {
        var seen = Set<String>()
        return skills.filter { $0.isActive && seen.insert($0.name).inserted }
    }

    public var loadedInstructions: [InstructionFileState] { instructions.filter(\.isLoaded) }
}

public struct AgentState: Identifiable, Sendable {
    public var id: AgentID { adapter.id }
    public var name: String { adapter.name }
    public var adapter: AgentAdapter
    public var installation: AgentInstallation
    /// Managed by Kitfold (config override, else "detected").
    public var enabled: Bool
    public var scopes: [Scope: AgentScopeState]

    public func state(_ scope: Scope) -> AgentScopeState { scopes[scope] ?? AgentScopeState() }

    /// Everything the agent finds when started in `scope`, in precedence order.
    /// For a project, global skills are re-checked against the project's settings.
    public func reachableSkills(in scope: Scope) -> [Reach] {
        let local = state(scope).skills.map { Reach(skill: $0, inherited: false) }
        guard !scope.isGlobal else { return local }
        let policy = state(scope).policy
        let global = state(.global).skills.map { s -> Reach in
            var s = s
            if s.root.spec.role != .bundled || adapter.descriptor.policyCoversBundled {
                s.native = policy.state(name: s.name, skillFile: s.skillFile)
            }
            return Reach(skill: s, inherited: true)
        }
        return adapter.descriptor.globalSkillsWin ? global + local : local + global
    }

    /// What reaches the agent's context in `scope`, de-duplicated by name (first wins).
    public func visibleSkills(in scope: Scope) -> [ObservedSkill] {
        var seen = Set<String>()
        return reachableSkills(in: scope).map { $0.skill }.filter { $0.isActive && seen.insert($0.name).inserted }
    }
}

/// A skill as seen from a scope; `inherited` = it's deployed globally, seen from a project.
public struct Reach: Sendable, Hashable {
    public var skill: ObservedSkill
    public var inherited: Bool
}

/// How a skill reaches an agent.
public struct Exposure: Hashable, Sendable, Identifiable {
    public enum Via: Hashable, Sendable {
        /// Symlink in the agent's own skills dir.
        case link(ownedByKitfold: Bool)
        /// A real folder in the agent's own skills dir.
        case localFolder
        /// The skill lives in a directory several agents read (e.g. ~/.agents/skills).
        case sharedDir
        /// Read through another agent's directory (OpenCode → ~/.claude/skills).
        case foreignDir(AgentID?)
        case bundled
        /// A SKILL.md nested inside another skill's folder.
        case nested(String)
    }
    public var id: String { observed.id }
    public var via: Via
    public var observed: ObservedSkill
    /// Seen from a project, but deployed globally.
    public var inherited: Bool
    public var isActive: Bool { observed.isActive }
}

public struct Issue: Identifiable, Hashable, Sendable {
    public enum Severity: Int, Sendable, Hashable, Comparable {
        case info = 0, warning = 1, error = 2
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }
    public enum Kind: String, Sendable, Hashable {
        case brokenLink, duplicateName, invalidSkill, blockDrift, foreignBlock, sizeLimit, nestedSkill
        case conflict, sharedInstructionFile, fallbackChange, missingResource, stillVisible, unsupported, disabledNatively
        /// A link for one agent lands in a folder another agent reads too.
        case sharedSkillFolder
    }
    public var id: String
    public var severity: Severity
    public var kind: Kind
    public var title: String
    public var detail: String
    public var paths: [String]
    public var agent: AgentID?
    /// Other agents the same problem affects (reported once, shown on each agent's page).
    public var alsoAffects: [AgentID]
    public var scope: Scope?

    public var affectedAgents: [AgentID] { (agent.map { [$0] } ?? []) + alsoAffects }

    public init(
        _ kind: Kind, _ severity: Severity, _ title: String, detail: String = "", paths: [String] = [],
        agent: AgentID? = nil, alsoAffects: [AgentID] = [], scope: Scope? = nil, key: String? = nil
    ) {
        self.kind = kind; self.severity = severity; self.title = title; self.detail = detail; self.paths = paths
        self.agent = agent; self.alsoAffects = alsoAffects; self.scope = scope
        self.id = "\(kind.rawValue)|\(key ?? paths.joined(separator: ","))|\(agent?.rawValue ?? "")|\(scope?.description ?? "")"
    }
}

/// Everything Kitfold knows about the machine at one moment. Immutable; rescan to refresh.
public struct Snapshot: Sendable {
    public var env: KitfoldEnvironment
    public var config: KitfoldConfig
    public var agents: [AgentState]
    /// Every distinct skill directory: library, sources, and anything found in agent dirs.
    public var catalog: [SkillEntry]
    public var profiles: [ProfileEntry]
    public var issues: [Issue]
    /// Paths Kitfold deployed (from the state DB).
    public var ownedPaths: Set<String>
    /// Settings entries Kitfold wrote: ledger key → value.
    public var ownedSettings: [String: String] = [:]
    public var scannedAt: Date
    /// Precomputed lookups (the matrix asks for hundreds of cells per render).
    var exposureIndex: [String: [Exposure]] = [:]
    var catalogIndex: [String: [SkillEntry]] = [:]

    init(
        env: KitfoldEnvironment, config: KitfoldConfig, agents: [AgentState], catalog: [SkillEntry], profiles: [ProfileEntry],
        issues: [Issue], ownedPaths: Set<String>, scannedAt: Date
    ) {
        self.env = env; self.config = config; self.agents = agents; self.catalog = catalog; self.profiles = profiles
        self.issues = issues; self.ownedPaths = ownedPaths; self.scannedAt = scannedAt
    }

    static func indexKey(_ agent: AgentID, _ scope: Scope, _ name: String) -> String { "\(agent.rawValue)|\(scope)|\(name)" }

    mutating func buildIndex() {
        catalogIndex = Dictionary(grouping: catalog, by: \.name)
        var index: [String: [Exposure]] = [:]
        for a in agents {
            for scope in scopes {
                for e in computeExposures(agent: a, scope: scope) {
                    var keys = [Snapshot.indexKey(a.id, scope, e.observed.name)]
                    if e.observed.entryName != e.observed.name { keys.append(Snapshot.indexKey(a.id, scope, e.observed.entryName)) }
                    for k in keys { index[k, default: []].append(e) }
                }
            }
        }
        exposureIndex = index
    }

    public var scopes: [Scope] { [.global] + config.projects.map { .project($0.path) } }
    public var managedAgents: [AgentState] { agents.filter(\.enabled) }

    public func agent(_ id: AgentID) -> AgentState? { agents.first { $0.id == id } }

    /// Preferred catalog entry for a name: library first, then sources, then the rest.
    public func skill(named name: String) -> SkillEntry? {
        let matches = catalogIndex.isEmpty ? catalog.filter { $0.name == name } : (catalogIndex[name] ?? [])
        return matches.first { $0.origin == .library }
            ?? matches.first {
                if case .source = $0.origin { return true }; return false
            }
            ?? matches.first
    }

    public func skillEntries(named name: String) -> [SkillEntry] { catalog.filter { $0.name == name } }

    /// Unique skill names across the catalog.
    public var skillNames: [String] {
        var seen = Set<String>()
        return catalog.compactMap { seen.insert($0.name).inserted ? $0.name : nil }.sorted()
    }

    public func profile(_ id: String) -> ProfileEntry? { profiles.first { $0.id == id } }

    /// How `skillName` reaches `agent` in `scope` (including global inheritance for projects).
    public func exposures(skill skillName: String, agent: AgentID, scope: Scope) -> [Exposure] {
        if !exposureIndex.isEmpty { return exposureIndex[Snapshot.indexKey(agent, scope, skillName)] ?? [] }
        guard let a = self.agent(agent) else { return [] }
        return computeExposures(agent: a, scope: scope).filter { $0.observed.name == skillName || $0.observed.entryName == skillName }
    }

    func computeExposures(agent a: AgentState, scope: Scope) -> [Exposure] {
        a.reachableSkills(in: scope).compactMap { pair -> Exposure? in
            let s = pair.skill
            guard s.isReadable, s.skipReason == nil else { return nil }
            let via: Exposure.Via
            if let parent = s.nestedIn { return Exposure(via: .nested(parent), observed: s, inherited: pair.inherited) }
            switch s.root.spec.role {
            case .primary: via = s.isSymlink ? .link(ownedByKitfold: ownedPaths.contains(s.entryPath)) : .localFolder
            case .shared: via = .sharedDir
            case .foreign: via = .foreignDir(s.root.spec.owner)
            case .bundled: via = .bundled
            }
            return Exposure(via: via, observed: s, inherited: pair.inherited)
        }
    }

    /// Agents (and where) a catalog skill actually reaches in `scope`.
    public func reach(of entry: SkillEntry, scope: Scope) -> [AgentID: [Exposure]] {
        var out: [AgentID: [Exposure]] = [:]
        for a in managedAgents {
            let ex = exposures(skill: entry.name, agent: a.id, scope: scope).filter { $0.observed.realPath == entry.path }
            if !ex.isEmpty { out[a.id] = ex }
        }
        return out
    }

    public func issues(for agent: AgentID) -> [Issue] { issues.filter { $0.affectedAgents.contains(agent) } }

    /// Rough context cost: skill name+description (always in the prompt) plus loaded instruction bytes.
    public func contextEstimate(agent: AgentID, scope: Scope) -> ContextEstimate {
        guard let a = self.agent(agent) else { return ContextEstimate() }
        let skills = a.visibleSkills(in: scope)
        let chars = skills.reduce(0) { $0 + $1.name.count + ($1.skill?.description.count ?? 0) }
        var files = a.state(.global).loadedInstructions
        if !scope.isGlobal { files += a.state(scope).loadedInstructions }
        return ContextEstimate(skillCount: skills.count, skillChars: chars, instructionBytes: files.reduce(0) { $0 + $1.byteCount })
    }
}

public struct ContextEstimate: Sendable, Hashable {
    public var skillCount = 0
    public var skillChars = 0
    public var instructionBytes = 0
    /// ~4 bytes per token; good enough to compare agents and spot bloat.
    public var approxTokens: Int { (skillChars + instructionBytes) / 4 }
}
