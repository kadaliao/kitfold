import Foundation
import Testing

@testable import KitfoldCore

/// Many agents: the catalog, agents found on the Mac, the user's own, and what deleting a skill
/// does across all of them.
@Suite struct AgentCatalogTests {
    @Test func catalogIsWellFormed() {
        let all = AgentCatalog.all
        #expect(all.count > 60)
        #expect(Set(all.map(\.id)).count == all.count, "agent ids repeat")
        #expect(Set(all.map(\.name)).count == all.count, "agent names repeat")
        // The CLI heads the matrix's columns with them.
        let monograms = Dictionary(grouping: all, by: { $0.monogram.lowercased() }).filter { $0.value.count > 1 }
        #expect(monograms.isEmpty, "monograms repeat: \(monograms.mapValues { $0.map(\.name) })")
        var owners: [String: AgentID] = [:]
        for d in all {
            #expect(SkillEntry.slugify(d.id.rawValue) == d.id.rawValue, "\(d.id) isn't a slug")
            #expect(!d.skillRoots.isEmpty, "\(d.name) has no skills folder")
            #expect(d.monogram.count == 2, "\(d.name): monogram \(d.monogram)")
            #expect(d.docsURL.isEmpty || URL(string: d.docsURL) != nil)
            // No folder is two agents' own: the second reads it as the first one's.
            for r in d.skillRoots where r.role == .primary {
                let key = "\(r.scope)|\(r.base)|\(r.base == .configDir ? d.configDir + "/" : "")\(r.path)"
                if let o = owners[key] { Testing.Issue.record("\(key) belongs to \(o) and \(d.id)") }
                owners[key] = d.id
            }
        }
        let trae = try! #require(AgentCatalog.descriptor("trae-cn"))
        let shared = try! #require(trae.skillRoots.first { $0.scope == .project && $0.path == ".trae/skills" })
        #expect(shared.role == .foreign && shared.owner == "trae")
    }

