import Foundation

/// How a path in an agent descriptor is anchored.
public enum PathBase: String, Sendable, Hashable, Codable {
    case home  // ~
    case configDir  // the agent's config dir (~/.claude, $CODEX_HOME…)
    case project  // project root
    case absolute  // path is absolute already (e.g. /etc/codex/skills)
}

public enum ScopeKind: String, Sendable, Hashable, Codable { case global, project }

/// One directory an agent scans for skills.
public struct SkillRootSpec: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Hashable, Codable {
        /// The agent's own skills directory. Kitfold deploys symlinks here.
        case primary
        /// A cross-agent directory (e.g. `~/.agents/skills`) that several agents read.
        /// Anything placed here is visible to all of them — Kitfold never deploys here implicitly.
        case shared
        /// Another agent's directory this agent also reads (e.g. OpenCode → `~/.claude/skills`).
        case foreign
        /// Plugin / extension / bundled / admin skills. Read-only to Kitfold.
        case bundled
    }

    public var base: PathBase
    public var path: String
    public var scope: ScopeKind
    public var role: Role
    /// For `.foreign`, the agent that owns the directory.
    public var owner: AgentID?
    /// Skills are found deeper than `<root>/<name>/SKILL.md` (plugins, extensions).
    public var nestedDepth: Int
    /// Entry names that are not skills (reserved by the agent, e.g. Claude's `synced`).
    public var ignore: [String]
    /// Human explanation shown in the UI.
    public var note: String
    /// Whether this behavior was verified against docs/source (vs. assumed).
    public var verified: Bool
    /// Environment variables that, set to a true value, make the agent skip this folder.
    public var skippedWhen: [String]

    public init(
        _ base: PathBase, _ path: String, scope: ScopeKind, role: Role, owner: AgentID? = nil,
        nestedDepth: Int = 0, ignore: [String] = [], note: String = "", verified: Bool = true, skippedWhen: [String] = []
    ) {
        self.base = base; self.path = path; self.scope = scope; self.role = role; self.owner = owner
        self.nestedDepth = nestedDepth; self.ignore = ignore; self.note = note; self.verified = verified
        self.skippedWhen = skippedWhen
    }

    /// The values OpenCode reads as true (`1`, `true`, `yes`, `on`, `y`).
    static func isTrue(_ value: String?) -> Bool { ["1", "true", "yes", "on", "y"].contains(value ?? "") }

    func isSkipped(in env: KitfoldEnvironment) -> Bool { skippedWhen.contains { Self.isTrue(env.variables[$0]) } }
}

/// One instruction file (or a `dir/*.md` pattern) an agent loads.
public struct InstructionFileSpec: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Hashable, Codable {
        /// Kitfold writes its managed blocks here for this agent/scope.
        case primary
        /// Also loaded (shown in the effective view, not written).
        case loaded
        /// Loaded only when none of `related` exists.
        case fallback
        /// Replaces every file in `related` when present.
        case override
    }
    public var base: PathBase
    /// Relative path; may end in `/*.md` or `/**/*.md` to match a folder of files.
    public var path: String
    public var scope: ScopeKind
    public var role: Role
    public var related: [String]
    public var relatedBase: PathBase?
    public var note: String
    public var verified: Bool

    public init(
        _ base: PathBase, _ path: String, scope: ScopeKind, role: Role, related: [String] = [],
        relatedBase: PathBase? = nil, note: String = "", verified: Bool = true
    ) {
        self.base = base; self.path = path; self.scope = scope; self.role = role
        self.related = related; self.relatedBase = relatedBase; self.note = note; self.verified = verified
    }
}

/// How (if at all) an agent lets you hide one skill without deleting it.
public enum SkillDisableMechanism: String, Sendable, Hashable, Codable {
    case none
    case claudeSettings  // skillOverrides in settings.json / settings.local.json
    case codexConfig  // [[skills.config]] enabled = false in $CODEX_HOME/config.toml
    case openCodePermission  // permission.skill { name: deny } in opencode.json
    case geminiSettings  // skills.disabled in settings.json
}

