import Foundation

/// Every agent Kitfold knows: the four described in depth (`BuiltinAgents`) and the many that keep
/// skills the common way (`AgentCatalog.specs`). Agents found on the Mac but in neither list come
/// from `AgentDiscovery`, and the user's own from `KitfoldConfig.customAgents`; the scanner adds those.
public enum AgentCatalog {
    public static var all: [AgentDescriptor] { BuiltinAgents.all + known }
    public static var adapters: [AgentAdapter] { all.map(AgentAdapter.init) }

    /// The catalog agents as descriptors, with every folder an agent reads but doesn't own given its
    /// role: the cross-agent folders are shared; one another agent calls its own is that agent's
    /// (`foreign`, with its owner). A folder two agents both call their own belongs to the first that
    /// lists it (built-in agents first); the other reads it as that agent's, so Kitfold never passes
    /// a link there off as private to one of them.
    public static let known: [AgentDescriptor] = {
        var owners: [String: AgentID] = [:]  // "global|~/x/skills" or "project|.x/skills" → owner
        func key(_ r: SkillRootSpec, home: String) -> String {
            switch r.base {
            case .configDir: return "\(r.scope)|" + (home as NSString).appendingPathComponent(r.path)
            case .home: return "\(r.scope)|~/" + r.path
            case .project, .absolute: return "\(r.scope)|" + r.path
            }
        }
        for d in BuiltinAgents.all {
            for r in d.skillRoots where r.role == .primary { owners[key(r, home: d.configDir)] = d.id }
        }
        var descriptors = specs.map(\.descriptor)
        for d in descriptors {
            for r in d.skillRoots where r.role == .primary && owners[key(r, home: d.configDir)] == nil {
                owners[key(r, home: d.configDir)] = d.id
            }
        }
        for di in descriptors.indices {
            let d = descriptors[di]
            for i in d.skillRoots.indices {
                var r = d.skillRoots[i]
                let k = key(r, home: d.configDir)
                switch r.role {
                case .primary:
                    guard let owner = owners[k], owner != d.id else { continue }
                    r.role = .foreign
                    r.owner = owner
                    r.note = AgentSpec.Notes.otherAgentsFolder
                case .foreign where r.owner == nil:  // one of `reads`
                    if AgentSpec.sharedFolders.contains(k) {
                        r.role = .shared
                        r.note = AgentSpec.Notes.sharedFolder
                    } else if let owner = owners[k], owner != d.id {
                        r.owner = owner
                        r.note = owner == .claudeCode ? AgentSpec.Notes.claudeFolder : AgentSpec.Notes.otherAgentsFolder
                    } else {
                        r.role = .shared
                        r.note = AgentSpec.Notes.otherFolder
                    }
                default: continue
                }
                descriptors[di].skillRoots[i] = r
            }
        }
        return descriptors
    }()

    /// Looks for a descriptor among everything known, built-in first.
    public static func descriptor(_ id: AgentID) -> AgentDescriptor? { all.first { $0.id == id } }
}