    @Test func aCatalogAgentShowsUpWhenItsFolderExists() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".kiro/skills/notes")
        h.installBinary("kiro-cli")
        let ws = try h.workspace()
        let snap = ws.snap()
        let kiro = try #require(snap.agent("kiro"))
        #expect(kiro.installation.isInstalled && kiro.enabled)
        #expect(kiro.visibleSkills(in: .global).map(\.name) == ["notes"])
        #expect(snap.skill(named: "notes")?.origin == .agentLocal("kiro"))
        // Known but not installed: scanned, not managed.
        let goose = try #require(snap.agent("goose"))
        #expect(!goose.installation.isDetected && !goose.enabled)
        #expect(snap.agents.prefix(4).map(\.id) == [.claudeCode, .codex, .openCode, .geminiCLI])
    }

    @Test func aFolderLeftBehindIsShownButNotManaged() throws {
        let h = FakeHome()
        h.installAgents()
        // The skills CLI made ~/.kiro/skills; Kiro itself isn't installed.
        h.skill(".agents/skills/pdf")
        h.link(".kiro/skills/pdf", to: ".agents/skills/pdf")
        h.link(".kiro/skills/gone", to: ".agents/skills/gone")
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "lint", description: "Lint")
        try ws.assign(ResourceRef(.skill, "lint"), .all, .on)
        let snap = ws.snap()
        let kiro = try #require(snap.agent("kiro"))
        #expect(kiro.installation.isDetected && !kiro.installation.isInstalled && !kiro.enabled)
        // "All agents" means the managed ones: nothing is linked into a leftover folder…
        #expect(h.kind(".kiro/skills/lint") == .missing)
        // …but its broken links are reported and cleaned up, and deleting a skill takes its links too.
        #expect(snap.issues.contains { $0.kind == .brokenLink && $0.paths.contains(h.path(".kiro/skills/gone")) })
        #expect(ws.planRemoveBrokenLinks(snapshot: snap).changes.map(\.change.path) == [h.path(".kiro/skills/gone")])
        let delete = try ws.planSkillDelete(try #require(snap.skill(named: "pdf")), snapshot: snap)
        #expect(delete.changes.contains { $0.change.path == h.path(".kiro/skills/pdf") })
    }

    @Test func linksAnAgentWontFollowAreShownAsSkipped() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/pdf")
        h.link(".continue/skills/pdf", to: ".agents/skills/pdf")  // Continue skips linked folders
        h.skill(".continue/skills/notes")  // a real folder loads
        try FileManager.default.createDirectory(
            atPath: h.path(".vscode/extensions/continue.continue-2.1.0"), withIntermediateDirectories: true)
        let ws = try h.workspace()
        let snap = ws.snap()
        let cont = try #require(snap.agent("continue"))
        #expect(cont.enabled)
        #expect(cont.visibleSkills(in: .global).map(\.name) == ["notes"])
        #expect(snap.issues.contains { $0.title == "Continue ignores “pdf”" })
        // Kitfold can't give it a skill by linking, and says so.
        var draft = ws.config
        draft.setRule(ResourceRef(.skill, "pdf"), agent: .agent("continue"), scope: .global, state: .on)
        let plan = ws.plan(draft, snapshot: Scanner(env: h.env, adapters: ws.adapters).scan(config: draft, ownedPaths: []))
        #expect(plan.issues.contains { $0.title == "Continue doesn't load linked skill folders" })
        #expect(!plan.changes.contains { $0.change.path.contains(".continue/") })
    }

    @Test func findsAgentsKitfoldDoesNotKnow() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".acme-bot/skills/alpha")  // an unknown agent's folder
        h.skill(".config/zap/skills/beta")
        h.skill(".kiro/skills/gamma")  // a catalog agent's: not found twice
        h.write(".notes/skills/readme.md", "not a skill\n")  // no SKILL.md anywhere
        try FileManager.default.createDirectory(atPath: h.path(".empty/skills"), withIntermediateDirectories: true)
        h.skill(".store/skills/delta")  // registered as a source below: a store, not an agent
        let ws = try h.workspace()
        var c = ws.config
        c.sources.append(SkillSourceConfig(id: "store", label: "Store", path: "~/.store/skills"))
        try ws.saveConfigDirectly(c)

        let found = ws.snap().agents.filter { $0.adapter.descriptor.source == .discovered }
        #expect(found.map(\.id) == ["acme-bot", "zap"])
        let acme = try #require(found.first)
        #expect(acme.name == "Acme Bot" && acme.installation.isDetected)
        #expect(acme.visibleSkills(in: .global).map(\.name) == ["alpha"])
        #expect(acme.adapter.primarySkillDir(.global, h.env) == h.path(".acme-bot/skills"))
        // No guessed project folder: it would be created in every project.
        #expect(acme.adapter.primarySkillDir(.project(h.path("work/app")), h.env) == nil)

        // The folder may be anything (a repository, someone's collection): listed, not managed, so an
        // "all agents" rule leaves it alone…
        #expect(!acme.enabled)
        _ = try ws.library.createSkill(name: "omega", description: "Omega")
        try ws.assign(ResourceRef(.skill, "omega"), .all, .on)
        #expect(h.kind(".acme-bot/skills/omega") == .missing)
        // …until it's switched on.
        var on = ws.config
        on.agents["acme-bot"] = AgentSettings(enabled: true)
        try ws.saveConfigDirectly(on)
        try ws.apply(ws.plan(ws.config, snapshot: ws.snap()), summary: "test")
        if case .symlink = h.kind(".acme-bot/skills/omega") {} else { Testing.Issue.record("no link for the found agent") }
    }

    @Test func aFoundAgentsIdDependsOnlyOnWhereItIs() throws {
        let h = FakeHome()
        h.skill(".config/grok/skills/a")  // not Grok's folder (that's ~/.grok/skills)
        h.skill(".config/tool/skills/b")
        h.skill(".tool/skills/c")
        let ws = try h.workspace()
        let ids = Set(ws.snap().agents.filter { $0.adapter.descriptor.source == .discovered }.map(\.id.rawValue))
        #expect(ids == ["grok-config", "tool", "tool-config"])
    }

    @Test func aCustomAgentOnAKnownAgentsFolderReadsItAsThatAgents() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        var c = ws.config
        c.customAgents = [CustomAgent(id: "mine", name: "Mine", skills: "~/.claude/skills")]
        try ws.saveConfigDirectly(c)
        let mine = try #require(ws.snap().agent("mine"))
        #expect(mine.adapter.descriptor.skillRoots.first?.role == .foreign)
        #expect(mine.adapter.descriptor.skillRoots.first?.owner == .claudeCode)
        #expect(mine.adapter.primarySkillDir(.global, h.env) == nil)
    }

    @Test func customAgentsComeFromKitfoldJSON() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".acme-bot/skills/alpha")
        let ws = try h.workspace()
        var c = ws.config
        c.customAgents = [
            CustomAgent(id: "acme", name: "Acme", skills: "~/.acme-bot/skills", projectSkills: ".acme/skills"),
            CustomAgent(id: "lab", name: "Lab Agent", skills: "~/lab/agent-skills", instructions: "~/lab/RULES.md"),
        ]
        try ws.saveConfigDirectly(c)
        #expect(FS.read(h.env.configFile)?.contains("\"customAgents\"") == true)

        let snap = ws.snap()
        // The custom agent claims the folder, so it isn't "found" as another one.
        #expect(!snap.agents.contains { $0.adapter.descriptor.source == .discovered })
        let acme = try #require(snap.agent("acme"))
        #expect(acme.name == "Acme" && acme.adapter.descriptor.source == .custom && acme.enabled)
        #expect(acme.visibleSkills(in: .global).map(\.name) == ["alpha"])
        // Not on disk yet: listed, not managed until its folder exists or it's switched on.
        let lab = try #require(snap.agent("lab"))
        #expect(!lab.enabled)
        #expect(lab.adapter.primaryInstructionFile(.global, h.env) == h.path("lab/RULES.md"))

        // Older files without the key still load, and an empty list isn't written.
        var plain = ws.config
        plain.customAgents = []
        try ws.saveConfigDirectly(plain)
        #expect(FS.read(h.env.configFile)?.contains("customAgents") == false)
    }

    @Test func aProfileForAnAgentWithoutAnInstructionFileSaysSo() throws {
        let h = FakeHome()
        h.installAgents()
        try FileManager.default.createDirectory(atPath: h.path(".roo"), withIntermediateDirectories: true)
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Writer", body: "Be brief.")
        var draft = ws.config
        draft.setRule(ResourceRef(.profile, "writer"), agent: .agent("roo"), scope: .global, state: .on)
        let plan = ws.plan(draft, snapshot: Scanner(env: h.env, adapters: ws.adapters).scan(config: draft, ownedPaths: []))
        let issue = try #require(plan.issues.first { $0.kind == .unsupported && $0.agent == "roo" })
        #expect(issue.title == "Roo Code can't get profiles")
        #expect(!plan.changes.contains { $0.agents.contains("roo") })
    }

    @Test func aProfileFileThatNeedsFrontmatterGetsIt() throws {
        let h = FakeHome()
        h.installAgents()
        h.installBinary("kiro-cli")
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Writer", body: "Be brief.")
        _ = try ws.library.createProfile(name: "Tester", body: "Test it.")
        try ws.assign(ResourceRef(.profile, "writer"), .agent("kiro"), .on)
        // Kiro applies a steering file in every session only with `inclusion: always`.
        let text = try #require(h.read(".kiro/steering/kitfold.md"))
        #expect(text.hasPrefix("---\ninclusion: always\n---\n\n<!-- kitfold:begin"))
        #expect(text.contains("Be brief."))
        // A second profile goes after the header too, and the last one taking the file away removes it.
        try ws.assign(ResourceRef(.profile, "tester"), .agent("kiro"), .on)
        let both = try #require(h.read(".kiro/steering/kitfold.md"))
        #expect(both.hasPrefix("---\ninclusion: always\n---\n") && both.contains("Test it.") && both.contains("Be brief."))
        try ws.assign(ResourceRef(.profile, "writer"), .agent("kiro"), nil)
        try ws.assign(ResourceRef(.profile, "tester"), .agent("kiro"), nil)
        #expect(h.kind(".kiro/steering/kitfold.md") == .missing)
    }
}

