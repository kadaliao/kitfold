import Foundation
import Testing

@testable import KitfoldCore

@Suite struct ScanTests {
    @Test func effectiveViewAcrossSharedAndForeignDirs() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/eli5")
        h.link(".claude/skills/eli5", to: ".agents/skills/eli5")
        h.link(".claude/skills/gone", to: ".agents/skills/does-not-exist")
        let ws = try h.workspace()
        let s = ws.snap()

        // Claude sees it through its own link; Codex/Gemini through the shared dir; OpenCode through both.
        #expect(s.exposures(skill: "eli5", agent: .claudeCode, scope: .global).map(\.via) == [.link(ownedByKitfold: false)])
        #expect(s.exposures(skill: "eli5", agent: .codex, scope: .global).map(\.via) == [.sharedDir])
        #expect(s.exposures(skill: "eli5", agent: .geminiCLI, scope: .global).map(\.via) == [.sharedDir])
        #expect(s.exposures(skill: "eli5", agent: .openCode, scope: .global).count == 2)
        #expect(s.agent(.openCode)!.visibleSkills(in: .global).map(\.name) == ["eli5"])

        #expect(s.issues.contains { $0.kind == .brokenLink && $0.agent == .claudeCode })
        // Bootstrap registered ~/.agents/skills as a source, so eli5 is in the catalog once.
        #expect(s.catalog.filter { $0.name == "eli5" }.count == 1)
    }

    @Test func codexDisabledByConfigIsNotActive() throws {
        let h = FakeHome()
        h.installAgents()
        let dir = h.skill(".agents/skills/pdf")
        h.write(".codex/config.toml", "[[skills.config]]\npath = \"\(dir)/SKILL.md\"\nenabled = false\n")
        let s = try h.workspace().snap()
        #expect(s.agent(.codex)!.visibleSkills(in: .global).isEmpty)
        #expect(s.agent(.geminiCLI)!.visibleSkills(in: .global).map(\.name) == ["pdf"])
    }

    @Test func nestedSkillsCountForCodexAndOpenCodeOnly() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/suite")
        h.skill(".agents/skills/suite/skills/inner-one")
        h.link(".claude/skills/suite", to: ".agents/skills/suite")
        let s = try h.workspace().snap()
        #expect(s.agent(.openCode)!.visibleSkills(in: .global).map(\.name).sorted() == ["inner-one", "suite"])
        #expect(s.agent(.codex)!.visibleSkills(in: .global).map(\.name).sorted() == ["inner-one", "suite"])
        #expect(s.agent(.claudeCode)!.visibleSkills(in: .global).map(\.name) == ["suite"])
        #expect(s.agent(.geminiCLI)!.visibleSkills(in: .global).map(\.name) == ["suite"])
        #expect(s.exposures(skill: "inner-one", agent: .codex, scope: .global).first?.via == .nested("suite"))
    }

    @Test func codexDisableAppliesToSystemSkills() throws {
        let h = FakeHome()
        h.installAgents()
        let dir = h.skill(".codex/skills/.system/imagegen")
        h.write(".codex/config.toml", "[[skills.config]]\npath = \"\(dir)/SKILL.md\"\nenabled = false\n")
        let s = try h.workspace().snap()
        #expect(s.agent(.codex)!.state(.global).skills.contains { $0.name == "imagegen" })
        #expect(!s.agent(.codex)!.visibleSkills(in: .global).contains { $0.name == "imagegen" })
    }

    @Test func instructionFallbacks() throws {
        let h = FakeHome()
        h.installAgents()
        h.write(".claude/CLAUDE.md", "claude memory")
        var s = try h.workspace().snap()
        // OpenCode falls back to ~/.claude/CLAUDE.md while ~/.config/opencode/AGENTS.md is missing.
        #expect(s.agent(.openCode)!.state(.global).loadedInstructions.map(\.file.path) == [h.path(".claude/CLAUDE.md")])
        h.write(".config/opencode/AGENTS.md", "oc")
        s = try h.workspace().snap()
        #expect(s.agent(.openCode)!.state(.global).loadedInstructions.map(\.file.path) == [h.path(".config/opencode/AGENTS.md")])
    }
}

@Suite struct ApplyUndoTests {
    @Test func assignToOneAgentOnlyAndUndo() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha skill")

