import Foundation
import Testing

@testable import KitfoldCore

/// Surgical JSON edits: one key changes, every other byte stays.
@Suite struct JSONEditTests {
    func roundTrip(_ original: String, _ path: [String], expect: String? = nil) throws {
        let added = try JSONEdit.set(original, path: path, literal: "\"off\"")
        if let expect { #expect(added == expect) }
        #expect(try JSONEdit.parse(added).kind == .object)
        #expect(try JSONEdit.remove(added, path: path) == original)
    }

    @Test func prettyPrintedKeepsEverythingElse() throws {
        let original = "{\n  \"env\": {\n    \"API_KEY\": \"sk-secret\"\n  },\n  \"model\": \"opus\"\n}\n"
        try roundTrip(
            original, ["skillOverrides", "pdf"],
            expect:
                "{\n  \"env\": {\n    \"API_KEY\": \"sk-secret\"\n  },\n  \"model\": \"opus\",\n  \"skillOverrides\": {\n    \"pdf\": \"off\"\n  }\n}\n"
        )
    }

    @Test func otherLayouts() throws {
        try roundTrip(
            "{\n\t\"a\": 1\n}", ["skillOverrides", "pdf"], expect: "{\n\t\"a\": 1,\n\t\"skillOverrides\": {\n\t\t\"pdf\": \"off\"\n\t}\n}")
        try roundTrip("{\n    \"a\": [1, 2]\n}\n", ["skillOverrides", "pdf"])
        try roundTrip("{\"a\": 1}", ["skillOverrides", "pdf"], expect: "{\"a\": 1, \"skillOverrides\": {\"pdf\": \"off\"}}")
        try roundTrip("{}", ["skillOverrides", "pdf"], expect: "{\n  \"skillOverrides\": {\n    \"pdf\": \"off\"\n  }\n}")
        try roundTrip("{\n  \"skillOverrides\": {\n    \"a\": \"on\"\n  }\n}\n", ["skillOverrides", "pdf"])
        try roundTrip("{\n  \"a\": 1 }", ["b"])
    }

    @Test func commentsAndTrailingCommas() throws {
        let original = """
            {
              // personal settings
              "permission": {
                "skill": {
                  "*": "allow", // default
                },
              },
            }
            """
        let added = try JSONEdit.set(original, path: ["permission", "skill", "pdf"], literal: "\"deny\"")
        #expect(added.contains("\"*\": \"allow\", // default\n      \"pdf\": \"deny\","))
        #expect(try JSONEdit.remove(added, path: ["permission", "skill", "pdf"]) == original)
    }

    @Test func replacesAnExistingValueInPlace() throws {
        let original = "{\n  \"skillOverrides\": {\"pdf\": \"name-only\", \"x\": \"on\"}\n}"
        #expect(
            try JSONEdit.set(original, path: ["skillOverrides", "pdf"], literal: "\"off\"")
                == "{\n  \"skillOverrides\": {\"pdf\": \"off\", \"x\": \"on\"}\n}")
    }

    @Test func arrays() throws {
        let original = "{\n  \"skills\": {\n    \"disabled\": [\"a\"]\n  }\n}\n"
        let added = try JSONEdit.append(original, path: ["skills", "disabled"], literal: "\"pdf\"")
        #expect(added == "{\n  \"skills\": {\n    \"disabled\": [\"a\", \"pdf\"]\n  }\n}\n")
        #expect(try JSONEdit.removeElements(added, path: ["skills", "disabled"]) { $0.stringValue == "pdf" } == original)
    }

    @Test func refusesWrongShapesAndBadJSON() throws {
        #expect(throws: JSONEdit.Failure.wrongType(path: ["skillOverrides"])) {
            try JSONEdit.set("{\"skillOverrides\": \"off\"}", path: ["skillOverrides", "pdf"], literal: "\"off\"")
        }
        #expect(throws: (any Error).self) { try JSONEdit.parse("{ \"a\": }") }
        #expect(throws: (any Error).self) { try JSONEdit.parse("{ \"a\": 1 } x") }
        #expect(try JSONEdit.parse("{\"k\\\"ey\": \"v\\u00e9\"}").member("k\"ey")?.value.stringValue == "vé")
    }
}

