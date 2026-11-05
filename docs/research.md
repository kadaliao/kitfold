# 调研：各 Agent 的 Skills / 指令文件约定，以及现有工具

调研日期 2026-11-04。对应版本：Claude Code 2.1.318、Codex CLI 0.164.0、OpenCode 1.19.4、Gemini CLI 0.66.0（Gemini CLI 读的是 npm 包源码）。

标记约定：**[已验证]** 指对照了官方文档、对应版本的源码，或在隔离环境（假 HOME / 假 CODEX_HOME）里实测过；**[假设]** 指推断，还没有证据。

---

## 1. Claude Code 2.1.318

### Skills
| 位置 | 作用域 | 说明 |
|---|---|---|
| `/Library/Application Support/ClaudeCode/.claude/skills` | 企业 | 优先级最高 [已验证 docs] |
| `~/.claude/skills/<name>/SKILL.md` | 个人 | 只扫一层；`synced/` 是保留名（claude.ai 同步） [已验证 docs] |
| `.claude/skills/` | 项目 | 从启动目录一直往上找到 repo 根；子目录里的 `.claude/skills` 在读写该目录文件时懒加载 [已验证 docs] |
| 插件 `<installPath>/skills/` | 插件 | 以 `/plugin:skill` 命名空间调用；由 `installed_plugins.json` + settings 的 `enabledPlugins` 决定是否生效 [已验证 实机] |

- 同名时：企业 > 个人 > 项目。**个人（全局）技能压过项目技能**，这一点和其他 Agent 相反 [已验证 docs]。
- **不读 `~/.agents/skills`**，也不读 `.agents/`：docs 写明不读；实测只放在 `~/.agents/skills` 里的技能确实不出现在技能列表中 [已验证 docs + 二进制 + 实测]。
- 符号链接的技能目录会跟随，多个链接指向同一目标只加载一次；断链静默跳过 [已验证 实测：约 80 个链接全部生效，其中的断链被跳过且没有任何提示]。
- Frontmatter 字段全部可选，`name` 缺省为目录名；目录名和 `name` 都能用来调用 [已验证 docs]。
- **不删除就隐藏一个技能**：settings 里的 `skillOverrides: {"name": "on" | "name-only" | "user-invocable-only" | "off"}`，用户、项目、local 三层 settings 都能写；对插件技能无效 [已验证 docs]。另有权限规则 `Skill(name)` deny。

### 指令文件（全部拼接，从宽到窄）
1. 托管策略 `/Library/Application Support/ClaudeCode/CLAUDE.md`
2. `~/.claude/CLAUDE.md`，以及 `~/.claude/rules/**/*.md`（启动时加载）
3. 从 repo 根到启动目录，每层依次读 `CLAUDE.md` 或 `.claude/CLAUDE.md`，再读 `CLAUDE.local.md`；`.claude/rules/**/*.md` 里不带 `paths` 的规则也在启动时加载
4. 子目录的同类文件按需加载

- `@path` 导入最多 4 跳 [已验证 docs]。
- **AGENTS.md（v2.1.277 起）**：默认模式下，只有当前目录及其上层都没有 `CLAUDE.md` / `.claude/CLAUDE.md` / `CLAUDE.local.md` 时才读 `AGENTS.md`；用户级 CLAUDE.md 和 rules 不参与这个判断 [已验证 docs]。

> 对 Kitfold 的影响：如果在一个依赖 AGENTS.md 的仓库里新建 `CLAUDE.local.md`，Claude 就不再读 AGENTS.md。所以 Kitfold 把 Claude 的 Profile 写进 `.claude/rules/kitfold.md`（全局是 `~/.claude/rules/kitfold.md`）：启动即加载、只有 Claude 读、不影响 AGENTS.md 的回退逻辑。

## 2. Codex CLI 0.164.0

### Skills [全部已验证：`openai/codex@rust-v0.164.0` 源码 + 假 CODEX_HOME 实测]
| 位置 | 说明 |
|---|---|
| 仓库 `.codex/skills` | 从项目根到 cwd 的每一层；**项目未被信任时也会加载** |
| 仓库 `.agents/skills` | 从 cwd 往上到项目根（项目根由 `project_root_markers` 判定，默认 `.git`） |
| `$CODEX_HOME/skills` | 源码注释称 deprecated，但 0.164 仍然加载；**只有 Codex 读** |
| `~/.agents/skills` | 用户级共享目录 |
| `$CODEX_HOME/skills/.system` | 内置技能，每次启动重写 |
| `/etc/codex/skills` | 管理员 |
| 插件 `skills/` | 重命名为 `plugin:skill` |

