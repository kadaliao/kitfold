import Foundation

/// The only things Kitfold ever does to files. All are reversible.
public enum FileChange: Codable, Hashable, Sendable {
    case createSymlink(path: String, target: String)
    case removeSymlink(path: String, target: String)
    /// `before == nil` creates the file; `after == nil` deletes it.
    case writeFile(path: String, before: String?, after: String?)
    /// Move a folder (used to bring a skill into the library). `path` is the destination.
    case moveItem(from: String, path: String)

    public var path: String {
        switch self {
        case .createSymlink(let p, _), .removeSymlink(let p, _), .writeFile(let p, _, _), .moveItem(_, let p): return p
        }
    }

    public var inverse: FileChange {
        switch self {
        case .createSymlink(let p, let t): return .removeSymlink(path: p, target: t)
        case .removeSymlink(let p, let t): return .createSymlink(path: p, target: t)
        case .writeFile(let p, let b, let a): return .writeFile(path: p, before: a, after: b)
        case .moveItem(let from, let to): return .moveItem(from: to, path: from)
        }
    }
}

/// A settings entry Kitfold takes or gives up ownership of (recorded in the ledger, reversed on undo).
public struct OwnershipEdit: Codable, Hashable, Sendable {
    /// `<settings file>#<entry key>` (see `NativeSettings.ledgerKey`).
    public var key: String
    /// The value Kitfold wrote.
    public var value: String
    public var skill: String
    public var ownedBefore: Bool
    public var ownedAfter: Bool

    public init(key: String, value: String, skill: String, ownedBefore: Bool, ownedAfter: Bool) {
        self.key = key; self.value = value; self.skill = skill; self.ownedBefore = ownedBefore; self.ownedAfter = ownedAfter
    }

    public var inverse: OwnershipEdit {
        OwnershipEdit(key: key, value: value, skill: skill, ownedBefore: ownedAfter, ownedAfter: ownedBefore)
    }
}

public struct PlannedChange: Identifiable, Hashable, Sendable {
    public enum Risk: Int, Sendable, Hashable, Comparable {
        /// Touches only things Kitfold created, or creates new things.
        case safe = 0
        /// Touches something Kitfold didn't create (e.g. removes a link made by another tool).
        case caution = 1
        public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    }
    public var id: String { change.path + "|" + summary }
    public var change: FileChange
    public var summary: String
    public var agents: [AgentID]
    public var scope: Scope
    public var resource: ResourceRef?
    public var risk: Risk
    public var note: String?
    /// Shown instead of a line diff: the settings entries this change adds or removes. When set,
    /// the file's text is never displayed — agent settings files can hold secrets.
    public var details: [String]?
    public var ownership: [OwnershipEdit]

    public init(
        _ change: FileChange, summary: String, agents: [AgentID], scope: Scope, resource: ResourceRef? = nil,
        risk: Risk = .safe, note: String? = nil, details: [String]? = nil, ownership: [OwnershipEdit] = []
    ) {
        self.change = change; self.summary = summary; self.agents = agents; self.scope = scope
        self.resource = resource; self.risk = risk; self.note = note; self.details = details; self.ownership = ownership
    }

    /// Line diff of a file edit; nil for settings files (see `details`).
    public var diff: [LineDiff.Op]? {
        guard details == nil, case .writeFile(_, let b, let a) = change else { return nil }
        return LineDiff.diff(b ?? "", a ?? "")
    }
}

/// Output of the planner: what would change, and what can't be done (with reasons).
public struct Plan: Sendable {
    public var changes: [PlannedChange]
    /// Problems the plan can't solve automatically (shown in the review sheet).
    public var issues: [Issue]

    public init(changes: [PlannedChange] = [], issues: [Issue] = []) { self.changes = changes; self.issues = issues }

    public var isEmpty: Bool { changes.isEmpty }
    public var hasCaution: Bool { changes.contains { $0.risk == .caution } }
}
