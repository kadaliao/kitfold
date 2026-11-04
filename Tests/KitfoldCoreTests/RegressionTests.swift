import Foundation
import Testing

@testable import KitfoldCore

/// Fixes for problems found in review; each test reproduces the original failure.
@Suite struct RegressionTests {
    @Test func backslashesSurviveSaveAndReadCycles() {
        var text = Frontmatter.render(fields: [("description", .string(#"Win: C:\tools and "quotes" \n literal"#))], body: "")
        for _ in 0..<3 {
            let value = Frontmatter.parse(text)["description"] ?? ""
            #expect(value == #"Win: C:\tools and "quotes" \n literal"#)
            text = Frontmatter.render(fields: [("description", .string(value))], body: "")
        }
    }

    @Test func diffHunksNeverRepeatLines() {
        let old = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 4", with: "four").replacingOccurrences(of: "line 8", with: "eight")
        let hunks = LineDiff.hunks(LineDiff.diff(old, new), context: 3)
        #expect(hunks.count == 1)
        let shown = hunks.flatMap(\.lines).compactMap { op -> String? in
            if case .same(let s) = op { return s }
            return nil
        }
        #expect(shown.count == Set(shown).count)
    }

    @Test func savingSettingsDoesNotBlockUndo() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        try ws.assign(ResourceRef(.skill, "alpha"), .agent(.codex), .on)
        let tx = try #require(ws.history().first)
        var c = ws.config
        c.preferences.backupRetentionDays = 7
        try ws.saveConfigDirectly(c)
        try ws.undo(tx.id)
        #expect(h.kind(".codex/skills/alpha") == .missing)
        #expect(ws.config.rules.isEmpty)
        #expect(ws.config.preferences.backupRetentionDays == 7)  // the later setting is kept
    }

    @Test func undoingAnAdoptRefusesWhileNewerLinksDependOnIt() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/delta")
        let ws = try h.workspace()
        let s = ws.snap()
        try ws.apply(try ws.planAdopt(try #require(s.catalog.first { $0.name == "delta" }), snapshot: s), summary: "adopt")
        let adopt = try #require(ws.history().first)
        try ws.assign(ResourceRef(.skill, "delta"), .agent(.claudeCode), .on)
        #expect(throws: KitfoldError.self) { try ws.undo(adopt.id) }
        #expect(FS.realPath(h.path(".claude/skills/delta")) != nil)
    }

    @Test func offOnlyTouchesTheSkillWithThatName() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "pdf", description: "PDF")
        h.skill("elsewhere/pdf-impl", name: "pdf-pro")
        h.link(".codex/skills/pdf", to: "elsewhere/pdf-impl")
        let plan = try ws.assign(ResourceRef(.skill, "pdf"), .agent(.codex), .off)
        #expect(!plan.changes.contains { $0.change.path == h.path(".codex/skills/pdf") })
        if case .symlink = h.kind(".codex/skills/pdf") {} else { Testing.Issue.record("pdf-pro's link was removed") }
    }

    @Test func switchingEverythingOffRaisesNoFalseAlarm() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        try ws.assign(ResourceRef(.skill, "alpha"), .all, .on)
        let plan = try ws.assign(ResourceRef(.skill, "alpha"), .all, .off)
        #expect(plan.issues.isEmpty)
        #expect(!plan.changes.contains { $0.details != nil })  // links were enough; no settings written
        for a in ws.snap().agents { #expect(a.visibleSkills(in: .global).isEmpty) }
    }

    @Test func agentsSkipSkillsWithoutTheFrontmatterTheyNeed() throws {
        let h = FakeHome()
        h.installAgents()
        try FS.write("---\ndescription: No name here\n---\n", to: h.path(".agents/skills/nameless/SKILL.md"))
        try FS.write("---\nname: quiet\n---\n", to: h.path(".agents/skills/quiet/SKILL.md"))
        let s = try h.workspace().snap()
        #expect(s.agent(.codex)!.visibleSkills(in: .global).map(\.name) == ["nameless"])
        #expect(s.agent(.openCode)!.visibleSkills(in: .global).map(\.name) == ["quiet"])
        #expect(s.agent(.geminiCLI)!.visibleSkills(in: .global).isEmpty)
        #expect(s.issues.contains { $0.kind == .invalidSkill && $0.agent == .geminiCLI })
    }

    @Test func codexOverrideFileIsReported() throws {
        let h = FakeHome()
        h.installAgents()
        h.write(".codex/AGENTS.override.md", "Temporary rules\n")
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Reviewer", body: "Be strict.")
        let plan = try ws.assign(ResourceRef(.profile, "reviewer"), .agent(.codex), .on)
        #expect(plan.issues.contains { $0.kind == .fallbackChange && $0.agent == .codex })
        #expect(plan.changes.first { $0.change.path == h.path(".codex/AGENTS.md") }?.note == nil)
    }

    @Test func linkingForClaudeTellsAboutOpenCode() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "alpha", description: "Alpha")
        let on = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.claudeCode), .on)
        #expect(on.issues.contains { $0.kind == .sharedSkillFolder && $0.agent == .openCode && $0.title.contains("too") })
        let off = try ws.assign(ResourceRef(.skill, "alpha"), .agent(.claudeCode), .off)
        #expect(off.issues.contains { $0.kind == .sharedSkillFolder && $0.agent == .openCode && $0.title.contains("stop") })
    }

    @Test func projectPathsAreAbsolute() throws {
        let h = FakeHome()
        var c = KitfoldConfig()
        c.projects = [ProjectConfig(path: "~/work/app"), ProjectConfig(path: "..")]
        c.rules = [AssignmentRule(ResourceRef(.skill, "x"), scope: .project("~/work/app"), agent: .all, state: .on)]
        c.resolvePaths(h.env)
        #expect(c.projects.map(\.path) == [h.path("work/app")])
        #expect(c.rules.first?.scope == .project(h.path("work/app")))
    }
}
