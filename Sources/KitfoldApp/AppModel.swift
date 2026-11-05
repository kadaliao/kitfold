import AppKit
import Foundation
import KitfoldCore
import Observation

enum SidebarItem: Hashable {
    case dashboard
    case skills
    case profiles
    case agent(AgentID)
    case project(String)
    case history
}

/// What a matrix cell shows for (skill, agent, scope).
struct CellState: Equatable {
    enum Reach: Equatable {
        case off
        case kitfoldLink
        case otherLink
        case localFolder
        case shared  // lives in a dir the agent reads directly
        case viaOtherAgent  // OpenCode via ~/.claude/skills
        case plugin
        case inherited  // project view: comes from global
        case nested  // SKILL.md inside another skill's folder
        case disabledNatively
    }
    var reach: Reach
    /// Explicit rule in the draft (nil = no opinion).
    var rule: RuleState?
    /// Draft differs from saved config for this cell.
    var pending: Bool
    /// Why the cell's rule can't take effect (e.g. Codex can't hide a global skill in one project).
    var blocked: String? = nil

    var isOn: Bool {
        switch reach {
        case .off, .disabledNatively: return false
        default: return true
        }
    }
    /// What the user will get after applying the draft (best effort, for display).
    var willBeOn: Bool { rule.map { $0 == .on } ?? isOn }
}

@MainActor
@Observable
final class AppModel {
    private(set) var workspace: Workspace?
    private(set) var snapshot: Snapshot?
    /// Edited intent. Both "skill → agents" and "agent → skills" views write here.
    var draft = KitfoldConfig()
    private(set) var plan: Plan?
    var isScanning = false
    var isPlanning = false
    var errorMessage: String?
    var toast: String?
    /// The language Kitfold's text is in. Views rebuild when it changes.
    private(set) var language = Localization.language

    var selection: SidebarItem? = .dashboard
    var selectedSkillPath: String?
    var skillsMatrix = false
    /// The scope the Skills page shows.
    var skillsScope: Scope = .global
    var selectedProfileID: String?
    var showReview = false
    var showPalette = false
    var showNewProfile = false
    var showNewSkill = false
    var editingInstruction: InstructionTarget?
    var reviewPlan: ReviewRequest?

