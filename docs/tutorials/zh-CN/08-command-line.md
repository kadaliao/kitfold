# 08 命令行

Kitfold 附带一个命令行工具 `kitfold`。它和 App 用的是同一套核心、同一个 `~/.kitfold`：同样的分配规则，同样先预览再应用，同样记进历史记录。读完这篇，你可以在终端里查看每个 Agent 加载了什么、分配技能和 Profile、撤销变更，也知道怎么把它写进脚本。

## 找到 kitfold

- **在仓库里直接运行**：`swift run kitfold status`（会先编译），或者 `make cli ARGS="status"`。`make build` 之后，可执行文件在 `.build/debug/kitfold`。
- **打包好的 App 里**：从安装包装进“应用程序”的，在 `/Applications/Kitfold.app/Contents/Resources/kitfold`；`make app` 会把它放进 `build/Kitfold.app/Contents/Resources/kitfold`。

想在任何目录下直接敲 `kitfold`，把它链接到 `PATH` 里的某个目录，比如：

```bash
ln -s /Applications/Kitfold.app/Contents/Resources/kitfold ~/.local/bin/kitfold
```

App 挪了位置，这个链接就要重新建。

App 和命令行可以混着用：命令行应用的变更会出现在 App 的“历史记录”里，可以在 App 里撤销，反过来也一样。App 开着的时候用命令行改了分配，切回 App、点“重新扫描”或者拨下一个开关时，App 会重新读取 `kitfold.json`（命令行应用或撤销过的话，还会重新扫描），并提示“kitfold.json 在 Kitfold 之外被修改，已重新载入。”。你在 App 里还没应用的开关会保留下来；两边改了同一个开关的，以 App 里还没应用的为准。

## 先在沙盒里练

```bash
KITFOLD_LANG=zh-Hans make demo DIR=/tmp/kf-demo
.build/debug/kitfold --home /tmp/kf-demo status
```

`make demo` 会生成一套虚构的数据：四个 Agent、一些技能、三个 Profile、两个项目（acme-web 和 payments-api），以及几条历史记录。前面的 `KITFOLD_LANG=zh-Hans` 让这些历史记录用中文写入，不加就是英文。

`--home` 让 `kitfold` 把那个目录当成 `$HOME`：Agent 的目录、Kitfold 自己的数据都在里面，你真实的配置一个字节都不会碰。

用 `--home` 时，路径里的 `~` 记得加引号，比如 `--project '~/work/acme-web'`。这样 `~` 由 `kitfold` 按沙盒来展开，而不会被 shell 展开成你真正的主目录。

本篇的输出都来自这套演示数据。每条命令实际运行时都带着 `--home /tmp/kf-demo --no-color`，下面为了简洁省略不写。

## 选项

| 选项 | 作用 |
|---|---|
| `--home <目录>` | 把这个目录当成 `$HOME`，在沙盒里试 |
| `--project <路径>` | 作用于某个项目，而不是全局。可以用相对路径，Kitfold 会找到它的 git 根目录 |
| `--yes`、`-y` | 真正应用或撤销。不加只预览 |
| `--off` | 关闭（`assign`、`profile`） |
| `--clear` | 清除规则，恢复原样（`assign`、`profile`） |
| `--force` | 不会生效的规则也照样保存（`assign`、`profile`），见下文“不会生效的规则不保存” |
| `--all` | 让 `skills` 也列出没有任何 Agent 加载的技能 |
| `--lang en\|zh-Hans` | 输出语言。也可以设环境变量 `KITFOLD_LANG`；都不设就跟随系统语言 |
| `--no-color` | 不输出颜色。输出不是终端时（管道、重定向）本来就不带颜色 |

选项写在命令前后都可以。拼错的选项会直接报错，不会被猜成别的意思。

## 查看

这几个命令只读，不会改任何东西。

### status：总体情况