@Suite struct CodexConfigTests {
    @Test func managedSectionRoundTrips() {
        let original = "model = \"o3\"\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
        let added = CodexConfig.withBlock(original, paths: ["/s/a/SKILL.md"], env: FakeHome().env)
        #expect(added == original + CodexConfig.begin + "\n[[skills.config]]\npath = \"/s/a/SKILL.md\"\nenabled = false\n# kitfold:end\n")
        let entries = CodexConfig.entries(in: added)
        #expect(entries.count == 1 && entries[0].inKitfoldBlock && entries[0].fields["enabled"] == "false")
        #expect(CodexConfig.withBlock(added, paths: [], env: FakeHome().env) == original)
    }

    @Test func detectsLayoutsThatWouldBreak() {
        #expect(CodexConfig.conflictsWithArrayTables("[skills]\nconfig = []\n"))
        #expect(CodexConfig.conflictsWithArrayTables("skills = { config = [] }\n"))
        #expect(CodexConfig.conflictsWithArrayTables("[skills.config]\npath = \"x\"\n"))
        #expect(!CodexConfig.conflictsWithArrayTables("[skills]\nfoo = 1\n[[skills.config]]\npath = \"x\"\n"))
    }

    @Test func removesOnlyTheUsersEntry() {
        let h = FakeHome()
        let text =
            "a = 1\n\n[[skills.config]]\npath = \"/x/SKILL.md\"\nenabled = false\n\n[[skills.config]]\nname = \"y\"\nenabled = false\n"
        #expect(
            CodexConfig.removeEntries(matching: "skills.config/path:/x/SKILL.md", from: text, env: h.env)
                == "a = 1\n\n[[skills.config]]\nname = \"y\"\nenabled = false\n")
    }
}