/// One agent in the catalog. Most agents keep skills the same way: a folder of their own in their
/// config folder and in each project, often the cross-agent `.agents/skills`, sometimes Claude
/// Code's folders for compatibility. This says which, in a line or two.
struct AgentSpec {
    var id: AgentID
    var name: String
    var vendor: String
    /// The agent's config folder: its existence means "installed", and `skills` hangs off it. Tilde allowed.
    var home: String
    var homeEnv: String?
    var binaries: [String]
    /// Its own global skills folders, highest precedence first: relative to `home`, or starting with `~/`.
    var skills: [String]
    /// Its own project skills folders, relative to the project root.
    var projectSkills: [String]
    /// Reads `~/.agents/skills` (global) and `.agents/skills` (project).
    var agentsGlobal: Bool
    var agentsProject: Bool
    /// Reads Claude Code's `~/.claude/skills` and `.claude/skills` too.
    var claudeGlobal: Bool
    var claudeProject: Bool
    /// Other folders it reads, globally (`~/…`) and in a project. Whose they are is worked out from
    /// the other agents (`AgentCatalog.known`).
    var reads: [String]
    var projectReads: [String]
    /// The folders it reads come before its own (on a name clash, theirs win).
    var readsFirst: Bool
    /// Environment variables that switch off all the folders it reads, or only Claude Code's.
    var readsSkippedWhen: [String]
    var claudeSkippedWhen: [String]
    /// It loads linked skill folders from its own global and project folders (fx and Continue don't).
    var followsLinks: Bool
    var projectFollowsLinks: Bool
    /// Plugin or bundled skills the agent ships, read-only to Kitfold (relative to `home` or `~/`).
    var bundled: [String]
    var instructions: [InstructionFileSpec]
    var requiresName: Bool
    var requiresDescription: Bool
    var nestedDepth: Int
    var docs: String
    var monogram: String?
    var tint: String?
    var markers: [String]
    var configDirMeansInstalled: Bool
    /// The folders were checked against the agent's docs or source (otherwise: the skills CLI's table).
    var verified: Bool
    var notes: [String]

    init(
        _ id: AgentID, _ name: String, vendor: String = "", home: String, homeEnv: String? = nil, binaries: [String] = [],
        skills: [String] = ["skills"], projectSkills: [String] = [], agentsGlobal: Bool = false, agentsProject: Bool = false,
        claudeGlobal: Bool = false, claudeProject: Bool = false, reads: [String] = [], projectReads: [String] = [],
        readsFirst: Bool = false, readsSkippedWhen: [String] = [], claudeSkippedWhen: [String] = [], followsLinks: Bool = true,
        projectFollowsLinks: Bool = true,
        bundled: [String] = [], instructions: [InstructionFileSpec] = [],
        requiresName: Bool = false, requiresDescription: Bool = false, nestedDepth: Int = 0, docs: String = "",
        monogram: String? = nil, tint: String? = nil, markers: [String] = [], configDirMeansInstalled: Bool = true,
        verified: Bool = false, notes: [String] = []
    ) {
        self.id = id; self.name = name; self.vendor = vendor; self.home = home; self.homeEnv = homeEnv; self.binaries = binaries
        self.skills = skills; self.projectSkills = projectSkills; self.agentsGlobal = agentsGlobal; self.agentsProject = agentsProject
        self.claudeGlobal = claudeGlobal; self.claudeProject = claudeProject; self.reads = reads; self.projectReads = projectReads
        self.readsFirst = readsFirst; self.readsSkippedWhen = readsSkippedWhen; self.claudeSkippedWhen = claudeSkippedWhen
        self.followsLinks = followsLinks; self.projectFollowsLinks = projectFollowsLinks
        self.configDirMeansInstalled = configDirMeansInstalled; self.bundled = bundled
        self.instructions = instructions; self.requiresName = requiresName; self.requiresDescription = requiresDescription
        self.nestedDepth = nestedDepth; self.docs = docs; self.monogram = monogram; self.tint = tint; self.markers = markers
        self.verified = verified; self.notes = notes
    }

