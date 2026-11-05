import Foundation
import Testing

@testable import KitfoldCore

/// Problems found while trying every feature for the tutorials; each test reproduces the original failure.
@Suite struct TutorialFindingsTests {
    /// The app keeps a draft while the CLI changes kitfold.json; its next apply must not write the old rules back.
    @Test func appPicksUpRulesTheCLIChanged() throws {
        let h = FakeHome()
        h.installAgents()
        let app = try h.workspace()
        _ = try app.library.createSkill(name: "alpha", description: "Alpha")
        _ = try app.library.createSkill(name: "beta", description: "Beta")
        var draft = app.config
        draft.setRule(ResourceRef(.skill, "beta"), agent: .agent(.codex), scope: .global, state: .on)  // not applied yet

        let cli = try h.workspace()
        try cli.assign(ResourceRef(.skill, "alpha"), .agent(.claudeCode), .on)
        #expect(h.kind(".claude/skills/alpha") != .missing)

        #expect(app.configChangedOnDisk)
        let before = try #require(try app.reloadConfigIfChanged())
        #expect(!app.configChangedOnDisk)
        #expect(app.config.state(ResourceRef(.skill, "alpha"), agent: .claudeCode, scope: .global) == .on)
        let merged = app.config.replaying(rulesOf: draft, since: before)
        #expect(merged.overridden == 0)
        #expect(merged.config.state(ResourceRef(.skill, "beta"), agent: .codex, scope: .global) == .on)

        try app.apply(app.plan(merged.config, snapshot: app.snap()), summary: "app")
        #expect(h.kind(".claude/skills/alpha") != .missing)  // the CLI's link stays
        #expect(h.kind(".codex/skills/beta") != .missing)
        #expect(app.config.rules.count == 2)
        #expect(try app.reloadConfigIfChanged() == nil)  // its own writes aren't outside changes
    }

    @Test func replayingCountsRulesBothSidesChanged() {
        let ref = ResourceRef(.skill, "alpha")
        let base = KitfoldConfig()
        var draft = base, outside = base
        draft.setRule(ref, agent: .agent(.codex), scope: .global, state: .on)
        outside.setRule(ref, agent: .agent(.codex), scope: .global, state: .off)
        let merged = outside.replaying(rulesOf: draft, since: base)
        #expect(merged.overridden == 1)
        #expect(merged.config.state(ref, agent: .codex, scope: .global) == .on)
    }
}

extension TutorialFindingsTests {
    /// “Keep edit” used to save the profile while building the preview; cancelling left it changed.
    @Test func keepingAnOutsideEditWaitsForApplyAndUndoes() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Backend", body: "Prefer Go.", skills: [])
        try ws.assign(ResourceRef(.profile, "backend"), .agent(.claudeCode), .on)
        let file = h.path(".claude/rules/kitfold.md")
        h.write(
            ".claude/rules/kitfold.md", h.read(".claude/rules/kitfold.md")!.replacingOccurrences(of: "Prefer Go.", with: "Prefer Rust."))
        let profileFile = ws.library.profilePath(id: "backend")
        let original = FS.read(profileFile)

        let plan = try ws.adoptDrift(file: file, profile: "backend", snapshot: ws.snap())
        #expect(FS.read(profileFile) == original)  // only previewed
        #expect(plan.changes.contains { $0.change.path == profileFile })

        try ws.apply(plan, summary: "keep")
        #expect(ws.library.profiles().first { $0.id == "backend" }?.body == "Prefer Rust.")
        #expect(ManagedBlock.findAll(in: h.read(".claude/rules/kitfold.md")!).first?.isModifiedOutsideKitfold == false)

        try ws.undo(try #require(ws.history().first).id)
        #expect(FS.read(profileFile) == original)
        #expect(ManagedBlock.findAll(in: h.read(".claude/rules/kitfold.md")!).first?.isModifiedOutsideKitfold == true)
    }
}

extension TutorialFindingsTests {
    /// A file with an outside edit is left out of an apply; the plan says so, at the health check's level.
    @Test func fileWithAnOutsideEditIsListedAsNotWritten() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Backend", body: "Prefer Go.", skills: [])
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        try ws.assign(ResourceRef(.profile, "backend"), .agent(.claudeCode), .on)
        h.write(
            ".claude/rules/kitfold.md", h.read(".claude/rules/kitfold.md")!.replacingOccurrences(of: "Prefer Go.", with: "Prefer Rust."))

        let plan = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.codex), .on)
        #expect(plan.notWritten.map(\.paths) == [[h.path(".claude/rules/kitfold.md")]])
        #expect(plan.notWritten.first?.severity == .warning)
        #expect(!plan.otherIssues.contains { $0.kind == .blockDrift })
        #expect(ws.snap().issues.first { $0.kind == .blockDrift }?.severity == .warning)
        #expect(h.kind(".codex/skills/alpha") != .missing)  // the rest was applied
    }
}

extension TutorialFindingsTests {
    /// The CLI refuses a rule that only explains why it can't work: Codex can't hide a global skill in one project.
    @Test func codexProjectOffNamesItsBlocker() throws {
        let h = FakeHome()
        h.installAgents()
        try FileManager.default.createDirectory(atPath: h.path("work/app/.git"), withIntermediateDirectories: true)
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        try ws.assign(ResourceRef(.skill, "alpha"), .agent(.codex), .on)
        let project = Scope.project(h.path("work/app"))
        var draft = ws.config
        draft.projects.append(ProjectConfig(path: h.path("work/app")))
        draft.setRule(ResourceRef(.skill, "alpha"), agent: .agent(.codex), scope: project, state: .off)
        let plan = ws.plan(
            draft,
            snapshot: Scanner(env: h.env, adapters: ws.adapters).scan(
                config: draft, ownedPaths: ws.store.ownedPaths(), ownedSettings: ws.store.ownedSettings(), probeVersions: false))
        #expect(!plan.issues(about: ResourceRef(.skill, "alpha"), agents: [.codex], scope: project).isEmpty)
        #expect(plan.issues(about: ResourceRef(.skill, "alpha"), agents: [.claudeCode], scope: project).isEmpty)
        #expect(!plan.changes.contains { $0.change.path != h.env.configFile })
    }
}