/// End to end in a fake home: Kitfold writes each agent's own switch when links can't hide a skill.
@Suite struct NativeWriteTests {
    func mode(_ p: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: p))?[.posixPermissions] as? Int) ?? -1 }

    func project(_ h: FakeHome, _ ws: Workspace) throws -> Scope {
        try FileManager.default.createDirectory(atPath: h.path("proj/.git/info"), withIntermediateDirectories: true)
        try ws.saveConfigDirectly(ws.addingProject(h.path("proj"), to: ws.config))
        return .project(h.path("proj"))
    }

    @Test func codexHidesASharedSkillInItsOwnSection() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/shared-one")
        let original = "model = \"o3\"\n\n[mcp_servers.x]\ncommand = \"x\"\nenv = { TOKEN = \"sk-123\" }\n"
        h.write(".codex/config.toml", original)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: h.path(".codex/config.toml"))
        let ws = try h.workspace()
        let ref = ResourceRef(.skill, "shared-one")

        let plan = try ws.assign(ref, .agent(.codex), .off)
        let change = try #require(plan.changes.first { $0.change.path == h.path(".codex/config.toml") })
        #expect(change.diff == nil)
        #expect(change.details == ["+ [[skills.config]] path = \"~/.agents/skills/shared-one/SKILL.md\", enabled = false"])
        #expect(!plan.issues.contains { $0.kind == .stillVisible })
        #expect(try #require(h.read(".codex/config.toml")).hasPrefix(original))
        #expect(mode(h.path(".codex/config.toml")) == 0o600)

        let s = ws.snap()
        #expect(s.agent(.codex)!.visibleSkills(in: .global).isEmpty)
        #expect(s.agent(.geminiCLI)!.visibleSkills(in: .global).map(\.name) == ["shared-one"])  // others unaffected
        #expect(ws.plan(ws.config, snapshot: s).changes.isEmpty)  // stable

        try ws.undo(try #require(ws.history().first).id)
        #expect(h.read(".codex/config.toml") == original)
        try ws.assign(ref, .agent(.codex), .off)
        try ws.assign(ref, .agent(.codex), nil)  // no intent left: Kitfold takes its entry back
        #expect(h.read(".codex/config.toml") == original)
    }

    @Test func claudeHidesALocalFolderWithoutTouchingOtherSettings() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".claude/skills/local-one")
        let original = "{\n  \"env\": {\n    \"API_KEY\": \"sk-secret\"\n  },\n  \"model\": \"opus\"\n}\n"
        h.write(".claude/settings.json", original)
        let ws = try h.workspace()
        let ref = ResourceRef(.skill, "local-one")
        let key = h.path(".claude/settings.json") + "#skillOverrides/local-one"

        let plan = try ws.assign(ref, .agent(.claudeCode), .off)
        let change = try #require(plan.changes.first { $0.change.path == h.path(".claude/settings.json") })
        #expect(change.details == ["+ skillOverrides › \"local-one\": \"off\""])
        #expect(change.risk == .safe)
        #expect(
            h.read(".claude/settings.json")
                == "{\n  \"env\": {\n    \"API_KEY\": \"sk-secret\"\n  },\n  \"model\": \"opus\",\n  \"skillOverrides\": {\n    \"local-one\": \"off\"\n  }\n}\n"
        )
        #expect(ws.store.ownedSettings()[key] == "off")
        #expect(!ws.store.ownedPaths().contains(key))
        let s = ws.snap()
        #expect(s.agent(.claudeCode)!.visibleSkills(in: .global).isEmpty)
        // OpenCode reads ~/.claude/skills too, and keeps the skill: the switch is Claude's alone.
        #expect(s.agent(.openCode)!.visibleSkills(in: .global).map(\.name) == ["local-one"])
        let native = s.agent(.claudeCode)!.state(.global).skills.first!.native
        #expect(native == .disabled(source: "~/.claude/settings.json", byKitfold: true))

        // Switching it back on removes Kitfold's entry; undo brings entry and ownership back.
        try ws.assign(ref, .agent(.claudeCode), .on)
        #expect(h.read(".claude/settings.json") == original)
        #expect(ws.store.ownedSettings()[key] == nil)
        try ws.undo(try #require(ws.history().first).id)
        #expect(ws.store.ownedSettings()[key] == "off")
        #expect(ws.snap().agent(.claudeCode)!.visibleSkills(in: .global).isEmpty)
    }

    @Test func claudeProjectSwitchUsesTheLocalSettingsFile() throws {
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "gamma", description: "Gamma")
        let ref = ResourceRef(.skill, "gamma")
        try ws.assign(ref, .agent(.claudeCode), .on)
        let proj = try project(h, ws)

        let plan = try ws.assign(ref, .agent(.claudeCode), .off, scope: proj)
        #expect(!plan.issues.contains { $0.kind == .stillVisible })
        #expect(h.read("proj/.claude/settings.local.json") == "{\n  \"skillOverrides\": {\n    \"gamma\": \"off\"\n  }\n}\n")
        #expect(h.read("proj/.git/info/exclude")?.contains("/.claude/settings.local.json") == true)
        let s = ws.snap()
        #expect(s.agent(.claudeCode)!.visibleSkills(in: proj).isEmpty)
        #expect(s.agent(.claudeCode)!.visibleSkills(in: .global).map(\.name) == ["gamma"])

        try ws.assign(ref, .agent(.claudeCode), nil, scope: proj)
        #expect(h.kind("proj/.claude/settings.local.json") == .missing)  // Kitfold created it, so it goes
        #expect(h.read("proj/.git/info/exclude")?.contains("settings.local.json") != true)
    }

    @Test func claudeProjectCanBringBackAGloballyHiddenSkill() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".claude/skills/pdf")
        h.write(".claude/settings.json", "{\n  \"skillOverrides\": {\n    \"pdf\": \"off\"\n  }\n}\n")
        let ws = try h.workspace()
        let proj = try project(h, ws)
        try ws.assign(ResourceRef(.skill, "pdf"), .agent(.claudeCode), .on, scope: proj)
        #expect(h.read("proj/.claude/settings.local.json") == "{\n  \"skillOverrides\": {\n    \"pdf\": \"on\"\n  }\n}\n")
        #expect(h.read(".claude/settings.json") == "{\n  \"skillOverrides\": {\n    \"pdf\": \"off\"\n  }\n}\n")
        #expect(ws.snap().agent(.claudeCode)!.visibleSkills(in: proj).map(\.name) == ["pdf"])
    }

    @Test func openCodeOffWhileClaudeOnIsolatesTheTwo() throws {
        // Claude's link lands in ~/.claude/skills, which OpenCode also reads; OpenCode gets a deny rule.
        let h = FakeHome()
        h.installAgents()
        let ws = try h.workspace()
        _ = try ws.library.createSkill(name: "gamma", description: "Gamma")
        let ref = ResourceRef(.skill, "gamma")
        try ws.assign(ref, .agent(.claudeCode), .on) { $0.setRule(ref, agent: .agent(.openCode), scope: .global, state: .off) }
        #expect(
            h.read(".config/opencode/opencode.json")
                == "{\n  \"permission\": {\n    \"skill\": {\n      \"gamma\": \"deny\"\n    }\n  }\n}\n")
        let s = ws.snap()
        #expect(s.agent(.claudeCode)!.visibleSkills(in: .global).map(\.name) == ["gamma"])
        #expect(s.agent(.openCode)!.visibleSkills(in: .global).isEmpty)
        #expect(ws.plan(ws.config, snapshot: s).changes.isEmpty)
    }

    @Test func geminiListAndTheUsersOwnEntry() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/eli5")
        h.skill(".agents/skills/pdf")
        let original = "{\n  \"theme\": \"dark\",\n  \"skills\": {\n    \"disabled\": [\"PDF\"]\n  }\n}\n"
        h.write(".gemini/settings.json", original)
        let ws = try h.workspace()

        try ws.assign(ResourceRef(.skill, "eli5"), .agent(.geminiCLI), .off)
        #expect(
            h.read(".gemini/settings.json") == "{\n  \"theme\": \"dark\",\n  \"skills\": {\n    \"disabled\": [\"PDF\", \"eli5\"]\n  }\n}\n"
        )
        try ws.assign(ResourceRef(.skill, "eli5"), .agent(.geminiCLI), nil)
        #expect(h.read(".gemini/settings.json") == original)

        // An explicit "on" removes the user's own entry, flagged as caution.
        let plan = try ws.assign(ResourceRef(.skill, "pdf"), .agent(.geminiCLI), .on)
        #expect(plan.changes.contains { $0.change.path == h.path(".gemini/settings.json") && $0.risk == .caution })
        #expect(h.read(".gemini/settings.json") == "{\n  \"theme\": \"dark\"\n}\n")
        #expect(ws.snap().agent(.geminiCLI)!.visibleSkills(in: .global).map(\.name) == ["eli5", "pdf"])
    }

    @Test func leavesTheUsersOwnSwitchAlone() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".agents/skills/pdf")
        let original = "{\"skills\": {\"disabled\": [\"pdf\"]}}"
        h.write(".gemini/settings.json", original)
        let ws = try h.workspace()
        let plan = try ws.assign(ResourceRef(.skill, "pdf"), .agent(.geminiCLI), .off)
        #expect(!plan.changes.contains { $0.change.path == h.path(".gemini/settings.json") })
        try ws.assign(ResourceRef(.skill, "pdf"), .agent(.geminiCLI), nil)
        #expect(h.read(".gemini/settings.json") == original)
    }

    @Test func unreadableSettingsAreReportedNotRewritten() throws {
        let h = FakeHome()
        h.installAgents()
        h.skill(".claude/skills/local-one")
        h.write(".claude/settings.json", "{ \"model\": ")
        let ws = try h.workspace()
        var draft = ws.config
        draft.setRule(ResourceRef(.skill, "local-one"), agent: .agent(.claudeCode), scope: .global, state: .off)
        let plan = ws.plan(draft, snapshot: ws.snap())
        #expect(!plan.changes.contains { $0.change.path == h.path(".claude/settings.json") })
        #expect(plan.issues.contains { $0.kind == .unsupported && $0.agent == .claudeCode })
    }

    @Test func journalIsOwnerOnly() throws {
        let h = FakeHome()
        let ws = try h.workspace()
        _ = ws
        #expect(mode(h.path(".kitfold/state.sqlite")) == 0o600)
    }
}