@Suite struct DeleteEverywhereTests {
    @Test func deletingTakesTheSkillOutOfEveryAgentsFolder() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/pdf")
        // The skills CLI links a skill into each agent's own folder, relative links included.
        h.link(".claude/skills/pdf", to: ".agents/skills/pdf")
        try FS.createSymlink(at: h.path(".kiro/skills/pdf"), to: "../../.agents/skills/pdf")
        h.link(".trae/skills/pdf", to: ".agents/skills/pdf")
        h.link(".acme-bot/skills/pdf", to: ".agents/skills/pdf")  // an agent Kitfold found
        h.link(".codeium/windsurf/skills/pdf", to: ".claude/skills/pdf")  // a link to a link
        let ws = try h.workspace()
        let snap = ws.snap()
        let plan = try ws.planSkillDelete(try #require(snap.skill(named: "pdf")), snapshot: snap)
        let unlinked = Set(
            plan.changes.compactMap { c -> String? in
                if case .removeSymlink(let p, _) = c.change { return p }
                return nil
            })
        let links = [".claude/skills/pdf", ".kiro/skills/pdf", ".trae/skills/pdf", ".acme-bot/skills/pdf", ".codeium/windsurf/skills/pdf"]
        #expect(unlinked == Set(links.map(h.path)))
        try ws.apply(plan, summary: "delete")
        for l in links + [".agents/skills/pdf"] { #expect(h.kind(l) == .missing, "\(l) is still there") }
        #expect(ws.snap().issues.filter { $0.kind == .brokenLink }.isEmpty)

        try ws.undo(ws.history().first!.id)
        #expect(h.kind(".agents/skills/pdf") == .directory)
        if case .symlink(let raw) = h.kind(".kiro/skills/pdf") {
            #expect(raw == "../../.agents/skills/pdf")
        } else {
            Testing.Issue.record("the Kiro link wasn't restored")
        }
    }

    @Test func deletingLeavesOtherPendingChangesAlone() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/pdf")
        h.link(".claude/skills/pdf", to: ".agents/skills/pdf")
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "lint", description: "Lint")
        try ws.assign(ResourceRef(.skill, "lint"), .all, .on)
        // An agent installed since: the "all agents" rule now has a link to make for it.
        h.installBinary("kiro-cli")
        let snap = ws.snap()
        #expect(ws.plan(ws.config, snapshot: snap).changes.contains { $0.change.path == h.path(".kiro/skills/lint") })