        let plan = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.codex), .on)
        #expect(
            plan.changes.contains {
                $0.change == .createSymlink(path: h.path(".codex/skills/alpha"), target: h.path(".kitfold/library/skills/alpha"))
            })
        #expect(h.kind(".claude/skills/alpha") == .missing)

        let s = ws.snap()
        #expect(s.agent(.codex)!.visibleSkills(in: .global).map(\.name) == ["alpha"])
        #expect(s.agent(.claudeCode)!.visibleSkills(in: .global).isEmpty)
        #expect(s.agent(.openCode)!.visibleSkills(in: .global).isEmpty)  // isolation: nothing leaked
        #expect(s.ownedPaths.contains(h.path(".codex/skills/alpha")))

        // Re-planning the same config is a no-op.
        #expect(ws.plan(ws.config, snapshot: s).changes.isEmpty)

        // Undo removes the link AND reverts the intent in kitfold.json.
        let tx = ws.history().first!
        try ws.undo(tx.id)
        #expect(h.kind(".codex/skills/alpha") == .missing)
        #expect(ws.config.rules.isEmpty)
        #expect(ws.plan(ws.config, snapshot: ws.snap()).changes.isEmpty)
    }

    @Test func allAgentsWildcardAndRemoveTakesBackOnlyOwnLinks() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "beta", description: "Beta")
        try ws.assign(ResourceRef(.skill, "beta"), .all, .on)
        for p in [".claude/skills/beta", ".codex/skills/beta", ".config/opencode/skills/beta", ".gemini/skills/beta"] {
            if case .symlink = h.kind(p) {
            } else if p.contains("opencode") {
                // OpenCode already sees it through ~/.claude/skills — no duplicate link is created.
                #expect(h.kind(p) == .missing)
            } else {
                Testing.Issue.record("expected link at \(p)")
            }
        }
        // Clearing the rule removes exactly what Kitfold created.
        h.link(".claude/skills/handmade", to: ".kitfold/library/skills/beta")
        try ws.assign(ResourceRef(.skill, "beta"), .all, nil)
        #expect(h.kind(".claude/skills/beta") == .missing)
        #expect(h.kind(".codex/skills/beta") == .missing)
        if case .symlink = h.kind(".claude/skills/handmade") {} else { Testing.Issue.record("foreign link was removed") }
    }

    @Test func crossAgentDependencyKeepsOpenCodeWorking() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "gamma", description: "Gamma")
        try ws.assign(ResourceRef(.skill, "gamma"), .agent(.claudeCode), .on)
        try ws.assign(ResourceRef(.skill, "gamma"), .agent(.openCode), .on)
        #expect(h.kind(".config/opencode/skills/gamma") == .missing)  // seen via ~/.claude/skills
        // Turning Claude off must not silently take gamma away from OpenCode.
        try ws.assign(ResourceRef(.skill, "gamma"), .agent(.claudeCode), .off)
        #expect(h.kind(".claude/skills/gamma") == .missing)
        if case .symlink = h.kind(".config/opencode/skills/gamma") {} else { Testing.Issue.record("OpenCode lost gamma") }
        #expect(ws.snap().agent(.openCode)!.visibleSkills(in: .global).map(\.name) == ["gamma"])
    }

    @Test func offForSharedDirIsReportedNotFaked() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/shared-one")
        let ws = try h.workspace()
        var draft = ws.config
        draft.setRule(ResourceRef(.skill, "shared-one"), agent: .agent(.codex), scope: .global, state: .off)
        let plan = ws.plan(draft, snapshot: ws.snap())
        #expect(plan.changes.allSatisfy { $0.change.path == h.path(".kitfold/kitfold.json") })
        #expect(plan.issues.contains { $0.kind == .stillVisible && $0.agent == .codex })
    }

    @Test func neverReplacesUnknownFolders() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".codex/skills/delta", description: "user's own")
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "delta", description: "library version")
        var draft = ws.config
        draft.setRule(ResourceRef(.skill, "delta"), agent: .agent(.codex), scope: .global, state: .on)
        let plan = ws.plan(draft, snapshot: ws.snap())
        #expect(plan.issues.contains { $0.kind == .conflict })
        #expect(!plan.changes.contains { $0.change.path == h.path(".codex/skills/delta") })
    }

    @Test func preconditionFailureRollsBack() throws {
        let h = FakeHome()
        h.installAgents()
        h.write(".codex/AGENTS.md", "mine\n")
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Reviewer", body: "Review carefully.")
        _ = try ws.library.createSkill(name: "eps", description: "e")
        var draft = ws.config
        draft.setRule(ResourceRef(.skill, "eps"), agent: .agent(.codex), scope: .global, state: .on)
        draft.setRule(ResourceRef(.profile, "reviewer"), agent: .agent(.codex), scope: .global, state: .on)
        let plan = ws.plan(draft, snapshot: ws.snap())
        h.write(".codex/AGENTS.md", "mine, edited after the preview\n")
        #expect(throws: KitfoldError.self) { try ws.apply(plan, summary: "x") }
        // Nothing half-applied.
        #expect(h.kind(".codex/skills/eps") == .missing)
        #expect(h.read(".codex/AGENTS.md") == "mine, edited after the preview\n")
        #expect(ws.history().isEmpty)
    }
}

@Suite struct ProfileTests {
    @Test func claudeProfileGoesToRulesFileAndDriftIsProtected() throws {
        let h = FakeHome()
        h.installAgents()
        h.write(".claude/CLAUDE.md", "user memory\n")
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Backend", body: "Prefer Go.", skills: [])
        try ws.assign(ResourceRef(.profile, "backend"), .agent(.claudeCode), .on)

        // Claude-only file; the user's CLAUDE.md (which OpenCode falls back to) is untouched.
        #expect(h.read(".claude/CLAUDE.md") == "user memory\n")
        let rules = h.read(".claude/rules/kitfold.md")!
        #expect(ManagedBlock.findAll(in: rules).first?.body == "Prefer Go.")
        #expect(
            ws.snap().agent(.claudeCode)!.state(.global).loadedInstructions.contains { $0.file.path == h.path(".claude/rules/kitfold.md") })