```console
$ kitfold status
Kitfold  ~/.kitfold  ·  库：10 个技能、3 个 Profile

Claude Code  已安装 2.1.318
  9 个技能生效  ·  始终加载约 274 token  ·  配置 ~/.claude
Codex        已安装 0.164.0
  14 个技能生效  ·  始终加载约 298 token  ·  配置 ~/.codex
OpenCode     已安装 1.19.4
  12 个技能生效  ·  始终加载约 267 token  ·  配置 ~/.config/opencode
Gemini CLI   已安装 0.66.0
  11 个技能生效  ·  始终加载约 232 token  ·  配置 ~/.gemini
另有 72 个 Kitfold 认识的 Agent 不在这台 Mac 上（--all 会列出）。

问题（1 个警告或错误，1 条提示）
  ✗ 技能链接“old-linter”已失效
    ~/.claude/skills/old-linter → ~/.agents/skills/old-linter，目标已不存在。Claude Code、OpenCode 会静默跳过它。
```

不带命令直接运行 `kitfold`，效果也一样。它列出这台 Mac 上的 Agent，加 `--all` 会列出 Kitfold 认识的所有 Agent。每个 Agent 一行状态（已安装；只有配置：目录在、命令不在；只有目录：只剩卸载后留下的目录，在你打开开关之前 Kitfold 不管理它）和版本，下面是它在全局实际生效的技能数、每次会话都会占用的上下文（技能名称和描述，加上已加载的指令文件，按每个 token 4 字节估算），以及配置目录。

最后是问题清单：`✗` 是错误，`!` 是警告。提示只计数、不列出，想看就到 App 的“概览”页打开“显示提示”。每种问题的含义见 [09 常见问题与排错](09-troubleshooting.md)。

### skills：技能 × Agent 矩阵

```console
$ kitfold skills
CC Claude Code、CX Codex、OC OpenCode、GM Gemini CLI
                  CC  CX  OC  GM  
api-docs          ·   ◆   ◆   ◆   
code-review       ●   ●   ◇   ●   
commit-message    ○   ◆   ◇   ◆   
deep-research     ○   ◆   ◇   ◆   
frontend-design   ○   ◆   ◇   ◆   
github-pr         P   ·   ·   ·   
i18n-sync         ·   ×   ◆   ◆   
k8s-debug         ·   ●   ·   ·   
notebook-tools    ·   ■   ·   ·   
pdf-tools         ○   ◆   ◇   ◆   
playwright-e2e    ·   ◆   ◆   ◆   
release-notes     ●   ●   ◇   ·   
security-audit    ○   ◆   ◇   ◆   
skill-creator     ·   P   ·   ·   
spreadsheet-ops   ○   ◆   ◇   ◆   
sql-explainer     ·   ◆   ◆   ◆   

● Kitfold 链接  ○ 其他链接  ■ 本地目录  ◆ 共享目录  ◇ 经由其他 Agent 的目录  n 嵌套在其他技能中  P 插件  × 已在 Agent 自己的设置中关闭
```

列是 Claude Code（CC）、Codex（CX）、OpenCode（OC）、Gemini CLI（GM），每一格说明这个 Agent 有没有加载这个技能、从哪条路加载：

| 符号 | 含义 |
|---|---|
| ● | Kitfold 建的链接，在 Agent 自己的技能目录里 |
| ○ | 别的工具或手动建的链接 |
| ■ | Agent 技能目录里的真实目录 |
| ◆ | 来自共享目录，比如 `~/.agents/skills` |
| ◇ | 经由别的 Agent 的目录，比如 OpenCode 读取 `~/.claude/skills` |
| n | 嵌套在另一个技能里 |
| P | 插件 |
| × | 技能在，但被 Agent 自己的设置关闭了 |
| · | 没有加载 |

比如 `code-review` 这一行：Kitfold 给 Claude Code、Codex、Gemini CLI 各建了一个链接，OpenCode 没有自己的链接，却通过 Claude Code 的目录也加载了它。`i18n-sync` 在 Codex 那一格是 `×`，因为 `~/.codex/config.toml` 把它关掉了。

默认只列出至少有一个 Agent 加载的技能，加 `--all` 会列出全部。加 `--project '~/work/acme-web'` 看某个项目里的情况。

### agents：每个 Agent 去哪找

