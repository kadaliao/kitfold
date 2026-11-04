import Foundation

/// Reads the machine (never writes) and builds a `Snapshot`.
public struct Scanner: Sendable {
    public var env: KitfoldEnvironment
    public var adapters: [AgentAdapter]

    public init(env: KitfoldEnvironment, adapters: [AgentAdapter]) {
        self.env = env
        self.adapters = adapters
    }

    public func scan(
        config: KitfoldConfig, ownedPaths: Set<String>, ownedSettings: [String: String] = [:], probeVersions: Bool = true
    ) -> Snapshot {
        var env = self.env
        for (k, v) in config.agents { if let dir = v.configDir { env.configDirOverrides[AgentID(k)] = dir } }
        let library = LibraryStore(env: env)
        var catalog = library.catalog(sources: config.sources)
        let scopes: [Scope] = [.global] + config.projects.map { .project($0.path) }

        // Probe agents concurrently: `--version` calls dominate scan time.
        let probes = UnsafeSendableBox([AgentInstallation?](repeating: nil, count: adapters.count))
        let probeEnv = env
        let list = adapters
        DispatchQueue.concurrentPerform(iterations: list.count) { i in
            let p = AgentProbe.probe(list[i], env: probeEnv, runVersion: probeVersions)
            probes.lock.withLock { probes.value[i] = p }
        }

        var agents: [AgentState] = []
        for (i, adapter) in adapters.enumerated() {
            let inst = probes.value[i]!
            var scopeStates: [Scope: AgentScopeState] = [:]
            for scope in scopes {
                let policy = NativePolicy.load(adapter: adapter, scope: scope, env: env, ledger: ownedSettings)
                var skills =
                    adapter.skillRoots(scope, env).flatMap { observe(root: $0, nestedDepth: adapter.descriptor.nestedSkillDepth) }
                    + BundledSkills.observe(adapter: adapter, scope: scope, env: env)
                for i in skills.indices {
                    if let s = skills[i].skill { skills[i].skipReason = adapter.descriptor.skipReason(s) }
                    if skills[i].root.spec.role != .bundled || adapter.descriptor.policyCoversBundled {
                        skills[i].native = policy.state(name: skills[i].name, skillFile: skills[i].skillFile)
                    }
                }
                let effective = Set(adapter.effectiveInstructionFiles(scope, env).map(\.path))
                let files = adapter.instructionFiles(scope, env).map { f in
                    instructionState(f, loaded: effective.contains(f.path))
                }
                scopeStates[scope] = AgentScopeState(skills: skills, instructions: files, policy: policy)
            }
            agents.append(
                AgentState(
                    adapter: adapter, installation: inst,
                    enabled: config.isAgentEnabled(adapter.id, detected: inst.isDetected), scopes: scopeStates))
        }

        // Which agents load the same instruction file?
        for scope in scopes {
            var readers: [String: [AgentID]] = [:]
            for a in agents {
                for f in a.state(scope).instructions where f.isLoaded {
                    readers[f.realPath ?? f.file.path, default: []].append(a.id)
                }
            }
            for ai in agents.indices {
                guard var st = agents[ai].scopes[scope] else { continue }
                for fi in st.instructions.indices {
                    let key = st.instructions[fi].realPath ?? st.instructions[fi].file.path
                    st.instructions[fi].sharedWith = (readers[key] ?? []).filter { $0 != agents[ai].id }
                }
                agents[ai].scopes[scope] = st
            }
        }

        // Fold skills discovered in agent directories into the catalog.
        var known = Set(catalog.map(\.path))
        for a in agents {
            for scope in scopes {
                for s in a.state(scope).skills {
                    guard var entry = s.skill, let real = s.realPath, !known.contains(real) else { continue }
                    if let parent = s.nestedIn {
                        entry.origin = .nested(parent)
                        catalog.append(entry)
                        known.insert(real)
                        continue
                    }
                    switch s.root.spec.role {
                    case .bundled: entry.origin = .bundled(a.id)
                    case .primary, .foreign, .shared:
                        entry.origin = s.isSymlink ? .external : .agentLocal(s.root.spec.owner ?? a.id)
                    }
                    catalog.append(entry)
                    known.insert(real)
                }
            }
        }

        var snapshot = Snapshot(
            env: env, config: config, agents: agents, catalog: catalog, profiles: library.profiles(), issues: [],
            ownedPaths: ownedPaths, scannedAt: Date())
        snapshot.ownedSettings = ownedSettings
        snapshot.buildIndex()
        snapshot.issues = Diagnostics.issues(in: snapshot)
        return snapshot
    }

