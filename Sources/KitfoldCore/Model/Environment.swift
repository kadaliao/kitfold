import Foundation

/// Everything that ties Kitfold to a concrete machine. Tests build one rooted in a temp dir,
/// so no code path ever has to touch the real home directory implicitly.
public struct KitfoldEnvironment: Sendable, Hashable {
    /// User home directory (absolute, no trailing slash).
    public var home: String
    /// Kitfold's own data directory (library, config, state database, backups).
    public var kitfoldHome: String
    /// Process environment (CODEX_HOME, CLAUDE_CONFIG_DIR, PATH…).
    public var variables: [String: String]
    /// User-specified config directory per agent (Settings → Agents), tilde allowed.
    public var configDirOverrides: [AgentID: String]
    /// Extra directories to search for agent binaries (GUI apps get a minimal PATH).
    public var extraBinaryDirs: [String]

    public init(
        home: String, kitfoldHome: String? = nil, variables: [String: String] = [:],
        configDirOverrides: [AgentID: String] = [:], extraBinaryDirs: [String] = []
    ) {
        // Use the real path: resolved link targets (realpath) must abbreviate back to `~`,
        // even when $HOME itself goes through a symlink (e.g. /var → /private/var).
        let realHome = FS.realPath(home) ?? FS.standardize(home)
        self.home = realHome
        self.kitfoldHome = FS.standardize(kitfoldHome ?? (realHome as NSString).appendingPathComponent(".kitfold"))
        self.variables = variables
        self.configDirOverrides = configDirOverrides
        self.extraBinaryDirs = extraBinaryDirs
    }

    public static func current() -> KitfoldEnvironment {
        var env = ProcessInfo.processInfo.environment
        let home = env["KITFOLD_FAKE_HOME"] ?? NSHomeDirectory()
        if let fake = env["KITFOLD_FAKE_HOME"] {
            // A fake home must not reach the real agents' folders through their own variables.
            for key in agentDirVariables where env[key].map({ !FS.isInside($0, fake) }) ?? false { env[key] = nil }
        }
        return KitfoldEnvironment(home: home, kitfoldHome: env["KITFOLD_HOME"].map { FS.expandTilde($0, home: home) }, variables: env)
    }

    /// Variables that move an agent's config folder.
    static let agentDirVariables = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "OPENCODE_CONFIG_DIR", "GEMINI_CLI_HOME"]

    public func expand(_ p: String) -> String { FS.standardize(FS.expandTilde(p, home: home)) }
    public func abbreviate(_ p: String) -> String { FS.abbreviate(p, home: home) }

    // Kitfold layout
    public var libraryDir: String { kitfoldHome + "/library" }
    public var librarySkillsDir: String { libraryDir + "/skills" }
    public var libraryProfilesDir: String { libraryDir + "/profiles" }
    public var configFile: String { kitfoldHome + "/kitfold.json" }
    public var stateDatabase: String { kitfoldHome + "/state.sqlite" }
    public var backupsDir: String { kitfoldHome + "/backups" }

    public var binarySearchDirs: [String] {
        var dirs = (variables["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += extraBinaryDirs.map(expand)
        dirs += [
            "~/.local/bin", "~/.bun/bin", "~/.cargo/bin", "~/.npm-global/bin", "~/.volta/bin",
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
        ].map(expand)
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