```console
$ kitfold agents
Claude Code  由 Kitfold 管理
  技能目录（按优先级）：
    内置       /Library/Application Support/ClaudeCode/.claude/skills (0)
    自己的     ~/.claude/skills (9)
    内置       ~/.claude/skills/synced (0)
  指令文件：
    /Library/Application Support/ClaudeCode/CLAUDE.md 不存在
    ~/.claude/CLAUDE.md 已加载
    ~/.claude/rules/kitfold.md 已加载 [kitfold: code-reviewer]

…

OpenCode  由 Kitfold 管理
  技能目录（按优先级）：
    自己的     ~/.config/opencode/skills (0)
    别的 Agent ~/.claude/skills (9)
    共享       ~/.agents/skills (10)
  指令文件：
    ~/.config/opencode/AGENTS.md 不存在
    ~/.claude/CLAUDE.md 已加载
```

技能目录按优先级排列，括号里是在这个目录找到的技能数。目录前面的词说明它对这个 Agent 是什么角色：

| 角色 | 含义 |
|---|---|
| 自己的 | Agent 自己的技能目录，Kitfold 的链接放在这里 |
| 共享 | 几个 Agent 共用的目录，比如 `~/.agents/skills` |
| 别的 Agent | 别的 Agent 的目录，比如 OpenCode 读取的 `~/.claude/skills` |
| 内置 | 内置、插件或系统技能的目录 |

指令文件按加载顺序列出，标明“已加载”“存在，未加载”或“不存在”；`[kitfold: code-reviewer]` 表示文件里有 Kitfold 写入的 Profile 块。

加 `--project '~/work/payments-api'` 会列出这个项目里的目录和文件。`skills` 和 `agents` 的 `--project` 可以指向任何目录，不必是已经添加过的项目。

### profiles：Profile 的 id 和名称

```console
$ kitfold profiles
backend-engineer  Backend Engineer  Go services, infra and on-call
code-reviewer     Code Reviewer  Strict, evidence-based reviews
researcher        Researcher  Sourced answers, clear charts
```

每行依次是 id、名称和描述。`profile` 命令要用的是 id。

### plan：磁盘和 kitfold.json 一致吗

```console
$ kitfold plan
无需更改。
```

`plan` 把 `~/.kitfold/kitfold.json` 里记录的分配和磁盘上的实际情况对比，列出让两者一致所需的变更。一切正常时，输出就是一句“无需更改。”什么时候会不一致，见下文“apply”一节。

## 分配技能：assign

```
kitfold assign <技能> <Agent> [--off | --clear] [--project <路径>] [--force] [--yes]
```

Agent 用它的 ID：`claude-code`、`codex`、`opencode`、`gemini-cli`；`'*'` 或 `all` 表示所有 Agent（`*` 要加引号，免得被 shell 展开）。

### 先预览

不加 `--yes` 时，`assign` 只打印预览，什么也不改：

```console
$ kitfold assign test-writer codex
  + 链接 ~/.codex/skills/test-writer → ~/.kitfold/library/skills/test-writer
    为 Codex 链接 test-writer（已分配）
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

要应用 1 处文件变更吗？加上 --yes 重新运行即可应用。
```

每处变更前面的标记：

| 标记 | 含义 |
|---|---|
| `+ 链接` / `- 链接` | 创建 / 移除一个链接 |
| `+ 文件` / `- 文件` | 创建 / 删除一个文件（删除只针对 Kitfold 自己创建的文件） |
| `~ 修改` | 修改一个文件，下面跟着改动的内容 |
| `→ 移动` | 移动一个目录（移入库或删除技能时） |
| `（注意）` | 这处变更会动到不是 Kitfold 创建的东西 |

预览覆盖的是让磁盘和 `kitfold.json` 一致所需的**全部**变更。如果之前有别的地方走了样（比如手动删了一个 Kitfold 建的链接），也会在这次一起修好。

### 应用

确认没问题，加上 `--yes` 再运行一次：

```console
$ kitfold assign test-writer codex --yes
  + 链接 ~/.codex/skills/test-writer → ~/.kitfold/library/skills/test-writer
    为 Codex 链接 test-writer（已分配）
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

已应用。撤销请运行：kitfold undo 20261105-114618-68ee3c
```

### 关闭：--off

