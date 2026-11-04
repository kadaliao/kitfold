import Foundation

/// Built-in agent descriptors. Every path here comes from the research in docs/research.md
/// (verified against docs and source of the versions noted). `verified: false` marks assumptions.
///
/// Kitfold's deployment choice per agent is "isolation first": deploy into the directory/file
/// that *only that agent* reads, so assigning to one agent never leaks into another.
public enum BuiltinAgents {
    public static let all: [AgentDescriptor] = [claudeCode, codex, openCode, geminiCLI]
    public static var adapters: [AgentAdapter] { all.map(AgentAdapter.init) }

    /// Claude Code 2.1.318.
    public static let claudeCode = AgentDescriptor(
        id: .claudeCode, name: "Claude Code", vendor: "Anthropic",
        binaryNames: ["claude"], binaryDirs: ["~/.local/bin", "~/.claude/local"],
        configDir: "~/.claude", configDirEnv: "CLAUDE_CONFIG_DIR",
        skillRoots: [
            SkillRootSpec(
                .absolute, "/Library/Application Support/ClaudeCode/.claude/skills", scope: .global, role: .bundled,
                note: "Enterprise-managed skills; beat personal and project skills."),
            SkillRootSpec(
                .configDir, "skills", scope: .global, role: .primary, ignore: ["synced"],
                note:
                    "Personal skills, one level deep. Symlinked folders are followed and loaded once. Claude Code does not read ~/.agents/skills."
            ),
            SkillRootSpec(
                .configDir, "skills/synced", scope: .global, role: .bundled,
                note: "Skills synced from claude.ai (reserved folder)."),
            SkillRootSpec(
                .project, ".claude/skills", scope: .project, role: .primary,
                note: "Project skills. Claude walks from the start directory up to the repo root; a personal skill with the same name wins."
            ),
        ],
        instructionFiles: [
            InstructionFileSpec(
                .absolute, "/Library/Application Support/ClaudeCode/CLAUDE.md", scope: .global, role: .loaded,
                note: "Managed policy; always loaded."),
            InstructionFileSpec(
                .configDir, "CLAUDE.md", scope: .global, role: .loaded,
                note: "User memory; always loaded. OpenCode also falls back to this file."),
            InstructionFileSpec(
                .configDir, "rules/kitfold.md", scope: .global, role: .primary,
                note: "Kitfold's file. User rules load at launch and only Claude Code reads them, so nothing leaks to OpenCode."),
            InstructionFileSpec(.configDir, "rules/**/*.md", scope: .global, role: .loaded, note: "User rules."),
            InstructionFileSpec(.project, "CLAUDE.md", scope: .project, role: .loaded),
            InstructionFileSpec(.project, ".claude/CLAUDE.md", scope: .project, role: .loaded),
            InstructionFileSpec(.project, "CLAUDE.local.md", scope: .project, role: .loaded, note: "Personal project notes."),
            InstructionFileSpec(
                .project, ".claude/rules/kitfold.md", scope: .project, role: .primary,
                note: "Kitfold's file. Rules without `paths` load at launch and don't stop Claude from reading AGENTS.md."),
            InstructionFileSpec(
                .project, ".claude/rules/**/*.md", scope: .project, role: .loaded, note: "Project rules (path-scoped ones load on demand)."),
            InstructionFileSpec(
                .project, "AGENTS.md", scope: .project, role: .fallback,
                related: ["CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md"],
                note: "Since 2.1.277, read only when no CLAUDE.md / .claude/CLAUDE.md / CLAUDE.local.md exists (default mode)."),
        ],
        skillDisable: .claudeSettings, bundledProvider: .claudePlugins, globalSkillsWin: true,
        nestedSkillDepth: 0, policyCoversBundled: false,
        instructionByteLimit: nil, docsURL: "https://code.claude.com/docs/en/skills",
        monogram: "CC", tint: "#D97757",
        notes: [
            "Hide a skill without deleting it: `skillOverrides` in settings (on / name-only / user-invocable-only / off).",
            "Never reads ~/.agents/skills or AGENTS.override.md.",
        ])

    /// Codex CLI 0.164.0.
    public static let codex = AgentDescriptor(
        id: .codex, name: "Codex", vendor: "OpenAI",
        binaryNames: ["codex"], binaryDirs: ["~/.local/bin"],
        configDir: "~/.codex", configDirEnv: "CODEX_HOME",
        skillRoots: [
            SkillRootSpec(
                .configDir, "skills", scope: .global, role: .primary,
                note: "$CODEX_HOME/skills: only Codex reads it. Marked deprecated upstream but still loaded in 0.164."),
            SkillRootSpec(
                .home, ".agents/skills", scope: .global, role: .shared,
                note: "Also read by OpenCode and Gemini CLI."),
            SkillRootSpec(
                .configDir, "skills/.system", scope: .global, role: .bundled,
                note: "Built-in system skills; Codex rewrites this folder at startup."),
            SkillRootSpec(.absolute, "/etc/codex/skills", scope: .global, role: .bundled, note: "Admin skills."),
            SkillRootSpec(
                .project, ".codex/skills", scope: .project, role: .primary,
                note: "Codex-only project skills (loaded even before the project is trusted)."),
            SkillRootSpec(
                .project, ".agents/skills", scope: .project, role: .shared,
                note: "Also read by OpenCode and Gemini CLI."),
        ],
        instructionFiles: [
            InstructionFileSpec(
                .configDir, "AGENTS.override.md", scope: .global, role: .override, related: ["AGENTS.md"],
                note: "If present and non-empty, replaces the global AGENTS.md."),
            InstructionFileSpec(
                .configDir, "AGENTS.md", scope: .global, role: .primary,
                note: "Global instructions; only Codex reads this file."),
            InstructionFileSpec(
                .project, "AGENTS.override.md", scope: .project, role: .override, related: ["AGENTS.md"],
                note: "Replaces AGENTS.md in this directory."),
            InstructionFileSpec(
                .project, "AGENTS.md", scope: .project, role: .primary,
                note: "Shared: OpenCode reads it too, and Claude Code when there's no CLAUDE.md."),
        ],
        skillDisable: .codexConfig, bundledProvider: .codexPlugins, globalSkillsWin: false,
        nestedSkillDepth: 6, policyCoversBundled: true, requiresDescription: true,
        instructionByteLimit: 32 * 1024, docsURL: "https://developers.openai.com/codex",
        monogram: "CX", tint: "#7C8CF8",
        notes: [
            "Hide a skill: `[[skills.config]] path = \"…/SKILL.md\"  enabled = false` — only honored in $CODEX_HOME/config.toml.",
            "Same-name skills from different folders are both listed (not merged).",
            "A symlinked SKILL.md file is skipped; link whole folders.",
        ])

