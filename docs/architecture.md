# 技术选型与架构

## 1. SwiftUI vs Tauri

| 维度 | SwiftUI（原生） | Tauri 2（Rust + WebView） |
|---|---|---|
| 原生体验 | 系统控件、侧栏、Liquid Glass、快捷键、拖放、辅助功能、深浅色全部开箱即用，最接近 Proxyman / Raycast 的质感 | 靠 CSS 模仿；侧栏、菜单、焦点环、滚动手感总有一点"网页味" |
| 资源占用 | 一个约 5–10 MB 的二进制，空闲内存 ~40 MB，不常驻后台 | 二进制小，但带一个 WKWebView 进程，空闲 ~80–150 MB |
| 开发成本 | 单语言（Swift）。界面和核心之间不需要 IPC，也不需要序列化 | Rust + TS 两套栈，命令层需要类型桥接；前端生态和 UI 组件迭代快 |
| 文件系统 / 符号链接 / SQLite | Foundation + Darwin + 系统 libsqlite3，零依赖 | Rust 生态成熟（`std::fs`、rusqlite） |
| 跨平台 | 界面层只能跑在 macOS；核心库（Foundation）可以编译到 Linux，Windows 支持较弱 | 三平台一套代码 |
| 竞品 | — | Magpie（Wails）、cc-switch 和 skills-manager（Tauri）都是 WebView 路线 |

**选择：SwiftUI，核心与界面严格分离。**

理由：
1. 产品定义里明确"首先是一款 macOS 桌面应用"，"原生 macOS 风格、精致克制"，对标的是原生工具。这正是 WebView 竞品做不出差异化的地方。
2. 真正难、真正值钱的是**核心**：适配器、实际生效视图、规划、日志、撤销。它被写成一个只依赖 Foundation + SQLite 的 Swift 包（`KitfoldCore`），同时支撑 App 和 `kitfold` CLI。
3. 以后需要 Windows / Linux 时有两条路，都不用重写核心逻辑：
   - (a) 用 `kitfold` CLI 加 `--json` 输出做后端，外面套 Tauri 壳；
   - (b) 按 `kitfold.json` 和状态库的文档化格式，用其他语言重新实现。

## 2. 模块划分

```
Sources/
  KitfoldCore/                  ← 与界面无关，可测试
    Model/        Identifiers (AgentID, Scope, ResourceRef) · Config (kitfold.json) · Resources (SkillEntry, ProfileEntry) · Environment
    Adapters/     AgentAdapter（声明式描述 + 解析）· BuiltinAgents（4 个 Agent）· NativePolicy（读各 Agent 自己的禁用设置）
    Scan/         Scanner → Snapshot（实际生效视图）· BundledSkills（插件/扩展）· Diagnostics（健康检查）
    Library/      LibraryStore（技能、Profile、导入、Git 源）
    Sync/         Planner（意图 vs 磁盘 → 计划）· Plan/FileChange · Executor（前置条件、备份、回滚、撤销）· ManagedBlock
    State/        SQLite 包装 · StateStore（部署账本 + 操作日志）
    Workspace.swift   统一入口：scan → plan → apply → undo
  kitfold/        CLI
  KitfoldApp/     SwiftUI 界面（AppModel + 各页面）
Tests/KitfoldCoreTests/   假 HOME 中的端到端测试
```

## 3. 数据模型

### 磁盘布局
```
~/.kitfold/
  kitfold.json          用户意图（规则、项目、来源、设置）：可读、可 diff、能放进 dotfiles
  state.sqlite          运行时状态：部署账本 + 操作日志（不是配置）
  library/
    skills/<name>/SKILL.md …      Kitfold 管理的技能
    profiles/<id>.md              Profile = frontmatter(name, description, skills[], order) + 正文
  sources/<repo>/       通过 Git 导入的源（浅克隆）
  backups/<tx-id>/…     每次 apply 前被覆盖文件的备份；profiles/<id>/ 下是 Profile 的历史版本
```