        let plan = try ws.planSkillDelete(try #require(snap.skill(named: "pdf")), snapshot: snap)
        #expect(!plan.changes.contains { $0.change.path.contains("lint") })
        #expect(plan.changes.contains { $0.change.path == h.path(".claude/skills/pdf") })
    }

    @Test func deletingASkillsCLISkillTakesItOffItsList() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/pdf")
        h.skill(".agents/skills/docx")
        let lock = """
            {
              "version": 3,
              "skills": {
                "docx": {
                  "source": "anthropics/skills",
                  "sourceType": "github"
                },
                "pdf": {
                  "source": "anthropics/skills",
                  "sourceType": "github"
                }
              },
              "dismissed": {}
            }

            """
        h.write(".agents/.skill-lock.json", lock)
        let ws = try h.workspace()
        let snap = ws.snap()
        let plan = try ws.planSkillDelete(try #require(snap.skill(named: "pdf")), snapshot: snap)
        // Taking it off the list replaces the "its next update may bring it back" warning.
        #expect(!plan.issues.contains { $0.kind == .conflict })
        try ws.apply(plan, summary: "delete")
        let after = try #require(h.read(".agents/.skill-lock.json"))
        #expect(!after.contains("\"pdf\""))
        #expect(after.contains("\"docx\": {\n      \"source\": \"anthropics/skills\""))
        #expect(after.contains("\"dismissed\": {}"))

        try ws.undo(ws.history().first!.id)
        #expect(h.read(".agents/.skill-lock.json") == lock)
    }

    @Test func aSkillOffTheSkillsCLIListIsntItsToBringBack() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/pdf")
        h.skill(".agents/skills/mine")  // put there by hand
        h.write(".agents/.skill-lock.json", #"{"version": 3, "skills": {"pdf": {"source": "anthropics/skills"}}}"#)
        let ws = try h.workspace()
        let snap = ws.snap()
        let mine = try #require(snap.skill(named: "mine"))
        #expect(ws.managingTool(for: mine) == nil)
        #expect(ws.managingTool(for: try #require(snap.skill(named: "pdf"))) == "skills CLI")
        let plan = try ws.planSkillDelete(mine, snapshot: snap)
        #expect(!plan.issues.contains { $0.kind == .conflict })
        #expect(!plan.changes.contains { $0.change.path == h.path(".agents/.skill-lock.json") })
    }

