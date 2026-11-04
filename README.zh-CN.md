<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Kitfold 图标">
</p>

<h1 align="center">Kitfold</h1>

<p align="center">
  <b>One library. Every agent. Your rules.</b><br>
  一款原生 macOS 应用，统一管理 Claude Code、Codex、OpenCode、Gemini CLI 的 Skills 和指令文件。
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

<p align="center">
  <a href="https://github.com/kadaliao/kitfold/actions/workflows/ci.yml"><img src="https://github.com/kadaliao/kitfold/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white" alt="Swift 6.2+">
</p>

<p align="center">
  <img src="docs/assets/screenshots/01-agents.jpg" alt="Kitfold 的 Codex 页面，按来源分组列出 Codex 加载的每个技能">
</p>

## 为什么需要 Kitfold

每个 Coding Agent 都有自己的技能目录和指令文件（`CLAUDE.md`、`AGENTS.md`、`GEMINI.md`），发现规则、优先级、回退逻辑也各不相同。它们还会互相读对方的目录：OpenCode 会加载 Claude Code 的技能，Codex、OpenCode、Gemini CLI 都会读 `~/.agents/skills`。于是一些简单的问题很难回答：

- 每个 Agent **实际**加载了什么？从哪来？
- 怎么只给 Codex 某个技能，不给 OpenCode？
- 改了这个文件，会影响哪些 Agent？

Kitfold 回答这些问题，并且让你点一下就能安全地改变答案。

## 功能

- **实际生效视图**：对每个 Agent、每个项目，算出它真正会加载的内容：自己的目录、共享目录、别的 Agent 的目录、插件、嵌套的 `SKILL.md`，以及被它自己的设置关闭的技能。重复、断链、指令超长都会被标出来。
- **精确共享与隔离**：可以把技能分配给一个、几个或全部 Agent，全局或按项目都行。Kitfold 只部署到那个 Agent 独有的目录。做不到隔离时（比如技能放在共享目录里），会说明原因，不会假装已经做到。
- **Profiles**：可复用的指令集，比如 *Code Reviewer*、*Backend Engineer*，可以附带一组技能。每个 Profile 以一个带标记的块写进各 Agent 自己的文件，文件里的其他内容一律不碰。
- **安全优先**：
  - 所有改动先给出 diff 预览；
  - 写入前重新核对文件；
  - 被覆盖的文件先备份，每次应用都记日志；
  - 任何一次应用都能撤销，连同引起它的分配一起撤回；
  - 不认识的目录、其他工具的托管块，一律不碰。
- **本地优先**：不需要账号，不依赖云，不常驻后台。你的意图保存在一个可读的 `~/.kitfold/kitfold.json` 里。
- **键盘优先**：⌘K 跳到任何地方，⌘↩ 预览并应用。

| | |
|---|---|
| ![技能 × Agent 矩阵](docs/assets/screenshots/02-matrix.jpg) | ![带 diff 的变更预览](docs/assets/screenshots/03-review.jpg) |
| ![技能详情](docs/assets/screenshots/04-skill.jpg) | ![Profile 编辑器](docs/assets/screenshots/05-profiles.jpg) |

## 支持的 Agent

| Agent | 验证版本 | Kitfold 把技能部署到 | Profile 写到 | 原生"隐藏技能"设置（只读） |
|---|---|---|---|---|
| Claude Code | 2.1.318 | `~/.claude/skills`、`.claude/skills` | `~/.claude/rules/kitfold.md`、`.claude/rules/kitfold.md` | `skillOverrides` |
| Codex | 0.164.0 | `$CODEX_HOME/skills`、`.codex/skills` | `~/.codex/AGENTS.md`、`AGENTS.md` | `[[skills.config]]` |
| OpenCode | 1.19.4 | `~/.config/opencode/skills`、`.opencode/skills` | `~/.config/opencode/AGENTS.md`、`AGENTS.md` | `permission.skill` |
| Gemini CLI | 0.66.0 | `~/.gemini/skills`、`.gemini/skills` | `~/.gemini/GEMINI.md`、`GEMINI.md` | `skills.disabled` |

每个 Agent 都只是一份声明式描述，新增 Agent 不需要改核心逻辑，见[接入新 Agent](docs/adding-an-agent.md)。这些路径背后的调研和来源见 [docs/research.md](docs/research.md)。

## 开始使用

环境要求：运行需要 macOS 15 及以上；构建需要 Xcode 26 及以上（Swift 6.2+）。CI 使用 Swift 6.2 构建。

```bash
git clone https://github.com/kadaliao/kitfold.git && cd kitfold
make app          # 生成 build/Kitfold.app
open build/Kitfold.app
```

目前还没有预编译的发布包。`make run` 可以直接从构建目录启动 App。

**首次启动是只读的。** Kitfold 会创建 `~/.kitfold/` 来存放自己的数据，并把 `~/.agents/skills`（以及 Magpie 的库，如果存在）登记为技能来源。在你拨动开关并确认预览之前，磁盘上的其他东西都不会改变。

### 命令行

App 和命令行用的是同一套核心：

```bash
swift run kitfold status                          # 各 Agent 状态、上下文大小、健康检查
swift run kitfold skills                          # 技能 × Agent 矩阵（实际生效）
swift run kitfold agents                          # 每个 Agent 扫描的目录、加载的文件
swift run kitfold assign pdf-tools codex          # 预览：把技能给 Codex
swift run kitfold assign pdf-tools codex --yes    # ……并应用
swift run kitfold profile code-reviewer '*' --project ~/work/app --yes
swift run kitfold history
swift run kitfold undo --yes                      # 撤销最近一次应用
swift run kitfold --home /tmp/sandbox status      # 在沙盒 $HOME 里随便试
```

## 工作原理

```
kitfold.json（你的意图） ─┐
                          ├─ Planner ─→ Plan（变更 + 问题） ─→ 预览 ─→ Executor ─→ 日志 / 账本
磁盘（扫描得到的 Snapshot）┘
```

- **规则只记录你明确表达过的意图**。你没碰过的技能和 Profile 保持原样，所以首次启动不会改动任何东西。
- **规划分两轮**：先算删除，再在删除之后的视图上算新增。这样即使某个 Agent 只是通过另一个 Agent 的目录看到某个技能，也不会悄悄失去它。
- **执行器只做四种操作**：建链接、删链接、写文件、移动目录。每种都可逆，执行前检查前置条件，并记录在 `~/.kitfold/state.sqlite`。

详见 [docs/architecture.md](docs/architecture.md)。

## 文档

- [开发指南](docs/development.md)：构建、测试、沙盒、截图（英文）
- [接入新 Agent](docs/adding-an-agent.md)（英文）
- [设计文档](docs/README.md)：调研、架构、交互、路线图
- [更新日志](CHANGELOG.md)

## 参与贡献

欢迎贡献，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。特别注意：**测试和手动验证都不能写入你真实的 `$HOME`**。本项目遵守[行为准则](CODE_OF_CONDUCT.md)。报告安全问题请见 [SECURITY.md](SECURITY.md)。

## 许可证

[MIT](LICENSE) © 2026 Kada Liao
