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
    /// kitfold.json as this workspace last read or wrote it, to notice edits made elsewhere (the CLI, an editor).
    private var configText: String?

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
        configText = FS.read(env.configFile)
    }

    /// First-run config: no rules (so nothing changes), plus well-known skill folders as sources.
    static func bootstrapConfig(env: KitfoldEnvironment) -> KitfoldConfig {
        var c = KitfoldConfig()
        let shared = env.expand("~/.agents/skills")
        if FS.isDirectoryFollowing(shared) {
            let lock = FS.exists(env.expand("~/.agents/.skill-lock.json"))
            c.sources.append(
                SkillSourceConfig(
                    id: "agents", label: SkillSourceConfig.firstRunLabels["agents"]!, path: "~/.agents/skills",
                    managedBy: lock ? "skills CLI" : nil))
        }
        let magpie = env.expand("~/.config/magpie/library/skills")
        if FS.isDirectoryFollowing(magpie) {
            c.sources.append(
                SkillSourceConfig(
                    id: "magpie", label: SkillSourceConfig.firstRunLabels["magpie"]!, path: "~/.config/magpie/library/skills",
                    managedBy: "Magpie"))
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
        var change = PlannedChange(
            .writeFile(path: env.configFile, before: before, after: after),
            summary: L("Save assignments to kitfold.json"), agents: [], scope: .global)
        change.savesConfig = true
        return change
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
        guard let a = decode(from), let b = decode(to), let now = decode(current) else { return change }
        guard let text = try? Workspace.encode(now.replaying(rulesOf: b, since: a).config) else { return change }
        var c = change
        c.change = .writeFile(path: path, before: current, after: text)
        return c
    }

    public func history(limit: Int = 100) -> [TransactionRecord] { store.transactions(limit: limit) }

    func ab(_ p: String) -> String { env.abbreviate(p) }

    /// Read kitfold.json again. If it can't be decoded, the config stays as it was and the error is thrown once:
    /// the text is remembered, so `reloadConfigIfChanged` doesn't report the same broken file again.
    public func reloadConfig() throws {
        let text = FS.read(env.configFile)
        configText = text
        guard let text else { return }
        var c = try JSONDecoder().decode(KitfoldConfig.self, from: Data(text.utf8))
        c.resolvePaths(env)
        config = c
    }

    /// kitfold.json no longer has the text this workspace last read or wrote: something else changed it.
    public var configChangedOnDisk: Bool { FS.read(env.configFile) != configText }

    /// Reload kitfold.json if it was changed outside this workspace. Returns the config as it was before,
    /// or nil when nothing changed, so a caller holding unapplied edits can replay them on the new one.
    public func reloadConfigIfChanged() throws -> KitfoldConfig? {
        guard configChangedOnDisk else { return nil }
        let before = config
        try reloadConfig()
        return before
    }

    /// Settings that don't touch agent files (sources, projects list, preferences) are saved directly.
    public func saveConfigDirectly(_ c: KitfoldConfig) throws {
        var c = c
        c.normalize()
        let text = try Workspace.encode(c)
        try FS.write(text, to: env.configFile)
        configText = text
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

    /// Keep an edit made outside Kitfold: copy the block's text into the profile, then re-stamp the block
    /// (and update other files using the profile). The profile is written as part of the plan, so
    /// cancelling the review changes nothing and undo puts the old profile back.
    public func adoptDrift(file: String, profile: String, snapshot: Snapshot) throws -> Plan {
        guard let text = FS.read(file), let block = ManagedBlock.findAll(in: text).first(where: { $0.profile == profile }) else {
            throw KitfoldError.notFound(L("block \(profile) in \(file)"))
        }
        guard var p = library.profiles().first(where: { $0.id == profile }) else { throw KitfoldError.notFound(L("profile \(profile)")) }
        let path = library.profilePath(id: p.id)
        let before = FS.read(path)
        p.body = block.body
        var snap = snapshot
        snap.profiles = snap.profiles.filter { $0.id != p.id } + [p]
        var plan = self.plan(config, snapshot: snap, overwriteDrift: [file])
        if before != p.rendered() {
            plan.changes.insert(
                PlannedChange(
                    .writeFile(path: path, before: before, after: p.rendered()), summary: L("Copy the edit into profile “\(p.name)”"),
                    agents: [], scope: .global, resource: ResourceRef(.profile, p.id)), at: 0)
        }
        return plan
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

    /// Saving SKILL.md is an apply of its own: the old text is backed up, and History can undo it.
    public func planSkillEdit(_ entry: SkillEntry, text: String) -> (plan: Plan, summary: String) {
        (planEdit(path: entry.skillFile, newText: text, agents: [], scope: .global), L("Edit SKILL.md of “\(entry.name)”"))
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

    /// Where deleted skills and profiles go. Backups are pruned; this folder never is.
    public var trashDir: String { env.backupsDir + "/trash" }

    /// Plan to delete a skill: take back every link to its folder, clear its rules (so the agents'
    /// own switches Kitfold wrote for it go too), take it out of the profiles that bundle it, and
    /// move the folder to Kitfold's trash. Nothing is erased, so an undo — or a later look in the
    /// trash — brings it all back.
    public func planSkillDelete(_ entry: SkillEntry, snapshot: Snapshot) throws -> Plan {
        switch entry.origin {
        case .library, .source, .agentLocal: break
        case .bundled:
            throw KitfoldError.invalid(L("Plugin skills can't be deleted; switch the plugin off in the agent instead"))
        case .nested(let parent):
            throw KitfoldError.invalid(L("\(entry.name) lives inside “\(parent)”; delete that skill instead"))
        case .external:
            throw KitfoldError.invalid(
                L(
                    "\(entry.name) is only linked into an agent's folder from \(env.abbreviate(entry.path)). Switch it off to remove the link; the folder itself is yours to delete."
                ))
        }
        let ref = ResourceRef(.skill, entry.name)
        /// The link's text as stored on disk (may be relative), so undo recreates it exactly.
        func rawLink(_ path: String) -> String {
            if case .symlink(let raw) = FS.kind(path) { return raw }
            return ""
        }
        // Drop the rules and the profile entries first, then let the planner take back what
        // Kitfold deployed for the skill — the same changes as switching it off everywhere.
        var draft = config
        draft.removeRules(for: ref)
        let bundling = snapshot.profiles.filter { $0.skills.contains(entry.name) }
        var snap = snapshot
        snap.profiles = snapshot.profiles.map { p in
            var p = p
            p.skills.removeAll { $0 == entry.name }
            return p
        }
        var plan = Planner(snapshot: snap, config: draft).plan()
        // The planner warns that taking a link back costs an agent that reads the same folder the
        // skill, and says to switch it on there. Every agent loses a deleted skill, so drop that.
        plan.issues.removeAll { $0.kind == .sharedSkillFolder && $0.key == entry.name }

        // Links elsewhere that point at this folder: in a shared folder, in an unmanaged agent's
        // folder, left behind by a Move into Library, made by another tool. Each would be a broken
        // link once the folder is gone.
        var done = Set(
            plan.changes.compactMap { c -> String? in
                if case .removeSymlink(let p, _) = c.change { return p }
                return nil
            })
        for a in snapshot.agents {
            for scope in snapshot.scopes {
                for o in a.state(scope).skills
                where o.isSymlink && o.realPath == entry.path && done.insert(o.entryPath).inserted {
                    let owned = snapshot.ownedPaths.contains(o.entryPath)
                    plan.changes.append(
                        PlannedChange(
                            .removeSymlink(path: o.entryPath, target: rawLink(o.entryPath)),
                            summary: L("Remove the link at \(ab(o.entryPath))"), agents: [a.id], scope: scope, resource: ref,
                            risk: owned ? .safe : .caution,
                            note: owned ? nil : L("This link wasn't created by Kitfold (another tool or by hand). Undo restores it.")))
                }
            }
        }
        for p in bundling {
            var left = p
            left.skills.removeAll { $0 == entry.name }
            let path = library.profilePath(id: p.id)
            plan.changes.append(
                PlannedChange(
                    .writeFile(path: path, before: FS.read(path), after: left.rendered()),
                    summary: L("Take \(entry.name) out of profile “\(p.name)”"), agents: [], scope: .global,
                    resource: ResourceRef(.profile, p.id)))
        }
        plan.changes.append(
            PlannedChange(
                .moveItem(from: entry.path, path: trashDir + "/" + entry.folderName + "-" + Executor.newID()),
                summary: L("Move \(entry.name) to Kitfold's trash"), agents: [], scope: .global, resource: ref,
                risk: entry.origin == .library ? .safe : .caution,
                note: L("The folder is kept in \(ab(trashDir)), and undo puts it back where it was.")))
        if draft != config, let change = configChange(to: draft) { plan.changes.append(change) }

        var issues: [Issue] = []
        // A folder several agents read directly: they lose the skill with it, link or no link.
        let readers = snapshot.managedAgents.filter { a in
            snapshot.scopes.contains { scope in
                snapshot.exposures(skill: entry.name, agent: a.id, scope: scope)
                    .contains { $0.isActive && !$0.inherited && !$0.observed.isSymlink && $0.observed.realPath == entry.path }
            }
        }
        if !readers.isEmpty {
            issues.append(
                Issue(
                    .sharedSkillFolder, .warning, L("\(Localization.list(readers.map(\.name))) read this folder"),
                    detail: L("They lose “\(entry.name)” when the folder goes."),
                    paths: [entry.path], agent: readers[0].id, alsoAffects: readers.dropFirst().map(\.id), key: entry.name))
        }
        if case .source(let id) = entry.origin, let s = config.sources.first(where: { $0.id == id }) {
            if let owner = s.managedBy {
                issues.append(
                    Issue(
                        .conflict, .warning, L("\(owner) manages \(ab(s.path))"),
                        detail: L("Deleting the folder doesn't tell \(owner). Its next update may bring the skill back."),
                        paths: [entry.path], key: entry.path))
            } else if let url = s.gitURL {
                issues.append(
                    Issue(
                        .conflict, .warning, L("\(ab(s.path)) is a clone of \(url)"),
                        detail: L("Deleting the folder doesn't change the repository. The next `git pull` may bring the skill back."),
                        paths: [entry.path], key: entry.path))
            }
        }
        // Rules go by name, so another folder with the same name takes the deleted one's place.
        let sameName = snapshot.skillEntries(named: entry.name).filter { $0.path != entry.path }
        if !sameName.isEmpty {
            issues.append(
                Issue(
                    .duplicateName, .warning, L("Another folder is named “\(entry.name)” too"),
                    detail: L(
                        "\(Localization.list(sameName.map { ab($0.path) })) stays, and agents may keep loading a skill by that name. Its assignments are cleared either way."
                    ),
                    paths: sameName.map(\.path), key: entry.name))
        }
        plan.issues += issues
        return plan
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