    @Test func deletingALinkedFolderLeavesTheFolder() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill("dev/kit/beta")  // a repository checkout, say
        h.link(".claude/skills/beta", to: "dev/kit/beta")
        h.link(".kiro/skills/beta", to: "dev/kit/beta")
        let ws = try h.workspace()
        let snap = ws.snap()
        let entry = try #require(snap.skill(named: "beta"))
        #expect(entry.origin == .external && entry.origin.isDeletable && entry.origin.deleteKeepsFolder)
        let plan = try ws.planSkillDelete(entry, snapshot: snap)
        #expect(
            !plan.changes.contains {
                if case .moveItem = $0.change { return true }; return false
            })
        #expect(plan.issues.contains { $0.title == "The folder stays where it is" })
        try ws.apply(plan, summary: "delete")
        #expect(h.kind(".claude/skills/beta") == .missing && h.kind(".kiro/skills/beta") == .missing)
        #expect(h.kind("dev/kit/beta") == .directory)
        #expect(ws.snap().skill(named: "beta") == nil)
    }

    @Test func aLinkIntoADiskThatIsntMountedIsLeftAlone() throws {
        let h = FakeHome()
        h.installAgents()
        h.link(".claude/skills/archive", to: "/Volumes/KitfoldTestsNoSuchDisk/skills/archive")
        let ws = try h.workspace()
        #expect(ws.planRemoveBrokenLinks(snapshot: ws.snap()).changes.isEmpty)
    }

    @Test func anExistingProfileFileWithoutItsFrontmatterIsFlagged() throws {
        let h = FakeHome()
        h.installAgents()
        h.installBinary("kiro-cli")
        h.write(".kiro/steering/kitfold.md", "My own notes.\n")
        let ws = try h.workspace()
        _ = try ws.library.createProfile(name: "Writer", body: "Be brief.")
        var draft = ws.config
        draft.setRule(ResourceRef(.profile, "writer"), agent: .agent("kiro"), scope: .global, state: .on)
        let plan = ws.plan(draft, snapshot: Scanner(env: h.env, adapters: ws.adapters).scan(config: draft, ownedPaths: []))
        let issue = try #require(plan.issues.first { $0.title == "Kiro may not apply kitfold.md" })
        #expect(issue.detail.contains("inclusion: always"))
        // The user's text stays at the top; the block goes in as usual.
        let write = try #require(plan.changes.first { $0.change.path == h.path(".kiro/steering/kitfold.md") })
        if case .writeFile(_, _, let after?) = write.change {
            #expect(after.contains("My own notes.") && after.contains("Be brief.") && !after.hasPrefix("---"))
        }
    }

    @Test func brokenLinksCanBeCleanedUp() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/kept")
        h.link(".claude/skills/kept", to: ".agents/skills/kept")
        h.link(".claude/skills/gone", to: ".agents/skills/gone")  // deleted outside Kitfold
        h.link(".kiro/skills/gone", to: ".agents/skills/gone")
        h.link(".gemini/skills/old", to: "nowhere/old")
        let ws = try h.workspace()
        let snap = ws.snap()
        #expect(snap.issues.contains { $0.kind == .brokenLink })

        // Just the ones an issue names…
        let one = ws.planRemoveBrokenLinks(snapshot: snap, paths: [h.path(".gemini/skills/old")])
        #expect(one.changes.map(\.change.path) == [h.path(".gemini/skills/old")])
        // …or all of them; the working link stays.
        let all = ws.planRemoveBrokenLinks(snapshot: snap)
        #expect(Set(all.changes.map(\.change.path)) == Set([".claude/skills/gone", ".kiro/skills/gone", ".gemini/skills/old"].map(h.path)))
        try ws.apply(all, summary: "clean")
        #expect(h.kind(".claude/skills/gone") == .missing && h.kind(".kiro/skills/gone") == .missing)
        if case .symlink = h.kind(".claude/skills/kept") {} else { Testing.Issue.record("a working link was removed") }
        #expect(!ws.snap().issues.contains { $0.kind == .brokenLink })

        try ws.undo(ws.history().first!.id)
        if case .symlink = h.kind(".kiro/skills/gone") {} else { Testing.Issue.record("undo didn't restore the link") }
    }
}
