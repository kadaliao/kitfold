import Foundation

/// Entry point for both the app and the CLI: one object that owns the config, the library,
/// the state database, and the scan → plan → apply → undo cycle.
///
/// Both UI perspectives ("pick a skill → choose agents" and "pick an agent → choose skills")
/// edit the same `KitfoldConfig.rules`; there is no second source of truth.
public final class Workspace: @unchecked Sendable {
    public let env: KitfoldEnvironment
    public let adapters: [AgentAdapter]
    public let library: LibraryStore
    public let store: StateStore
    public let executor: Executor
    public private(set) var config: KitfoldConfig
    /// True when kitfold.json didn't exist yet (first launch).
    public let isFirstRun: Bool

    public init(env: KitfoldEnvironment = .current(), adapters: [AgentAdapter] = BuiltinAgents.adapters) throws {
        self.env = env
        self.adapters = adapters
        library = LibraryStore(env: env)
        try library.ensureLayout()
        store = try StateStore(path: env.stateDatabase)
        executor = Executor(env: env, store: store)
        if var c = try KitfoldConfig.load(from: env.configFile) {
            c.resolvePaths(env)
            config = c
            isFirstRun = false
        } else {
            config = Workspace.bootstrapConfig(env: env)
            isFirstRun = true
            try config.save(to: env.configFile)
        }
    }

    /// First-run config: no rules (so nothing changes), plus well-known skill folders as sources.
    static func bootstrapConfig(env: KitfoldEnvironment) -> KitfoldConfig {
        var c = KitfoldConfig()
        let shared = env.expand("~/.agents/skills")
        if FS.isDirectoryFollowing(shared) {
            let lock = FS.exists(env.expand("~/.agents/.skill-lock.json"))
            c.sources.append(
                SkillSourceConfig(
                    id: "agents", label: "Shared (~/.agents/skills)", path: "~/.agents/skills",
                    managedBy: lock ? "skills CLI" : nil))
        }
        let magpie = env.expand("~/.config/magpie/library/skills")
        if FS.isDirectoryFollowing(magpie) {
            c.sources.append(
                SkillSourceConfig(id: "magpie", label: "Magpie library", path: "~/.config/magpie/library/skills", managedBy: "Magpie"))
        }
        return c
    }

    // MARK: scan / plan / apply

    public func scan(probeVersions: Bool = true) -> Snapshot {
        Scanner(env: env, adapters: adapters).scan(
            config: config, ownedPaths: store.ownedPaths(), ownedSettings: store.ownedSettings(), probeVersions: probeVersions)
    }

    /// Plan for a (possibly edited) config. Includes the kitfold.json write itself, so an undo
    /// rolls back the intent together with the files.
    /// `current` is the saved config to compare with (pass it when planning off the main thread).
    public func plan(
        _ draft: KitfoldConfig, snapshot: Snapshot, overwriteDrift: Set<String> = [], current: KitfoldConfig? = nil
    ) -> Plan {
        var plan = Planner(snapshot: snapshot, config: draft, overwriteDrift: overwriteDrift).plan()
        if draft != (current ?? config), let change = configChange(to: draft) { plan.changes.append(change) }
        return plan
    }

    func configChange(to draft: KitfoldConfig) -> PlannedChange? {
        var d = draft
        d.normalize()
        guard let after = try? Workspace.encode(d) else { return nil }
        let before = FS.read(env.configFile)
        guard before != after else { return nil }
        return PlannedChange(
            .writeFile(path: env.configFile, before: before, after: after),
            summary: L("Save assignments to kitfold.json"), agents: [], scope: .global)
    }