    /// Notes shared by every generated descriptor; translated like the built-in agents' notes.
    enum Notes {
        static let ownFolder = "Its own skills folder."
        static let ownProjectFolder = "Its own project skills folder."
        static let sharedFolder = "The cross-agent folder: several agents read it."
        static let claudeFolder = "Claude Code's folder, read for compatibility."
        static let otherAgentsFolder = "Another agent's folder that this agent reads too."
        static let otherFolder = "Another skills folder it reads; other tools may use it too."
        static let bundledFolder = "Skills that come with the agent. Read-only to Kitfold."
        static let fromSkillsCLI = "Folders as listed by the skills CLI (vercel-labs/skills); not yet checked against the agent's own docs."
        static let discovered =
            "Kitfold found this skills folder on your Mac and lists it as an agent's. Switch “Managed by Kitfold” on to give it skills; to name its project folder too, add it as your own agent in Settings › Agents."
        static let discoveredFolder = "Found on this Mac."
        static let custom = "Added by you (customAgents in kitfold.json)."
        static let ownInstructions = "Its own instruction file: only this agent reads it, so Kitfold writes its profiles here."
        static let roo = "Roo Code was discontinued on 2026-05-15 (its repository is archived)."
        static let fx =
            "fx doesn't load linked folders from ~/.fx/skills, so Kitfold can't link skills there; fx finds them in ~/.agents/skills and in other agents' folders."
        static let zed = "Zed has no skills folder of its own: it reads only ~/.agents/skills, so a skill can't be given to Zed alone."
        static let geminiFile = "Gemini CLI's file. Antigravity reads it too, so a profile Kitfold writes there for Gemini CLI reaches it."
        static let antigravity =
            "The app and agy read ~/.gemini/config/skills; only the Antigravity IDE still reads the old ~/.gemini/antigravity/skills."
        static let cursor =
            "In the IDE, Settings › Agents › Third-Party Imports turns off Claude Code's and Codex's folders. The CLI always reads them."
        static let devin = "Devin Desktop (Windsurf until June 2026) and Devin for Terminal load the same folders."
        static let claudeFile = "Claude Code's file. Grok reads it too, so a profile Kitfold writes there for Claude Code reaches Grok."
        static let grok =
            "`[compat.claude] skills = false` in ~/.grok/config.toml stops Grok reading Claude Code's skill folders. It also reads Cursor's."
        static let continueLinks =
            "Continue skips linked skill folders, so Kitfold can't give it skills; copy a skill's folder into ~/.continue/skills instead."
        static let amp =
            "amp.skills.disableClaudeCodeSkills and amp.skills.disableGlobalAgentsSkills in Amp's settings stop it reading Claude Code's folders and the shared ones."
        static let all = [
            ownFolder, ownProjectFolder, sharedFolder, claudeFolder, otherAgentsFolder, otherFolder, bundledFolder, fromSkillsCLI,
            discovered,
            discoveredFolder, custom, ownInstructions, roo, fx, zed, amp, geminiFile, antigravity,
            cursor, devin, claudeFile, grok, continueLinks,
        ]
    }

    /// A root given as `~/x` is anchored at home, anything else at the config folder.
    static func root(_ path: String, scope: ScopeKind, role: SkillRootSpec.Role, note: String, verified: Bool) -> SkillRootSpec {
        if path.hasPrefix("~/") {
            return SkillRootSpec(.home, String(path.dropFirst(2)), scope: scope, role: role, note: note, verified: verified)
        }
        if path.hasPrefix("/") { return SkillRootSpec(.absolute, path, scope: scope, role: role, note: note, verified: verified) }
        return SkillRootSpec(.configDir, path, scope: scope, role: role, note: note, verified: verified)
    }

    /// The agent's own global instruction file, where Kitfold writes profiles: relative to its config
    /// folder, or starting with `~/`.
    static func ownInstructions(_ path: String, scope: ScopeKind = .global, header: String? = nil) -> InstructionFileSpec {
        let (base, rel): (PathBase, String) =
            scope == .project ? (.project, path) : path.hasPrefix("~/") ? (.home, String(path.dropFirst(2))) : (.configDir, path)
        return InstructionFileSpec(base, rel, scope: scope, role: .primary, note: Notes.ownInstructions, header: header)
    }

    /// Frontmatter that makes a rules file apply in every session.
    static let kiroSteeringHeader = "---\ninclusion: always\n---\n\n"
    static let alwaysOnRuleHeader = "---\ntrigger: always_on\n---\n\n"
    static let cursorRuleHeader = "---\nalwaysApply: true\n---\n\n"