        // Hand edit → planner refuses to overwrite.
        h.write(".claude/rules/kitfold.md", rules.replacingOccurrences(of: "Prefer Go.", with: "Prefer Rust."))
        var p = try ws.profileEntry("backend")
        p.body = "Prefer Go 1.30."
        try ws.saveProfile(p)
        let plan = ws.plan(ws.config, snapshot: ws.snap())
        #expect(plan.issues.contains { $0.kind == .blockDrift })
        #expect(!plan.changes.contains { $0.change.path == h.path(".claude/rules/kitfold.md") })

        // Keep the edit: profile takes the hand-edited text, block is re-stamped.
        let adopt = try ws.adoptDrift(file: h.path(".claude/rules/kitfold.md"), profile: "backend", snapshot: ws.snap())
        try ws.apply(adopt, summary: "adopt")
        #expect(try ws.profileEntry("backend").body == "Prefer Rust.")
        #expect(ManagedBlock.findAll(in: h.read(".claude/rules/kitfold.md")!).first?.isModifiedOutsideKitfold == false)
        #expect(!ws.profileVersions("backend").isEmpty)

        // Unassign: Kitfold created the file, so it removes it.
        try ws.assign(ResourceRef(.profile, "backend"), .agent(.claudeCode), nil)
        #expect(h.kind(".claude/rules/kitfold.md") == .missing)
    }

    @Test func profileBundlesSkillsAndSharedFileWarning() throws {
        let h = FakeHome()
        h.installAgents()
        let proj = h.path("work/app")
        try FileManager.default.createDirectory(atPath: proj + "/.git/info", withIntermediateDirectories: true)
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "lint", description: "Lint")
        _ = try ws.library.createProfile(name: "Web", body: "Use TypeScript.", skills: ["lint"])
        var draft = ws.addingProject(proj, to: ws.config)
        draft.setRule(ResourceRef(.profile, "web"), agent: .agent(.codex), scope: .project(proj), state: .on)
        let snap = Scanner(env: h.env, adapters: ws.adapters).scan(config: draft, ownedPaths: [], probeVersions: false)
        let plan = ws.plan(draft, snapshot: snap)
        // The profile's skill is linked into Codex's project folder…
        #expect(plan.changes.contains { $0.change.path == proj + "/.codex/skills/lint" })
        // …its text goes to AGENTS.md, which OpenCode also reads.
        #expect(plan.changes.contains { $0.change.path == proj + "/AGENTS.md" })
        #expect(plan.issues.contains { $0.kind == .sharedInstructionFile && $0.agent == .openCode })
        try ws.apply(plan, summary: "web")
        // Kitfold's project files are kept out of git locally.
        let exclude = FS.read(proj + "/.git/info/exclude") ?? ""
        #expect(exclude.contains("/.codex/skills/lint"))
        #expect(exclude.contains("/AGENTS.md"))
    }

    @Test func adoptLocalFolderIntoLibrary() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".codex/skills/local-one")
        let ws = try h.workspace()
        let s = ws.snap()
        let entry = try #require(s.catalog.first { $0.name == "local-one" })
        let plan = try ws.planAdopt(entry, snapshot: s)
        try ws.apply(plan, summary: "adopt")
        #expect(h.kind(".kitfold/library/skills/local-one") == .directory)
        #expect(ws.snap().agent(.codex)!.visibleSkills(in: .global).map(\.name) == ["local-one"])
        // Adoption records the intent, so the next plan doesn't treat the new link as leftover.
        #expect(ws.config.state(ResourceRef(.skill, "local-one"), agent: .codex, scope: .global) == .on)
        #expect(ws.plan(ws.config, snapshot: ws.snap()).changes.isEmpty)
        try ws.undo(ws.history().first!.id)
        #expect(h.kind(".codex/skills/local-one") == .directory)
        #expect(h.kind(".kitfold/library/skills/local-one") == .missing)
    }
}

extension Workspace {
    func profileEntry(_ id: String) throws -> ProfileEntry {
        guard let p = library.profiles().first(where: { $0.id == id }) else { throw KitfoldError.notFound(id) }
        return p
    }
}

@Suite struct PermissionTests {
    @Test func writesKeepModeAndBackupsArePrivate() throws {
        let h = FakeHome()
        h.installAgents()
        h.write(".codex/AGENTS.md", "secret-ish notes\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: h.path(".codex/AGENTS.md"))
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "P", body: "Be brief.")
        try ws.assign(ResourceRef(.profile, "p"), .agent(.codex), .on)
        func mode(_ p: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: p))?[.posixPermissions] as? Int) ?? -1 }
        #expect(mode(h.path(".codex/AGENTS.md")) == 0o600)  // rewritten, mode kept
        let tx = try #require(ws.history().first)
        let backup = try #require(tx.operations.compactMap(\.backupPath).first)
        #expect(mode(backup) == 0o600)
        #expect(mode(h.path(".kitfold/backups")) == 0o700)
    }
}