    /// OpenCode 1.19.4.
    public static let openCode = AgentDescriptor(
        id: .openCode, name: "OpenCode", vendor: "SST",
        binaryNames: ["opencode"], binaryDirs: ["~/.opencode/bin", "~/.local/bin"],
        configDir: "~/.config/opencode", configDirEnv: nil,
        skillRoots: [
            SkillRootSpec(
                .configDir, "skills", scope: .global, role: .primary,
                note: "Only OpenCode reads it (also `skill/`)."),
            SkillRootSpec(
                .home, ".claude/skills", scope: .global, role: .foreign, owner: .claudeCode,
                note: "OpenCode also loads Claude Code's skills unless OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1."),
            SkillRootSpec(
                .home, ".agents/skills", scope: .global, role: .shared,
                note: "Also read by Codex and Gemini CLI."),
            SkillRootSpec(
                .project, ".opencode/skills", scope: .project, role: .primary,
                note: "Only OpenCode reads it. Walks from cwd up to the git worktree root."),
            SkillRootSpec(
                .project, ".claude/skills", scope: .project, role: .foreign, owner: .claudeCode,
                note: "Claude Code's project skills, read for compatibility."),
            SkillRootSpec(
                .project, ".agents/skills", scope: .project, role: .shared,
                note: "Also read by Codex and Gemini CLI."),
        ],
        instructionFiles: [
            InstructionFileSpec(
                .configDir, "AGENTS.md", scope: .global, role: .primary,
                note: "Only OpenCode reads it. When it exists, OpenCode stops reading ~/.claude/CLAUDE.md."),
            InstructionFileSpec(
                .home, ".claude/CLAUDE.md", scope: .global, role: .fallback, related: ["AGENTS.md"],
                relatedBase: .configDir, note: "Used only when ~/.config/opencode/AGENTS.md doesn't exist."),
            InstructionFileSpec(
                .project, "AGENTS.md", scope: .project, role: .primary,
                note: "Shared with Codex (and Claude Code when there's no CLAUDE.md)."),
            InstructionFileSpec(
                .project, "CLAUDE.md", scope: .project, role: .fallback, related: ["AGENTS.md"],
                note: "Used only when no AGENTS.md exists up the tree."),
        ],
        skillDisable: .openCodePermission, bundledProvider: nil, globalSkillsWin: false,
        nestedSkillDepth: 8, policyCoversBundled: true, requiresName: true,
        instructionByteLimit: nil, docsURL: "https://opencode.ai/docs/skills",
        monogram: "OC", tint: "#E0A030",
        notes: [
            "Same-name skills are de-duplicated by name; which copy wins isn't predictable.",
            "Recurses into skill folders: a SKILL.md nested inside another skill becomes its own skill.",
            "Hide a skill: `permission.skill: { \"name\": \"deny\" }` in opencode.json (global or project).",
        ])

    /// Gemini CLI 0.66.0.
    public static let geminiCLI = AgentDescriptor(
        id: .geminiCLI, name: "Gemini CLI", vendor: "Google",
        binaryNames: ["gemini"], binaryDirs: [],
        configDir: "~/.gemini", configDirEnv: nil,
        skillRoots: [
            SkillRootSpec(
                .home, ".agents/skills", scope: .global, role: .shared,
                note: "Overrides ~/.gemini/skills on a name clash; also read by Codex and OpenCode."),
            SkillRootSpec(
                .configDir, "skills", scope: .global, role: .primary,
                note: "Only Gemini CLI reads it. One level deep; name and description are both required."),
            SkillRootSpec(
                .project, ".agents/skills", scope: .project, role: .shared,
                note: "Start directory only, trusted folders only."),
            SkillRootSpec(
                .project, ".gemini/skills", scope: .project, role: .primary,
                note: "Start directory only (no parent walk), trusted folders only."),
        ],
        instructionFiles: [
            InstructionFileSpec(.configDir, "GEMINI.md", scope: .global, role: .primary, note: "Only Gemini CLI reads it."),
            InstructionFileSpec(
                .project, "GEMINI.md", scope: .project, role: .primary,
                note: "Gemini walks up to the .git root; trusted folders only. `context.fileName` can add AGENTS.md."),
        ],
        skillDisable: .geminiSettings, bundledProvider: .geminiExtensions, globalSkillsWin: false,
        nestedSkillDepth: 0, policyCoversBundled: true, requiresName: true, requiresDescription: true,
        instructionByteLimit: nil, docsURL: "https://geminicli.com/docs/cli/skills",
        monogram: "GM", tint: "#4C8BF5",
        notes: [
            "Gemini CLI was replaced by Antigravity CLI for free and Google One users on 2026-06-18.",
            "Hide a skill: `skills.disabled` in settings.json (merged across user and workspace).",
        ])
}