```console
$ kitfold assign deep-research opencode --off
  ~ 修改 ~/.config/opencode/opencode.json
    对 OpenCode 隐藏 deep-research
    + permission.skill › "deep-research": "deny"
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

要应用 1 处文件变更吗？加上 --yes 重新运行即可应用。
```

OpenCode 是通过 `~/.claude/skills` 和共享目录 `~/.agents/skills` 看到 `deep-research` 的，这两个目录别的 Agent 也在读，删掉链接或目录会连累它们。所以 Kitfold 改的是 OpenCode 自己的设置，而且只改这一条。设置文件只显示变化的条目，不显示原文（里面可能有 API key）。原因详见 [03 把技能分给指定的 Agent](03-assign-skills.md)。

### 恢复原样：--clear

`--off` 是一条“关闭”规则；`--clear` 是把规则删掉，让 Kitfold 不再管这个技能对这个 Agent 的状态。Kitfold 会收回它自己做过的东西（它建的链接、它写的设置项），别的保持原样：

```console
$ kitfold assign test-writer codex --clear
  - 链接 ~/.codex/skills/test-writer
    为 Codex 移除 test-writer 的链接（已不再分配）
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

要应用 1 处文件变更吗？加上 --yes 重新运行即可应用。
```

对一个本来就没有规则的技能用 `--clear`，结果就是“无需更改。”。

### 只在一个项目里：--project

```console
$ kitfold assign perf-profiler gemini-cli --project '~/work/acme-web'
  + 链接 ~/work/acme-web/.gemini/skills/perf-profiler → ~/.kitfold/library/skills/perf-profiler
    为 Gemini CLI 链接 perf-profiler（已分配）
  ~ 修改 ~/work/acme-web/.git/info/exclude
    让 git 忽略 acme-web 中 Kitfold 的文件 — .git/info/exclude 只对本地这个克隆生效，不会被提交。
      /.claude/skills/design-tokens
    + /.gemini/skills/perf-profiler
      /.opencode/skills/figma-handoff
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

要应用 2 处文件变更吗？加上 --yes 重新运行即可应用。
```

链接放在项目自己的 `.gemini/skills` 里，只在这个项目中生效；Kitfold 还会把它写进 `.git/info/exclude`，免得被提交。如果这个目录还不是 Kitfold 的项目，应用时会顺便添加。项目的更多细节见 [06 按项目配置](06-projects.md)。

### 不会生效的规则不保存

`assign` 和 `profile` 不保存注定不起作用的规则：技能或 Profile 不存在，或者有东西挡着、这条规则不会带来任何变化时，命令什么都不保存，返回 1，并说明原因。比如 Codex 没法只在一个项目里隐藏全局技能：

```console
$ kitfold assign code-review codex --off --project '~/work/acme-web'
  ! 在这个项目中，Codex 仍能看到“code-review”
    它在全局启用，而 Codex 只从 $CODEX_HOME/config.toml 读取 `[[skills.config]]`，所以无法只在一个项目里隐藏技能。请改为在全局关闭它。
错误：没有保存：这条规则不会带来任何变化。加 --force 仍会保存。
```

名字写错时也一样：

```console
$ kitfold assign no-such-skill codex
错误：没有名为 no-such-skill 的技能。kitfold skills --all 会列出所有技能；加 --force 仍会保存这条规则。
$ kitfold profile reviewer codex
错误：没有 id 为 reviewer 的 Profile（现有：backend-engineer、code-reviewer、researcher）。加 --force 仍会保存这条规则。
```

确实想留下这条规则（比如技能稍后才会放进库里），加 `--force`。`--clear` 不受这个限制。

## 分配 Profile：profile

```
kitfold profile <Profile ID> <Agent> [--off | --clear] [--project <路径>] [--force] [--yes]
```

Profile ID 是它在 `~/.kitfold/library/profiles/` 里的文件名，不是显示名称：演示数据里是 `code-reviewer`、`backend-engineer`、`researcher`。`kitfold profiles` 会列出来。