    static func encode(_ c: KitfoldConfig) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try enc.encode(c), as: UTF8.self) + "\n"
    }

    /// Apply a reviewed plan. Returns nil when there was nothing to do.
    @discardableResult
    public func apply(_ plan: Plan, summary: String) throws -> TransactionRecord? {
        guard !plan.changes.isEmpty else { return nil }
        let tx = try executor.apply(plan.changes, summary: summary)
        try reloadConfig()
        executor.pruneBackups(olderThan: config.preferences.backupRetentionDays)
        return tx
    }

    @discardableResult
    public func undo(_ txID: String) throws -> TransactionRecord {
        let tx = try executor.undo(txID) { self.mergedConfigUndo($0) }
        try reloadConfig()
        return tx
    }

    /// Undo only the rules a transaction changed, on top of kitfold.json as it is now, so saving
    /// settings (projects, sources, preferences) after an apply doesn't block undoing it.
    func mergedConfigUndo(_ change: PlannedChange) -> PlannedChange {
        guard case .writeFile(let path, .some(let from), .some(let to)) = change.change, path == env.configFile,
            let current = FS.read(path), current != from
        else { return change }
        let decode = { (s: String) in try? JSONDecoder().decode(KitfoldConfig.self, from: Data(s.utf8)) }
        guard let a = decode(from), let b = decode(to), var now = decode(current) else { return change }
        struct Key: Hashable {
            var resource: ResourceRef
            var scope: Scope
            var agent: AgentSelector
        }
        let keys = Set((a.rules + b.rules).map { Key(resource: $0.resource, scope: $0.scope, agent: $0.agent) })
        for k in keys {
            let wanted = b.rule(k.resource, agent: k.agent, scope: k.scope)?.state
            if a.rule(k.resource, agent: k.agent, scope: k.scope)?.state != wanted {
                now.setRule(k.resource, agent: k.agent, scope: k.scope, state: wanted)
            }
        }
        guard let text = try? Workspace.encode(now) else { return change }
        var c = change
        c.change = .writeFile(path: path, before: current, after: text)
        return c
    }

    public func history(limit: Int = 100) -> [TransactionRecord] { store.transactions(limit: limit) }

    public func reloadConfig() throws {
        if var c = try KitfoldConfig.load(from: env.configFile) {
            c.resolvePaths(env)
            config = c
        }
    }

    /// Settings that don't touch agent files (sources, projects list, preferences) are saved directly.
    public func saveConfigDirectly(_ c: KitfoldConfig) throws {
        var c = c
        c.normalize()
        try c.save(to: env.configFile)
        config = c
    }

    // MARK: instruction files

    /// Edit any instruction file (CLAUDE.md, AGENTS.md…) through the same preview/undo path.
    public func planEdit(path: String, newText: String, agents: [AgentID], scope: Scope) -> Plan {
        let before = FS.read(path)
        guard before != newText else { return Plan() }
        return Plan(changes: [
            PlannedChange(
                .writeFile(path: path, before: before, after: newText),
                summary: L("Edit \(env.abbreviate(path))"), agents: agents, scope: scope)
        ])
    }

    /// Keep an edit made outside Kitfold: copy the block's text into the profile, then re-stamp the block.
    public func adoptDrift(file: String, profile: String, snapshot: Snapshot) throws -> Plan {
        guard let text = FS.read(file), let block = ManagedBlock.findAll(in: text).first(where: { $0.profile == profile }) else {
            throw KitfoldError.notFound(L("block \(profile) in \(file)"))
        }
        guard var p = library.profiles().first(where: { $0.id == profile }) else { throw KitfoldError.notFound(L("profile \(profile)")) }
        p.body = block.body
        try saveProfile(p)
        return plan(config, snapshot: scan(probeVersions: false), overwriteDrift: [file])
    }

    // MARK: profiles (library edits keep a version history)

    public var profileHistoryDir: String { env.backupsDir + "/profiles" }

    public func saveProfile(_ p: ProfileEntry) throws {
        let path = library.profilePath(id: p.id)
        if let old = FS.read(path), old != p.rendered() {
            let stamp = Executor.newID()
            try FS.writePrivate(old, to: profileHistoryDir + "/\(p.id)/\(stamp).md")
        }
        try library.saveProfile(p)
    }

    /// Earlier saved versions of a profile, newest first.
    public func profileVersions(_ id: String) -> [(date: Date, path: String)] {
        let dir = profileHistoryDir + "/" + id
        return FS.children(dir).filter { $0.hasSuffix(".md") }.map { dir + "/" + $0 }
            .map { (date: FS.modificationDate($0) ?? .distantPast, path: $0) }
            .sorted { $0.date > $1.date }
    }

    // MARK: skills

    /// Save SKILL.md, keeping the previous version in backups.
    public func saveSkillFile(_ entry: SkillEntry, text: String) throws {
        if let old = FS.read(entry.skillFile), old != text {
            try FS.writePrivate(old, to: env.backupsDir + "/skills/\(entry.folderName)/\(Executor.newID()).md")
        }
        try FS.write(text, to: entry.skillFile)
    }

    /// Plan to bring a skill folder into the Kitfold library, leaving a link in its old place so
    /// every agent that saw it keeps seeing it. Undoable like any other plan.
    public func planAdopt(_ entry: SkillEntry, snapshot: Snapshot) throws -> Plan {
        if entry.origin == .library { throw KitfoldError.invalid(L("\(entry.name) is already in the library")) }
        if case .bundled = entry.origin { throw KitfoldError.invalid(L("Plugin skills can't be moved")) }
        if case .nested(let parent) = entry.origin {
            throw KitfoldError.invalid(L("\(entry.name) lives inside “\(parent)”; move that skill instead"))
        }
        let dest = env.librarySkillsDir + "/" + entry.folderName
        guard !FS.exists(dest) else { throw KitfoldError.invalid(L("The library already has a folder named \(entry.folderName)")) }
        var changes = [
            PlannedChange(
                .moveItem(from: entry.path, path: dest),
                summary: L("Move \(entry.name) into the Kitfold library"), agents: [], scope: .global,
                resource: ResourceRef(.skill, entry.name))
        ]
        changes.append(
            PlannedChange(
                .createSymlink(path: entry.path, target: dest),
                summary: L("Leave a link at \(env.abbreviate(entry.path))"), agents: [], scope: .global,
                resource: ResourceRef(.skill, entry.name),
                note: L("Agents and tools that used the old path keep working.")))
        // Agents that had it as a real folder in their own skills dir keep it — now as an explicit
        // assignment, so the planner treats the new link as intended rather than leftover.
        var draft = config
        for a in snapshot.managedAgents {
            for scope in snapshot.scopes
            where a.state(scope).skills.contains(where: {
                $0.root.spec.role == .primary && !$0.isSymlink && $0.realPath == entry.path
            }) {
                draft.setRule(ResourceRef(.skill, entry.name), agent: .agent(a.id), scope: scope, state: .on)
            }
        }
        if draft != config, let change = configChange(to: draft) { changes.append(change) }

        var issues: [Issue] = []
        if case .source(let id) = entry.origin, let s = config.sources.first(where: { $0.id == id }), let owner = s.managedBy {
            issues.append(
                Issue(
                    .conflict, .warning, L("\(owner) manages \(env.abbreviate(s.path))"),
                    detail: L(
                        "After the move, \(owner) may treat \(entry.name) as replaced by a link. Updates from \(owner) will no longer reach it."
                    ),
                    paths: [entry.path], key: entry.path))
        }
        return Plan(changes: changes, issues: issues)
    }

    // MARK: projects

    public func addingProject(_ path: String, to c: KitfoldConfig) -> KitfoldConfig {
        var c = c
        let abs = FS.absolute(env.expand(path), relativeTo: FileManager.default.currentDirectoryPath)
        let root = FS.gitRoot(from: abs) ?? abs
        if !c.projects.contains(where: { $0.path == FS.standardize(root) }) { c.projects.append(ProjectConfig(path: root)) }
        return c
    }
}
