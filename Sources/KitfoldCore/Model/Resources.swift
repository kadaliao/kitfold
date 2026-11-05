import Foundation

/// Where a skill's real directory lives, which decides what Kitfold may do with it.
public enum SkillOrigin: Hashable, Sendable {
    /// Inside `~/.kitfold/library/skills` — fully managed and editable.
    case library
    /// Inside a registered source folder (e.g. `~/.agents/skills`, a cloned repo).
    case source(id: String)
    /// A real folder sitting directly in an agent's skills directory (not shared, not managed).
    case agentLocal(AgentID)
    /// A symlink target somewhere outside every known source (e.g. a repo checkout).
    case external
    /// Plugin / extension / bundled skills. Read-only.
    case bundled(AgentID)
    /// A SKILL.md inside another skill's folder (loaded as its own skill by Codex/OpenCode).
    case nested(String)

    public var isEditable: Bool {
        switch self {
        case .bundled: return false
        default: return true
        }
    }

    /// Folders Kitfold may delete: its own library, a registered source, an agent's own skills
    /// folder. Not a plugin's (the agent's plugin system owns it), not a nested `SKILL.md` (the
    /// skill around it owns the folder), and not a folder reached only through a link — that one
    /// may be anything, anywhere (a repository checkout, someone's home-made collection).
    public var isDeletable: Bool {
        switch self {
        case .library, .source, .agentLocal: return true
        case .external, .bundled, .nested: return false
        }
    }
}

/// A skill directory known to Kitfold (one per real path).
public struct SkillEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    /// Agent-facing name (frontmatter `name`, else folder name).
    public var name: String
    public var folderName: String
    public var description: String
    /// Real (resolved) path of the skill directory.
    public var path: String
    public var origin: SkillOrigin
    public var frontmatter: Frontmatter
    public var skillFileHash: String
    public var modifiedAt: Date?
    public var problems: [String]

    public var skillFile: String { path + "/SKILL.md" }
    public var tags: [String] { frontmatter.list("tags") + frontmatter.list("category") }

    /// Read a skill directory. Returns nil if there's no SKILL.md.
    public static func read(directory: String, origin: SkillOrigin) -> SkillEntry? {
        let real = FS.realPath(directory) ?? directory
        let file = real + "/SKILL.md"
        guard let text = FS.read(file) else { return nil }
        let fm = Frontmatter.parse(text)
        let folder = (real as NSString).lastPathComponent
        var problems: [String] = []
        if !fm.present { problems.append(L("SKILL.md has no frontmatter (name/description)")) }
        if let e = fm.parseError { problems.append(e) }
        let name = fm["name"].flatMap { $0.isEmpty ? nil : $0 } ?? folder
        if fm["description"]?.isEmpty ?? true { problems.append(L("Missing description — agents use it to decide when to load the skill")) }
        if !SkillEntry.isValidName(name) {
            problems.append(L("Name “\(name)” should be at most 64 characters: lowercase letters, digits, “-”, “_” or “:”"))
        }
        return SkillEntry(
            name: name, folderName: folder, description: fm["description"] ?? "", path: real, origin: origin,
            frontmatter: fm, skillFileHash: Hashing.short(text), modifiedAt: FS.modificationDate(file), problems: problems)
    }

    public static func isValidName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64
            && s.allSatisfy { ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":" }
    }

    public static func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// A reusable instruction set ("Backend Developer", "Code Reviewer").
/// Stored as `~/.kitfold/library/profiles/<id>.md` with frontmatter:
///
///     ---
///     name: Backend Developer
///     description: Go/Python services, strict tests
///     skills: [pdf, high-signal-review]
///     order: 10
///     ---
///     …instruction text…
public struct ProfileEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var skills: [String]
    public var order: Int
    public var body: String
    public var path: String
    public var modifiedAt: Date?

    public static func read(path: String) -> ProfileEntry? {
        guard let text = FS.read(path) else { return nil }
        let fm = Frontmatter.parse(text)
        let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return ProfileEntry(
            id: id, name: fm["name"] ?? id, description: fm["description"] ?? "", skills: fm.list("skills"),
            order: Int(fm["order"] ?? "") ?? 100, body: fm.body.trimmingCharacters(in: .newlines), path: path,
            modifiedAt: FS.modificationDate(path))
    }

    public func rendered() -> String {
        var fields: [(String, Frontmatter.Value)] = [("name", .string(name))]
        if !description.isEmpty { fields.append(("description", .string(description))) }
        fields.append(("skills", .list(skills)))
        if order != 100 { fields.append(("order", .string(String(order)))) }
        return Frontmatter.render(fields: fields, body: body + "\n")
    }

    /// Text placed in an instruction file for a list of profiles.
    public static func compose(_ profiles: [ProfileEntry]) -> String {
        if profiles.count == 1 { return profiles[0].body }
        return profiles.map { "<!-- profile: \($0.id) -->\n\($0.body)" }.joined(separator: "\n\n")
    }
}
