import Foundation
import Testing

@testable import KitfoldCore

@Suite struct FrontmatterTests {
    @Test func scalarsListsAndBlocks() {
        let fm = Frontmatter.parse(
            """
            ---
            name: pdf-tools
            description: "Read: and write PDFs"
            tags: [docs, "pdf"]
            skills:
              - alpha
              - beta
            long: >
              folded line one
              line two
            literal: |
              keep
              lines
            metadata:
              short-description: nested
            ---
            # Body
            """)
        #expect(fm.present)
        #expect(fm["name"] == "pdf-tools")
        #expect(fm["description"] == "Read: and write PDFs")
        #expect(fm.list("tags") == ["docs", "pdf"])
        #expect(fm.list("skills") == ["alpha", "beta"])
        #expect(fm["long"] == "folded line one line two")
        #expect(fm["literal"] == "keep\nlines")
        #expect(fm.body.contains("# Body"))
        #expect(fm.parseError == nil)
    }

    @Test func noFrontmatter() {
        let fm = Frontmatter.parse("# Just markdown")
        #expect(!fm.present)
        #expect(fm.body == "# Just markdown")
    }

    @Test func multilinePlainScalar() {
        let fm = Frontmatter.parse("---\ndescription: first part\n  second part\nname: x\n---\n")
        #expect(fm["description"] == "first part second part")
        #expect(fm["name"] == "x")
    }

    @Test func renderRoundTrip() {
        let text = Frontmatter.render(fields: [("name", .string("a: b")), ("skills", .list(["x", "y"]))], body: "Body\n")
        let fm = Frontmatter.parse(text)
        #expect(fm["name"] == "a: b")
        #expect(fm.list("skills") == ["x", "y"])
        #expect(fm.body.trimmingCharacters(in: .whitespacesAndNewlines) == "Body")
    }
}

@Suite struct ManagedBlockTests {
    @Test func insertAtTopKeepsUserContent() {
        let user = "# My notes\n\nkeep me\n"
        let out = ManagedBlock.apply([("backend", "Use Go."), ("review", "Be strict.")], to: user)
        let blocks = ManagedBlock.findAll(in: out)
        #expect(blocks.map(\.profile) == ["backend", "review"])
        #expect(blocks[0].body == "Use Go.")
        #expect(!blocks[0].isModifiedOutsideKitfold)
        #expect(out.hasSuffix(user))
        #expect(ManagedBlock.userContent(of: out) == user)
    }

    @Test func replaceInPlaceAndRemove() {
        let start = "intro\n\n" + ManagedBlock.apply([("a", "one")], to: "") + "\noutro\n"
        let updated = ManagedBlock.apply([("a", "two")], to: start)
        #expect(updated.hasPrefix("intro\n"))
        #expect(updated.hasSuffix("outro\n"))
        #expect(ManagedBlock.findAll(in: updated).first?.body == "two")
        let removed = ManagedBlock.apply([], to: updated)
        #expect(ManagedBlock.findAll(in: removed).isEmpty)
        #expect(removed.contains("intro") && removed.contains("outro"))
    }

    @Test func emptyFileRoundTrip() {
        let out = ManagedBlock.apply([("a", "x")], to: "")
        #expect(ManagedBlock.apply([], to: out) == "")
    }

    @Test func detectsDriftAndForeignBlocks() {
        var text = ManagedBlock.apply([("a", "original")], to: "<!-- magpie:begin · x -->\nm\n<!-- magpie:end -->\n")
        text = text.replacingOccurrences(of: "original", with: "edited by hand")
        let b = ManagedBlock.findAll(in: text)
        #expect(b.count == 1)
        #expect(b[0].isModifiedOutsideKitfold)
        #expect(ManagedBlock.foreignBlocks(in: text) == ["magpie"])
    }
}

@Suite struct DiffTests {
    @Test func basicDiff() {
        let ops = LineDiff.diff("a\nb\nc\n", "a\nB\nc\nd\n")
        let s = LineDiff.stats(ops)
        #expect(s.added == 2 && s.removed == 1)
        let hunks = LineDiff.hunks(ops)
        #expect(hunks.count == 1)
    }

    @Test func identical() {
        #expect(LineDiff.stats(LineDiff.diff("x\ny", "x\ny")) == (0, 0))
    }
}

@Suite struct NativeConfigParsingTests {
    @Test func tomlArrayTables() {
        let toml = """
            model = "x"
            [[skills.config]]
            path = "/a/SKILL.md"
            enabled = false # off
            [[skills.config]]
            name = 'b'
            enabled = true
            [plugins."p@m"]
            enabled = true
            [projects."/x"]
            trust_level = "trusted"
            """
        let entries = MiniTOML.arrayTables(named: "skills.config", in: toml)
        #expect(entries.count == 2)
        #expect(entries[0]["path"] == "/a/SKILL.md" && entries[0]["enabled"] == "false")
        #expect(entries[1]["name"] == "b")
        #expect(MiniTOML.tables(prefix: "plugins", in: toml)["p@m"]?["enabled"] == "true")
    }

    @Test func jsoncComments() {
        let text = """
            {
              // comment
              "a": "http://x/*not a comment*/", /* block */
              "b": [1, 2,],
            }
            """
        let obj = try? JSONSerialization.jsonObject(with: Data(JSONC.strip(text).utf8)) as? [String: Any]
        #expect(obj?["a"] as? String == "http://x/*not a comment*/")
        #expect((obj?["b"] as? [Int]) == [1, 2])
    }

    @Test func openCodeWildcards() {
        let home = FakeHome()
        home.write(".config/opencode/opencode.json", #"{"permission": {"skill": {"*": "allow", "internal-*": "deny"}}}"#)
        let adapter = AgentAdapter(BuiltinAgents.openCode)
        let p = NativePolicy.load(adapter: adapter, scope: .global, env: home.env)
        #expect(p.state(name: "internal-docs", skillFile: nil).isDisabled)
        #expect(!p.state(name: "pdf", skillFile: nil).isDisabled)
    }

    @Test func claudeProjectOverridesGlobal() {
        let home = FakeHome()
        home.write(".claude/settings.json", #"{"skillOverrides": {"pdf": "off"}}"#)
        home.write("proj/.claude/settings.local.json", #"{"skillOverrides": {"pdf": "on", "eli5": "name-only"}}"#)
        let a = AgentAdapter(BuiltinAgents.claudeCode)
        #expect(NativePolicy.load(adapter: a, scope: .global, env: home.env).state(name: "pdf", skillFile: nil).isDisabled)
        let pp = NativePolicy.load(adapter: a, scope: .project(home.path("proj")), env: home.env)
        #expect(!pp.state(name: "pdf", skillFile: nil).isDisabled)
        #expect(pp.state(name: "eli5", skillFile: nil) != .enabled)
    }
}
