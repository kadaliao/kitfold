import Foundation

/// Health checks over a snapshot: broken links, duplicates, drift, foreign blocks, size limits.
enum Diagnostics {
    static func issues(in s: Snapshot) -> [Issue] {
        var out: [Issue] = []
        func ab(_ p: String) -> String { s.env.abbreviate(p) }

        // Broken links, grouped by folder so one dead link read by three agents is one problem.
        struct Broken { var target: String; var agents: [AgentID] }
        var broken: [Scope: [String: [String: Broken]]] = [:]  // scope → folder → link path → info

        // Broken links are reported for every agent whose folder is here, managed or not: they're
        // left behind by skills deleted elsewhere, and cleaning them up is the same either way.
        for a in s.agents where a.enabled || a.installation.isDetected {
            for scope in s.scopes {
                let st = a.state(scope)
                for o in st.skills where o.isBroken || a.enabled {
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
                                .invalidSkill, .warning, L("“\(o.entryName)” has no SKILL.md"),
                                detail: L("\(ab(o.entryPath)) is in a skills folder but isn't a skill."),
                                paths: [o.entryPath], agent: a.id, scope: scope))
                    } else if let why = o.skipReason {
                        let fix =
                            o.isSymlink && !o.root.spec.followsLinks
                            ? L("\(why). Put a copy of the folder there instead of a link.")
                            : L("\(why). Add it to \(ab(o.skillFile ?? o.entryPath)).")
                        out.append(
                            Issue(
                                .invalidSkill, .warning, L("\(a.name) ignores “\(o.name)”"), detail: fix, paths: [o.entryPath],
                                agent: a.id, scope: scope))
                    }
                }

                guard a.enabled else { continue }
                // Name clashes the agent sees here. In a project, only report clashes involving project skills.
                let reachable = a.reachableSkills(in: scope).filter { $0.skill.isActive }
                var sameFolderTwice = 0
                var twiceVia = Set<String>()  // the folders those skills are found through
                for (name, group) in Dictionary(grouping: reachable, by: { $0.skill.name }) where group.count > 1 {
                    if !scope.isGlobal && group.allSatisfy({ $0.inherited }) { continue }
                    let folders = Set(group.compactMap { $0.skill.realPath })
                    if folders.count > 1 {
                        let first = group[0].skill
                        let others = Localization.list(group.dropFirst().map { ab($0.skill.entryPath) })
                        out.append(
                            Issue(
                                .duplicateName, .warning, L("\(a.name) sees \(folders.count) different skills named “\(name)”"),
                                detail: L("\(ab(first.entryPath)) takes precedence. Also found: \(others)"),
                                paths: group.map { $0.skill.entryPath }, agent: a.id, scope: scope, key: name))
                    } else {
                        sameFolderTwice += 1
                        twiceVia.formUnion(group.map { $0.skill.root.path })
                    }
                }
                if sameFolderTwice > 0 {
                    let roots = Localization.list(twiceVia.map(ab).sorted())
                    out.append(
                        Issue(
                            .duplicateName, .info,
                            sameFolderTwice == 1
                                ? L("\(a.name) reaches 1 skill through two folders")
                                : L("\(a.name) reaches \(sameFolderTwice) skills through two folders"),
                            detail: L(
                                "The same skill folders are found via \(roots). Some agents list them twice or warn about a conflict."),
                            agent: a.id, scope: scope, key: "same-folder"))
                }

                var loadedBytes = 0
                for f in st.instructions where f.exists {
                    if f.isLoaded { loadedBytes += f.byteCount }
                    for b in f.driftedBlocks {
                        out.append(
                            Issue(
                                .blockDrift, .warning, L("Profile “\(s.profileName(b.profile))” was edited outside Kitfold"),
                                detail: L("\(ab(f.file.path)): Kitfold won't overwrite it until you keep or discard the edit."),
                                paths: [f.file.path], agent: a.id, scope: scope, key: f.file.path + b.profile))
                    }
                    for tool in f.foreignBlocks {
                        out.append(
                            Issue(
                                .foreignBlock, .info,
                                L("\(tool.capitalized) manages part of \((f.file.path as NSString).lastPathComponent)"),
                                detail: L("\(ab(f.file.path)) has a block written by \(tool). Kitfold leaves it alone."),
                                paths: [f.file.path], key: f.file.path + tool))
                    }
                }
                if let limit = a.adapter.descriptor.instructionByteLimit, loadedBytes > limit {
                    out.append(
                        Issue(
                            .sizeLimit, .warning, L("\(a.name) instructions exceed \(limit / 1024) KiB"),
                            detail: L("\(loadedBytes) bytes are loaded; \(a.name) cuts off everything past \(limit) bytes."),
                            agent: a.id, scope: scope))
                }
            }
        }

        func names(_ ids: [AgentID]) -> String { Localization.list(ids.compactMap { s.agent($0)?.name }) }
        for (scope, folders) in broken {
            // A folder with many: one issue for the folder. The rest: one issue per skill name, so a
            // skill deleted from under several agents shows up once, not once per agent.
            var byName: [String: [(path: String, info: Broken)]] = [:]
            for (folder, links) in folders {
                let agents = Array(Set(links.values.flatMap(\.agents))).sorted()
                if links.count >= 3 {
                    let list = Localization.list(links.keys.map { ($0 as NSString).lastPathComponent }.sorted())
                    out.append(
                        Issue(
                            .brokenLink, .error, L("\(links.count) broken skill links in \(ab(folder))"),
                            detail: L("\(list) point to folders that no longer exist. Skipped silently by \(names(agents))."),
                            paths: links.keys.sorted(), agent: agents.first, alsoAffects: Array(agents.dropFirst()), scope: scope,
                            key: folder))
                } else {
                    for (path, b) in links { byName[(path as NSString).lastPathComponent, default: []].append((path, b)) }
                }
            }
            for (name, links) in byName {
                let agents = Array(Set(links.flatMap(\.info.agents))).sorted()
                let paths = links.map(\.path).sorted()
                if links.count == 1, let (path, b) = links.first {
                    out.append(
                        Issue(
                            .brokenLink, .error, L("Broken skill link “\(name)”"),
                            detail: L("\(ab(path)) → \(ab(b.target)), which no longer exists. Skipped silently by \(names(b.agents))."),
                            paths: [path], agent: agents.first, alsoAffects: Array(agents.dropFirst()), scope: scope, key: path))
                } else {
                    out.append(
                        Issue(
                            .brokenLink, .error, L("\(links.count) broken links to “\(name)”"),
                            detail: L(
                                "\(Localization.list(paths.map(ab))) point to a folder that no longer exists. Skipped silently by \(names(agents))."
                            ),
                            paths: paths, agent: agents.first, alsoAffects: Array(agents.dropFirst()), scope: scope, key: "broken|" + name))
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
                out.append(Issue(.invalidSkill, .info, L("\(e.name): \(p)"), paths: [e.path], key: e.path + p))
            }
            let nested = nestedSkillFiles(in: e.path)
            if !nested.isEmpty {
                let shown = Localization.list(nested.prefix(3).map(ab))
                out.append(
                    Issue(
                        .nestedSkill, .warning, L("“\(e.name)” contains \(nested.count) nested SKILL.md"),
                        detail: L("Codex and OpenCode load each nested SKILL.md as a separate skill: \(shown)"),
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
