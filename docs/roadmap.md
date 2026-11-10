# 路线图

状态以本文件为准。已完成内容的细节见 [CHANGELOG](../CHANGELOG.md)。

## 0.1.0（已完成）

| 模块 | 内容 |
|---|---|
| 调研与设计 | [research](research.md)、[architecture](architecture.md)、[ux](ux.md) |
| 核心模型 | AgentID / Scope / AssignmentRule、`kitfold.json`、Frontmatter、LineDiff、按 Profile 分块的托管块 |
| 适配器 | Claude Code、Codex、OpenCode、Gemini CLI 的声明式描述；读取各自的原生禁用设置；插件和扩展技能；嵌套 SKILL.md |
| 扫描 | 实际生效视图、健康检查（断链、同名、嵌套、外部修改、超限）、上下文估算 |
| 规划 | 两轮 Planner、Profile 托管块、共享文件和回退行为变化的提示、`.git/info/exclude` |
| 执行 | 前置条件、备份、回滚、操作日志、撤销（意图和文件一起撤回）、部署账本、把技能收编进库 |
| CLI | `status` / `skills` / `agents` / `plan` / `assign` / `profile` / `apply` / `history` / `undo`，`--home` 沙盒 |
| 界面 | Dashboard、Skills（列表/矩阵）、Agent、Profiles、Projects、History、变更预览、⌘K、设置、拖放 |
| 验证 | 29 个测试；实际生效视图与 `opencode debug skill` 对照 101/102 一致（见 [research §6](research.md)） |
| 工具 | `scripts/bundle.sh` 打包 App；演示数据和发布截图脚本 |

已知差异：OpenCode 在代码里注册的内置技能 `customize-opencode` 没有建模（磁盘上没有文件），所以上下文估算会少算一个。

## 0.2.0（已完成）

| 模块 | 内容 |
|---|---|
| 原生开关写入 | 链接藏不住的技能，写 Agent 自己的设置：Claude `skillOverrides`（项目级写 `settings.local.json`）、Codex `[[skills.config]]`（`config.toml` 末尾的托管段，只能全局）、OpenCode `permission.skill`、Gemini `skills.disabled`。只改那一条，其余字节不动、权限不变；预览只显示变化的条目；Kitfold 写过的条目记在账本里，规则撤掉时收回，撤销时连同所有权一起恢复。设计见 [architecture §5](architecture.md) |
| 界面 | 每个 Agent 用自己的标志；单个开关的历史记录写明做了什么 |
| 诊断 | 链接同时影响别的 Agent 时提示；Codex 的 `AGENTS.override.md` 让 Profile 失效时提示；按各 Agent 要求的 frontmatter 判断技能是否会被跳过 |
| 修复 | 一轮全面排查后的修复，见 [CHANGELOG](../CHANGELOG.md) |
| 中文 | App、CLI 和核心产生的所有提示都有简体中文；默认跟随系统语言，可在设置里单独指定（与系统设置里的"App 语言"是同一个设置），CLI 用 `--lang` 或 `KITFOLD_LANG`。漏翻和多余的翻译由测试拦下，见 [localization](localization.md) |
| 教程 | 中英文教程 9 篇，从第一次打开到排错，配演示数据的截图，见 [tutorials](tutorials/README.md)；帮助菜单里可以直接打开 |
| 工具 | `scripts/video/make.sh` 生成发布视频和 GIF：中英文、横屏 16:9 / 竖屏 9:16，Gemini TTS 配音并带字幕 |

已知限制：Codex 只认 `$CODEX_HOME/config.toml` 里的 `[[skills.config]]`，所以没法只在一个项目里对 Codex 隐藏技能，Kitfold 会说明这一点。

## 0.3.0（已完成）

| 模块 | 内容 |
|---|---|
| 删除技能 | 技能页和技能列表右键菜单里的“删除…”，CLI `kitfold delete <技能>`。收回指向它的链接、为它写的原生开关和分配，从 Profile 里去掉，目录移到 `~/.kitfold/backups/trash/`；先预览，可撤销。插件技能、嵌套技能和只经链接到达的目录不能删 |

## 0.4.0（已完成）

| 模块 | 内容 |
|---|---|
| 更多 Agent | `AgentCatalog`：约 70 个 Agent 各用一行描述（自己的全局/项目技能目录、是否读 `~/.agents/skills` 和 Claude Code 的目录、安装标志）。核对过官方文档的标为已验证，其余取自 skills CLI 的 Agent 清单，界面标为未验证。只列出这台 Mac 上有的 |
| 自动发现 | `AgentDiscovery`：`~/.<名字>/skills`、`~/.config/<名字>/skills` 里有技能、又不属于任何已知 Agent 或来源的目录，当作一个 Agent 列出 |
| 自定义 Agent | 设置 › Agent › 添加 Agent…，或 `kitfold.json` 的 `customAgents` |
| 删除技能 | 清理所有已知 Agent 目录里指向它的链接；skills CLI 装的技能同时从 `.skill-lock.json` 去掉；只是链接进来的技能也能删（只收回链接，目录留在原处）；不再夹带其他待应用的改动 |
| 失效链接 | 一键移除（问题里的按钮、概览页、`kitfold clean`），可撤销；同一技能在多个目录里的失效链接合并为一条 |
| 界面 | 技能详情的“谁会用到”改为每个 Agent 一行；矩阵和 Profile 网格可以横向滚动 |

## 已知问题

写教程时发现的问题都已修好，见 [CHANGELOG](../CHANGELOG.md)。新发现、还没修的问题记在 [known-issues](known-issues.md)。

## 下一步

1. **上下文瘦身模式**：Claude `skillOverrides` 的 `name-only` / `user-invocable-only`，OpenCode 的 `ask`。需要在"开/关"之外给规则加第三种状态。
2. **OpenCode/Codex 项目级 Profile 隔离**：用 OpenCode 的 `instructions[]` 指向 Kitfold 自己的文件，避免和 Codex 共用 AGENTS.md。
3. **FSEvents 监听**：取代手动重新扫描，实时提示外部修改和断链；只在窗口打开时运行，不常驻后台。
4. **CLI `--json` 和 `kitfold check`**：有漂移时返回非零退出码，方便 CI，也方便以后接跨平台外壳。
5. **Git 源更新**：pull 时检测本地修改，冲突时让用户选择保留哪一方。
6. **清理过期的原生条目**：比如 Codex 里指向已删除技能的 `[[skills.config]]`（调研时一台机器上 65 条里只有 5 条还有效），给出一键清理（可撤销）。

## 以后

- 为常用的目录型 Agent 补上原生“隐藏技能”设置和 Profile 目标文件（目前只有内置的 4 个有），见 [adding-an-agent](adding-an-agent.md)。
- 自动更新（0.2.0 起有签名、公证的 DMG 安装包）。
- Windows / Linux：核心库与界面无关，可以复用；界面需要另做（详见 [architecture §1](architecture.md)）。