    /// The cross-agent folders: several agents read them and none owns them.
    static let sharedFolders: Set<String> = ["global|~/.agents/skills", "global|~/.config/agents/skills", "project|.agents/skills"]

    var descriptor: AgentDescriptor {
        func own(_ p: String, _ scope: ScopeKind) -> SkillRootSpec {
            var r =
                scope == .global
                ? Self.root(p, scope: .global, role: .primary, note: Notes.ownFolder, verified: verified)
                : SkillRootSpec(.project, p, scope: .project, role: .primary, note: Notes.ownProjectFolder, verified: verified)
            r.followsLinks = scope == .global ? followsLinks : projectFollowsLinks
            return r
        }
        // Read folders start out as `foreign` without an owner; AgentCatalog.known works out whose they are.
        func read(_ p: String, _ scope: ScopeKind) -> SkillRootSpec {
            let claude = p == "~/.claude/skills" || p == ".claude/skills"
            var r =
                scope == .global
                ? Self.root(p, scope: .global, role: .foreign, note: "", verified: verified)
                : SkillRootSpec(.project, p, scope: .project, role: .foreign, verified: verified)
            r.skippedWhen = readsSkippedWhen + (claude ? claudeSkippedWhen : [])
            return r
        }
        var globalReads = reads, projectOthers = projectReads
        if agentsGlobal && !globalReads.contains("~/.agents/skills") { globalReads.insert("~/.agents/skills", at: 0) }
        if claudeGlobal && !globalReads.contains("~/.claude/skills") { globalReads.append("~/.claude/skills") }
        if agentsProject && !projectOthers.contains(".agents/skills") { projectOthers.insert(".agents/skills", at: 0) }
        if claudeProject && !projectOthers.contains(".claude/skills") { projectOthers.append(".claude/skills") }

        let ownGlobal = skills.map { own($0, .global) }, readGlobal = globalReads.map { read($0, .global) }
        let ownProject = projectSkills.map { own($0, .project) }, readProject = projectOthers.map { read($0, .project) }
        var roots = readsFirst ? readGlobal + ownGlobal : ownGlobal + readGlobal
        roots += bundled.map { Self.root($0, scope: .global, role: .bundled, note: Notes.bundledFolder, verified: verified) }
        roots += readsFirst ? readProject + ownProject : ownProject + readProject

        var d = AgentDescriptor(
            id: id, name: name, vendor: vendor, binaryNames: binaries, binaryDirs: [], configDir: home, configDirEnv: homeEnv,
            skillRoots: roots, instructionFiles: instructions, skillDisable: .none, bundledProvider: nil, globalSkillsWin: false,
            nestedSkillDepth: nestedDepth, policyCoversBundled: false, requiresName: requiresName,
            requiresDescription: requiresDescription, instructionByteLimit: nil, docsURL: docs,
            monogram: monogram ?? AgentSpec.monogram(for: name), tint: tint ?? AgentSpec.tint(for: id.rawValue),
            notes: (verified ? [] : [Notes.fromSkillsCLI]) + notes, source: .catalog, markers: markers)
        d.configDirMeansInstalled = configDirMeansInstalled
        return d
    }

    /// Two letters for a badge: the initials of a two-word name, else the first two letters.
    static func monogram(for name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { !$0.isEmpty }
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String(a).uppercased() + String(b).uppercased() }
        let letters = Array(words.first ?? "?")
        return String(letters.prefix(1)).uppercased() + String(letters.dropFirst().prefix(1)).lowercased()
    }

    /// A stable colour per agent, from a palette that reads on light and dark backgrounds.
    static func tint(for id: String) -> String {
        let palette = [
            "#5B8DEF", "#E0614F", "#3BA776", "#C27BD8", "#E59A2C", "#2FA6B8", "#8C7AE6", "#D6567F", "#6C9A3B", "#B07A4F",
            "#4F7CAC", "#CF6B3E",
        ]
        let sum = id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return palette[Int(sum % UInt32(palette.count))]
    }
}
