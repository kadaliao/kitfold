// Simplified Chinese for agent descriptors and adapters (Adapters/).
// Keys are the English exactly as written at the call site, with each interpolation as %@.
// Use %1$@, %2$@ … to reorder. Terms follow docs/localization.md.
extension Translations {
    static let zhHansAgents: KeyValuePairs<String, String> = [
        // AgentAdapter.swift: AgentDescriptor.skipReason (shown before "%@. Fix %@ first." etc., so no final period)
        "%@ skips skills without a name and description": "%@ 会跳过没有名称和描述的技能",
        "%@ skips skills without a name in SKILL.md": "%@ 会跳过 SKILL.md 中没有名称的技能",
        "%@ skips skills without a description in SKILL.md": "%@ 会跳过 SKILL.md 中没有描述的技能",

        // BuiltinAgents.swift: notes, shown through Localization.translate(note).

        // Claude Code: skill folders
        "Enterprise-managed skills; beat personal and project skills.": "企业托管的技能，优先于个人技能和项目技能。",
        "Personal skills, one level deep. Symlinked folders are followed and loaded once. Claude Code does not read ~/.agents/skills.":
            "个人技能，只扫描一层。符号链接的目录会被跟随，且只加载一次。Claude Code 不读取 ~/.agents/skills。",
        "Skills synced from claude.ai (reserved folder).": "从 claude.ai 同步的技能（保留目录）。",
        "Project skills. Claude walks from the start directory up to the repo root; a personal skill with the same name wins.":
            "项目技能。Claude 从启动目录逐级向上查找，直到仓库根目录；同名时个人技能优先。",
        // Claude Code: instruction files
        "Managed policy; always loaded.": "托管策略，始终加载。",
        "User memory; always loaded. OpenCode also falls back to this file.": "用户记忆，始终加载。OpenCode 也会回退到这个文件。",
        "Kitfold's file. User rules load at launch and only Claude Code reads them, so nothing leaks to OpenCode.":
            "Kitfold 的文件。用户规则在启动时加载，且只有 Claude Code 读取，所以不会泄漏给 OpenCode。",
        "User rules.": "用户规则。",
        "Personal project notes.": "个人的项目笔记。",
        "Kitfold's file. Rules without `paths` load at launch and don't stop Claude from reading AGENTS.md.":
            "Kitfold 的文件。不带 `paths` 的规则在启动时加载，也不妨碍 Claude 读取 AGENTS.md。",
        "Project rules (path-scoped ones load on demand).": "项目规则（限定路径的规则按需加载）。",
        "Since 2.1.277, read only when no CLAUDE.md / .claude/CLAUDE.md / CLAUDE.local.md exists (default mode).":
            "自 2.1.277 起，只在没有 CLAUDE.md / .claude/CLAUDE.md / CLAUDE.local.md 时读取（默认模式）。",
        // Claude Code: notes
        "Hide a skill without deleting it: `skillOverrides` in settings (on / name-only / user-invocable-only / off).":
            "不删除也能隐藏技能：设置里的 `skillOverrides`（on / name-only / user-invocable-only / off）。",
        "Never reads ~/.agents/skills or AGENTS.override.md.": "从不读取 ~/.agents/skills 或 AGENTS.override.md。",

        // Codex: skill folders
        "$CODEX_HOME/skills: only Codex reads it. Marked deprecated upstream but still loaded in 0.164.":
            "$CODEX_HOME/skills：只有 Codex 读取。上游已标为弃用，但 0.164 仍会加载。",
        "Also read by OpenCode and Gemini CLI.": "OpenCode 和 Gemini CLI 也会读取。",
        "Built-in system skills; Codex rewrites this folder at startup.": "内置的系统技能；Codex 启动时会重写这个目录。",
        "Admin skills.": "管理员技能。",
        "Codex-only project skills (loaded even before the project is trusted).": "只有 Codex 读取的项目技能（项目还未被信任时也会加载）。",
        // Codex: instruction files
        "If present and non-empty, replaces the global AGENTS.md.": "存在且非空时，替代全局的 AGENTS.md。",
        "Global instructions; only Codex reads this file.": "全局指令，只有 Codex 读取这个文件。",
        "Replaces AGENTS.md in this directory.": "替代这个目录里的 AGENTS.md。",
        "Shared: OpenCode reads it too, and Claude Code when there's no CLAUDE.md.":
            "共享文件：OpenCode 也会读取，没有 CLAUDE.md 时 Claude Code 也会读取。",
        // Codex: notes
        "Hide a skill: `[[skills.config]] path = \"…/SKILL.md\"  enabled = false` — only honored in $CODEX_HOME/config.toml.":
            "隐藏技能：`[[skills.config]] path = \"…/SKILL.md\"  enabled = false`，只在 $CODEX_HOME/config.toml 中生效。",
        "Same-name skills from different folders are both listed (not merged).": "不同目录里的同名技能会都列出来（不合并）。",
        "A symlinked SKILL.md file is skipped; link whole folders.": "符号链接形式的 SKILL.md 文件会被跳过；请链接整个目录。",

        // OpenCode: skill folders
        "Only OpenCode reads it (also `skill/`).": "只有 OpenCode 读取（也认 `skill/`）。",
        "OpenCode also loads Claude Code's skills unless OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1.":
            "OpenCode 也会加载 Claude Code 的技能，除非设置了 OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1。",
        "Also read by Codex and Gemini CLI.": "Codex 和 Gemini CLI 也会读取。",
        "Only OpenCode reads it. Walks from cwd up to the git worktree root.": "只有 OpenCode 读取。从 cwd 逐级向上查找，直到 git worktree 根目录。",
        "Claude Code's project skills, read for compatibility.": "Claude Code 的项目技能，为了兼容而读取。",
        // OpenCode: instruction files
        "Only OpenCode reads it. When it exists, OpenCode stops reading ~/.claude/CLAUDE.md.":
            "只有 OpenCode 读取。这个文件存在时，OpenCode 不再读取 ~/.claude/CLAUDE.md。",
        "Used only when ~/.config/opencode/AGENTS.md doesn't exist.": "只在 ~/.config/opencode/AGENTS.md 不存在时使用。",
        "Shared with Codex (and Claude Code when there's no CLAUDE.md).": "与 Codex 共享（没有 CLAUDE.md 时也与 Claude Code 共享）。",
        "Used only when no AGENTS.md exists up the tree.": "只在当前目录及其上层都没有 AGENTS.md 时使用。",
        // OpenCode: notes
        "Same-name skills are de-duplicated by name; which copy wins isn't predictable.": "同名技能按名称去重，最终用哪一份无法预测。",
        "Recurses into skill folders: a SKILL.md nested inside another skill becomes its own skill.":
            "会递归扫描技能目录：嵌套在另一个技能里的 SKILL.md 会成为独立的技能。",
        "Hide a skill: `permission.skill: { \"name\": \"deny\" }` in opencode.json (global or project).":
            "隐藏技能：opencode.json 里的 `permission.skill: { \"name\": \"deny\" }`（全局或项目）。",

        // Gemini CLI: skill folders
        "Overrides ~/.gemini/skills on a name clash; also read by Codex and OpenCode.": "同名时覆盖 ~/.gemini/skills；Codex 和 OpenCode 也会读取。",
        "Only Gemini CLI reads it. One level deep; name and description are both required.": "只有 Gemini CLI 读取。只扫描一层；名称和描述都必填。",
        "Start directory only, trusted folders only.": "只看启动目录，且只在受信任的目录中生效。",
        "Start directory only (no parent walk), trusted folders only.": "只看启动目录（不向上查找），且只在受信任的目录中生效。",
        // Gemini CLI: instruction files
        "Only Gemini CLI reads it.": "只有 Gemini CLI 读取。",
        "Gemini walks up to the .git root; trusted folders only. `context.fileName` can add AGENTS.md.":
            "Gemini 逐级向上查找，直到 .git 所在的根目录；只在受信任的目录中生效。`context.fileName` 可以追加 AGENTS.md。",
        // Gemini CLI: notes
        "Gemini CLI was replaced by Antigravity CLI for free and Google One users on 2026-06-18.":
            "对免费用户和 Google One 用户，Gemini CLI 已于 2026-06-18 被 Antigravity CLI 取代。",
        "Hide a skill: `skills.disabled` in settings.json (merged across user and workspace).":
            "隐藏技能：settings.json 里的 `skills.disabled`（用户级和工作区级取并集）。",
    ]
}