/// Declarative description of an agent. Adding an agent = adding one of these;
/// no business logic hard-codes agent paths.
public struct AgentDescriptor: Sendable, Hashable, Codable, Identifiable {
    public var id: AgentID
    public var name: String
    public var vendor: String
    public var binaryNames: [String]
    public var binaryDirs: [String]
    public var configDir: String
    public var configDirEnv: String?
    /// Highest precedence first, per scope.
    public var skillRoots: [SkillRootSpec]
    public var instructionFiles: [InstructionFileSpec]
    public var skillDisable: SkillDisableMechanism
    /// Plugin / extension skills discovered through the agent's own index.
    public var bundledProvider: BundledProvider?
    /// On a name clash, the global skill beats the project one (Claude Code).
    public var globalSkillsWin: Bool
    /// How deep the agent looks for SKILL.md inside a skill folder (0 = top level only).
    /// Codex and OpenCode treat nested SKILL.md files as separate skills.
    public var nestedSkillDepth: Int
    /// The agent's own disable settings also apply to plugin/bundled skills.
    public var policyCoversBundled: Bool
    /// Frontmatter the agent insists on; a SKILL.md without it is skipped.
    public var requiresName = false
    public var requiresDescription = false

    /// Why the agent would skip this skill, if it would.
    public func skipReason(_ skill: SkillEntry) -> String? {
        let noName = requiresName && (skill.frontmatter["name"] ?? "").isEmpty
        let noDescription = requiresDescription && skill.description.isEmpty
        switch (noName, noDescription) {
        case (true, true): return L("\(name) skips skills without a name and description")
        case (true, false): return L("\(name) skips skills without a name in SKILL.md")
        case (false, true): return L("\(name) skips skills without a description in SKILL.md")
        default: return nil
        }
    }
    /// Max bytes of instructions the agent reads (nil = unknown/unbounded).
    public var instructionByteLimit: Int?
    public var docsURL: String
    public var monogram: String
    /// Accent color, hex.
    public var tint: String
    public var notes: [String]
}

public struct ResolvedSkillRoot: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var spec: SkillRootSpec
    public var agent: AgentID
    public var scope: Scope
}

public struct ResolvedInstructionFile: Sendable, Hashable, Identifiable {
    public var id: String { "\(agent)|\(path)" }
    public var path: String
    public var spec: InstructionFileSpec
    public var agent: AgentID
    public var scope: Scope
    public var related: [String]
}

/// Resolves a descriptor's relative specs against a concrete environment.
public struct AgentAdapter: Sendable, Hashable, Identifiable {
    public var descriptor: AgentDescriptor
    public var id: AgentID { descriptor.id }
    public var name: String { descriptor.name }

    public init(_ descriptor: AgentDescriptor) { self.descriptor = descriptor }

    public func configDir(_ env: KitfoldEnvironment) -> String {
        if let o = env.configDirOverrides[id], !o.isEmpty { return env.expand(o) }
        if let key = descriptor.configDirEnv, let v = env.variables[key], !v.isEmpty { return env.expand(v) }
        return env.expand(descriptor.configDir)
    }

    func resolve(_ base: PathBase, _ path: String, scope: Scope, env: KitfoldEnvironment) -> String? {
        switch base {
        case .home: return env.expand("~/" + path)
        case .configDir: return FS.standardize(configDir(env) + "/" + path)
        case .absolute: return FS.standardize(path)
        case .project:
            guard let root = scope.projectPath else { return nil }
            return FS.standardize(root + "/" + path)
        }
    }

    public func skillRoots(_ scope: Scope, _ env: KitfoldEnvironment) -> [ResolvedSkillRoot] {
        let kind: ScopeKind = scope.isGlobal ? .global : .project
        return descriptor.skillRoots.filter { $0.scope == kind && !$0.isSkipped(in: env) }.compactMap { spec in
            resolve(spec.base, spec.path, scope: scope, env: env).map {
                ResolvedSkillRoot(path: $0, spec: spec, agent: id, scope: scope)
            }
        }
    }

    /// Where Kitfold deploys skills for this agent in `scope`.
    public func primarySkillDir(_ scope: Scope, _ env: KitfoldEnvironment) -> String? {
        skillRoots(scope, env).first { $0.spec.role == .primary }?.path
    }

