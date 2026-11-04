import Foundation

/// Health checks over a snapshot: broken links, duplicates, drift, foreign blocks, size limits.
enum Diagnostics {
    static func issues(in s: Snapshot) -> [Issue] {
        var out: [Issue] = []
        func ab(_ p: String) -> String { s.env.abbreviate(p) }

        // Broken links, grouped by folder so one dead link read by three agents is one problem.
        struct Broken { var target: String; var agents: [AgentID] }
        var broken: [Scope: [String: [String: Broken]]] = [:]  // scope → folder → link path → info

        for a in s.agents where a.enabled {
            for scope in s.scopes {
                let st = a.state(scope)
                for o in st.skills {
                    if o.isBroken {
                        let folder = (o.entryPath as NSString).deletingLastPathComponent
                        var b =
                            broken[scope, default: [:]][folder, default: [:]][o.entryPath]
                            ?? Broken(target: o.linkTarget ?? "?", agents: [])
                        if !b.agents.contains(a.id) { b.agents.append(a.id) }
                        broken[scope, default: [:]][folder, default: [:]][o.entryPath] = b
                    } else if !o.isReadable {
                        out.append(
                            Issue(
                                .invalidSkill, .warning, "“\(o.entryName)” has no SKILL.md",
                                detail: "\(ab(o.entryPath)) is in a skills folder but isn't a skill.",
                                paths: [o.entryPath], agent: a.id, scope: scope))
                    }
                }

                // Name clashes the agent sees here. In a project, only report clashes involving project skills.
                let reachable = a.reachableSkills(in: scope).filter { $0.skill.isActive }
                var sameFolderTwice = 0
                for (name, group) in Dictionary(grouping: reachable, by: { $0.skill.name }) where group.count > 1 {
                    if !scope.isGlobal && group.allSatisfy({ $0.inherited }) { continue }
                    let folders = Set(group.compactMap { $0.skill.realPath })
                    if folders.count > 1 {
                        let first = group[0].skill
                        out.append(
                            Issue(
                                .duplicateName, .warning, "\(a.name) sees \(folders.count) different skills named “\(name)”",
                                detail: "\(ab(first.entryPath)) takes precedence. Also found: "
                                    + group.dropFirst().map { ab($0.skill.entryPath) }.joined(separator: ", "),
                                paths: group.map { $0.skill.entryPath }, agent: a.id, scope: scope, key: name))
                    } else {
                        sameFolderTwice += 1
                    }
                }
                if sameFolderTwice > 0 {
                    let roots = Set(reachable.map { $0.skill.root.path }).map(ab).sorted()
                    out.append(
                        Issue(
                            .duplicateName, .info, "\(a.name) reaches \(sameFolderTwice) skills through two folders",
                            detail:
                                "The same skill folders are found via \(roots.joined(separator: ", ")). Some agents list them twice or warn about a conflict.",
                            agent: a.id, scope: scope, key: "same-folder"))
                }

                var loadedBytes = 0
                for f in st.instructions where f.exists {
                    if f.isLoaded { loadedBytes += f.byteCount }
                    for b in f.driftedBlocks {
                        out.append(
                            Issue(
                                .blockDrift, .warning, "Profile “\(b.profile)” was edited outside Kitfold",
                                detail: "\(ab(f.file.path)): Kitfold won't overwrite it until you keep or discard the edit.",
                                paths: [f.file.path], agent: a.id, scope: scope, key: f.file.path + b.profile))
                    }
                    for tool in f.foreignBlocks {
                        out.append(
                            Issue(
                                .foreignBlock, .info, "\(tool.capitalized) manages part of \((f.file.path as NSString).lastPathComponent)",
                                detail: "\(ab(f.file.path)) has a block written by \(tool). Kitfold leaves it alone.",
                                paths: [f.file.path], key: f.file.path + tool))
                    }
                }
                if let limit = a.adapter.descriptor.instructionByteLimit, loadedBytes > limit {
                    out.append(
                        Issue(
                            .sizeLimit, .warning, "\(a.name) instructions exceed \(limit / 1024) KiB",
                            detail: "\(loadedBytes) bytes are loaded; \(a.name) cuts off everything past \(limit) bytes.",
                            agent: a.id, scope: scope))
                }
            }
        }

        func names(_ ids: [AgentID]) -> String { ids.compactMap { s.agent($0)?.name }.joined(separator: ", ") }
        for (scope, folders) in broken {
            for (folder, links) in folders {
                let agents = Array(Set(links.values.flatMap(\.agents))).sorted()
                if links.count >= 3 {
                    let list = links.keys.map { ($0 as NSString).lastPathComponent }.sorted()
                    out.append(
                        Issue(
                            .brokenLink, .error, "\(links.count) broken skill links in \(ab(folder))",
                            detail:
                                "\(list.joined(separator: ", ")) point to folders that no longer exist. Skipped silently by \(names(agents)).",
                            paths: links.keys.sorted(), agent: agents.first, alsoAffects: Array(agents.dropFirst()), scope: scope,
                            key: folder))
                } else {
                    for (path, b) in links {
                        out.append(
                            Issue(
                                .brokenLink, .error, "Broken skill link “\((path as NSString).lastPathComponent)”",
                                detail: "\(ab(path)) → \(ab(b.target)), which no longer exists. Skipped silently by \(names(b.agents)).",
                                paths: [path], agent: b.agents.first, alsoAffects: Array(b.agents.dropFirst()), scope: scope, key: path))
                    }
                }
            }
        }

        // Skill-folder quality, once per folder in the library and sources.
        for e in s.catalog {
            switch e.origin {
            case .library, .source: break
            default: continue
            }
            for p in e.problems {
                out.append(Issue(.invalidSkill, .info, "\(e.name): \(p)", paths: [e.path], key: e.path + p))
            }
            let nested = nestedSkillFiles(in: e.path)
            if !nested.isEmpty {
                out.append(
                    Issue(
                        .nestedSkill, .warning, "“\(e.name)” contains \(nested.count) nested SKILL.md",
                        detail: "Codex and OpenCode load each nested SKILL.md as a separate skill: "
                            + nested.prefix(3).map(ab).joined(separator: ", "),
                        paths: [e.path] + nested, key: e.path))
            }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
            .sorted { ($0.severity.rawValue, $1.title) > ($1.severity.rawValue, $0.title) }
    }

    /// SKILL.md files below a skill's top level (resource folders), up to a few levels deep.
    static func nestedSkillFiles(in dir: String, maxDepth: Int = 4) -> [String] {
        var out: [String] = []
        func walk(_ d: String, _ depth: Int) {
            guard depth <= maxDepth else { return }
            for name in FS.children(d) where !name.hasPrefix(".") && !Hashing.ignoredNames.contains(name) {
                let p = d + "/" + name
                if case .directory = FS.kind(p) {
                    if FS.exists(p + "/SKILL.md") { out.append(p + "/SKILL.md") }
                    walk(p, depth + 1)
                }
            }
        }
        walk(dir, 1)
        return out
    }
}
