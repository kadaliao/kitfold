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
                guard let entry = snapshot.skill(named: name) else {
                    plan.issues.append(
                        Issue(
                            .missingResource, .error, "Skill “\(name)” isn't in the library",
                            detail: "It's assigned to \(a.name) but no folder with that name was found.",
                            agent: a.id, scope: scope, key: name))
                    continue
                }
                if case .bundled = entry.origin {
                    plan.issues.append(
                        Issue(
                            .unsupported, .info, "“\(name)” comes from a plugin",
                            detail: "Plugin skills are managed by the agent's plugin system.", agent: a.id, scope: scope, key: name))
                    continue
                }
                let same = exposures.filter { $0.observed.realPath == entry.path }
                if same.contains(where: \.isActive) { continue }  // already visible
                if willBeVisible(entry, to: a, scope: scope, given: plan) { continue }  // via a link planned for another agent
                if let blocked = same.first, case .disabled(let source) = blocked.observed.native {
                    plan.issues.append(
                        Issue(
                            .disabledNatively, .warning, "“\(name)” is switched off in \(a.name)'s settings",
                            detail: "\(source) disables it. Remove that entry to let \(a.name) load it.",
                            paths: [blocked.observed.entryPath], agent: a.id, scope: scope, key: name))
                    continue
                }
                guard let dir = a.primarySkillDir(scope, env) else {
                    plan.issues.append(
                        Issue(
                            .unsupported, .warning, "\(a.name) has no \(scope.isGlobal ? "global" : "project") skills folder",
                            agent: a.id, scope: scope, key: name))
                    continue
                }
                let linkPath = dir + "/" + linkName(entry)
                let why = via.map { "via profile “\($0)”" } ?? "assigned"
                let others = exposures.filter { $0.observed.realPath != entry.path }
                let note =
                    others.isEmpty
                    ? nil
                    : "Another “\(name)” is also visible: \(others.map { ab($0.observed.entryPath) }.joined(separator: ", "))"
                switch removed.contains(linkPath) ? FS.Kind.missing : FS.kind(linkPath) {
                case .missing:
                    plan.changes.append(
                        PlannedChange(
                            .createSymlink(path: linkPath, target: entry.path),
                            summary: "Link \(name) for \(a.name) (\(why))", agents: [a.id], scope: scope, resource: ref, note: note))
                case .symlink(let raw):
                    let dest = FS.absolute(raw, relativeTo: dir)
                    let owned = snapshot.ownedPaths.contains(linkPath)
                    plan.changes.append(
                        PlannedChange(
                            .removeSymlink(path: linkPath, target: raw),
                            summary: "Replace link \(linkName(entry)) for \(a.name)", agents: [a.id], scope: scope, resource: ref,
                            risk: owned ? .safe : .caution, note: "Currently points to \(ab(dest))"))
                    plan.changes.append(
                        PlannedChange(
                            .createSymlink(path: linkPath, target: entry.path),
                            summary: "Link \(name) for \(a.name) (\(why))", agents: [a.id], scope: scope, resource: ref))
                case .directory, .file:
                    plan.issues.append(
                        Issue(
                            .conflict, .error, "A folder named “\(linkName(entry))” already exists for \(a.name)",
                            detail:
                                "\(ab(linkPath)) isn't managed by Kitfold, so it won't be replaced. Import it into the library or rename one of them.",
                            paths: [linkPath], agent: a.id, scope: scope, key: name))
                }

            case .off:
                for e in exposures where e.isActive || !e.inherited {
                    let o = e.observed
                    if e.inherited {
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, "“\(name)” stays visible to \(a.name) in this project",
                                detail: "It's enabled globally (\(ab(o.entryPath))). \(disableHint(a))",
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                        continue
                    }
                    switch e.via {
                    case .link(let owned):
                        plan.changes.append(
                            PlannedChange(
                                .removeSymlink(path: o.entryPath, target: rawLink(o.entryPath)),
                                summary: "Unlink \(name) from \(a.name)", agents: [a.id], scope: scope, resource: ref,
                                risk: owned ? .safe : .caution,
                                note: owned ? nil : "This link wasn't created by Kitfold (another tool or by hand). Undo restores it."))
                    case .localFolder:
                        plan.issues.append(
                            Issue(
                                .conflict, .warning, "“\(name)” is a real folder in \(a.name)'s skills",
                                detail:
                                    "\(ab(o.entryPath)) isn't a link, so Kitfold won't delete it. Import it into the library first, then it can be switched off.",
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    case .sharedDir:
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, "“\(name)” stays visible to \(a.name)",
                                detail:
                                    "It lives in \(ab(o.root.path)), which \(a.name) reads directly. Move it into the Kitfold library to control it per agent. \(disableHint(a))",
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    case .foreignDir(let owner):
                        let ownerName = owner.flatMap { snapshot.agent($0)?.adapter.name } ?? "another agent"
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, "“\(name)” stays visible to \(a.name)",
                                detail: "\(a.name) also reads \(ownerName)'s folder \(ab(o.root.path)). \(disableHint(a))",
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    case .bundled:
                        plan.issues.append(
                            Issue(
                                .unsupported, .info, "“\(name)” comes from a plugin",
                                detail: "Disable the plugin in \(a.name) instead.", agent: a.id, scope: scope, key: name))
                    case .nested(let parent):
                        plan.issues.append(
                            Issue(
                                .stillVisible, .warning, "“\(name)” stays visible to \(a.name)",
                                detail:
                                    "It's a SKILL.md nested inside “\(parent)” (\(ab(o.entryPath))), and \(a.name) loads nested skills on its own. Switch off “\(parent)”, or move the inner file out. \(disableHint(a))",
                                paths: [o.entryPath], agent: a.id, scope: scope, key: name))
                    }
                }

            case nil:
                // No intent left: take back only what Kitfold itself deployed.
                for o in ownedHere where o.name == name {
                    plan.changes.append(
                        PlannedChange(
                            .removeSymlink(path: o.entryPath, target: rawLink(o.entryPath)),
                            summary: "Unlink \(name) from \(a.name) (no longer assigned)", agents: [a.id], scope: scope, resource: ref))
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

    func disableHint(_ a: AgentAdapter) -> String {
        switch a.descriptor.skillDisable {
        case .none: return ""
        case .claudeSettings: return "Claude Code can also hide it with `skillOverrides` in settings (coming to Kitfold)."
        case .codexConfig: return "Codex can also hide it with `[[skills.config]] enabled = false` (coming to Kitfold)."
        case .openCodePermission: return "OpenCode can also deny it via `permission.skill` (coming to Kitfold)."
        case .geminiSettings: return "Gemini CLI can also disable it in settings (coming to Kitfold)."
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
            guard let file = agent.adapter.primaryInstructionFile(scope, env) else { continue }
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
                    .missingResource, .error, "Profile “\(r.resource.id)” doesn't exist",
                    detail: "Remove the assignment or restore the profile file.", scope: scope, key: r.resource.id))
        }

        for (file, target) in targets.sorted(by: { $0.key < $1.key }) {
            let profiles = target.profiles.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            let current = FS.read(file)
            let existing = ManagedBlock.findAll(in: current ?? "")
            if profiles.isEmpty && existing.isEmpty { continue }

            if let real = FS.realPath(file), FS.isInside(real, env.kitfoldHome) {
                plan.issues.append(
                    Issue(
                        .conflict, .error, "\(ab(file)) points into Kitfold's library",
                        detail: "Writing it would feed Kitfold's output back into its own source. Replace the link with a regular file.",
                        paths: [file], scope: scope))
                continue
            }
            let drifted = existing.filter(\.isModifiedOutsideKitfold)
            if !drifted.isEmpty && !overwriteDrift.contains(file) {
                plan.issues.append(
                    Issue(
                        .blockDrift, .error, "\((file as NSString).lastPathComponent) was edited outside Kitfold",
                        detail:
                            "Profile block(s) \(drifted.map { "“\($0.profile)”" }.joined(separator: ", ")) in \(ab(file)) changed by hand. Keep the edit (copy it into the profile) or overwrite it.",
                        paths: [file], scope: scope, key: file))
                continue
            }

            let newText = ManagedBlock.apply(profiles.map { ($0.id, $0.body) }, to: current ?? "")
            var after: String? = newText
            if newText.isEmpty {
                // Only delete files Kitfold created; never empty a user's file silently.
                if current == nil { continue }
                if snapshot.ownedPaths.contains(file) { after = nil }
            }
            if after == current { continue }

            let names = profiles.map(\.name).joined(separator: ", ")
            let agentNames = target.agents.compactMap { snapshot.agent($0)?.adapter.name }.joined(separator: ", ")
            let summary: String
            if profiles.isEmpty {
                summary = "Remove Kitfold profiles from \(ab(file))"
            } else if current == nil {
                summary = "Create \(ab(file)) with \(names)"
            } else {
                summary = "Update \(names) in \(ab(file))"
            }
            plan.changes.append(
                PlannedChange(
                    .writeFile(path: file, before: current, after: after), summary: summary, agents: target.agents, scope: scope,
                    resource: profiles.count == 1 ? ResourceRef(.profile, profiles[0].id) : nil,
                    risk: drifted.isEmpty ? .safe : .caution,
                    note: drifted.isEmpty ? (agentNames.isEmpty ? nil : "Read by \(agentNames)") : "Overwrites edits made outside Kitfold"))

            // Agents sharing this target file get the union, even profiles they weren't assigned.
            let all = Set(profiles.map(\.id))
            for (agentID, mine) in target.wanted.sorted(by: { $0.key < $1.key }) where mine != all && !all.isEmpty {
                let extra = profiles.filter { !mine.contains($0.id) }.map(\.name).joined(separator: ", ")
                let name = snapshot.agent(agentID)?.adapter.name ?? agentID.rawValue
                plan.issues.append(
                    Issue(
                        .sharedInstructionFile, .warning, "\(name) also reads \((file as NSString).lastPathComponent)",
                        detail: "\(ab(file)) is shared, so \(name) will see \(extra) too. Agents can't be isolated within one file.",
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
                            .sharedInstructionFile, .warning, "\(other.adapter.name) also reads \((file as NSString).lastPathComponent)",
                            detail:
                                "\(ab(file)) is shared, so \(other.adapter.name) will see \(names) too. Agents can't be isolated within one file.",
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
                                "\(ag.adapter.name) will stop reading \((f.file.path as NSString).lastPathComponent)",
                                detail:
                                    "Today \(ag.adapter.name) falls back to \(ab(f.file.path)) because \(ab(file)) doesn't exist. Creating it changes that.",
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
                        summary: "Keep Kitfold's files in \(project.name) out of git", agents: [], scope: .project(root),
                        note: ".git/info/exclude is local to this clone and never committed."))
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