- 递归最深 6 层：技能内部嵌套的 `SKILL.md` 会被当成另一个技能。
- 目录符号链接会跟随，**但符号链接形式的 `SKILL.md` 文件会被跳过**，所以只能链接整个目录。
- 按真实 SKILL.md 路径去重：同一目标被两处链接只出现一次；**不同路径的同名技能会都列出来**。
- `description` 必填；`name` 可选，缺省取目录名（链接时取目标目录名）。
- **隐藏一个技能**：`[[skills.config]]`，用 `path = "…/SKILL.md"`（或 `name`）加 `enabled = false`。**只在 `$CODEX_HOME/config.toml` 里生效**，写在项目 `.codex/config.toml` 里会被忽略。实测一台机器上有 65 条这样的条目，其中只有 5 条指向仍然存在的技能。

### 指令文件 [已验证]
- 全局：`$CODEX_HOME/AGENTS.override.md`（非空时）否则 `AGENTS.md`。
- 项目：从项目根到 cwd，每层取第一个存在的 `AGENTS.override.md` > `AGENTS.md` > `project_doc_fallback_filenames`，根在前拼接，总上限 `project_doc_max_bytes`（默认 32 KiB）。
- 不读 CLAUDE.md，除非把它加进 fallback 列表。
- 注意：Codex 自己的 "profiles"（`--profile <name>` → `<name>.config.toml`）只管模型、沙箱这类设置，和 Kitfold 的 Profile 不是一回事。

## 3. OpenCode 1.19.4

### Skills [已验证：`sst/opencode@v1.19.4` 源码 + 实机 `opencode debug skill`]
扫描顺序：`~/.claude/skills` → `~/.agents/skills` → 从 cwd 到 worktree 根每层的 `.claude/skills`、`.agents/skills` → 每个配置目录下的 `skill(s)/`（`~/.config/opencode`、各层 `.opencode/`、`~/.opencode`、`$OPENCODE_CONFIG_DIR`）→ 配置里的 `skills.paths[]`、`skills.urls[]`。

- **会读 Claude Code 的技能目录**；`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` 或 `OPENCODE_DISABLE_CLAUDE_CODE` 设为真值时不读，全局的 `~/.claude/skills` 和项目里的 `.claude/skills` 都不读。真值是 `1`、`true`、`yes`、`on`、`y`；`0`、`false`、`no`、`off`、`n` 为假；其他值（包括空串、大写的 `FALSE`）直接报错退出（2026-11-05 在沙盒 HOME 里用 `opencode debug skill` 实测）。Kitfold 按同样的规则判断，但只能看到它自己进程里的环境变量。
- **只按名字去重，最后解析到的赢**。解析是并发的，所以哪份胜出不可预测。实测一台机器上有 77 个名字同时出现在 `~/.claude/skills` 和 `~/.agents/skills`。
- 递归扫描所有子目录，`references/` 里的 SKILL.md 也会变成独立技能（实测一个技能的 `references/` 里带出了 3 个）。
- 必须有 `name`，否则丢弃；`description` 可选。文档要求的命名规则在代码里并未强制。
- **隐藏一个技能**：opencode.json 里的 `permission.skill: {"<pattern>": "allow" | "ask" | "deny"}`，最后匹配的规则生效；全局、项目、单个 agent 都能写。

### 指令文件 [已验证]
- 全局：`~/.config/opencode/AGENTS.md`，**不存在时回退到 `~/.claude/CLAUDE.md`**。
- 项目：从 cwd 到 worktree 根，找第一个出现的文件名（`AGENTS.md` > `CLAUDE.md` > `CONTEXT.md`），这条路径上该名字的所有文件都会读。
- opencode.json 的 `instructions[]` 支持 glob、绝对路径和 URL。

> 对 Kitfold 的影响：往 `~/.claude/CLAUDE.md` 写的内容会通过回退泄漏给 OpenCode；新建 `~/.config/opencode/AGENTS.md` 又会让 OpenCode 不再读 `~/.claude/CLAUDE.md`。两件事都必须在变更预览里明说。

## 4. Gemini CLI 0.66.0

geminicli.com 顶部写着："Gemini CLI was replaced by Antigravity CLI on June 18th, 2026"（针对免费和 Google One 用户）。

### Skills [已验证：`@google/gemini-cli-core@0.66.0` 源码]
优先级从低到高（后者覆盖前者，按 `name`）：内置 → 扩展 `<ext>/skills/` → `~/.gemini/skills` → `~/.agents/skills` → `<cwd>/.gemini/skills` → `<cwd>/.agents/skills`。

- 项目级只看启动目录，不往上找，而且只在受信任文件夹里生效。
- 只扫一层，`name` 和 `description` 都必填。
- 同名但路径不同（按未解析路径比较）会给出 "Skill conflict detected" 警告。当 `~/.gemini/skills/x → ~/.agents/skills/x` 和 `~/.agents/skills/x` 同时存在时就会触发 [推断]。
- **隐藏一个技能**：settings 的 `skills.disabled: [...]`，用户级和工作区级取并集。