```console
$ kitfold profile researcher gemini-cli
  ~ 修改 ~/.gemini/GEMINI.md
    更新 ~/.gemini/GEMINI.md 中的 Researcher — 由 Gemini CLI 读取
    + <!-- kitfold:begin profile=researcher hash=0abfe27fba6b -->
    + ## Researcher
    + 
    + - Use primary sources and link every claim.
    + - Say what is unknown instead of guessing.
    + <!-- kitfold:end profile=researcher -->
    + 
      # Gemini
  + 链接 ~/.gemini/skills/data-viz → ~/.kitfold/library/skills/data-viz
    为 Gemini CLI 链接 data-viz（通过 Profile“Researcher”）
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

要应用 2 处文件变更吗？加上 --yes 重新运行即可应用。
```

Profile 以一个带标记的块写进 Agent 自己的指令文件，文件原有的内容不动。它附带的技能也会一起分配：`data-viz` 要建链接；`deep-research` 已经能通过 `~/.agents/skills` 看到，就不用再建。

预览里有 Kitfold 自己不会自动处理的事情时，会列在“需要注意”下面。比如把 Code Reviewer 分给 acme-web 里的所有 Agent：

```console
$ kitfold profile code-reviewer '*' --project '~/work/acme-web'
  + 文件 ~/work/acme-web/.claude/rules/kitfold.md
    创建 ~/work/acme-web/.claude/rules/kitfold.md，写入 Code Reviewer — 由 Claude Code 读取
  …
  + 文件 ~/work/acme-web/AGENTS.md
    创建 ~/work/acme-web/AGENTS.md，写入 Code Reviewer — 由 Codex、OpenCode 读取
  + 文件 ~/work/acme-web/GEMINI.md
    创建 ~/work/acme-web/GEMINI.md，写入 Code Reviewer — 由 Gemini CLI 读取
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

需要注意
  ! OpenCode 将不再读取 CLAUDE.md
    因为 ~/work/acme-web/AGENTS.md 不存在，OpenCode 目前会回退到 ~/work/acme-web/CLAUDE.md。创建它之后就不会了。

要应用 4 处文件变更吗？加上 --yes 重新运行即可应用。
```

“需要注意”里的事情不会自动改，要你自己判断。各种提示的意思见 [09 常见问题与排错](09-troubleshooting.md)。

## 删除技能：delete

```
kitfold delete <技能> [--yes]
```

`delete` 让所有 Agent 都不再用到这个技能，并把它的目录移到 Kitfold 的废纸篓 `~/.kitfold/backups/trash/`。和 `assign` 一样，不加 `--yes` 只预览：

```console
$ kitfold delete release-notes
  - 链接 ~/.claude/skills/release-notes
    为 Claude Code 移除 release-notes 的链接（已不再分配）
  - 链接 ~/.codex/skills/release-notes
    为 Codex 移除 release-notes 的链接（已不再分配）
  → 移动 ~/.kitfold/library/skills/release-notes → ~/.kitfold/backups/trash/release-notes-20261105-154817-42b6ea
    把 release-notes 移到 Kitfold 的废纸篓 — 目录会保留在 ~/.kitfold/backups/trash，撤销会把它放回原处。
  ~ 修改 ~/.kitfold/kitfold.json
    把分配保存到 kitfold.json

需要注意
  ! OpenCode 将不再加载“release-notes”
    OpenCode 只在 Claude Code 的目录 ~/.claude/skills 中找到它。为 OpenCode 打开“release-notes”，它就能继续加载。

要应用 3 处文件变更吗？加上 --yes 重新运行即可应用。
```

技能的分配会被清除，所以 Kitfold 会收回为它做过的事，相当于对每个 Agent 都用了 `--clear`：它的链接，以及它在 Agent 自己设置里的条目。指向这个目录的其他链接也会移除，免得留下失效的链接；不是 Kitfold 创建的会标上“（注意）”。附带它的 Profile 会把它去掉。加上 `--yes` 才会应用，`kitfold undo` 可以把这些全部恢复。

如果目录还有别的 Agent 在读，或者由别的工具管理，预览会说明：

