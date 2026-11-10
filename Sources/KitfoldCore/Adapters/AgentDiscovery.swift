import Foundation

/// Finds agents Kitfold has no description for: a `skills` folder in `~/.<name>/` or
/// `~/.config/<name>/` that holds at least one skill and that no known agent or skill source
/// claims. Most agents keep their skills exactly there, so such a folder is usually one, but it may
/// also be someone's collection or a repository checkout: a found agent is listed, its skills are
/// shown (and cleaned up when deleted), and Kitfold manages it only once the user switches it on.
/// Read-only, like the rest of the scan.
public enum AgentDiscovery {
    /// Folders that hold skills but belong to no agent.
    static let ignoredNames: Set<String> = [
        "agents", "kitfold", "cache", "local", "npm", "pnpm", "yarn", "bun", "cargo", "rustup", "Trash", "git", "ssh", "gnupg",
        "docker", "vscode", "vscode-server", "skill-migration-backup",
    ]

    /// Descriptors for the unclaimed skills folders, in name order. `known` are the agents already
    /// described (built-in, catalog, custom); `sources` the skill folders Kitfold reads as sources.
    public static func find(env: KitfoldEnvironment, known: [AgentAdapter], sources: [String]) -> [AgentDescriptor] {
        var claimed = Set(sources.map(env.expand))
        claimed.insert(env.librarySkillsDir)
        claimed.insert(env.expand("~/.agents/skills"))
        var agentHomes = Set<String>()
        for a in known {
            for r in a.skillRoots(.global, env) { claimed.insert(r.path) }
            agentHomes.insert(a.configDir(env))
        }
        var ids = Set(known.map(\.id.rawValue))
        var out: [AgentDescriptor] = []
        for (parent, prefix) in [(env.home, "."), (env.expand("~/.config"), "")] {
            for name in FS.children(parent).sorted() where name.hasPrefix(prefix) {
                let bare = String(name.dropFirst(prefix.count))
                guard !bare.isEmpty, !bare.hasPrefix("."), !ignoredNames.contains(bare), bare != "config" else { continue }
                let home = parent + "/" + name
                let skills = home + "/skills"
                guard !agentHomes.contains(home), !claimed.contains(skills), FS.isDirectoryFollowing(skills),
                    !FS.isInside(skills, env.kitfoldHome), holdsSkills(skills)
                else { continue }
                // The id is what rules are saved under, so it comes from where the folder is, not
                // from which other folders happen to exist: `~/.x` is `x`, `~/.config/x` is `x-config`
                // when `x` is taken by a known agent or `~/.x`.
                var id = slug(bare)
                if ids.contains(id) { id += prefix == "." ? "-home" : "-config" }
                if ids.contains(id) {
                    var n = 2
                    while ids.contains("\(id)-\(n)") { n += 1 }
                    id = "\(id)-\(n)"
                }
                ids.insert(id)
                out.append(descriptor(id: AgentID(id), folder: bare, home: home, env: env))
            }
        }
        return out
    }

    /// At least one entry is a skill: a folder (or a link to one) with a SKILL.md.
    static func holdsSkills(_ dir: String) -> Bool {
        FS.children(dir).contains { name in
            !name.hasPrefix(".") && FS.exists(dir + "/" + name + "/SKILL.md")
        }
    }

    static func descriptor(id: AgentID, folder: String, home: String, env: KitfoldEnvironment) -> AgentDescriptor {
        let name = displayName(folder)
        // No project folder: where the agent keeps skills in a project can only be guessed, and a guess
        // would create a folder in every project. A custom agent (Settings › Agents) can name one.
        var d = AgentDescriptor(
            id: id, name: name, vendor: "", binaryNames: [], binaryDirs: [], configDir: env.abbreviate(home),
            configDirEnv: nil,
            skillRoots: [SkillRootSpec(.configDir, "skills", scope: .global, role: .primary, note: AgentSpec.Notes.discoveredFolder)],
            instructionFiles: [], skillDisable: .none, bundledProvider: nil, globalSkillsWin: false, nestedSkillDepth: 0,
            policyCoversBundled: false, instructionByteLimit: nil, docsURL: "", monogram: AgentSpec.monogram(for: name),
            tint: AgentSpec.tint(for: id.rawValue), notes: [AgentSpec.Notes.discovered], source: .discovered)
        d.configDirMeansInstalled = false
        return d
    }

    /// `openclaw-autoclaw` → `Openclaw Autoclaw`, `workbuddy` → `Workbuddy`.
    static func displayName(_ folder: String) -> String {
        folder.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func slug(_ s: String) -> String {
        let out = SkillEntry.slugify(s)
        return out.isEmpty ? "agent" : out
    }
}