### 指令文件 [已验证]
- `~/.gemini/GEMINI.md`；项目从启动目录往上到 `.git`，按 inode 去重（所以符号链接只加载一次）。
- `context.fileName` 是在 GEMINI.md 的基础上**追加**文件名，不是替换。
- `@import` 不支持 `~`，并且解析真实路径后必须仍在导入方的根目录内，所以不能 `@import` Kitfold 库里的文件。

---

## 5. 典型机器上的现状（这些正是 Kitfold 要解决的问题）

下面是一台装了约 80 个技能、同时用 `npx skills` 和 Magpie 的开发机：
- `~/.agents/skills` 由 `npx skills` 管理，但它的 lock 文件只记录了其中一小部分技能的来源。
- `~/.claude/skills` 几乎全是指向 `~/.agents/skills` 的链接，其中有断链，Claude Code 跳过时没有任何提示。
- OpenCode 通过 `~/.claude/skills` 和 `~/.agents/skills` 两个目录读到同一批技能，约 77 个名字重复。Gemini CLI 的情况类似。
- Codex 的 config.toml 里有几十条 `[[skills.config]] enabled = false`，大部分指向已删除的目录，已经过期。真正生效的几条从目录上完全看不出来。
- Codex 和 OpenCode 会把技能内部嵌套的 SKILL.md 当成独立技能。两个"技能合集"因此额外带进了二十多个技能。
- 第三方工具在 `~/.claude/CLAUDE.md` 里写了托管块，同时把技能链接给了多个 Agent。这些技能可能和用户自己写的规则相互冲突（比如规则禁止的服务，技能却在调用），只有把**实际生效**的配置放在一起看，才能发现。

## 6. 实测核对（2026-11-04）

在上述机器上用 `kitfold skills` 计算 OpenCode 会加载哪些技能，和 OpenCode 自己的 `opencode debug skill` 输出逐个比对：
- OpenCode 报告 102 个，Kitfold 算出其中的 101 个，没有多算。
- 唯一的差异是 `customize-opencode`，它是在代码里注册的内置技能，磁盘上没有对应文件。

Codex 的 3 条针对 `~/.agents/skills` 下技能的禁用、1 条针对内置技能的禁用，都在矩阵里正确显示为"被 Agent 自己的设置关闭"。

## 7. 现有工具

| 工具 | 真相来源 | 部署方式 | 作用域 | 指令文件 | 外部修改 | 预览/撤销 |
|---|---|---|---|---|---|---|
| Magpie (yetone, Go+Wails) | `~/.config/magpie/library` + `library.json` | 绝对符号链接 / 带标记的副本；CLAUDE.md 托管块（带 hash） | 按 Agent；项目只支持技能 | **只有一套**全局指令 | 回收到库；更新时拒绝覆盖 | 每次变更备份，保留 30 份 |
| vercel `skills` CLI | `~/.agents/skills` + lock | 相对链接，失败就复制 | 全局/项目 | 无 | 覆盖 | 无 |
| cc-switch (Tauri) | `~/.cc-switch` + SQLite | 链接，失败就复制 | 只有全局 | **整文件覆盖**，每个 App 一份 | 切换前回收 | 备份 |
| ruler / rulesync | `.ruler/` / `.rulesync/` | 生成后覆盖 | 项目 | 所有 Agent 同一份 / 按 target | `.bak` / 无 | dry-run |
| skillshare | `~/.config/skillshare` | 链接/复制/@import | 全局/项目 + 过滤 | import/块/链接 | 当作"本地覆盖"保留 | 备份 + 回收站 |

**值得借鉴**
- Magpie 和 skillshare 的所有权账本：只拿回自己写过的东西。
- 托管块里带 hash，用来检测外部修改。
- Agent 本来就读共享目录时，不再给它重复链接。
- 先 dry-run 再收编；不认识的目录一律保留。
- `.git/info/exclude` 托管块。
- skillshare 的上下文 token 分析。
- rulesync 的 `--check` 漂移检测。

**要做得更好**
- **隔离**：cc-switch #4407 说明，技能放在共享目录时，"对某个 Agent 关闭"会静默失效。Kitfold 对"哪个 Agent 读哪个目录"建模，做不到隔离时直接告诉用户原因和办法。
- **实际生效视图**：没有任何一个工具能回答"Codex 现在到底加载了什么、从哪来、被谁遮蔽、有没有超过 32 KiB"。
- **安全**：
  - 绝不整文件覆盖（cc-switch #7673）。
  - 绝不替换不认识的目录（skills CLI #1906）。
  - 写入前检查目标不是 Kitfold 自己的源文件，避免 Magpie #2349 那种自我回写，导致文件膨胀到 GB 级。
  - 写之前做前置条件检查，有操作日志，可以撤销。
- **Profile 可以分配给单个 Agent 和单个项目**：Magpie #4646 正在要这个能力。

**共存**
- 不写 `.skill-lock.json`，只读，用来标注技能来源。
- 认出 `<!-- magpie:begin -->` 等其他工具的托管块，不去碰。
- 链接到其他工具库里的技能，标注归属后保持不动。
