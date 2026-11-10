import Foundation

// The catalog: agents that keep skills in folders of their own. Unverified entries follow the
// skills CLI's agent table (github.com/vercel-labs/skills, src/agents.ts, November 2026); verified
// ones were checked against the agent's docs or source (see docs/research.md §8).
//
// Built-in agents (Claude Code, Codex, OpenCode, Gemini CLI) are in BuiltinAgents.swift.
// Order matters only when two agents call the same folder their own: the first one owns it.
// `binaries` lists only names no other common tool uses (`goose`, `forge`, `pi`, `fx`, `hermes` do);
// the config folder is enough to tell an agent is installed.
extension AgentCatalog {
    static let specs: [AgentSpec] = [
        // MARK: IDEs and their CLIs
        AgentSpec(
            "cursor", "Cursor", vendor: "Anysphere", home: "~/.cursor", binaries: ["cursor-agent"], projectSkills: [".cursor/skills"],
            agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true, reads: ["~/.codex/skills"],
            projectReads: [".codex/skills"], bundled: ["skills-cursor"],
            instructions: [AgentSpec.ownInstructions(".cursor/rules/kitfold.mdc", scope: .project, header: AgentSpec.cursorRuleHeader)],
            requiresName: true, requiresDescription: true, nestedDepth: 6, docs: "https://cursor.com/docs/skills",
            monogram: "Cu", tint: "#6E6E73", markers: ["/Applications/Cursor.app"], configDirMeansInstalled: false, verified: true,
            notes: [AgentSpec.Notes.cursor]),
        AgentSpec(
            "kiro", "Kiro", vendor: "AWS", home: "~/.kiro", homeEnv: "KIRO_HOME", binaries: ["kiro-cli"],
            projectSkills: [".kiro/skills"],
            instructions: [
                AgentSpec.ownInstructions("steering/kitfold.md", header: AgentSpec.kiroSteeringHeader),
                AgentSpec.ownInstructions(".kiro/steering/kitfold.md", scope: .project, header: AgentSpec.kiroSteeringHeader),
            ],
            requiresName: true, requiresDescription: true, docs: "https://kiro.dev/docs/skills/", tint: "#7B5CFA",
            markers: ["/Applications/Kiro.app"], configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "trae", "Trae", vendor: "ByteDance", home: "~/.trae", projectSkills: [".trae/skills"], agentsGlobal: true,
            agentsProject: true, reads: ["~/.trae-cn/skills"], instructions: [AgentSpec.ownInstructions("user_rules/kitfold.md")],
            requiresName: true, requiresDescription: true, docs: "https://docs.trae.ai/ide/skills", tint: "#F04B4B",
            markers: ["/Applications/Trae.app"], configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "trae-cn", "Trae CN", vendor: "ByteDance", home: "~/.trae-cn", projectSkills: [".trae/skills"], agentsGlobal: true,
            agentsProject: true, reads: ["~/.trae/skills"], instructions: [AgentSpec.ownInstructions("user_rules/kitfold.md")],
            requiresName: true, requiresDescription: true, docs: "https://docs.trae.cn/ide_skills", monogram: "TN", tint: "#E0614F",
            markers: ["/Applications/Trae CN.app"], configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "antigravity", "Antigravity", vendor: "Google", home: "~/.gemini/antigravity",
            skills: ["~/.gemini/config/skills", "skills"], projectReads: [".agents/skills", ".agent/skills"],
            instructions: [
                AgentSpec.ownInstructions("~/.gemini/config/rules/kitfold.md", header: AgentSpec.alwaysOnRuleHeader),
                InstructionFileSpec(
                    .home, ".gemini/GEMINI.md", scope: .global, role: .loaded, note: AgentSpec.Notes.geminiFile),
            ],
            requiresDescription: true, docs: "https://antigravity.google/docs/skills", monogram: "AG", tint: "#3C7BF4",
            markers: ["/Applications/Antigravity.app"], configDirMeansInstalled: false, verified: true, notes: [AgentSpec.Notes.antigravity]
        ),
        AgentSpec(
            "antigravity-cli", "Antigravity CLI", vendor: "Google", home: "~/.gemini/antigravity-cli", binaries: ["agy"],
            reads: ["~/.gemini/skills", "~/.gemini/config/skills"], projectReads: [".agents/skills", ".agent/skills"],
            instructions: [
                AgentSpec.ownInstructions("~/.gemini/config/rules/kitfold.md", header: AgentSpec.alwaysOnRuleHeader),
                InstructionFileSpec(
                    .home, ".gemini/GEMINI.md", scope: .global, role: .loaded, note: AgentSpec.Notes.geminiFile),
            ],
            requiresDescription: true, docs: "https://antigravity.google/docs/cli/gcli-migration", monogram: "AC", tint: "#4285F4",
            verified: true),
        AgentSpec(
            "github-copilot", "GitHub Copilot", vendor: "GitHub", home: "~/.copilot", homeEnv: "COPILOT_HOME", binaries: ["copilot"],
            projectSkills: [".github/skills"], agentsGlobal: true, agentsProject: true, claudeProject: true,
            instructions: [AgentSpec.ownInstructions("copilot-instructions.md")],
            docs: "https://docs.github.com/en/copilot/reference/cli-command-reference", tint: "#8957E5", verified: true),
        AgentSpec(
            "zed", "Zed", vendor: "Zed Industries", home: "~/.config/zed", binaries: ["zed"], skills: [], agentsGlobal: true,
            agentsProject: true, instructions: [AgentSpec.ownInstructions("AGENTS.md")], requiresName: true,
            requiresDescription: true, docs: "https://zed.dev/docs/ai/skills", monogram: "Zd", tint: "#2F80ED",
            markers: ["/Applications/Zed.app"], verified: true, notes: [AgentSpec.Notes.zed]),
        AgentSpec(
            "junie", "Junie", vendor: "JetBrains", home: "~/.junie", homeEnv: "JUNIE_HOME", binaries: ["junie"],
            projectSkills: [".junie/skills"], agentsGlobal: true, agentsProject: true,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], requiresName: true,
            docs: "https://junie.jetbrains.com/docs/agent-skills.html", tint: "#2EA44F", verified: true),
        AgentSpec(
            "qoder", "Qoder", vendor: "Alibaba", home: "~/.qoder", homeEnv: "QODER_CONFIG_DIR", binaries: ["qodercli"],
            projectSkills: [".qoder/skills"], agentsGlobal: true, agentsProject: true,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], docs: "https://docs.qoder.com/cli/Skills", tint: "#2E6BF0",
            markers: ["/Applications/Qoder IDE.app", "/Applications/Qoder.app"], verified: true),
        AgentSpec(
            "qoder-cn", "Qoder CN", vendor: "Alibaba", home: "~/.qoder-cn", homeEnv: "QODERCN_CONFIG_DIR", binaries: ["qoderclicn"],
            projectSkills: [".qoder/skills"], agentsGlobal: true, agentsProject: true, reads: ["~/.qoder/skills"],
            projectReads: [".lingma/skills"], instructions: [AgentSpec.ownInstructions("AGENTS.md")],
            docs: "https://help.aliyun.com/zh/lingma/qodercli-cn/user-guide/skills", monogram: "QN", tint: "#4F7CAC", verified: true),
        AgentSpec(
            "lingma", "Lingma", vendor: "Alibaba", home: "~/.lingma", projectSkills: [".lingma/skills"], agentsGlobal: true,
            agentsProject: true,
            instructions: [AgentSpec.ownInstructions(".lingma/rules/kitfold.md", scope: .project, header: AgentSpec.alwaysOnRuleHeader)],
            requiresName: true, requiresDescription: true, docs: "https://help.aliyun.com/zh/lingma/user-guide/skills",
            tint: "#615CED", markers: ["/Applications/Lingma.app", "/Applications/Qoder CN IDE.app"], configDirMeansInstalled: false,
            verified: true),
        AgentSpec(
            "codebuddy", "CodeBuddy", vendor: "Tencent", home: "~/.codebuddy", homeEnv: "CODEBUDDY_CONFIG_DIR",
            binaries: ["codebuddy", "cbc", "codebuddy-code"], projectSkills: [".codebuddy/skills"], agentsGlobal: true,
            claudeGlobal: true, reads: ["~/.openclaw/skills"], bundled: ["connectors/skills"],
            instructions: [AgentSpec.ownInstructions("rules/kitfold.md", header: AgentSpec.cursorRuleHeader)],
            requiresName: true, requiresDescription: true, nestedDepth: 5, docs: "https://www.codebuddy.ai/docs/cli/skills",
            monogram: "CB", tint: "#4A6CF7", markers: ["/Applications/CodeBuddy.app", "/Applications/CodeBuddy CN.app"],
            configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "continue", "Continue", vendor: "Continue Dev", home: "~/.continue", homeEnv: "CONTINUE_GLOBAL_DIR",
            projectSkills: [".continue/skills"], claudeProject: true, followsLinks: false, projectFollowsLinks: false,
            instructions: [AgentSpec.ownInstructions("rules/kitfold.md", header: AgentSpec.cursorRuleHeader)],
            requiresName: true, requiresDescription: true, docs: "https://docs.continue.dev", monogram: "Cn", tint: "#BE1B55",
            markers: ["~/.vscode/extensions/continue.continue-*", "~/.continue/node_modules/@continuedev/cli"],
            configDirMeansInstalled: false, verified: true, notes: [AgentSpec.Notes.continueLinks]),
        AgentSpec(
            "augment", "Augment", vendor: "Augment Code", home: "~/.augment", binaries: ["auggie"],
            projectSkills: [".augment/skills"], agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true,
            instructions: [AgentSpec.ownInstructions("rules/kitfold.md")], requiresName: true, requiresDescription: true,
            docs: "https://docs.augmentcode.com/cli/skills", tint: "#3BA776", verified: true),
        AgentSpec(
            "cline", "Cline", vendor: "Cline", home: "~/.cline", homeEnv: "CLINE_DIR", binaries: ["cline"],
            projectSkills: [".cline/skills", ".clinerules/skills"], agentsGlobal: true, agentsProject: true, claudeProject: true,
            readsFirst: true, requiresName: true, requiresDescription: true, docs: "https://docs.cline.bot/features/skills",
            tint: "#5C6BC0", verified: true),
        AgentSpec(
            "roo", "Roo Code", vendor: "Roo Code", home: "~/.roo", projectSkills: [".roo/skills"], agentsGlobal: true,
            agentsProject: true, requiresName: true, requiresDescription: true, docs: "https://github.com/RooCodeInc/Roo-Code",
            tint: "#C27BD8", verified: true, notes: [AgentSpec.Notes.roo]),
        AgentSpec(
            "kilo", "Kilo Code", vendor: "Kilo", home: "~/.config/kilo", binaries: ["kilocode"],
            skills: ["~/.kilo/skills", "~/.kilocode/skills", "skills"], projectSkills: [".kilo/skills", ".kilocode/skills"],
            agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true,
            readsSkippedWhen: ["KILO_DISABLE_EXTERNAL_SKILLS"],
            claudeSkippedWhen: ["KILO_DISABLE_CLAUDE_CODE", "KILO_DISABLE_CLAUDE_CODE_SKILLS"],
            instructions: [AgentSpec.ownInstructions("~/.kilo/rules/kitfold.md")], requiresName: true, nestedDepth: 6,
            docs: "https://kilo.ai/docs/customize/skills", monogram: "Kl", tint: "#E5C33B", markers: ["~/.kilo", "~/.kilocode"],
            verified: true),

        // MARK: terminal agents
        AgentSpec(
            "amp", "Amp", vendor: "Amp", home: "~/.config/amp", binaries: ["amp"], agentsProject: true, claudeGlobal: true,
            claudeProject: true, reads: ["~/.config/agents/skills", "~/.agents/skills"], readsFirst: true,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], requiresName: true, requiresDescription: true, nestedDepth: 5,
            docs: "https://ampcode.com/manual", tint: "#F34E3F", verified: true, notes: [AgentSpec.Notes.amp]),
        AgentSpec(
            "droid", "Droid", vendor: "Factory", home: "~/.factory", binaries: ["droid"], skills: ["skills", "~/.agent/skills"],
            projectSkills: [".factory/skills", ".agent/skills"], agentsGlobal: true, agentsProject: true,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], requiresName: true,
            docs: "https://docs.factory.ai/cli/configuration/skills", tint: "#E59A2C", verified: true),
        AgentSpec(
            "devin", "Devin", vendor: "Cognition", home: "~/.config/devin", binaries: ["devin", "devin-desktop"],
            skills: ["skills", "~/.codeium/windsurf/skills"], projectSkills: [".devin/skills", ".windsurf/skills", ".cognition/skills"],
            agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true,
            reads: ["~/.cursor/skills", "~/.copilot/skills"], projectReads: [".cursor/skills", ".github/skills"],
            bundled: ["/Library/Application Support/Devin/skills"],
            instructions: [AgentSpec.ownInstructions("~/.devin/rules/kitfold.md", header: AgentSpec.alwaysOnRuleHeader)],
            docs: "https://docs.devin.ai/cli/extensibility/skills/overview", monogram: "Dv", tint: "#1F9D8B",
            markers: ["/Applications/Devin.app", "/Applications/Windsurf.app"], configDirMeansInstalled: false, verified: true,
            notes: [AgentSpec.Notes.devin]),
        AgentSpec(
            "grok", "Grok Build", vendor: "xAI", home: "~/.grok", homeEnv: "GROK_HOME", binaries: ["grok"],
            projectSkills: [".grok/skills"], agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true,
            reads: ["~/.cursor/skills"], projectReads: [".cursor/skills"], bundled: ["bundled/skills"],
            instructions: [
                AgentSpec.ownInstructions("rules/kitfold.md"),
                InstructionFileSpec(.home, ".claude/CLAUDE.md", scope: .global, role: .loaded, note: AgentSpec.Notes.claudeFile),
                InstructionFileSpec(.home, ".claude/rules/*.md", scope: .global, role: .loaded, note: AgentSpec.Notes.claudeFile),
            ],
            nestedDepth: 5, docs: "https://github.com/xai-org/grok-build", tint: "#111111", verified: true,
            notes: [AgentSpec.Notes.grok]),
        AgentSpec(
            "goose", "Goose", vendor: "Block", home: "~/.config/goose", projectSkills: [".goose/skills"], agentsGlobal: true,
            agentsProject: true, claudeGlobal: true, claudeProject: true, reads: ["~/.config/agents/skills"],
            instructions: [AgentSpec.ownInstructions(".goosehints")], requiresName: true, nestedDepth: 6,
            docs: "https://goose-docs.ai/docs/guides/context-engineering/using-skills", tint: "#4A4A4A", verified: true),
        AgentSpec(
            "crush", "Crush", vendor: "Charm", home: "~/.config/crush", binaries: ["crush"], projectSkills: [".crush/skills"],
            agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true, reads: ["~/.config/agents/skills"],
            projectReads: [".cursor/skills"], instructions: [AgentSpec.ownInstructions("CRUSH.md")], requiresName: true,
            requiresDescription: true, nestedDepth: 6, docs: "https://github.com/charmbracelet/crush", tint: "#6B50FF",
            markers: ["~/.local/share/crush"], verified: true),
        AgentSpec(
            "pi", "Pi", vendor: "Earendil", home: "~/.pi/agent", homeEnv: "PI_CODING_AGENT_DIR", projectSkills: [".pi/skills"],
            agentsGlobal: true, agentsProject: true, instructions: [AgentSpec.ownInstructions("AGENTS.md")],
            requiresDescription: true, docs: "https://github.com/earendil-works/pi", tint: "#2FA6B8", verified: true),
        AgentSpec(
            "warp", "Warp", vendor: "Warp", home: "~/.warp", skills: ["skills"], projectSkills: [".warp/skills"],
            agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true,
            reads: [
                "~/.codex/skills", "~/.cursor/skills", "~/.gemini/skills", "~/.copilot/skills", "~/.factory/skills",
                "~/.github/skills", "~/.opencode/skills", "~/.kiro/skills",
            ],
            projectReads: [
                ".codex/skills", ".cursor/skills", ".gemini/skills", ".copilot/skills", ".factory/skills", ".github/skills",
                ".opencode/skills", ".kiro/skills",
            ],
            docs: "https://docs.warp.dev", tint: "#01A4FF", markers: ["/Applications/Warp.app", "~/.warp_cli"],
            configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "qwen-code", "Qwen Code", vendor: "Alibaba", home: "~/.qwen", homeEnv: "QWEN_HOME", binaries: ["qwen"],
            projectSkills: [".qwen/skills"], agentsGlobal: true, agentsProject: true,
            instructions: [AgentSpec.ownInstructions("rules/kitfold.md")], requiresName: true, requiresDescription: true,
            docs: "https://qwenlm.github.io/qwen-code-docs/", monogram: "Qw", tint: "#615CED", verified: true),
        AgentSpec(
            "kimi-code-cli", "Kimi Code CLI", vendor: "Moonshot AI", home: "~/.kimi-code", homeEnv: "KIMI_CODE_HOME",
            binaries: ["kimi"], projectSkills: [".kimi-code/skills"], agentsGlobal: true, agentsProject: true,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], requiresName: true, requiresDescription: true,
            docs: "https://github.com/MoonshotAI/kimi-code", monogram: "Km", tint: "#1A1A1A", verified: true),
        AgentSpec(
            "iflow-cli", "iFlow CLI", vendor: "iFlow", home: "~/.iflow", binaries: ["iflow"], projectSkills: [".iflow/skills"],
            docs: "https://platform.iflow.cn/cli", tint: "#5B8DEF"),
        AgentSpec(
            "openhands", "OpenHands", vendor: "All Hands AI", home: "~/.openhands", binaries: ["openhands", "agent-canvas"],
            skills: ["skills", "microagents"], projectSkills: [".openhands/skills", ".openhands/microagents"], agentsGlobal: true,
            agentsProject: true, readsFirst: true, docs: "https://docs.openhands.dev/overview/skills", monogram: "OH",
            tint: "#E3B341", verified: true),
        AgentSpec(
            "mistral-vibe", "Mistral Vibe", vendor: "Mistral AI", home: "~/.vibe", homeEnv: "VIBE_HOME", binaries: ["vibe-acp"],
            projectSkills: [".vibe/skills"], agentsGlobal: true, agentsProject: true,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], requiresName: true, requiresDescription: true,
            docs: "https://docs.mistral.ai/vibe/code/cli/skills", tint: "#FA520F", verified: true),
        AgentSpec(
            "hermes-agent", "Hermes Agent", vendor: "Nous Research", home: "~/.hermes", homeEnv: "HERMES_HOME",
            projectSkills: [".hermes/skills"], agentsProject: true, instructions: [AgentSpec.ownInstructions("SOUL.md")],
            nestedDepth: 6, docs: "https://hermes-agent.nousresearch.com", tint: "#8C7AE6", verified: true),
        AgentSpec(
            "openclaw", "OpenClaw", vendor: "OpenClaw", home: "~/.openclaw", homeEnv: "OPENCLAW_STATE_DIR", binaries: ["openclaw"],
            skills: ["skills", "workspace/skills", "workspace/.agents/skills"], agentsGlobal: true, requiresDescription: true,
            docs: "https://docs.openclaw.ai", monogram: "Cw", tint: "#E0614F",
            markers: ["/Applications/OpenClaw.app", "~/.clawdbot", "~/.moltbot"], configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "autoclaw", "AutoClaw", vendor: "Zhipu AI", home: "~/.openclaw-autoclaw", skills: ["skills", "workspace/skills"],
            agentsGlobal: true, requiresDescription: true, monogram: "AW", tint: "#3BA776", markers: ["/Applications/AutoClaw.app"],
            configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "qclaw", "QClaw", vendor: "Tencent", home: "~/.qclaw", skills: ["skills", "workspace/skills"], agentsGlobal: true,
            requiresDescription: true, monogram: "QC", tint: "#4A6CF7", markers: ["/Applications/QClaw.app"],
            configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "workbuddy", "WorkBuddy", vendor: "Tencent", home: "~/.workbuddy", homeEnv: "WORKBUDDY_CONFIG_DIR",
            bundled: ["connectors/skills"], nestedDepth: 5, docs: "https://www.workbuddy.ai/docs", monogram: "WB", tint: "#2FA6B8",
            markers: ["/Applications/WorkBuddy.app"], configDirMeansInstalled: false, verified: true),
        AgentSpec(
            "fx", "fx", vendor: "Vercel Labs", home: "~/.fx", homeEnv: "FX_HOME", projectSkills: [".fx/skills", "skills"],
            agentsGlobal: true, agentsProject: true, claudeGlobal: true, claudeProject: true,
            reads: ["~/.config/opencode/skills", "~/.codex/skills", "~/.claw/skills"],
            projectReads: [".opencode/skills", ".codex/skills", ".claw/skills"], followsLinks: false,
            instructions: [AgentSpec.ownInstructions("AGENTS.md")], docs: "https://fx.sh/docs/capabilities/skills",
            tint: "#B07A4F", verified: true, notes: [AgentSpec.Notes.fx]),
        AgentSpec(
            "deepagents", "Deep Agents", vendor: "LangChain", home: "~/.deepagents", skills: ["agent/skills"], agentsProject: true,
            docs: "https://docs.langchain.com/oss/python/deepagents/cli", tint: "#1C3C3C"),
        AgentSpec(
            "tabnine-cli", "Tabnine CLI", vendor: "Tabnine", home: "~/.tabnine", skills: ["agent/skills"],
            projectSkills: [".tabnine/agent/skills"], docs: "https://docs.tabnine.com", monogram: "Tb", tint: "#6C47FF"),
        AgentSpec(
            "rovodev", "Rovo Dev", vendor: "Atlassian", home: "~/.rovodev", projectSkills: [".rovodev/skills"],
            docs: "https://support.atlassian.com/rovo/", tint: "#1868DB"),
        AgentSpec(
            "cortex", "Cortex Code", vendor: "Snowflake", home: "~/.snowflake/cortex", projectSkills: [".cortex/skills"],
            docs: "https://docs.snowflake.com", monogram: "Ct", tint: "#29B5E8"),
        AgentSpec(
            "firebender", "Firebender", vendor: "Firebender", home: "~/.firebender", agentsProject: true,
            docs: "https://docs.firebender.com", tint: "#F05A28"),
        AgentSpec(
            "forgecode", "ForgeCode", vendor: "Antinomy", home: "~/.forge", projectSkills: [".forge/skills"],
            tint: "#CF6B3E"),
        AgentSpec(
            "autohand-code", "Autohand Code CLI", vendor: "Autohand", home: "~/.autohand", homeEnv: "AUTOHAND_HOME",
            projectSkills: [".autohand/skills"], monogram: "AH"),
        AgentSpec("bob", "IBM Bob", vendor: "IBM", home: "~/.bob", projectSkills: [".bob/skills"], tint: "#0F62FE"),
        AgentSpec(
            "codearts-agent", "CodeArts Agent", vendor: "Huawei Cloud", home: "~/.codeartsdoer",
            projectSkills: [".codeartsdoer/skills"], tint: "#C7000B"),
        AgentSpec("codemaker", "Codemaker", vendor: "NetEase", home: "~/.codemaker", projectSkills: [".codemaker/skills"], monogram: "Cd"),
        AgentSpec("codestudio", "Code Studio", home: "~/.codestudio", projectSkills: [".codestudio/skills"]),
        AgentSpec("command-code", "Command Code", home: "~/.commandcode", projectSkills: [".commandcode/skills"], monogram: "Cm"),
        AgentSpec("aider-desk", "AiderDesk", home: "~/.aider-desk", projectSkills: [".aider-desk/skills"]),
        AgentSpec("astrbot", "AstrBot", home: "~/.astrbot", skills: ["data/skills"]),
        AgentSpec("dexto", "Dexto", home: "~/.dexto", skills: [], agentsGlobal: true, agentsProject: true),
        AgentSpec("inference-sh", "inference.sh", home: "~/.inferencesh", projectSkills: [".inferencesh/skills"]),
        AgentSpec("jazz", "Jazz", home: "~/.jazz", projectSkills: [".jazz/skills"]),
        AgentSpec(
            "kimchi", "Kimchi", home: "~/.config/kimchi", skills: ["harness/skills"], projectSkills: [".kimchi/skills"], monogram: "Kc"),
        AgentSpec("kode", "Kode", home: "~/.kode", projectSkills: [".kode/skills"]),
        AgentSpec("loaf", "Loaf", home: "~/.loaf", skills: [], agentsGlobal: true, agentsProject: true),
        AgentSpec("mcpjam", "MCPJam", home: "~/.mcpjam", projectSkills: [".mcpjam/skills"], monogram: "MJ"),
        AgentSpec(
            "minimax-code", "MiniMax Code", vendor: "MiniMax", home: "~/.minimax", projectSkills: [".minimax/skills"],
            markers: ["/Applications/MiniMax Code.app"]),
        AgentSpec("moxby", "Moxby", home: "~/.moxby", projectSkills: [".moxby/skills"]),
        AgentSpec("mux", "Mux", vendor: "Coder", home: "~/.mux", projectSkills: [".mux/skills"]),
        AgentSpec("ona", "Ona", vendor: "Gitpod", home: "~/.ona", projectSkills: [".ona/skills"]),
        AgentSpec(
            "posit-assistant", "Posit Assistant", vendor: "Posit", home: "~/.posit/assistant",
            projectSkills: [".posit/assistant/skills"], markers: ["~/.positai"]),
        AgentSpec("reasonix", "Reasonix", home: "~/.reasonix", homeEnv: "REASONIX_HOME", projectSkills: [".reasonix/skills"]),
        AgentSpec(
            "sarvam-code", "Sarvam Code", vendor: "Sarvam AI", home: "~/.sarvam", skills: [], agentsGlobal: true, agentsProject: true),
        AgentSpec("terramind", "Terramind", home: "~/.terramind", projectSkills: [".terramind/skills"]),
        AgentSpec("tinycloud", "Tinycloud", home: "~/.tinycloud", projectSkills: [".tinycloud/skills"]),
        AgentSpec(
            "zcode", "ZCode", vendor: "Zhipu AI", home: "~/.zcode", projectSkills: [".zcode/skills"], markers: ["/Applications/ZCode.app"]),
        AgentSpec("zencoder", "Zencoder", vendor: "Zencoder", home: "~/.zencoder", projectSkills: [".zencoder/skills"], monogram: "Zn"),
        AgentSpec("neovate", "Neovate", home: "~/.neovate", projectSkills: [".neovate/skills"]),
        AgentSpec("pochi", "Pochi", home: "~/.pochi", projectSkills: [".pochi/skills"]),
        AgentSpec("adal", "AdaL", home: "~/.adal", projectSkills: [".adal/skills"]),
    ]
}