extension TutorialFindingsTests {
    /// “OpenCode will load … too” was repeated for every project, and shown even where OpenCode's own rule decides.
    @Test func sharedFolderNoteIsSaidOncePerScope() throws {
        let h = FakeHome()
        h.installAgents()
        for p in ["work/a", "work/b"] {
            try FileManager.default.createDirectory(atPath: h.path(p + "/.git"), withIntermediateDirectories: true)
        }
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        let projects: (inout KitfoldConfig) -> Void = { c in
            c.projects = [ProjectConfig(path: h.path("work/a")), ProjectConfig(path: h.path("work/b"))]
        }
        let on = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.claudeCode), .on, mutate: projects)
        #expect(on.issues.filter { $0.kind == .sharedSkillFolder }.count == 1)
        try ws.assign(ResourceRef(.skill, "alpha"), .agent(.claudeCode), nil)

        // OpenCode's global "off" covers its projects too: nothing to say anywhere.
        try ws.assign(ResourceRef(.skill, "alpha"), .agent(.openCode), .off)
        let again = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.claudeCode), .on)
        #expect(!again.issues.contains { $0.kind == .sharedSkillFolder })
    }

    @Test func missingSkillIsOneIssuePerScopeNamingEveryAgent() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        var draft = ws.config
        draft.setAll(ResourceRef(.skill, "ghost"), scope: .global, state: .on)
        let plan = ws.plan(draft, snapshot: ws.snap())
        let missing = plan.issues.filter { $0.kind == .missingResource }
        #expect(missing.count == 1)
        #expect(missing.first?.affectedAgents.count == 4)
        #expect(missing.first?.detail.contains("Claude Code, Codex, OpenCode, Gemini CLI") == true)
    }
}

extension TutorialFindingsTests {
    /// Only a project file the user already had can be in git; removing one Kitfold created says nothing about commits.
    @Test func commitNoteOnlyForTheUsersOwnProjectFiles() throws {
        let h = FakeHome()
        h.installAgents()
        try FileManager.default.createDirectory(atPath: h.path("work/app/.git"), withIntermediateDirectories: true)
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        try ws.assign(ResourceRef(.skill, "alpha"), .agent(.geminiCLI), .on)
        let project = Scope.project(h.path("work/app"))
        let addProject: (inout KitfoldConfig) -> Void = { $0.projects = [ProjectConfig(path: h.path("work/app"))] }
        let off = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.geminiCLI), .off, scope: project, mutate: addProject)
        let settings = h.path("work/app/.gemini/settings.json")
        #expect(off.changes.first { $0.change.path == settings }?.note == nil)  // a new file
        let cleared = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.geminiCLI), nil, scope: project)
        let removal = try #require(cleared.changes.first { $0.change.path == settings })
        guard case .writeFile(_, _, nil) = removal.change else { Testing.Issue.record("expected the file to be removed"); return }
        #expect(removal.note == nil)

        h.write("work/app/.gemini/settings.json", "{\n  \"theme\": \"dark\"\n}\n")  // the user's own
        let again = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.geminiCLI), .off, scope: project)
        #expect(again.changes.first { $0.change.path == settings }?.note?.contains("committed") == true)
    }
}

extension TutorialFindingsTests {
    /// OpenCode skips Claude Code's folders when OPENCODE_DISABLE_CLAUDE_CODE_SKILLS (or …_CLAUDE_CODE) is true.
    @Test func openCodeCanBeToldNotToReadClaudesSkills() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".claude/skills/alpha")
        for (value, reads) in [("1", false), ("yes", false), ("0", true), ("false", true)] {
            let env = KitfoldEnvironment(home: h.root, variables: ["PATH": "/nonexistent", "OPENCODE_DISABLE_CLAUDE_CODE_SKILLS": value])
            let snap = try Workspace(env: env).scan(probeVersions: false)
            #expect(snap.agent(.openCode)?.visibleSkills(in: .global).contains { $0.name == "alpha" } == reads, "value \(value)")
        }
        let env = KitfoldEnvironment(home: h.root, variables: ["PATH": "/nonexistent", "OPENCODE_DISABLE_CLAUDE_CODE": "true"])
        let ws = try Workspace(env: env)
        _ = try ws.library.createSkill(name: "beta", description: "Beta")
        let plan = try ws.assign(ResourceRef(.skill, "beta"), .agent(.claudeCode), .on)
        #expect(!plan.issues.contains { $0.kind == .sharedSkillFolder })
    }
}

extension TutorialFindingsTests {
    /// Saving SKILL.md used to skip History; now it's an apply that undo reverts.
    @Test func savingSkillFileCanBeUndone() throws {
        let h = FakeHome()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        let entry = try #require(ws.snap().skill(named: "alpha"))
        let original = FS.read(entry.skillFile)
        let edit = ws.planSkillEdit(entry, text: "---\nname: alpha\ndescription: Better\n---\n")
        let tx = try #require(try ws.apply(edit.plan, summary: edit.summary))
        #expect(ws.snap().skill(named: "alpha")?.description == "Better")
        #expect(ws.history().first?.summary == "Edit SKILL.md of “alpha”")
        try ws.undo(tx.id)
        #expect(FS.read(entry.skillFile) == original)
    }
}
