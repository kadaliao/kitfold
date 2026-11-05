import Foundation

/// Pass 3 of the planner: hide (or un-hide) skills through each agent's own settings when links
/// alone can't do it — a skill in a shared folder, in another agent's folder, nested in another
/// skill, or enabled globally but switched off for one project.
///
/// The entries Kitfold owns in a settings file are recomputed from the rules every time, so a
/// cleared rule takes its entry back. Entries written by the user are left alone, except when an
/// explicit rule asks for the opposite (flagged as caution, and undoable).
extension Planner {
    /// Somewhere an agent will find a skill after this plan's link changes.
    struct NativeCandidate {
        var name: String
        var realPath: String
        var skillFile: String { realPath + "/SKILL.md" }
    }

    func planNativeSettings(_ plan: inout Plan) {
        var removed = Set<String>()
        var created: [(path: String, target: String)] = []
        for c in plan.changes {
            switch c.change {
            case .removeSymlink(let p, _): removed.insert(p)
            case .createSymlink(let p, let t): created.append((p, FS.standardize(t)))
            default: break
            }
        }
        for agent in snapshot.managedAgents where hasNativeSwitch(agent.adapter) {
            // A project inherits the global settings this plan is about to write.
            var written: [String: String?] = [:]
            for scope in snapshot.scopes {
                planNativeSettings(agent, scope, removed: removed, created: created, written: &written, &plan)
            }
        }
    }

    func nativeCandidates(
        _ name: String, _ agent: AgentState, _ scope: Scope, removed: Set<String>, created: [(path: String, target: String)]
    )
        -> [NativeCandidate]
    {
        var out: [NativeCandidate] = []
        for e in snapshot.exposures(skill: name, agent: agent.id, scope: scope)
        where !removed.contains(e.observed.entryPath) && e.observed.name == name {
            if case .bundled = e.via { continue }
            if let real = e.observed.realPath { out.append(NativeCandidate(name: e.observed.name, realPath: real)) }
        }
        var dirs = Set(agent.adapter.skillRoots(scope, env).map(\.path))
        if !scope.isGlobal { dirs.formUnion(agent.adapter.skillRoots(.global, env).map(\.path)) }
        for (p, t) in created where dirs.contains((p as NSString).deletingLastPathComponent) {
            if let entry = snapshot.catalog.first(where: { $0.path == t }), entry.name == name {
                out.append(NativeCandidate(name: name, realPath: t))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.realPath).inserted }
    }

