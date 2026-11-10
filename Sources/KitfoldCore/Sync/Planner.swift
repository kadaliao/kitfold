import Foundation

/// Compares the user's intent (`KitfoldConfig` rules) with what's on disk (`Snapshot`) and
/// produces the minimal set of file changes. Pure: reads the snapshot, never touches disk
/// except to read current file contents for diffs.
public struct Planner {
    public var snapshot: Snapshot
    public var config: KitfoldConfig
    /// Instruction files (path) whose externally edited blocks may be overwritten.
    public var overwriteDrift: Set<String>

    public init(snapshot: Snapshot, config: KitfoldConfig, overwriteDrift: Set<String> = []) {
        self.snapshot = snapshot
        self.config = config
        self.overwriteDrift = overwriteDrift
    }

    var env: KitfoldEnvironment { snapshot.env }
    func ab(_ p: String) -> String { env.abbreviate(p) }

    public func plan() -> Plan {
        var plan = Plan()
        // Pass 1: removals. Pass 2: additions, judged on the post-removal state — an agent may only
        // see a skill through a link another agent is about to lose (OpenCode reads ~/.claude/skills).
        for agent in snapshot.managedAgents {
            for scope in snapshot.scopes { planSkills(agent, scope, additions: false, removed: [], &plan) }
        }
        let removed = Set(
            plan.changes.compactMap { c -> String? in
                if case .removeSymlink(let p, _) = c.change { return p }
                return nil
            })
        for agent in snapshot.managedAgents {
            for scope in snapshot.scopes { planSkills(agent, scope, additions: true, removed: removed, &plan) }
        }
        // Pass 3: what links can't hide, the agent's own settings do.
        planNativeSettings(&plan)
        noteSharedFolders(&plan)
        noteMissingSkills(&plan)
        for scope in snapshot.scopes { planProfiles(scope, &plan) }
        planGitExcludes(&plan)
        // Stable, readable order: removals before creations on the same path.
        plan.changes.sort { a, b in
            if a.change.path != b.change.path { return a.change.path < b.change.path }
            if case .removeSymlink = a.change { return true }
            return false
        }
        var seen = Set<String>()
        plan.issues = plan.issues.filter { seen.insert($0.id).inserted }
        return plan
    }

    // MARK: skills

    /// Explicit rule first; otherwise "on" if an assigned profile bundles the skill.
    public func desiredSkill(_ name: String, agent: AgentID, scope: Scope) -> (state: RuleState?, viaProfile: String?) {
        if let s = config.state(ResourceRef(.skill, name), agent: agent, scope: scope) { return (s, nil) }
        for p in snapshot.profiles where p.skills.contains(name) {
            if config.state(ResourceRef(.profile, p.id), agent: agent, scope: scope) == .on { return (.on, p.id) }
        }
        return (nil, nil)
    }

    /// The link's text as stored on disk (may be relative), so undo recreates it exactly.
    func rawLink(_ path: String) -> String {
        if case .symlink(let raw) = FS.kind(path) { return raw }
        return ""
    }

    func linkName(_ e: SkillEntry) -> String { SkillEntry.isValidName(e.name) ? e.name : e.folderName }