```console
$ kitfold delete pdf-tools
  - 链接 ~/.claude/skills/pdf-tools（注意）
    移除 ~/.claude/skills/pdf-tools 处的链接 — 这个链接不是 Kitfold 创建的（来自其他工具或手动创建）。撤销可以恢复它。
  → 移动 ~/.agents/skills/pdf-tools → ~/.kitfold/backups/trash/pdf-tools-20261105-154817-5cae69（注意）
    把 pdf-tools 移到 Kitfold 的废纸篓 — 目录会保留在 ~/.kitfold/backups/trash，撤销会把它放回原处。

需要注意
  ! Codex、OpenCode、Gemini CLI 会读取这个目录
    目录被删除后，它们就会失去“pdf-tools”。
  ! skills CLI 管理着 ~/.agents/skills
    在这里删除目录不会通知 skills CLI，它下次更新时可能会把这个技能带回来。

要应用 2 处文件变更吗？加上 --yes 重新运行即可应用。
```

有多个同名目录时，删除的是库里那份，预览会说明另一个会保留。只是从库和来源之外的目录链接进来的技能，只会收回链接，目录留在原处。skills CLI 装的技能还会从 `~/.agents/.skill-lock.json` 里去掉，免得 `npx skills update` 又把它装回来。插件技能和嵌套技能不能删除：

```console
$ kitfold delete github-pr
错误：无法完成：插件技能无法删除，请在 Agent 里关闭这个插件
```


## 失效链接：clean

```
kitfold clean [--yes]
```

`clean` 移除这台 Mac 上各 Agent 目录里失效的技能链接，不管 Kitfold 是否管理那个 Agent：这些是在 Kitfold 之外删除技能目录后留下的。正常的链接不动。和其他命令一样先预览，`kitfold undo` 可以把链接恢复。

```console
$ kitfold clean
  - 链接 ~/.claude/skills/old-linter（注意）
    移除 ~/.claude/skills/old-linter 处失效的链接 — 它指向的 ~/.agents/skills/old-linter 已经不存在。

要应用 1 处文件变更吗？加上 --yes 重新运行即可应用。
```

## 历史记录和撤销

### history

```console
$ kitfold history
20261105-114618-bc32d5  从 OpenCode 收回 deep-research  2 项操作
20261105-114618-68ee3c  把 test-writer 分配给 Codex  2 项操作
20261105-114614-d57bc3  在 acme-web 中把 figma-handoff 分配给 OpenCode  3 项操作
…
```

每次应用或撤销都是一条，最新的在最上面。开头是它的 ID，后面是摘要和操作数。摘要用写入时的语言保存，之后切换语言也不会变。加 `--project <路径>` 只列出改动过这个项目里文件的应用。

### undo

不带 ID 的 `undo` 撤销最近一次仍然有效的应用。和其他命令一样，先预览：

```console
$ kitfold undo
撤销“从 OpenCode 收回 deep-research”（2 项操作）
  把分配保存到 kitfold.json
  对 OpenCode 隐藏 deep-research

加上 --yes 重新运行即可撤销。
$ kitfold undo --yes
撤销“从 OpenCode 收回 deep-research”（2 项操作）
  把分配保存到 kitfold.json
  对 OpenCode 隐藏 deep-research
已撤销。
```

撤销会连同那次的分配规则一起退回，`opencode.json` 里那一条也被收回。撤销本身也会记成一条历史：

```console
$ kitfold history
20261105-114618-732a17  撤销“从 OpenCode 收回 deep-research”  2 项操作
20261105-114618-bc32d5  从 OpenCode 收回 deep-research（已撤销）  2 项操作
20261105-114618-68ee3c  把 test-writer 分配给 Codex  2 项操作
…
```

再运行一次 `kitfold undo --yes`，会接着撤销更早的那一次（这里是“把 test-writer 分配给 Codex”），而不是把刚才的撤销又重做一遍。想撤销某一次，就把 ID 写上：`kitfold undo 20261105-114618-68ee3c --yes`。

撤销前，Kitfold 会检查涉及的每个文件。如果有文件在那次应用之后又被改过，就什么都不撤销，并告诉你是哪个文件：

```console
$ kitfold undo --yes
撤销“从 OpenCode 收回 deep-research”（2 项操作）
  把分配保存到 kitfold.json
  对 OpenCode 隐藏 deep-research
错误：前置检查未通过：这些文件在那次应用之后又被修改过，撤销会覆盖较新的修改：~/.config/opencode/opencode.json
```