为什么拆成 **JSON 意图 + SQLite 状态**：这和 Terraform 的 config/state 分离是一个思路。意图要给人看、能 diff、能用 dotfiles 工具同步到另一台 Mac；"Kitfold 在哪写过什么"属于本机运行时状态，放进事务性的数据库更合适。

### 标识与关系
- **AgentID**：`claude-code` / `codex` / `opencode` / `gemini-cli`。
- **Scope**：`global` 或 `project:<绝对路径>`（项目根取 git 根）。
- **ResourceRef**：`skill:<name>` 或 `profile:<id>`。技能按 **name** 标识。这是 Agent 自己识别技能的方式；同名的多个目录会被标出来，由用户处理。
- **AssignmentRule**：`(resource, scope, agent | "*", on | off)`。
  - **只记录用户明确表达的意图。** 没有规则 = 不表态 = 保持现状。所以首次启动是零变更、只读的。
  - 解析时具体 Agent 的规则优先于 `*`；`*` 也覆盖以后新增的 Agent。
  - Profile 规则为 on 时，Profile 自带的 skills 自动视为 on，除非某条技能规则显式 off。
- **SkillEntry**（目录）：真实路径、来源（library / source / agentLocal / external / bundled）、frontmatter、问题列表。
- **Deployment**（账本）：Kitfold 创建的链接或文件，记录 path、target、agents、scope、resource、事务 id。
- **Transaction / Operation**（日志）：每次 apply 的 FileChange 列表，以及备份路径和 `ownedBefore`（撤销时用来恢复所有权）。

## 4. Agent 适配器

Agent 之间的差异全部放在**声明式描述**（`AgentDescriptor`）里，业务逻辑里没有任何硬编码路径：

```swift
AgentDescriptor(
  id, name, binaryNames, configDir, configDirEnv,         // 检测；CLAUDE_CONFIG_DIR / CODEX_HOME / 用户覆盖
  skillRoots: [SkillRootSpec],                             // 按优先级排列，每个目录带一个角色：
      // primary 自己的目录（Kitfold 往这里部署）
      // shared  多个 Agent 共读（~/.agents/skills）
      // foreign 读别家 Agent 的目录（OpenCode → ~/.claude/skills）
      // bundled 插件、系统、管理员目录，只读
  instructionFiles: [InstructionFileSpec],                 // 每个文件带一个角色：
      // primary Kitfold 写入目标
      // loaded  也会被加载
      // fallback 仅当 related 都不存在时加载
      // override 存在时替换 related
  skillDisable: claudeSettings | codexConfig | openCodePermission | geminiSettings,
  bundledProvider: claudePlugins | codexPlugins | geminiExtensions,
  globalSkillsWin, instructionByteLimit, notes, tint, monogram)
```

`AgentAdapter` 把描述解析成具体路径，并计算实际生效的指令文件（处理 fallback / override）。`NativePolicy` 读取各 Agent 自己的禁用设置，只解析相关的那几个键；配置里的其他值（可能含密钥）不保存、不显示。新增一个 Agent 只需要再写一个描述，例如 Antigravity CLI。以后也可以让用户在设置里用 JSON 自定义。

**部署策略：隔离优先。** 每个 Agent 都部署到**只有它自己读**的位置：

| Agent | 技能（全局 / 项目） | Profile（全局 / 项目） |
|---|---|---|
| Claude Code | `~/.claude/skills` / `.claude/skills` | `~/.claude/rules/kitfold.md` / `.claude/rules/kitfold.md` |
| Codex | `$CODEX_HOME/skills` / `.codex/skills` | `~/.codex/AGENTS.md` / `AGENTS.md`（与 OpenCode 共享，会提示） |
| OpenCode | `~/.config/opencode/skills` / `.opencode/skills` | `~/.config/opencode/AGENTS.md`（会关掉回退，会提示）/ `AGENTS.md`（共享） |
| Gemini CLI | `~/.gemini/skills` / `.gemini/skills` | `~/.gemini/GEMINI.md` / `GEMINI.md` |