    func planSkills(_ agent: AgentState, _ scope: Scope, additions: Bool, removed: Set<String>, _ plan: inout Plan) {
        let a = agent.adapter
        let st = agent.state(scope)
        var names = Set(config.rules.filter { $0.resource.kind == .skill && $0.scope == scope }.map(\.resource.id))
        for p in snapshot.profiles where config.state(ResourceRef(.profile, p.id), agent: a.id, scope: scope) == .on {
            names.formUnion(p.skills)
        }
        let ownedHere = st.skills.filter { $0.root.spec.role == .primary && $0.isSymlink && snapshot.ownedPaths.contains($0.entryPath) }
        names.formUnion(ownedHere.map(\.name))

        for name in names.sorted() {
            let (state, via) = desiredSkill(name, agent: a.id, scope: scope)
            let ref = ResourceRef(.skill, name)
            let exposures = snapshot.exposures(skill: name, agent: a.id, scope: scope)
                .filter { !removed.contains($0.observed.entryPath) }
            if additions != (state == .on) { continue }
            switch state {
            case .on:
                guard let entry = snapshot.skill(named: name) else { continue }  // see noteMissingSkills
                if case .bundled = entry.origin {
                    plan.issues.append(
                        Issue(
                            .unsupported, .info, L("“\(name)” comes from a plugin"),
                            detail: L("Plugin skills are managed by the agent's plugin system."), agent: a.id, scope: scope, key: name))
                    continue
                }
                if let why = a.descriptor.skipReason(entry) {
                    plan.issues.append(
                        Issue(
                            .invalidSkill, .warning, L("\(a.name) can't load “\(name)”"),
                            detail: L("\(why). Fix \(ab(entry.skillFile)) first."), paths: [entry.skillFile], agent: a.id, scope: scope,
                            key: name))
                    continue
                }
                let same = exposures.filter { $0.observed.realPath == entry.path }
                if same.contains(where: \.isActive) { continue }  // already visible
                if willBeVisible(entry, to: a, scope: scope, given: plan) { continue }  // via a link planned for another agent
                if let blocked = same.first, case .disabled(let source, _) = blocked.observed.native {
                    // The settings pass switches it back on, or explains why it can't.
                    if hasNativeSwitch(a) { continue }
                    plan.issues.append(
                        Issue(
                            .disabledNatively, .warning, L("“\(name)” is switched off in \(a.name)'s settings"),
                            detail: L("\(source) disables it. Remove that entry to let \(a.name) load it."),
                            paths: [blocked.observed.entryPath], agent: a.id, scope: scope, key: name))
                    continue
                }
                guard let dir = a.primarySkillDir(scope, env) else {
                    if let own = a.skillRoots(scope, env).first(where: { $0.spec.role == .primary && !$0.spec.followsLinks }) {
                        plan.issues.append(
                            Issue(
                                .unsupported, .warning, L("\(a.name) doesn't load linked skill folders"),
                                detail: L(
                                    "Kitfold gives a skill to an agent by linking it into \(ab(own.path)), and \(a.name) skips links there. Copy the skill's folder there yourself to give it “\(name)”."
                                ),
                                agent: a.id, scope: scope, key: name))
                        continue
                    }
                    plan.issues.append(
                        Issue(
                            .unsupported, .warning,
                            scope.isGlobal ? L("\(a.name) has no global skills folder") : L("\(a.name) has no project skills folder"),
                            agent: a.id, scope: scope, key: name))
                    continue
                }
                let linkPath = dir + "/" + linkName(entry)
                let linkSummary =
                    via.map { L("Link \(name) for \(a.name) (via profile “\(snapshot.profileName($0))”)") }
                    ?? L("Link \(name) for \(a.name) (assigned)")
                let others = exposures.filter { $0.observed.realPath != entry.path }
                let note =
                    others.isEmpty
                    ? nil
                    : L("Another “\(name)” is also visible: \(Localization.list(others.map { ab($0.observed.entryPath) }))")
                switch removed.contains(linkPath) ? FS.Kind.missing : FS.kind(linkPath) {
                case .missing:
                    plan.changes.append(
                        PlannedChange(
                            .createSymlink(path: linkPath, target: entry.path),
                            summary: linkSummary, agents: [a.id], scope: scope, resource: ref, note: note))
                case .symlink(let raw):
                    let dest = FS.absolute(raw, relativeTo: dir)
                    let owned = snapshot.ownedPaths.contains(linkPath)
                    plan.changes.append(
                        PlannedChange(
                            .removeSymlink(path: linkPath, target: raw),
                            summary: L("Replace link \(linkName(entry)) for \(a.name)"), agents: [a.id], scope: scope, resource: ref,
                            risk: owned ? .safe : .caution, note: L("Currently points to \(ab(dest))")))
                    plan.changes.append(
                        PlannedChange(
                            .createSymlink(path: linkPath, target: entry.path),
                            summary: linkSummary, agents: [a.id], scope: scope, resource: ref))
                case .directory, .file:
                    plan.issues.append(
                        Issue(
                            .conflict, .error, L("A folder named “\(linkName(entry))” already exists for \(a.name)"),
                            detail: L(
                                "\(ab(linkPath)) is a real folder Kitfold didn't create, so it won't be replaced. If it's a copy of this skill, delete it and apply again; otherwise rename one of the two."
                            ),
                            paths: [linkPath], agent: a.id, scope: scope, key: name))
                }

            case .off:
                // A link named `pdf` may hold a skill called something else; that one stays.
                for e in exposures where (e.isActive || !e.inherited) && e.observed.name == name {
                    let o = e.observed
                    // Links Kitfold made here are taken back; anything else (including a global
                    // skill seen from a project) is hidden through the agent's own settings when
                    // it has them — see planNativeSettings.
                    let isPlugin = e.via == .bundled
                    let ownLink = e.via == .link(ownedByKitfold: true) && !e.inherited
                    if hasNativeSwitch(a) && !isPlugin && !ownLink { continue }
                    if e.inherited {
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, L("“\(name)” stays visible to \(a.name) in this project"),
                                detail: L("It's enabled globally (\(ab(o.entryPath)))."),
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                        continue
                    }
                    switch e.via {
                    case .link(let owned):
                        plan.changes.append(
                            PlannedChange(
                                .removeSymlink(path: o.entryPath, target: rawLink(o.entryPath)),
                                summary: L("Unlink \(name) from \(a.name)"), agents: [a.id], scope: scope, resource: ref,
                                risk: owned ? .safe : .caution,
                                note: owned ? nil : L("This link wasn't created by Kitfold (another tool or by hand). Undo restores it.")))
                    case .localFolder:
                        plan.issues.append(
                            Issue(
                                .conflict, .warning, L("“\(name)” is a real folder in \(a.name)'s skills"),
                                detail: L(
                                    "\(ab(o.entryPath)) isn't a link, so Kitfold won't delete it. Move it into the library first (Move into Library on the Skills page), then it can be switched off."
                                ),
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    case .sharedDir:
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, L("“\(name)” stays visible to \(a.name)"),
                                detail: L(
                                    "It lives in \(ab(o.root.path)), which \(a.name) reads directly. Move it into the Kitfold library to control it per agent."
                                ),
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    case .foreignDir(let owner):
                        let folder = ab(o.root.path)
                        let detail =
                            owner.flatMap { snapshot.agent($0)?.adapter.name }.map { L("\(a.name) also reads \($0)'s folder \(folder).") }
                            ?? L("\(a.name) also reads another agent's folder \(folder).")
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, L("“\(name)” stays visible to \(a.name)"),
                                detail: detail,
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    case .bundled:
                        plan.issues.append(
                            Issue(
                                .unsupported, .info, L("“\(name)” comes from a plugin"),
                                detail: L("Disable the plugin in \(a.name) instead."), agent: a.id, scope: scope, key: name))
                    case .nested(let parent):
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, L("“\(name)” stays visible to \(a.name)"),
                                detail: L(
                                    "It's a SKILL.md nested inside “\(parent)” (\(ab(o.entryPath))), and \(a.name) loads nested skills on its own. Switch off “\(parent)”, or move the inner file out."
                                ),
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    }
                }

            case nil:
                // No intent left: take back only what Kitfold itself deployed.
                for o in ownedHere where o.name == name {
                    plan.changes.append(
                        PlannedChange(
                            .removeSymlink(path: o.entryPath, target: rawLink(o.entryPath)),
                            summary: L("Unlink \(name) from \(a.name) (no longer assigned)"), agents: [a.id], scope: scope, resource: ref))
                }
            }
        }
    }

    /// A link planned for another agent lands in a folder this agent also reads
    /// (e.g. Claude's ~/.claude/skills, which OpenCode reads) — no second link needed.
    func willBeVisible(_ entry: SkillEntry, to a: AgentAdapter, scope: Scope, given plan: Plan) -> Bool {
        var dirs = Set(a.skillRoots(scope, env).filter { $0.spec.role != .primary }.map(\.path))
        if !scope.isGlobal { dirs.formUnion(a.skillRoots(.global, env).filter { $0.spec.role != .primary }.map(\.path)) }
        return plan.changes.contains { c in
            guard case .createSymlink(let p, let t) = c.change, FS.standardize(t) == entry.path else { return false }
            return dirs.contains((p as NSString).deletingLastPathComponent)
        }
    }

    func hasNativeSwitch(_ a: AgentAdapter) -> Bool { a.descriptor.skillDisable != .none }

    func projectName(_ scope: Scope) -> String {
        guard let path = scope.projectPath else { return "" }
        return config.projects.first { $0.path == path }?.name ?? (path as NSString).lastPathComponent
    }

    /// A skill given to agents that isn't anywhere: one issue per skill and scope, naming every agent.
    func noteMissingSkills(_ plan: inout Plan) {
        for scope in snapshot.scopes {
            var names = Set(config.rules.filter { $0.resource.kind == .skill && $0.scope == scope }.map(\.resource.id))
            for p in snapshot.profiles { names.formUnion(p.skills) }
            for name in names.sorted() where snapshot.skill(named: name) == nil {
                var agents: [AgentState] = []
                var profiles: [String] = []
                for a in snapshot.managedAgents {
                    let wanted = desiredSkill(name, agent: a.id, scope: scope)
                    guard wanted.state == .on else { continue }
                    agents.append(a)
                    if let id = wanted.viaProfile, !profiles.contains("“\(snapshot.profileName(id))”") {
                        profiles.append("“\(snapshot.profileName(id))”")
                    }
                }
                guard let first = agents.first else { continue }
                let who = Localization.list(agents.map(\.name))
                var detail =
                    scope.isGlobal
                    ? L("It's assigned to \(who) but no folder with that name was found.")
                    : L("It's assigned to \(who) in \(projectName(scope)) but no folder with that name was found.")
                if !profiles.isEmpty {
                    detail = Localization.sentences([detail, L("Profile \(Localization.list(profiles)) includes it.")])
                }
                plan.issues.append(
                    Issue(
                        .missingResource, .error, L("Skill “\(name)” isn't in the library"), detail: detail,
                        agent: first.id, alsoAffects: agents.dropFirst().map(\.id), scope: scope, key: name))
            }
        }
    }

    /// A link Kitfold adds to (or removes from) one agent's folder also changes what an agent that
    /// reads that folder sees — OpenCode reads ~/.claude/skills. Say so when that agent has no rule
    /// of its own for the skill (with a rule, the planner already handles it).
    func noteSharedFolders(_ plan: inout Plan) {
        let created = Set(
            plan.changes.compactMap { c -> String? in
                if case .createSymlink(let p, _) = c.change { return p }
                return nil
            })
        let removed = Set(
            plan.changes.compactMap { c -> String? in
                if case .removeSymlink(let p, _) = c.change { return p }
                return nil
            })
        for c in plan.changes {
            guard let ref = c.resource, ref.kind == .skill, let owner = c.agents.first, c.agents.count == 1 else { continue }
            let adding: Bool
            let path: String
            switch c.change {
            case .createSymlink(let p, _): adding = true; path = p
            case .removeSymlink(let p, _) where !created.contains(p): adding = false; path = p
            default: continue
            }
            let dir = (path as NSString).deletingLastPathComponent
            let ownerName = snapshot.agent(owner)?.adapter.name ?? owner.rawValue
            // Said once, for the scope of the link: projects inherit a global change, and the other
            // agent's own rule (in that project or globally) already decides what it loads.
            let scope = c.scope
            for other in snapshot.managedAgents where other.id != owner {
                guard desiredSkill(ref.id, agent: other.id, scope: scope).state == nil,
                    scope.isGlobal || desiredSkill(ref.id, agent: other.id, scope: .global).state == nil
                else { continue }
                var roots = other.adapter.skillRoots(scope, env)
                if !scope.isGlobal { roots += other.adapter.skillRoots(.global, env) }
                guard roots.contains(where: { $0.path == dir && $0.spec.role != .primary }) else { continue }
                let name = other.adapter.name
                let seen = snapshot.exposures(skill: ref.id, agent: other.id, scope: scope)
                    .filter { $0.isActive && !removed.contains($0.observed.entryPath) }
                if adding && seen.isEmpty {
                    plan.issues.append(
                        Issue(
                            .sharedSkillFolder, .warning,
                            scope.isGlobal
                                ? L("\(name) will load “\(ref.id)” too") : L("\(name) will load “\(ref.id)” too in \(projectName(scope))"),
                            detail: L(
                                "\(name) also reads \(ownerName)'s folder \(ab(dir)). Switch “\(ref.id)” off for \(name) to keep it to \(ownerName)."
                            ),
                            paths: [path], agent: other.id, scope: scope, key: ref.id))
                } else if !adding && seen.isEmpty
                    && snapshot.exposures(skill: ref.id, agent: other.id, scope: scope).contains(where: {
                        $0.isActive && $0.observed.entryPath == path
                    })
                {
                    plan.issues.append(
                        Issue(
                            .sharedSkillFolder, .warning,
                            scope.isGlobal
                                ? L("\(name) will stop loading “\(ref.id)”")
                                : L("\(name) will stop loading “\(ref.id)” in \(projectName(scope))"),
                            detail: L(
                                "\(name) found it only in \(ownerName)'s folder \(ab(dir)). Switch “\(ref.id)” on for \(name) to keep it there."
                            ),
                            paths: [path], agent: other.id, scope: scope, key: ref.id))
                }
            }
        }
    }

    // MARK: profiles

    func planProfiles(_ scope: Scope, _ plan: inout Plan) {
        struct Target {
            var agents: [AgentID] = []
            var profiles: [ProfileEntry] = []
            /// What each agent writing to this file actually asked for.
            var wanted: [AgentID: Set<String>] = [:]
        }
        var targets: [String: Target] = [:]
        for agent in snapshot.managedAgents {
            guard let file = agent.adapter.primaryInstructionFile(scope, env) else {
                // Only a rule naming this agent: a profile for all agents simply leaves it out.
                let named = config.rules.filter {
                    $0.resource.kind == .profile && $0.scope == scope && $0.state == .on && $0.agent == .agent(agent.id)
                }
                for r in named {
                    plan.issues.append(
                        Issue(
                            .unsupported, .warning, L("\(agent.adapter.name) can't get profiles"),
                            detail: L(
                                "Kitfold doesn't know an instruction file that only \(agent.adapter.name) reads, so “\(snapshot.profileName(r.resource.id))” doesn't reach it."
                            ),
                            agent: agent.id, scope: scope, key: r.resource.id))
                }
                continue
            }
            var t = targets[file] ?? Target()
            t.agents.append(agent.id)
            var mine = Set<String>()
            for p in snapshot.profiles where config.state(ResourceRef(.profile, p.id), agent: agent.id, scope: scope) == .on {
                mine.insert(p.id)
                if !t.profiles.contains(where: { $0.id == p.id }) { t.profiles.append(p) }
            }
            t.wanted[agent.id] = mine
            targets[file] = t
        }
        // Files that hold Kitfold blocks but are no longer targeted still need cleaning up.
        for agent in snapshot.managedAgents {
            for f in agent.state(scope).instructions where !f.blocks.isEmpty && targets[f.file.path] == nil {
                targets[f.file.path] = Target(agents: [agent.id])
            }
        }
        // A profile assigned to a missing profile id.
        for r in config.rules
        where r.resource.kind == .profile && r.scope == scope && r.state == .on
            && snapshot.profile(r.resource.id) == nil
        {
            plan.issues.append(
                Issue(
                    .missingResource, .error, L("Profile “\(r.resource.id)” doesn't exist"),
                    detail: L("Remove the assignment or restore the profile file."), scope: scope, key: r.resource.id))
        }

        for (file, target) in targets.sorted(by: { $0.key < $1.key }) {
            let profiles = target.profiles.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            let current = FS.read(file)
            let existing = ManagedBlock.findAll(in: current ?? "")
            if profiles.isEmpty && existing.isEmpty { continue }

            if let real = FS.realPath(file), FS.isInside(real, env.kitfoldHome) {
                plan.issues.append(
                    Issue(
                        .conflict, .error, L("\(ab(file)) points into Kitfold's library"),
                        detail: L("Writing it would feed Kitfold's output back into its own source. Replace the link with a regular file."),
                        paths: [file], scope: scope))
                continue
            }
            let drifted = existing.filter(\.isModifiedOutsideKitfold)
            // The file is left out of this apply (see Plan.notWritten); the rest goes ahead.
            if !drifted.isEmpty && !overwriteDrift.contains(file) {
                let blocks = Localization.list(drifted.map { "“\(snapshot.profileName($0.profile))”" })
                plan.issues.append(
                    Issue(
                        .blockDrift, .warning, L("\(ab(file)) won't be written"),
                        detail: L(
                            "Its block for \(blocks) was edited outside Kitfold. On the agent's page, keep the edit (copy it into the profile) or overwrite it, then apply again."
                        ),
                        paths: [file], scope: scope, key: file))
                continue
            }

            // A file that needs frontmatter keeps it first: Kitfold writes it when it creates the file,
            // and puts blocks after it.
            let header = snapshot.managedAgents.lazy.compactMap { a in
                a.adapter.instructionFiles(scope, self.env).first { $0.path == file && $0.spec.role == .primary }?.spec.header
            }.first
            let blocks = profiles.map { ($0.id, $0.body) }
            var newText: String
            let blank = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let header, let current, current.hasPrefix(header) {
                newText = header + ManagedBlock.apply(blocks, to: String(current.dropFirst(header.count)))
            } else {
                newText = ManagedBlock.apply(blocks, to: blank ? "" : current ?? "")
                if let header, blank, !newText.isEmpty { newText = header + newText }
                if let header, !blank, !profiles.isEmpty {
                    // Someone's own file: Kitfold won't rewrite its top, but the agent may skip it.
                    let wanted = header.split(separator: "\n").filter { $0 != "---" && !$0.isEmpty }.joined(separator: ", ")
                    let who = Localization.list(target.agents.compactMap { snapshot.agent($0)?.adapter.name })
                    plan.issues.append(
                        Issue(
                            .fallbackChange, .warning, L("\(who) may not apply \((file as NSString).lastPathComponent)"),
                            detail: L(
                                "\(ab(file)) already exists and doesn't start with the frontmatter that makes it apply in every session (\(wanted)). Kitfold adds its block anyway; add the frontmatter, or remove the file and apply again so Kitfold creates it."
                            ),
                            paths: [file], agent: target.agents.first, alsoAffects: Array(target.agents.dropFirst()), scope: scope,
                            key: file + "|header"))
                }
            }
            // A file Kitfold made, with nothing but its header left, goes like a file left empty.
            if let header, snapshot.ownedPaths.contains(file),
                newText.trimmingCharacters(in: .whitespacesAndNewlines) == header.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                newText = ""
            }
            var after: String? = newText
            if newText.isEmpty {
                // Only delete files Kitfold created; never empty a user's file silently.
                if current == nil { continue }
                if snapshot.ownedPaths.contains(file) { after = nil }
            }
            if after == current { continue }

            let names = Localization.list(profiles.map(\.name))
            // An override file (Codex's AGENTS.override.md) replaces this one while it isn't empty.
            var overridden: [AgentID] = []
            for agentID in target.agents where !profiles.isEmpty {
                guard let ag = snapshot.agent(agentID),
                    let o = ag.adapter.instructionFiles(scope, env).first(where: {
                        $0.spec.role == .override && $0.related.contains(file)
                            && !(FS.read($0.path) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    })
                else { continue }
                overridden.append(agentID)
                let fileName = (file as NSString).lastPathComponent, overrideName = (o.path as NSString).lastPathComponent
                plan.issues.append(
                    Issue(
                        .fallbackChange, .warning, L("\(ag.adapter.name) won't read \(fileName) while \(overrideName) exists"),
                        detail: L(
                            "\(ab(o.path)) replaces \(ab(file)), so the profile has no effect on \(ag.adapter.name). Empty or remove the override file, or move its text into a profile."
                        ),
                        paths: [o.path, file], agent: agentID, scope: scope, key: o.path))
            }
            let agentNames = Localization.list(
                target.agents.filter { !overridden.contains($0) }.compactMap { snapshot.agent($0)?.adapter.name })
            let summary: String
            if profiles.isEmpty {
                summary = L("Remove Kitfold profiles from \(ab(file))")
            } else if current == nil {
                summary = L("Create \(ab(file)) with \(names)")
            } else {
                summary = L("Update \(names) in \(ab(file))")
            }
            plan.changes.append(
                PlannedChange(
                    .writeFile(path: file, before: current, after: after), summary: summary, agents: target.agents, scope: scope,
                    resource: profiles.count == 1 ? ResourceRef(.profile, profiles[0].id) : nil,
                    risk: drifted.isEmpty ? .safe : .caution,
                    note: drifted.isEmpty
                        ? (agentNames.isEmpty ? nil : L("Read by \(agentNames)")) : L("Overwrites edits made outside Kitfold")))

            // Agents sharing this target file get the union, even profiles they weren't assigned.
            let all = Set(profiles.map(\.id))
            for (agentID, mine) in target.wanted.sorted(by: { $0.key < $1.key }) where mine != all && !all.isEmpty {
                let extra = Localization.list(profiles.filter { !mine.contains($0.id) }.map(\.name))
                let name = snapshot.agent(agentID)?.adapter.name ?? agentID.rawValue
                plan.issues.append(
                    Issue(
                        .sharedInstructionFile, .warning, L("\(name) also reads \((file as NSString).lastPathComponent)"),
                        detail: L("\(ab(file)) is shared, so \(name) will see \(extra) too. Agents can't be isolated within one file."),
                        paths: [file], agent: agentID, scope: scope, key: file))
            }
            // Who else reads this file? They get the same text.
            for other in snapshot.managedAgents where !target.agents.contains(other.id) {
                // After this change: a fallback file is read when none of its "related" files exist.
                let reads = other.adapter.instructionFiles(scope, env).contains { f in
                    guard f.path == file else { return false }
                    return f.spec.role != .fallback || !f.related.contains(where: FS.exists)
                }
                if reads && !profiles.isEmpty {
                    plan.issues.append(
                        Issue(
                            .sharedInstructionFile, .warning, L("\(other.adapter.name) also reads \((file as NSString).lastPathComponent)"),
                            detail: L(
                                "\(ab(file)) is shared, so \(other.adapter.name) will see \(names) too. Agents can't be isolated within one file."
                            ),
                            paths: [file], agent: other.id, scope: scope, key: file))
                }
            }
            // Creating a primary file can switch off a fallback the agent reads today.
            if current == nil {
                for agentID in target.agents {
                    guard let ag = snapshot.agent(agentID) else { continue }
                    for f in ag.state(scope).instructions where f.file.spec.role == .fallback && f.file.related.contains(file) && f.isLoaded
                    {
                        plan.issues.append(
                            Issue(
                                .fallbackChange, .warning,
                                L("\(ag.adapter.name) will stop reading \((f.file.path as NSString).lastPathComponent)"),
                                detail: L(
                                    "Today \(ag.adapter.name) falls back to \(ab(f.file.path)) because \(ab(file)) doesn't exist. Creating it changes that."
                                ),
                                paths: [file, f.file.path], agent: agentID, scope: scope))
                    }
                }
            }
        }
    }

    // MARK: git excludes

    /// Keep Kitfold-created project files out of git via `.git/info/exclude` (local, never committed).
    func planGitExcludes(_ plan: inout Plan) {
        guard config.preferences.gitExcludeProjectFiles else { return }
        for project in config.projects {
            let root = project.path
            let excludeFile = root + "/.git/info/exclude"
            guard FS.isDirectoryFollowing(root + "/.git") else { continue }
            var paths = Set(snapshot.ownedPaths.filter { FS.isInside($0, root) && $0 != excludeFile })
            for c in plan.changes {
                switch c.change {
                case .createSymlink(let p, _) where FS.isInside(p, root): paths.insert(p)
                case .removeSymlink(let p, _): paths.remove(p)
                case .writeFile(let p, nil, .some) where FS.isInside(p, root): paths.insert(p)
                case .writeFile(let p, _, nil): paths.remove(p)
                default: break
                }
            }
            let lines = paths.map { "/" + FS.relativePath(from: root, to: $0) }.sorted()
            let current = FS.read(excludeFile)
            let updated = GitExclude.apply(lines, to: current ?? "")
            if updated != (current ?? "") && !(current == nil && lines.isEmpty) {
                plan.changes.append(
                    PlannedChange(
                        .writeFile(path: excludeFile, before: current, after: updated),
                        summary: L("Keep Kitfold's files in \(project.name) out of git"), agents: [], scope: .project(root),
                        note: L(".git/info/exclude is local to this clone and never committed.")))
            }
        }
    }
}

enum GitExclude {
    static let begin = "# kitfold:begin (managed by Kitfold)"
    static let end = "# kitfold:end"

    static func apply(_ entries: [String], to text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if let s = lines.firstIndex(of: begin), let e = lines[s...].firstIndex(of: end) {
            lines.removeSubrange(s...e)
        }
        while lines.last == "" { lines.removeLast() }
        if !entries.isEmpty { lines += [begin] + entries + [end] }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}