    func planNativeSettings(
        _ agent: AgentState, _ scope: Scope, removed: Set<String>, created: [(path: String, target: String)],
        written: inout [String: String?], _ plan: inout Plan
    ) {
        let a = agent.adapter
        let m = a.descriptor.skillDisable
        let ledger = snapshot.ownedSettings
        let target = NativeSettings.target(a, scope, env)
        func read(_ f: String) -> String? {
            if let w = written[f] { return w }
            return FS.read(f)
        }
        let current = target.flatMap { read($0.file) }
        let policy = NativePolicy.load(adapter: a, scope: scope, env: env, ledger: ledger, read: read)
        // How the agent would see things if Kitfold had never written to this file.
        let base = policy.removing { $0.file == target?.file && $0.isOwned(by: ledger) }
        let owned = policy.rules.filter { $0.file == target?.file && $0.isOwned(by: ledger) }

        var desired: [String: NativeEntry] = [:]
        /// The user's entries that block an explicit "on" (removed).
        var userRemovals: [NativeRule] = []
        /// The user's entries for a key Kitfold now sets to "off" (replaced).
        var replaced: [NativeRule] = []
        var issues: [Issue] = []

        var names = Set(config.rules.filter { $0.resource.kind == .skill && $0.scope == scope }.map(\.resource.id))
        for p in snapshot.profiles where config.state(ResourceRef(.profile, p.id), agent: a.id, scope: scope) == .on {
            names.formUnion(p.skills)
        }
        for name in names.sorted() {
            guard let state = desiredSkill(name, agent: a.id, scope: scope).state else { continue }
            let candidates = nativeCandidates(name, agent, scope, removed: removed, created: created)
            switch state {
            case .off:
                let active = candidates.filter { !base.state(name: $0.name, skillFile: $0.skillFile).isDisabled }
                guard !active.isEmpty else { continue }
                guard target != nil else {
                    issues.append(
                        Issue(
                            .stillVisible, .warning, L("“\(name)” stays visible to \(a.name) in this project"),
                            detail: cantHideHere(a), paths: active.map(\.realPath), agent: a.id, scope: scope, key: name))
                    continue
                }
                for c in (m == .codexConfig ? active : [active[0]]) {
                    guard let e = NativeSettings.hideEntry(m, name: name, skillFile: c.skillFile) else { continue }
                    desired[e.key] = e
                    // The user's own entry for the same key with another value (e.g. `"on"`) is replaced.
                    if let mine = base.rules.last(where: { $0.file == target?.file && $0.key == e.key }) { replaced.append(mine) }
                }

            case .on:
                guard let entry = snapshot.skill(named: name) else { continue }
                if case .bundled = entry.origin { continue }
                let mine = candidates.filter { $0.realPath == entry.path }
                guard let first = mine.first,
                    !mine.contains(where: { !base.state(name: $0.name, skillFile: $0.skillFile).isDisabled })
                else { continue }
                var remaining = base
                var fixed = false
                // Up to two rules can stand in the way (an exact entry, then a broader one).
                for _ in 0..<3 {
                    guard let rule = remaining.rule(name: first.name, skillFile: first.skillFile), rule.state.isDisabled else {
                        fixed = true
                        break
                    }
                    if let t = target, rule.file == t.file, isExact(rule, name: first.name, skillFile: first.skillFile) {
                        userRemovals.append(rule)
                        remaining = remaining.removing { $0 == rule }
                        continue
                    }
                    if let t = target, t.canForceOn, let e = NativeSettings.showEntry(m, name: first.name) {
                        desired[e.key] = e
                        fixed = true
                    }
                    break
                }
                if !fixed {
                    let blocker = remaining.rule(name: first.name, skillFile: first.skillFile)
                    issues.append(
                        Issue(
                            .disabledNatively, .warning, L("“\(name)” is switched off in \(a.name)'s settings"),
                            detail: cantShow(a, scope: scope, blocker: blocker), paths: [first.realPath], agent: a.id, scope: scope,
                            key: name))
                }
            }
        }
        plan.issues += issues

        guard let target else { return }
        let ownedValues = Dictionary(owned.map { ($0.key, $0.value) }, uniquingKeysWith: { _, b in b })
        let dropOwned = owned.filter { desired[$0.key]?.value != $0.value }
        // Codex keeps Kitfold's entries in its own section, so a replaced user entry is removed.
        let userRemovalKeys = Set(userRemovals.map(\.key) + (m == .codexConfig ? replaced.map(\.key) : []))
        let additions = desired.values.filter { ownedValues[$0.key] != $0.value }.sorted()
        if dropOwned.isEmpty && userRemovalKeys.isEmpty && additions.isEmpty { return }

        // Edit the text: only the entries involved change.
        var text = current
        do {
            if m == .codexConfig {
                if CodexConfig.conflictsWithArrayTables(current ?? "") && !desired.isEmpty {
                    plan.issues.append(
                        Issue(
                            .unsupported, .warning, L("Kitfold can't add skill settings to \(ab(target.file))"),
                            detail: L(
                                "The file defines `skills.config` in a form that an appended `[[skills.config]]` table would break. Use `[[skills.config]]` tables there to let Kitfold manage it."
                            ),
                            paths: [target.file], agent: a.id, scope: scope))
                    return
                }
                var t = current ?? ""
                for k in userRemovalKeys.sorted() { t = try NativeSettings.remove(key: k, from: t, m, env: env) }
                let paths = desired.values.map { String($0.key.dropFirst("skills.config/path:".count)) }
                t = CodexConfig.withBlock(t, paths: paths, env: env)
                text = t
            } else {
                var t = current ?? ""
                for r in dropOwned where desired[r.key] == nil { t = try NativeSettings.remove(key: r.key, from: t, m, env: env) }
                for k in userRemovalKeys.sorted() { t = try NativeSettings.remove(key: k, from: t, m, env: env) }
                for e in additions { t = try NativeSettings.set(e, in: t, m) }
                text = t
            }
        } catch {
            plan.issues.append(
                Issue(
                    .unsupported, .warning, L("Kitfold can't read \(ab(target.file))"),
                    detail: L(
                        "It isn't valid \(m == .codexConfig ? "TOML" : "JSON"), so Kitfold won't edit it. Fix the file, then try again."),
                    paths: [target.file], agent: a.id, scope: scope))
            return
        }
        var after = text
        if let t = text, NativeSettings.isEmptyDocument(t, m), current == nil || snapshot.ownedPaths.contains(target.file) {
            after = nil  // only files Kitfold created are deleted
        }
        if after == current { return }
        written[target.file] = .some(after)

        var ownership: [OwnershipEdit] = []
        if m != .codexConfig {
            let ledgerKey = { (k: String) in NativeSettings.ledgerKey(file: target.file, key: k) }
            for r in dropOwned {
                ownership.append(OwnershipEdit(key: ledgerKey(r.key), value: r.value, skill: "", ownedBefore: true, ownedAfter: false))
            }
            for e in additions {
                ownership.append(OwnershipEdit(key: ledgerKey(e.key), value: e.value, skill: e.skill, ownedBefore: false, ownedAfter: true))
            }
        }
        let hidden = additions.filter(\.hides).map(\.skill)
        let unhidden = dropOwned.filter { desired[$0.key] == nil && NativeEntry(key: $0.key, value: $0.value, skill: "").hides }
        let shown =
            (unhidden + userRemovals).map { skillName(forKey: $0.key) } + additions.filter { !$0.hides }.map(\.skill)
        let summary: String
        switch (hidden.isEmpty, shown.isEmpty) {
        case (false, false): summary = L("Hide \(list(Set(hidden))) from \(a.name); Let \(a.name) load \(list(Set(shown))) again")
        case (false, true): summary = L("Hide \(list(Set(hidden))) from \(a.name)")
        case (true, false): summary = L("Let \(a.name) load \(list(Set(shown))) again")
        case (true, true): summary = L("Update \(a.name)'s skill settings")
        }

        let changesUserEntry = !userRemovals.isEmpty || !replaced.isEmpty
        let maybeCommitted = !scope.isGlobal && current != nil && m != .claudeSettings
        let note: String?
        switch (changesUserEntry, maybeCommitted) {
        case (true, true):
            note = L(
                "Changes an entry Kitfold didn't write. Undo restores it. If this file is committed, everyone using the repository gets this setting."
            )
        case (true, false): note = L("Changes an entry Kitfold didn't write. Undo restores it.")
        case (false, true): note = L("If this file is committed, everyone using the repository gets this setting.")
        case (false, false): note = nil
        }
        plan.changes.append(
            PlannedChange(
                .writeFile(path: target.file, before: current, after: after), summary: summary, agents: [a.id],
                scope: scope, resource: (hidden + shown).count == 1 ? ResourceRef(.skill, (hidden + shown)[0]) : nil,
                risk: userRemovals.isEmpty && replaced.isEmpty ? .safe : .caution, note: note,
                details: NativeSettings.semanticDiff(a, file: target.file, before: current, after: after, env: env),
                ownership: ownership))
    }