这时可以改用一次新的变更，比如 `kitfold assign deep-research opencode --clear --yes`：它只收回 Kitfold 写的那一条，你后来做的修改保留不动。

## apply：让磁盘回到 kitfold.json 记录的样子

`assign` 和 `profile` 已经包含了应用，平时用不到 `apply`。它用在磁盘被 Kitfold 之外的东西改过的时候，比如有人手动删掉了 Kitfold 给 Gemini CLI 建的 `code-review` 链接：

```console
$ kitfold plan
  + 链接 ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    为 Gemini CLI 链接 code-review（已分配）
$ kitfold apply
  + 链接 ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    为 Gemini CLI 链接 code-review（已分配）

要应用 1 处文件变更吗？加上 --yes 重新运行即可应用。
$ kitfold apply --yes
  + 链接 ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    为 Gemini CLI 链接 code-review（已分配）

已应用。撤销请运行：kitfold undo 20261105-114630-1dc731
```

这次应用在历史记录里叫“应用 kitfold.json”。

## 更新：version、update

```
kitfold version
kitfold update [--yes]
```

`version` 显示这个命令所在的 Kitfold.app 的版本。`update` 向 GitHub 查询最新版本，加上 `--yes` 就安装它、替换那个 App，检查和 App 里的“安装并重新打开”一样：核对发布页上的 SHA-256、同一个 Developer ID 团队的签名、Apple 公证。如果 App 开着，更新后请退出再重新打开。

```console
$ kitfold version
Kitfold 0.5.0
$ kitfold update
Kitfold 0.5.1 可以更新了（你现在用的是 0.5.0）
  https://github.com/kadaliao/kitfold/releases/tag/v0.5.1

加上 --yes 重新运行，就会安装它并替换 /Applications/Kitfold.app。
$ kitfold update --yes
Kitfold 0.5.1 可以更新了（你现在用的是 0.5.0）
  https://github.com/kadaliao/kitfold/releases/tag/v0.5.1
  正在下载 Kitfold 0.5.1…
  正在检查新版本…
  正在安装…
已把 Kitfold 0.5.1 安装到 /Applications/Kitfold.app。如果 App 开着，请退出后重新打开。
```

从源码构建的 `kitfold` 不属于已安装的 App，这时 `update` 只告诉你最新版本和下载地址。

## 在脚本里使用

- **先预览，后 `--yes`。** 不加 `--yes` 的命令从不写入，可以放心在脚本里先跑一遍看结果。
- **退出码。** 成功和预览都返回 0。用法错误、未知的命令或 Agent、不存在的技能或 Profile、不会生效的规则（没加 `--force` 时）、应用或撤销失败时返回 1，错误信息写到标准错误，以“错误：”开头：

  ```console
  $ kitfold assign test-writer claude
  错误：未知的 Agent claude（可选：claude-code、codex、opencode、gemini-cli、*）
  ```

  `status` 和 `plan` 即使列出了问题，也返回 0。
- **要解析输出，就固定语言。** 加 `--lang en`，输出文字就不会随系统语言变化；再加 `--no-color`（输出到管道时本来就没有颜色）。
- **每个 `--yes` 都是单独一条历史记录**，可以用 `kitfold undo --yes` 一条条往回退。

比如一个配置新环境的脚本：

```bash
#!/bin/sh
set -e
kitfold assign code-review '*' --yes
kitfold assign test-writer codex --yes
kitfold profile code-reviewer claude-code --yes
kitfold profile backend-engineer codex --project ~/work/payments-api --yes
```

忘了用法就运行 `kitfold help`（或者 `kitfold --help`、`kitfold -h`）：

```console
$ kitfold help
kitfold status [--all] | plan | apply [--yes] | profiles
kitfold skills [--all] [--project <path>] | agents [--all] [--project <path>]
kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
kitfold delete <skill> [--yes] | clean [--yes]
kitfold version | update [--yes]
kitfold history [--project <path>] | undo [<tx-id>] [--yes]
选项：--home <dir>（沙盒 $HOME）、--no-color、--lang en|zh-Hans
```

---

[← 上一篇：07 管理技能库](07-skill-library.md) · [目录](README.md) · [下一篇：09 常见问题与排错 →](09-troubleshooting.md)
