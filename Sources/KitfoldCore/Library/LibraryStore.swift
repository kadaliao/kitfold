import Foundation

/// The Kitfold library on disk plus registered source folders.
public struct LibraryStore: Sendable {
    public var env: KitfoldEnvironment

    public init(env: KitfoldEnvironment) { self.env = env }

    public func ensureLayout() throws {
        for d in [env.kitfoldHome, env.librarySkillsDir, env.libraryProfilesDir] {
            try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
        // Backups hold copies of the user's files: owner-only.
        try FileManager.default.createDirectory(
            atPath: env.backupsDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: env.backupsDir)
    }

    // MARK: skills

    /// Skill folders directly under `dir` (following symlinked folders).
    public func skills(in dir: String, origin: SkillOrigin, maxDepth: Int = 0) -> [SkillEntry] {
        var out: [SkillEntry] = []
        for child in FS.children(dir) where !child.hasPrefix(".") {
            let p = dir + "/" + child
            guard FS.isDirectoryFollowing(p) else { continue }
            if let e = SkillEntry.read(directory: p, origin: origin) {
                out.append(e)
            } else if maxDepth > 0 {
                out += skills(in: p, origin: origin, maxDepth: maxDepth - 1)
            }
        }
        return out
    }

    /// Library skills first, then each enabled source in configured order.
    public func catalog(sources: [SkillSourceConfig]) -> [SkillEntry] {
        var out = skills(in: env.librarySkillsDir, origin: .library)
        for s in sources where s.enabled {
            out += skills(in: env.expand(s.path), origin: .source(id: s.id), maxDepth: s.gitURL == nil ? 0 : 3)
        }
        return out
    }

    public func createSkill(name: String, description: String) throws -> String {
        let slug = SkillEntry.slugify(name)
        guard !slug.isEmpty else { throw KitfoldError.invalid("Skill name is empty") }
        let dir = env.librarySkillsDir + "/" + slug
        guard !FS.exists(dir) else { throw KitfoldError.invalid("A skill named \(slug) already exists in the library") }
        let text = Frontmatter.render(
            fields: [("name", .string(slug)), ("description", .string(description))],
            body: "# \(name)\n\nDescribe when and how to use this skill.\n")
        try FS.write(text, to: dir + "/SKILL.md")
        return dir
    }

    /// Copy a skill folder into the library (the original is left untouched).
    public func importFolder(_ source: String) throws -> String {
        let src = FS.realPath(source) ?? source
        guard FS.exists(src + "/SKILL.md") else { throw KitfoldError.invalid("\(source) has no SKILL.md") }
        let entry = SkillEntry.read(directory: src, origin: .external)
        let name = SkillEntry.slugify(entry?.name ?? (src as NSString).lastPathComponent)
        let dest = env.librarySkillsDir + "/" + name
        guard !FS.exists(dest) else { throw KitfoldError.invalid("The library already has a skill named \(name)") }
        try FileManager.default.createDirectory(atPath: env.librarySkillsDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: src, toPath: dest)
        return dest
    }

    /// Shallow-clone a Git repository into `~/.kitfold/sources/<name>` and return a source config for it.
    public func cloneGitSource(url: String) throws -> SkillSourceConfig {
        var name = (url as NSString).lastPathComponent
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        name = SkillEntry.slugify(name)
        guard !name.isEmpty else { throw KitfoldError.invalid("Can't derive a name from \(url)") }
        let dest = env.kitfoldHome + "/sources/" + name
        guard !FS.exists(dest) else { throw KitfoldError.invalid("\(env.abbreviate(dest)) already exists") }
        try FileManager.default.createDirectory(atPath: env.kitfoldHome + "/sources", withIntermediateDirectories: true)
        try Shell.run("/usr/bin/git", ["clone", "--depth", "1", url, dest])
        return SkillSourceConfig(id: "git-" + name, label: name, path: env.abbreviate(dest), gitURL: url)
    }

    public func pullGitSource(_ source: SkillSourceConfig) throws {
        try Shell.run("/usr/bin/git", ["-C", env.expand(source.path), "pull", "--ff-only"])
    }

    // MARK: profiles

    public func profiles() -> [ProfileEntry] {
        FS.children(env.libraryProfilesDir).filter { $0.hasSuffix(".md") }
            .compactMap { ProfileEntry.read(path: env.libraryProfilesDir + "/" + $0) }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    public func profilePath(id: String) -> String { env.libraryProfilesDir + "/\(id).md" }

    public func saveProfile(_ p: ProfileEntry) throws {
        try FS.write(p.rendered(), to: profilePath(id: p.id))
    }

    public func createProfile(name: String, description: String = "", body: String = "", skills: [String] = []) throws -> ProfileEntry {
        var id = SkillEntry.slugify(name)
        if id.isEmpty { id = "profile" }
        var candidate = id
        var n = 2
        while FS.exists(profilePath(id: candidate)) { candidate = "\(id)-\(n)"; n += 1 }
        let p = ProfileEntry(
            id: candidate, name: name, description: description, skills: skills, order: 100,
            body: body.isEmpty ? "## \(name)\n\n- " : body, path: profilePath(id: candidate), modifiedAt: nil)
        try saveProfile(p)
        return ProfileEntry.read(path: p.path) ?? p
    }

    /// Profiles are moved to the backups folder rather than deleted.
    public func trashProfile(id: String) throws {
        let src = profilePath(id: id)
        let dir = env.backupsDir + "/trash"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        try FileManager.default.moveItem(atPath: src, toPath: dir + "/\(id)-\(stamp).md")
    }
}

public enum Shell {
    @discardableResult
    public static func run(_ exe: String, _ args: [String], cwd: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw KitfoldError.io("\((exe as NSString).lastPathComponent) failed: \(String(decoding: e, as: UTF8.self).prefix(400))")
        }
        return String(decoding: o, as: UTF8.self)
    }
}