    /// The skill an entry is about (Codex entries name a SKILL.md path).
    func skillName(forKey key: String) -> String {
        let prefix = "skills.config/path:"
        guard key.hasPrefix(prefix) else { return NativeSettings.name(key).replacingOccurrences(of: "name:", with: "") }
        let dir = (String(key.dropFirst(prefix.count)) as NSString).deletingLastPathComponent
        return snapshot.catalog.first { $0.path == dir }?.name ?? (dir as NSString).lastPathComponent
    }

    func list(_ names: Set<String>) -> String {
        let sorted = names.sorted()
        return sorted.count <= 3 ? sorted.joined(separator: ", ") : sorted.prefix(3).joined(separator: ", ") + " +\(sorted.count - 3)"
    }

    /// The rule names exactly this skill (not a wildcard or "everything").
    func isExact(_ rule: NativeRule, name: String, skillFile: String) -> Bool {
        switch rule.match {
        case .name(let n): return n == name || n == name.lowercased()
        case .path(let p): return p == skillFile
        case .pattern(let p): return p == name
        case .all: return false
        }
    }

    func cantHideHere(_ a: AgentAdapter) -> String {
        switch a.descriptor.skillDisable {
        case .codexConfig:
            return L(
                "It's enabled globally, and Codex reads `[[skills.config]]` only from $CODEX_HOME/config.toml, so a skill can't be hidden in one project alone. Switch it off globally instead."
            )
        default: return L("\(a.name) has no per-project setting for this.")
        }
    }

    func cantShow(_ a: AgentAdapter, scope: Scope, blocker: NativeRule?) -> String {
        guard let b = blocker else { return L("Its settings switch it off.") }
        if b.match == .all { return L("\(ab(b.file)) switches off every skill (`\(b.key)`). Change that setting to load skills.") }
        if !scope.isGlobal, a.descriptor.skillDisable == .geminiSettings || a.descriptor.skillDisable == .codexConfig {
            return L(
                "\(ab(b.file)) switches it off for every project, and \(a.name) can't switch it back on for one project. Switch it on globally instead."
            )
        }
        return L("\(ab(b.file)) switches it off. Remove that entry to let \(a.name) load it.")
    }
}