    /// Entries in one skills directory, in name order. With `nestedDepth > 0`, SKILL.md files
    /// inside a skill's own folder are reported too (as the agent would load them).
    func observe(root: ResolvedSkillRoot, nestedDepth: Int = 0) -> [ObservedSkill] {
        let top = observeTop(root: root)
        guard nestedDepth > 0, root.spec.role != .bundled else { return top }
        var out: [ObservedSkill] = []
        for s in top {
            out.append(s)
            guard s.isReadable, let real = s.realPath else { continue }
            for dir in findNested(real, depth: nestedDepth - 1, stopAtSkill: false) {
                var n = observeEntry(dir, root: root)
                n.nestedIn = s.name
                out.append(n)
            }
        }
        return out
    }

    func observeTop(root: ResolvedSkillRoot) -> [ObservedSkill] {
        guard FS.isDirectoryFollowing(root.path) else { return [] }
        if root.spec.nestedDepth > 0 {
            return findNested(root.path, depth: root.spec.nestedDepth).map { observeEntry($0, root: root) }
        }
        return FS.children(root.path).compactMap { name -> ObservedSkill? in
            if name.hasPrefix(".") || root.spec.ignore.contains(name) { return nil }
            let p = root.path + "/" + name
            switch FS.kind(p) {
            case .file, .missing: return nil
            case .directory:
                // Real directories without SKILL.md are not skills (e.g. Claude's `synced/`).
                guard FS.exists(p + "/SKILL.md") else { return nil }
            case .symlink:
                break  // broken links are reported
            }
            return observeEntry(p, root: root)
        }
    }

    func observeEntry(_ p: String, root: ResolvedSkillRoot) -> ObservedSkill {
        let dest = FS.linkDestination(p)
        let real = FS.realPath(p)
        var skill: SkillEntry?
        if let real, FS.isDirectoryFollowing(real) { skill = SkillEntry.read(directory: real, origin: .external) }
        return ObservedSkill(
            agent: root.agent, scope: root.scope, root: root, entryPath: p, entryName: (p as NSString).lastPathComponent,
            linkTarget: dest, realPath: real, skill: skill)
    }

    /// Folders containing SKILL.md below `dir`. `stopAtSkill: false` keeps descending into skill
    /// folders too (OpenCode globs `**/SKILL.md`, so skills nested in nested skills load as well).
    func findNested(_ dir: String, depth: Int, stopAtSkill: Bool = true) -> [String] {
        guard depth >= 0 else { return [] }
        var out: [String] = []
        for name in FS.children(dir) where !name.hasPrefix(".") && !Hashing.ignoredNames.contains(name) {
            let p = dir + "/" + name
            guard FS.isDirectoryFollowing(p) else { continue }
            let isSkill = FS.exists(p + "/SKILL.md")
            if isSkill { out.append(p) }
            if !isSkill || !stopAtSkill { out += findNested(p, depth: depth - 1, stopAtSkill: stopAtSkill) }
        }
        return out
    }

    func instructionState(_ f: ResolvedInstructionFile, loaded: Bool) -> InstructionFileState {
        let kind = FS.kind(f.path)
        let text = FS.read(f.path) ?? ""
        let isLink: Bool
        if case .symlink = kind { isLink = true } else { isLink = false }
        return InstructionFileState(
            file: f, exists: kind != .missing, isLoaded: loaded, isSymlink: isLink, realPath: FS.realPath(f.path),
            byteCount: text.utf8.count, blocks: ManagedBlock.findAll(in: text),
            foreignBlocks: ManagedBlock.foreignBlocks(in: text), sharedWith: [])
    }
}

/// Small lock-protected box for collecting results from `concurrentPerform`.
final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T
    let lock = NSLock()
    init(_ v: T) { value = v }
}