    public func instructionFiles(_ scope: Scope, _ env: KitfoldEnvironment) -> [ResolvedInstructionFile] {
        let kind: ScopeKind = scope.isGlobal ? .global : .project
        let specs = descriptor.instructionFiles.filter { $0.scope == kind }
        var resolved: [(order: Int, file: ResolvedInstructionFile)] = []
        var seen = Set<String>()
        // Primary specs first so a pattern (e.g. rules/**/*.md) doesn't list Kitfold's own file twice.
        let ranked = specs.enumerated().sorted {
            ($0.element.role == .primary ? 0 : 1, $0.offset) < ($1.element.role == .primary ? 0 : 1, $1.offset)
        }
        for (order, spec) in ranked {
            guard let p = resolve(spec.base, spec.path, scope: scope, env: env) else { continue }
            let related = spec.related.compactMap { resolve(spec.relatedBase ?? spec.base, $0, scope: scope, env: env) }
            for path in AgentAdapter.expandPattern(p) where seen.insert(path).inserted {
                resolved.append((order, ResolvedInstructionFile(path: path, spec: spec, agent: id, scope: scope, related: related)))
            }
        }
        // Back to descriptor (load) order for display.
        return resolved.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map { $0.element.file }
    }

    /// `dir/*.md` → files in dir; `dir/**/*.md` → recursive. Plain paths are returned as-is.
    static func expandPattern(_ p: String) -> [String] {
        guard p.hasSuffix("*.md") else { return [p] }
        let recursive = p.hasSuffix("/**/*.md")
        let dir = recursive ? String(p.dropLast("/**/*.md".count)) : String(p.dropLast("/*.md".count))
        guard FS.isDirectoryFollowing(dir) else { return [] }
        if !recursive {
            return FS.children(dir).filter { $0.hasSuffix(".md") }.map { dir + "/" + $0 }
        }
        var out: [String] = []
        if let e = FileManager.default.enumerator(atPath: dir) {
            while let rel = e.nextObject() as? String { if rel.hasSuffix(".md") { out.append(dir + "/" + rel) } }
        }
        return out.sorted()
    }

    /// Where Kitfold writes its managed blocks for this agent in `scope`.
    public func primaryInstructionFile(_ scope: Scope, _ env: KitfoldEnvironment) -> String? {
        instructionFiles(scope, env).first { $0.spec.role == .primary }?.path
    }

    /// Files that are loaded right now, honoring fallback/override rules.
    public func effectiveInstructionFiles(_ scope: Scope, _ env: KitfoldEnvironment) -> [ResolvedInstructionFile] {
        let all = instructionFiles(scope, env)
        func present(_ p: String) -> Bool {
            // Codex ignores an empty override file.
            guard FS.exists(p) else { return false }
            return !(FS.read(p) ?? "x").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return all.filter { f in
            switch f.spec.role {
            case .primary, .loaded:
                let overridden = all.contains { $0.spec.role == .override && $0.related.contains(f.path) && present($0.path) }
                return !overridden && FS.exists(f.path)
            case .override:
                return present(f.path)
            case .fallback:
                return !f.related.contains(where: FS.exists) && FS.exists(f.path)
            }
        }
    }

    // MARK: detection

    public func findBinary(_ env: KitfoldEnvironment) -> String? {
        let dirs = descriptor.binaryDirs.map(env.expand) + env.binarySearchDirs
        for dir in dirs {
            for name in descriptor.binaryNames {
                let p = dir + "/" + name
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }
}

/// Result of probing the machine for one agent.
public struct AgentInstallation: Sendable, Hashable {
    public var binaryPath: String?
    public var version: String?
    public var configDir: String
    public var configDirExists: Bool
    public var isDetected: Bool { binaryPath != nil || configDirExists }
}

public enum AgentProbe {
    /// Runs `<binary> --version` with a short timeout. Never runs anything else.
    public static func version(binary: String, timeout: TimeInterval = 4) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["--version"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // First version-looking token of e.g. "codex-cli 0.164.0" / "2.1.318 (Claude Code)".
        if let r = text.range(of: #"\d+\.\d+(\.\d+)?([\-+][0-9A-Za-z.\-]+)?"#, options: .regularExpression) {
            return String(text[r])
        }
        return text.isEmpty ? nil : String(text.prefix(40))
    }

    public static func probe(_ adapter: AgentAdapter, env: KitfoldEnvironment, runVersion: Bool = true) -> AgentInstallation {
        let bin = adapter.findBinary(env)
        let dir = adapter.configDir(env)
        return AgentInstallation(
            binaryPath: bin,
            version: runVersion ? bin.flatMap { version(binary: $0) } : nil,
            configDir: dir,
            configDirExists: FS.isDirectoryFollowing(dir))
    }
}