    struct InstructionTarget: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var agents: [AgentID]
        var scope: Scope
    }

    /// A one-off plan (edit a file, adopt a skill, keep an edit) reviewed in the same sheet.
    struct ReviewRequest: Identifiable {
        let id = UUID()
        var title: String
        var plan: Plan
        var summary: String
    }

    /// The draft's rules differ from the saved ones: there's something to discard.
    var hasDraftEdits: Bool {
        guard let ws = workspace else { return false }
        return Set(draft.rules) != Set(ws.config.rules)
    }

    /// Something to apply: edited rules, or files that no longer match the saved ones
    /// (an assigned profile was edited, a link was deleted by hand…).
    var hasPendingChanges: Bool { hasDraftEdits || pendingCount > 0 }

    var pendingCount: Int { plan?.fileChanges.count ?? 0 }

    // MARK: lifecycle

    func load() {
        do {
            let ws = try Workspace()
            workspace = ws
            draft = ws.config
            if ws.isFirstRun { toast = L("Welcome. Kitfold only read your setup — nothing has been changed.") }
            rescan()
        } catch {
            errorMessage = L("Couldn't open Kitfold's data folder: \(error.localizedDescription)")
        }
    }

    /// A rescan asked for while one is running (e.g. right after an apply) runs once it finishes,
    /// so the app never settles on a snapshot taken before the change.
    private var rescanQueued = false

    func rescan(probeVersions: Bool = true) {
        guard let ws = workspace else { return }
        syncConfigFromDisk()
        lastSeenTransaction = ws.history(limit: 1).first?.id
        if isScanning {
            rescanQueued = true
            return
        }
        isScanning = true
        let config = draft
        Task.detached(priority: .userInitiated) {
            let snap = Scanner(env: ws.env, adapters: ws.adapters).scan(
                config: config, ownedPaths: ws.store.ownedPaths(), ownedSettings: ws.store.ownedSettings(), probeVersions: probeVersions)
            await MainActor.run {
                self.isScanning = false
                if self.rescanQueued {
                    self.rescanQueued = false
                    self.rescan(probeVersions: false)
                    return
                }
                self.snapshot = snap
                self.replan()
            }
        }
    }

    /// Recompute the plan for the current draft (cheap; reads only files that may change).
    /// Only the newest plan request may publish its result: quick successive toggles start
    /// overlapping tasks, and an older one finishing last must not overwrite a newer plan.
    private var planGeneration = 0

    func replan() {
        guard let ws = workspace, let snap = snapshot else { return }
        // kitfold.json changed elsewhere: the snapshot may be stale too (the CLI made links).
        if syncConfigFromDisk() {
            rescan(probeVersions: false)
            return
        }
        let draft = self.draft
        let saved = ws.config  // read here, on the main actor; the workspace isn't thread-safe
        planGeneration += 1
        let generation = planGeneration
        isPlanning = true
        Task.detached(priority: .userInitiated) {
            let p = ws.plan(draft, snapshot: snap, current: saved)
            await MainActor.run {
                guard generation == self.planGeneration else { return }
                self.plan = p
                self.isPlanning = false
            }
        }
    }

    /// The newest transaction when the app last scanned: another one means the CLI applied or undid something.
    private var lastSeenTransaction: String?

    /// Coming back to the app: rescan if the CLI (or anything else) changed kitfold.json or applied a change.
    func refreshIfChangedOutside() {
        guard let ws = workspace, snapshot != nil else { return }
        if ws.configChangedOnDisk || ws.history(limit: 1).first?.id != lastSeenTransaction { rescan(probeVersions: false) }
    }

    /// Load kitfold.json again if it changed outside the app (the CLI, an editor), keeping unapplied toggles
    /// on top of it. Without this the next apply would write the old rules back and take back the CLI's links.
    /// Returns true when it reloaded.
    @discardableResult
    func syncConfigFromDisk() -> Bool {
        guard let ws = workspace else { return false }
        do {
            guard let before = try ws.reloadConfigIfChanged() else { return false }
            let pending = Set(draft.rules) != Set(before.rules)
            let (merged, overridden) = ws.config.replaying(rulesOf: draft, since: before)
            draft = merged
            if let p = skillsScope.projectPath, !draft.projects.contains(where: { $0.path == p }) { skillsScope = .global }
            toast =
                !pending
                ? L("kitfold.json changed outside Kitfold. Reloaded it.")
                : overridden == 0
                    ? L("kitfold.json changed outside Kitfold. Reloaded it and kept your unapplied changes.")
                    : L("kitfold.json changed outside Kitfold. Reloaded it; where you both changed a switch, your unapplied change wins.")
            return true
        } catch {
            errorMessage = L(
                "kitfold.json changed outside Kitfold and can't be read: \(error.localizedDescription). Kitfold keeps using the version it had."
            )
            return false
        }
    }

    func discardDraft() {
        guard let ws = workspace else { return }
        draft = ws.config
        replan()
    }

    func applyDraft() {
        guard let ws = workspace, let plan else { return }
        perform(plan, summary: summaryForDraft(), using: ws)
    }

    /// `keepDraft`: a one-off review (edit a file, adopt a skill…) leaves unapplied toggles pending.
    func perform(_ plan: Plan, summary: String, using ws: Workspace? = nil, keepDraft: Bool = false) {
        guard let ws = ws ?? workspace else { return }
        let before = ws.config
        let pending = draft
        do {
            if try ws.apply(plan, summary: summary) != nil {
                let n = plan.fileChanges.count
                toast =
                    n == 0
                    ? L("Saved the assignments. Undo anytime from History.")
                    : n == 1
                        ? L("Applied 1 file change. Undo anytime from History.")
                        : L("Applied \(n) file changes. Undo anytime from History.")
            }
            // A one-off review keeps the toggles that were pending, on top of what was just saved.
            draft = keepDraft ? ws.config.replaying(rulesOf: pending, since: before).config : ws.config
            showReview = false
            reviewPlan = nil
            rescan(probeVersions: false)
        } catch {
            errorMessage = error.localizedDescription
            rescan(probeVersions: false)
        }
    }

    func undo(_ tx: TransactionRecord) {
        guard let ws = workspace else { return }
        do {
            try ws.undo(tx.id)
            draft = ws.config
            toast = L("Undid “\(tx.summary)”.")
            rescan(probeVersions: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func summaryForDraft() -> String {
        guard let ws = workspace else { return L("Apply changes") }
        let before = Set(ws.config.rules)
        let after = Set(draft.rules)
        let added = after.subtracting(before), removed = before.subtracting(after)
        let names = Set((added.union(removed)).map(\.resource.id)).sorted()
        if names.isEmpty {
            // Only files to bring in line with the saved rules, e.g. after editing an assigned profile.
            let files = plan?.fileChanges ?? []
            let profiles = Set(files.compactMap { $0.resource?.kind == .profile ? $0.resource?.id : nil })
            if files.count == 1, let only = files.first { return only.summary }
            if profiles.count == 1, let id = profiles.first {
                return L("Update profile \(snapshot?.profileName(id) ?? id)")
            }
            return L("Apply kitfold.json")
        }
        // One switch flipped: say exactly what it does, as the CLI does.
        let keys = Set(added.union(removed).map { "\($0.resource)|\($0.scope)|\($0.agent)" })
        if keys.count == 1, let r = added.first ?? removed.first {
            let what = r.resource.kind == .profile ? L("profile \(snapshot?.profileName(r.resource.id) ?? r.resource.id)") : r.resource.id
            let state = draft.rule(r.resource, agent: r.agent, scope: r.scope)?.state
            let place = projectName(r.scope)
            guard case .agent(let id) = r.agent else {
                switch (state, r.scope.isGlobal) {
                case (.on, true): return L("Give \(what) to all agents")
                case (.on, false): return L("Give \(what) to all agents in \(place)")
                case (.off, true): return L("Take \(what) from all agents")
                case (.off, false): return L("Take \(what) from all agents in \(place)")
                case (nil, true): return L("Reset \(what) for all agents")
                case (nil, false): return L("Reset \(what) for all agents in \(place)")
                }
            }
            let who = snapshot?.agent(id)?.name ?? id.rawValue
            switch (state, r.scope.isGlobal) {
            case (.on, true): return L("Give \(what) to \(who)")
            case (.on, false): return L("Give \(what) to \(who) in \(place)")
            case (.off, true): return L("Take \(what) from \(who)")
            case (.off, false): return L("Take \(what) from \(who) in \(place)")
            case (nil, true): return L("Reset \(what) for \(who)")
            case (nil, false): return L("Reset \(what) for \(who) in \(place)")
            }
        }
        let head = Localization.list(Array(names.prefix(3)))
        return names.count > 3 ? L("Update \(head) +\(names.count - 3)") : L("Update \(head)")
    }

    // MARK: rule editing (the single source of truth)

    func cell(skill: String, agent: AgentID, scope: Scope) -> CellState {
        let rule = draft.state(ResourceRef(.skill, skill), agent: agent, scope: scope)
        let saved = workspace?.config.state(ResourceRef(.skill, skill), agent: agent, scope: scope)
        guard let snap = snapshot else { return CellState(reach: .off, rule: rule, pending: rule != saved) }
        let entry = snap.skill(named: skill)
        let ex = snap.exposures(skill: skill, agent: agent, scope: scope)
            .filter { entry == nil || $0.observed.realPath == entry?.path || $0.observed.name == skill }
        var reach: CellState.Reach = .off
        if let e = ex.first(where: \.isActive) {
            if e.inherited && !scope.isGlobal {
                reach = .inherited
            } else {
                switch e.via {
                case .link(let owned): reach = owned ? .kitfoldLink : .otherLink
                case .localFolder: reach = .localFolder
                case .sharedDir: reach = .shared
                case .foreignDir: reach = .viaOtherAgent
                case .bundled: reach = .plugin
                case .nested: reach = .nested
                }
            }
        } else if !ex.isEmpty {
            reach = .disabledNatively
        }
        // A rule the plan can't carry out stays in kitfold.json; say so on the cell.
        let blocked =
            rule == nil
            ? nil
            : plan?.issues(about: ResourceRef(.skill, skill), agents: [agent], scope: scope).first { $0.severity >= .warning }
        return CellState(
            reach: reach, rule: rule, pending: rule != saved,
            blocked: blocked.map { [$0.title, $0.detail].filter { !$0.isEmpty }.joined(separator: "\n") })
    }

    /// Plugin skills are owned by the agent's plugin system; assigning them would only leave a dead rule.
    func isPluginSkill(_ skill: String) -> Bool {
        if case .bundled = snapshot?.skill(named: skill)?.origin { return true }
        return false
    }

    func toggle(skill: String, agent: AgentID, scope: Scope) {
        if isPluginSkill(skill) {
            toast = L("“\(skill)” comes from a plugin — switch it in the agent's plugin settings.")
            return
        }
        let c = cell(skill: skill, agent: agent, scope: scope)
        let ref = ResourceRef(.skill, skill)
        let target: RuleState = c.willBeOn ? .off : .on
        // Returning to "what's already on disk" clears the rule instead of pinning it.
        let saved = workspace?.config.state(ref, agent: agent, scope: scope)
        if saved == nil && ((target == .on) == c.isOn) && c.rule != nil {
            draft.setRule(ref, agent: .agent(agent), scope: scope, state: nil)
        } else {
            draft.setRule(ref, agent: .agent(agent), scope: scope, state: target)
        }
        replan()
    }

    /// Skills dropped on an agent: switched on in `scope`; from the sidebar, the scope the Skills page shows.
    func drop(skills names: [String], on agent: AgentState, scope: Scope? = nil) {
        let scope = scope ?? skillsScope
        var added: [String] = []
        for n in names where !isPluginSkill(n) && !cell(skill: n, agent: agent.id, scope: scope).willBeOn {
            toggle(skill: n, agent: agent.id, scope: scope)
            added.append(n)
        }
        let who = agent.adapter.name
        if added.isEmpty {
            toast = L("\(who) already has \(Localization.list(names)).")
        } else if scope.isGlobal {
            toast = L("Added \(Localization.list(added)) to \(who) — review to apply.")
        } else {
            toast = L("Added \(Localization.list(added)) to \(who) in \(projectName(scope)) — review to apply.")
        }
    }

    func setAll(skill: String, scope: Scope, on: Bool) {
        guard !isPluginSkill(skill) else { return }
        draft.setAll(ResourceRef(.skill, skill), scope: scope, state: on ? .on : .off)
        replan()
    }

    func profileState(_ id: String, agent: AgentID, scope: Scope) -> (on: Bool, pending: Bool) {
        let ref = ResourceRef(.profile, id)
        let d = draft.state(ref, agent: agent, scope: scope) == .on
        let s = workspace?.config.state(ref, agent: agent, scope: scope) == .on
        return (d, d != s)
    }

    func toggleProfile(_ id: String, agent: AgentID, scope: Scope) {
        let ref = ResourceRef(.profile, id)
        let on = draft.state(ref, agent: agent, scope: scope) == .on
        draft.setRule(ref, agent: .agent(agent), scope: scope, state: on ? nil : .on)
        replan()
    }

    // MARK: library actions

    var profiles: [ProfileEntry] { snapshot?.profiles ?? [] }

    func createProfile(name: String, description: String) {
        guard let ws = workspace else { return }
        do {
            let p = try ws.library.createProfile(name: name, description: description)
            selectedProfileID = p.id
            selection = .profiles
            rescan(probeVersions: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func saveProfile(_ p: ProfileEntry, renamedFrom oldID: String? = nil) {
        guard let ws = workspace else { return }
        do {
            try ws.saveProfile(p)
            toast = L("Saved “\(p.name)”. Agents using it are updated when you apply.")
            rescan(probeVersions: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteProfile(_ id: String) {
        guard let ws = workspace else { return }
        do {
            try ws.library.trashProfile(id: id)
            draft.removeRules(for: ResourceRef(.profile, id))
            selectedProfileID = nil
            toast = L("Profile moved to Kitfold's trash. Apply to remove it from agents.")
            rescan(probeVersions: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func createSkill(name: String, description: String) {
        guard let ws = workspace else { return }
        do {
            let dir = try ws.library.createSkill(name: name, description: description)
            selectedSkillPath = FS.realPath(dir) ?? dir
            selection = .skills
            rescan(probeVersions: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func importSkillFolder(_ url: URL) {
        guard let ws = workspace else { return }
        do {
            let dir = try ws.library.importFolder(url.path)
            selectedSkillPath = FS.realPath(dir) ?? dir
            toast = L("Copied into the library. The original folder is untouched.")
            rescan(probeVersions: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func addGitSource(_ url: String) {
        guard let ws = workspace else { return }
        Task.detached {
            do {
                let source = try ws.library.cloneGitSource(url: url)
                await MainActor.run {
                    self.saveSettings { $0.sources.append(source) }
                    self.toast = L("Added \(source.label) as a skill source.")
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func addSourceFolder(_ url: URL) {
        guard let ws = workspace else { return }
        let id = "folder-" + SkillEntry.slugify(url.lastPathComponent)
        saveSettings { c in
            guard !c.sources.contains(where: { $0.id == id }) else { return }
            c.sources.append(SkillSourceConfig(id: id, label: url.lastPathComponent, path: ws.env.abbreviate(url.path)))
        }
    }

    func removeSource(_ id: String) {
        saveSettings { $0.sources.removeAll { $0.id == id } }
    }

    /// Settings that don't touch agent files (sources, projects, agents, preferences), saved right away.
    /// `edit` changes kitfold.json as it is on disk now, so an edit made by the CLI meanwhile isn't lost.
    func saveSettings(_ edit: (inout KitfoldConfig) -> Void) {
        guard let ws = workspace else { return }
        syncConfigFromDisk()
        do {
            var c = ws.config
            edit(&c)
            c.rules = ws.config.rules  // never smuggle draft rules past the review
            try ws.saveConfigDirectly(c)
            draft.sources = ws.config.sources
            draft.agents = ws.config.agents
            draft.preferences = ws.config.preferences
            draft.projects = ws.config.projects
            rescan()
        } catch { errorMessage = error.localizedDescription }
    }

    func addProject(_ url: URL) {
        guard let ws = workspace else { return }
        var added: String?
        saveSettings { c in
            c = ws.addingProject(url.path, to: c)
            added = c.projects.last?.path
        }
        if let added { selection = .project(added) }
    }

    func removeProject(_ path: String) {
        guard let ws = workspace else { return }
        syncConfigFromDisk()
        if ws.config.rules.contains(where: { $0.scope == .project(path) }) {
            errorMessage = L(
                "This project still has assignments, including switched-off ones. Clear them (Clear in the row's menu) and apply first, so Kitfold can clean up its files there."
            )
            return
        }
        selection = .dashboard
        if skillsScope == .project(path) { skillsScope = .global }
        saveSettings { $0.projects.removeAll { $0.path == path } }
    }

    func saveSkillFile(_ entry: SkillEntry, text: String) {
        guard let ws = workspace else { return }
        let edit = ws.planSkillEdit(entry, text: text)
        guard !edit.plan.isEmpty else { return }
        perform(edit.plan, summary: edit.summary, keepDraft: true)
    }

    func reviewAdopt(_ entry: SkillEntry) {
        guard let ws = workspace, let snap = snapshot else { return }
        do {
            let p = try ws.planAdopt(entry, snapshot: snap)
            reviewPlan = ReviewRequest(
                title: L("Move “\(entry.name)” into the library"), plan: p, summary: L("Adopt \(entry.name)"))
        } catch { errorMessage = error.localizedDescription }
    }

    func reviewInstructionEdit(_ target: InstructionTarget, newText: String) {
        guard let ws = workspace else { return }
        let p = ws.planEdit(path: target.path, newText: newText, agents: target.agents, scope: target.scope)
        guard !p.isEmpty else { editingInstruction = nil; return }
        reviewPlan = ReviewRequest(
            title: L("Save \((target.path as NSString).lastPathComponent)"), plan: p,
            summary: L("Edit \(ws.env.abbreviate(target.path))"))
    }

    func reviewKeepEdit(file: String, profile: String) {
        guard let ws = workspace, let snap = snapshot else { return }
        do {
            let p = try ws.adoptDrift(file: file, profile: profile, snapshot: snap)
            let name = snap.profileName(profile)
            reviewPlan = ReviewRequest(title: L("Keep the edit to “\(name)”"), plan: p, summary: L("Keep edit to \(name)"))
        } catch { errorMessage = error.localizedDescription }
    }

    func reviewOverwrite(file: String) {
        guard let ws = workspace, let snap = snapshot else { return }
        let p = ws.plan(ws.config, snapshot: snap, overwriteDrift: [file])
        reviewPlan = ReviewRequest(
            title: L("Overwrite the outside edit"), plan: p, summary: L("Overwrite edit in \(ws.env.abbreviate(file))"))
    }

    // MARK: language

    /// nil follows the system. Messages from the core are made during a scan, so this rescans.
    func setLanguage(_ choice: Language?) {
        LanguageSettings.choose(choice)
        Localization.language = choice ?? LanguageSettings.system
        language = Localization.language
        rescan()
    }

    // MARK: helpers

    var env: KitfoldEnvironment? { workspace?.env }
    func ab(_ p: String) -> String { workspace?.env.abbreviate(p) ?? p }
    var agents: [AgentState] { snapshot?.agents ?? [] }
    var managedAgents: [AgentState] { snapshot?.managedAgents ?? [] }
    var scopes: [Scope] { snapshot?.scopes ?? [.global] }

    func projectName(_ scope: Scope) -> String {
        switch scope {
        case .global: return L("Global")
        case .project(let p): return draft.projects.first { $0.path == p }?.name ?? (p as NSString).lastPathComponent
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openInEditor(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func versionHistory(profile id: String) -> [(date: Date, path: String)] { workspace?.profileVersions(id) ?? [] }
    var history: [TransactionRecord] { workspace?.history() ?? [] }
}
