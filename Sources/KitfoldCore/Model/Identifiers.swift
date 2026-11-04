import Foundation

/// Stable identifier of an agent ("claude-code", "codex", …). Adapters are looked up by it.
public struct AgentID: RawRepresentable, Hashable, Codable, Sendable, Comparable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
    public static func < (a: AgentID, b: AgentID) -> Bool { a.rawValue < b.rawValue }

    public static let claudeCode: AgentID = "claude-code"
    public static let codex: AgentID = "codex"
    public static let openCode: AgentID = "opencode"
    public static let geminiCLI: AgentID = "gemini-cli"

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Where a configuration takes effect. Agents always load their global configuration;
/// a project scope adds (or, where the agent supports it, hides) things inside one repository.
public enum Scope: Hashable, Sendable, Comparable, CustomStringConvertible, Codable {
    case global
    case project(String)  // absolute, standardized project root

    public var description: String {
        switch self {
        case .global: return "global"
        case .project(let p): return "project:\(p)"
        }
    }

    public init?(string: String) {
        if string == "global" { self = .global; return }
        if string.hasPrefix("project:") { self = .project(String(string.dropFirst(8))); return }
        return nil
    }

    public var projectPath: String? {
        if case .project(let p) = self { return p }
        return nil
    }

    public var isGlobal: Bool { self == .global }

    public static func < (a: Scope, b: Scope) -> Bool {
        switch (a, b) {
        case (.global, .project): return true
        case (.project, .global): return false
        case (.global, .global): return false
        case (.project(let x), .project(let y)): return x < y
        }
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let v = Scope(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad scope \(s)"))
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

public enum ResourceKind: String, Codable, Sendable, Hashable {
    case skill, profile
}

public struct ResourceRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public var kind: ResourceKind
    public var id: String
    public init(_ kind: ResourceKind, _ id: String) { self.kind = kind; self.id = id }
    public var description: String { "\(kind.rawValue):\(id)" }
}