## 5. 分配 → 同步

```
kitfold.json（草稿） ─┐
                      ├─ Planner ─→ Plan { changes: [PlannedChange], issues: [Issue] } ─→ 预览 ─→ Executor ─→ 日志 / 账本
磁盘（Snapshot）    ──┘
```

**Snapshot**（只读扫描）包含：
- 每个 Agent 在每个作用域下看到的所有技能条目：是否符号链接、真实路径、是否被原生设置禁用、属于哪个目录角色；
- 每个指令文件：是否存在、是否真的被加载、谁共享它、Kitfold 的块、其他工具的块；
- 健康问题。

**Planner** 是纯函数，分两轮：
1. **删除轮**：规则为 off 的、Kitfold 自己部署过但已经没有规则支撑的，删除对应链接。别人创建的链接也可以删，但标为 caution，撤销时会恢复。
2. **新增轮**：在"删除之后"的视图上判断。已经能看到就跳过（包括共享目录、经由别的 Agent 的目录，以及本次计划里给别的 Agent 新建、恰好落在它也读的目录里的链接）；否则在它自己的目录建链接。

必须分两轮的原因：OpenCode 可能正是通过 Claude 目录里的链接看到某个技能，单轮规划会让它静默失去这个技能。

**做不到的情况不会假装做了**，而是生成 Issue 说明原因：
- **stillVisible**：技能在共享目录或别家目录里，删除链接也无法对这个 Agent 隐藏。建议移入库，或使用该 Agent 的原生开关。
- **conflict**：目标位置已有一个不认识的真实目录，绝不替换。
- **blockDrift**：托管块被外部修改过，必须先选"保留修改"或"覆盖"。
- **sharedInstructionFile**：比如项目里的 AGENTS.md 同时被 Codex 和 OpenCode 读。
- **fallbackChange**：新建某个文件会改变别的 Agent 的回退行为。
- **disabledNatively**：Agent 自己的设置把它关掉了。

**托管块**：每个 Profile 一个块。
```
<!-- kitfold:begin profile=backend hash=3f2a9c01b7de -->
…
<!-- kitfold:end profile=backend -->
```
hash 是 Kitfold 写入时正文的指纹，所以只看文件本身就能判断有没有外部修改。块外面的内容永远不碰；其他工具的块（magpie 等）会被识别出来，也不碰。

**Executor 的保证**：
- 每个操作执行前都重新检查前置条件：文件内容必须和预览时完全一致，链接必须还指向原来的地方。不一致就停下，并回滚已经做了的部分。
- 写入或删除文件前，先备份到 `backups/<tx>/`。
- 写入是原子的（临时文件 + rename）；如果目标是符号链接（比如 dotfiles 管理的 CLAUDE.md），写到它指向的真实文件，而不是把链接替换成普通文件。
- `kitfold.json` 的变更和文件变更放在**同一个事务**里，所以撤销会同时撤回意图，下次规划不会把改动又做回来。
- 撤销 = 逆序执行反向操作，同样先检查前置条件；只要有任何文件在 apply 之后又被改过，就整体拒绝，并列出是哪些文件。
- 写入的目标如果解析后落在 Kitfold 自己的目录里，直接拒绝，防止自我回写。

**项目文件和 git**：Kitfold 在项目里创建的链接和文件，会通过 `.git/info/exclude` 里的托管段排除。这个文件只在本地生效，不会被提交。

## 6. 安全边界

- 只做四种文件操作：建链接、删链接、写文件、移动目录。每种都有反操作。
- 永远不删真实目录，永远不覆盖不认识的目录，永远不整文件覆盖指令文件。
- 读取各 Agent 的配置时，只取需要的键；不打印、不保存任何其他值。
- "隔离"指的是配置的可见范围和分配范围，**不是**操作系统级沙箱。
