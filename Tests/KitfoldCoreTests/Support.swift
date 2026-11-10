import Foundation

@testable import KitfoldCore

/// A throwaway $HOME with helpers to lay out agent folders.
final class FakeHome {
    let root: String
    let env: KitfoldEnvironment

    init() {
        // Messages are checked in English whatever the machine's language is.
        Localization.language = .english
        let base = NSTemporaryDirectory() + "kitfold-tests/" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        root = FS.realPath(base)!
        env = KitfoldEnvironment(home: root, variables: ["PATH": "/nonexistent"])
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    func path(_ rel: String) -> String { root + "/" + rel }

    @discardableResult
    func skill(_ rel: String, name: String? = nil, description: String = "Test skill") -> String {
        let dir = path(rel)
        let n = name ?? (rel as NSString).lastPathComponent
        try! FS.write("---\nname: \(n)\ndescription: \(description)\n---\n\n# \(n)\n", to: dir + "/SKILL.md")
        return dir
    }

    func link(_ rel: String, to target: String) {
        try! FS.createSymlink(at: path(rel), to: target.hasPrefix("/") ? target : path(target))
    }

    func write(_ rel: String, _ text: String) { try! FS.write(text, to: path(rel)) }
    func read(_ rel: String) -> String? { FS.read(path(rel)) }
    func kind(_ rel: String) -> FS.Kind { FS.kind(path(rel)) }

    /// Make all four agents "detected" (config dirs exist).
    func installAgents() {
        for d in [".claude", ".codex", ".config/opencode", ".gemini"] {
            try! FileManager.default.createDirectory(atPath: path(d), withIntermediateDirectories: true)
        }
    }

    /// A stand-in command in `~/.local/bin`, which Kitfold searches for agents' commands.
    func installBinary(_ name: String) {
        write(".local/bin/" + name, "#!/bin/sh\necho 1.0.0\n")
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(".local/bin/" + name))
    }

    func workspace() throws -> Workspace { try Workspace(env: env) }
}

extension Workspace {
    /// Set a rule and apply the resulting plan; returns the plan that was applied.
    @discardableResult
    func assign(
        _ ref: ResourceRef, _ agent: AgentSelector, _ state: RuleState?, scope: Scope = .global,
        mutate: ((inout KitfoldConfig) -> Void)? = nil
    ) throws -> Plan {
        var draft = config
        mutate?(&draft)
        if agent == .all {
            draft.setAll(ref, scope: scope, state: state)
        } else {
            draft.setRule(ref, agent: agent, scope: scope, state: state)
        }
        let snap = Scanner(env: env, adapters: adapters).scan(
            config: draft, ownedPaths: store.ownedPaths(), ownedSettings: store.ownedSettings(), probeVersions: false)
        let plan = self.plan(draft, snapshot: snap)
        try apply(plan, summary: "test")
        return plan
    }

    func snap() -> Snapshot { scan(probeVersions: false) }
}
