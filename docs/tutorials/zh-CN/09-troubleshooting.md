# 09 常见问题与排错

Kitfold 发现的每个问题，都带一个标题和一段说明。这篇按标题来查：标题照抄 App 里显示的样子（例子用的是演示数据里的名字），下面是说明原文、它是什么意思、该怎么办。最后是几个常被问到的问题。

## 问题会出现在哪

- **“概览”页的“健康检查”**：列出错误和警告。打开卡片右上角的“显示提示”，还能看到提示。
- **Agent 页面最下面的“问题”**：只列和这个 Agent 有关的问题。侧栏里 Agent 名字旁边有橙色三角时，就说明它有错误或警告。
- **项目页面的“这个项目的问题”**：只列这个项目里的问题。
- **预览里的“这次不会写入”和“需要注意：不会自动更改”**：打开开关、准备应用时才会出现的问题。待应用栏和预览标题上的“N 项待检查”是其中错误和警告的数量，提示不算在内。
- **技能详情里的“问题”卡片**：技能自己的 `SKILL.md` 有毛病，见 [07 管理技能库](07-skill-library.md)。
- **命令行**：`kitfold status` 列出错误和警告，`assign`、`profile`、`plan` 的输出里有“这次不会写入”和“需要注意”。

问题分三级：错误（App 里是红色图标，命令行是 `✗`）、警告（橙色三角，`!`）、提示（灰色 ⓘ，`·`）。

## 健康检查里的问题

这些是扫描时发现的，反映磁盘上现在的情况。

### 技能链接“old-linter”已失效

> ~/.claude/skills/old-linter → ~/.agents/skills/old-linter，目标已不存在。Claude Code、OpenCode 会静默跳过它。

同一个目录里有 3 个以上失效的链接时，会合成一条，比如“~/.claude/skills 中有 3 个失效的技能链接”。几个 Agent 目录里指向同一个技能的失效链接也会合成一条，比如“3 个失效的链接指向“old-linter””。

**意思：** 技能目录里的链接指向的目录已经不在了。Agent 不会报错，只是悄悄跳过它。

**怎么办：** 通常是有人在 Kitfold 之外删了技能的目录，skills CLI（或你自己）在各 Agent 目录里建的链接就留了下来。点问题下面的“移除这条链接…”（或“移除这些链接…”），看过预览后应用。Kitfold 只移除失效的链接，不管是谁建的，撤销可以恢复。“概览”页“健康检查”顶部的“移除全部 N 个失效的链接…”会一次处理所有的；命令行里是 `kitfold clean`。

如果链接是 Kitfold 建的（目标在 `~/.kitfold/library/skills` 里），说明库里的技能被删了或改了名：找回技能，或者清除这条分配，免得 Kitfold 再建一次。技能已经不在了，App 的“技能”页面里也就找不到它，这时用命令行清除，比如 `kitfold assign k8s-debug codex --clear --yes`。

想删技能又不留下链接，就在 Kitfold 里删（见 [07 技能库](07-skill-library.md#删除技能)）。

### “notes”没有 SKILL.md

> ~/.gemini/skills/notes 在技能目录里，但不是技能。

**意思：** 技能目录里有一个链接，它指向的目录里没有 `SKILL.md`。（技能目录里没有 `SKILL.md` 的普通目录不算技能，也不会报。）

**怎么办：** 它不是技能，就把链接移走；它本该是技能，就补上 `SKILL.md`。

### Codex 看到 2 个名为“code-review”的不同技能

> ~/.codex/skills/code-review 优先。另外还找到：~/.agents/skills/code-review

**意思：** 同一个 Agent 在不同目录里找到了两个同名、但不是同一个目录的技能。排在前面的是它优先用的；有的 Agent 会两个都列出来（Codex），有的用哪个说不准（OpenCode）。

**怎么办：** 决定留哪一个，另一个改名（目录名和 `name` 一起改）或者移走。在“技能”页面选中这个技能，“问题”卡片会列出所有同名的目录；“各 Agent 从哪加载它”里标着“另一个目录”的，就是 Agent 实际读到的那一份。分配时，Kitfold 优先用库里的那份。

### OpenCode 通过两个目录重复找到 6 个技能

> 通过 ~/.agents/skills、~/.claude/skills 找到的是同一批技能目录。有些 Agent 会把它们列出两次，或者提示冲突。

这是一条提示。

**意思：** 同一个技能目录被同一个 Agent 从两条路找到了。演示数据里，skills CLI 在 `~/.claude/skills` 里建了指向 `~/.agents/skills` 的链接，而 OpenCode 这两个目录都读。

**怎么办：** 两边是同一份内容，一般不用管。只有 Agent 真的列出两次或者报冲突时，才去掉其中一条路。别为了 OpenCode 去删 `~/.claude/skills` 里的这些链接：Claude Code 不读 `~/.agents/skills`，它靠的就是这些链接。

### Codex 会忽略“quick-notes”

> Codex 会跳过 SKILL.md 中没有描述的技能。请在 ~/.agents/skills/quick-notes/SKILL.md 中补上。

**意思：** `SKILL.md` 的 frontmatter 缺了这个 Agent 要求的字段，Agent 会静默跳过它。OpenCode 要 `name`，Codex 要 `description`，Gemini CLI 两个都要。

**怎么办：** 在提示的文件里补上缺的字段。写法见 [07 管理技能库](07-skill-library.md)。

### “pdf-suite”里有 1 个嵌套的 SKILL.md

> Codex 和 OpenCode 会把每个嵌套的 SKILL.md 当作单独的技能加载：~/.kitfold/library/skills/pdf-suite/forms/SKILL.md

**意思：** 技能目录的子目录里还有 `SKILL.md`。Codex 和 OpenCode 会把它当成另一个独立的技能加载，哪怕你只想要外面那个。

**怎么办：** 里面那个如果只是示例或模板，就改个文件名或者移出去；如果它确实是个独立的技能，就把它挪成单独的技能目录。只是不想让某个 Agent 加载它，可以在“技能”页面为那个 Agent 关闭它，Kitfold 会写那个 Agent 自己的设置。

### Profile“Code Reviewer”在 Kitfold 之外被修改过

> ~/.claude/rules/kitfold.md：在你保留或放弃这处修改之前，Kitfold 不会覆盖它。

预览里，这个文件单独列在“这次不会写入”下：

> **这次不会写入 ~/.claude/rules/kitfold.md**
>
> 其中“Code Reviewer”的 Profile 块在 Kitfold 之外被修改过。请在 Agent 页面保留修改（写回 Profile）或覆盖它，然后再应用一次。

**意思：** Kitfold 写进指令文件的 Profile 块被人直接改过了。在你做决定之前，Kitfold 不再写这个文件，其他变更照常应用。

**怎么办：** 打开对应 Agent 的页面，在“指令文件”里找到这个文件，二选一：

- “保留修改”：打开预览，应用后把改动写回 Profile 并重写这个块；撤销这次应用，Profile 也会恢复；
- “覆盖…”：预览后，用 Profile 里的内容覆盖这处修改。

详见 [05 用 Profile 管理指令](05-profiles.md)。

### Magpie 管理着 GEMINI.md 的一部分

> ~/.gemini/GEMINI.md 中有一个由 magpie 写入的块，Kitfold 不会动它。

这是一条提示。

**意思：** 文件里有别的工具写的托管块（形如 `<!-- magpie:begin … -->`）。

**怎么办：** 不用处理。Kitfold 只改自己的块。

### Codex 的指令超过 32 KiB

> 已加载 34071 字节；Codex 会截掉 32768 字节之后的全部内容。

**意思：** Codex 只读指令文件的前 32 KiB，超出的部分模型根本看不到。

**怎么办：** 打开 Codex 的页面，“指令文件”里列着哪些文件被加载、各有多大。精简这些文件，或者把不是每次都需要的内容挪进技能：技能平时只占名称和描述，正文要用时才加载。

### 技能自己的问题

比如“quick-notes：缺少描述：Agent 靠它判断何时加载这个技能”。这些是库和来源里的技能 `SKILL.md` 写得不规范，属于提示。逐条说明见 [07 管理技能库](07-skill-library.md) 的“技能页上的问题”。

## 预览里“需要注意”的问题

这些是你打开或关闭开关之后、在预览里出现的问题。它们列在“需要注意：不会自动更改”下面：Kitfold 不替你处理，但其余的变更照常可以应用。

### “i18n-sync”在 Codex 的设置中被关闭了

> ~/.codex/config.toml 对所有项目关闭了它，而 Codex 无法只在一个项目里重新打开它。请改为在全局打开它。

**意思：** 你想让 Agent 加载这个技能，但 Agent 自己的设置把它关掉了，而 Kitfold 没法替你打开。

能打开的时候 Kitfold 会直接打开：比如在全局为 Codex 打开 `i18n-sync`，预览里会有一条标着“注意”的变更“让 Codex 重新加载 i18n-sync”，说明是“会改动一个不是 Kitfold 写入的设置项。撤销可以恢复它。”只有做不到时，才会出现这条问题。

**怎么办：** 看说明里是哪种情况：

- “… 对所有项目关闭了它，而 … 无法只在一个项目里重新打开它”：Codex 和 Gemini CLI 不能在单个项目里重新打开全局关掉的技能。改为在全局打开它。
- “… 关闭了所有技能（`…`）”：那项设置把所有技能都关了。改了它才能加载技能。
- “… 关闭了它。移除这个设置项，… 才能加载它。”：自己去删掉那条设置。

### 在这个项目中，Codex 仍能看到“deep-research”

> 它在全局启用，而 Codex 只从 $CODEX_HOME/config.toml 读取 `[[skills.config]]`，所以无法只在一个项目里隐藏技能。请改为在全局关闭它。

**意思：** 你在一个项目里关闭了一个全局启用的技能，但 Codex 没有项目级的开关。矩阵里这一格会带一个橙色的“!”；命令行的 `assign` 遇到只对 Codex 的这种规则，会拒绝保存（加 `--force` 仍会保存）。Claude Code、OpenCode 和 Gemini CLI 都能在单个项目里隐藏全局技能，见 [06 按项目配置](06-projects.md)。

**怎么办：** 接受它在这个项目里仍然可见，或者在全局为 Codex 关闭它。

### OpenCode 也会加载“test-writer”

> OpenCode 也会读取 Claude Code 的目录 ~/.claude/skills。要让它只给 Claude Code 用，请为 OpenCode 关闭“test-writer”。

反过来的情况是 **OpenCode 将不再加载“release-notes”**：

> OpenCode 只在 Claude Code 的目录 ~/.claude/skills 中找到它。为 OpenCode 打开“release-notes”，它就能继续加载。

在项目里，标题会写明是哪个项目，比如“在 acme-web 中，OpenCode 也会加载“test-writer””。

**意思：** Kitfold 把技能链接进 Claude Code 的目录，而 OpenCode 也读这个目录，所以 OpenCode 也会拿到它。反过来，移除这个链接时，原本只经由这里看到它的 OpenCode 也会失去它。

**怎么办：** 按说明做：只给 Claude Code 用，就同时为 OpenCode 关闭它（Kitfold 会写 OpenCode 的设置）；想让 OpenCode 继续用，就为 OpenCode 打开它。OpenCode 对这个技能有了自己的规则，这条提醒就会消失。不处理也可以，结果就是说明里讲的那样。

### OpenCode 也会读取 AGENTS.md

> ~/work/payments-api/AGENTS.md 是共享的，所以 OpenCode 也会看到 Backend Engineer、Researcher。同一个文件里无法按 Agent 隔离。

**意思：** Profile 要写进的指令文件，别的 Agent 也在读。比如项目里的 `AGENTS.md`，Codex 和 OpenCode 都读，没有 `CLAUDE.md` 时 Claude Code 也读。同一个文件里的内容，没法只给其中一个 Agent 看。

**怎么办：** 没有要修的，这是提醒。如果某段内容不能让别的 Agent 看到，就别放进会写到共享文件的 Profile 里。

### OpenCode 将不再读取 CLAUDE.md

> 因为 ~/work/acme-web/AGENTS.md 不存在，OpenCode 目前会回退到 ~/work/acme-web/CLAUDE.md。创建它之后就不会了。

**意思：** 有些 Agent 在自己的主文件不存在时，会回退去读别的文件。Kitfold 要创建这个主文件，回退就不会再发生。

**怎么办：** 如果 `CLAUDE.md` 里有 OpenCode 也需要的内容，把它放进一个 Profile，也分配给 OpenCode。

### AGENTS.override.md 存在时，Codex 不会读取 AGENTS.md

> ~/.codex/AGENTS.override.md 会替代 ~/.codex/AGENTS.md，所以这个 Profile 对 Codex 不起作用。请清空或移除这个覆盖文件，或者把其中的内容移到 Profile 里。

**意思：** 同一个目录里有非空的 `AGENTS.override.md` 时，Codex 会用它替代 `AGENTS.md`。Kitfold 把 Profile 写进 `AGENTS.md`，Codex 却不会读。

**怎么办：** 照说明做：清空或删除覆盖文件，或者把里面的内容挪进一个 Profile。

### “github-pr”来自插件

> 插件技能由 Agent 自己的插件系统管理。

关闭时说明会变成“请改为在 Claude Code 中停用这个插件。”

**意思：** 插件技能由 Agent 的插件系统管理，Kitfold 不能分配，也不能隐藏它们。所以插件技能详情的“谁会用到”里没有格子，只有一句说明。

**怎么办：** 在 Agent 自己的插件设置里启用或停用这个插件。

### Codex 无法加载“quick-notes”

> Codex 会跳过 SKILL.md 中没有描述的技能。请先修正 ~/.agents/skills/quick-notes/SKILL.md。

**意思：** 你想把一个缺少必需 frontmatter 的技能分给 Agent，但 Agent 反正会跳过它，所以 Kitfold 不建这个链接。

**怎么办：** 先补上缺的字段，再重新分配。

### Gemini CLI 已有名为“test-writer”的目录

> ~/.gemini/skills/test-writer 是一个不由 Kitfold 创建的真实目录，所以不会被替换。如果它只是这个技能的副本，删掉它再应用一次；否则请给其中一个改名。

**意思：** 要放链接的位置已经有一个同名的真实目录。Kitfold 从不删除或替换真实目录。

**怎么办：** 先看两者是不是同一个技能。是旧的副本，自己删掉或移走它，再应用一次；是两个不同的技能，就给其中一个改名（目录名和 `name` 一起改）。

### 其他问题

| 标题 | 意思 | 怎么办 |
|---|---|---|
| 技能“…”不在库中 | 分配了这个技能，但哪里都找不到这个名字的目录，可能被删了或改了名。说明里写着它分配给了哪些 Agent、在哪个项目，以及哪些 Profile 附带它，比如“它在 payments-api 中分配给了 Codex，但找不到同名的目录。Profile“Backend Engineer”包含它。” | 找回技能，或者用 `kitfold assign <技能> <Agent> --clear --yes` 清除这条分配；Profile 附带它的话，也从 Profile 里去掉 |
| Profile“…”不存在 | 分配的 Profile 文件不见了 | 移除这个分配，或者恢复 Profile 文件。删除的 Profile 在 `~/.kitfold/backups/trash/` |
| Kitfold 无法读取 … | Agent 的设置文件不是有效的 JSON 或 TOML，Kitfold 不会编辑它 | 修好文件再试 |
| Kitfold 无法向 … 添加技能设置 | `config.toml` 里 `skills.config` 的写法，会被 Kitfold 追加的 `[[skills.config]]` 表破坏 | 那里改用 `[[skills.config]]` 表 |
| … 指向 Kitfold 的库 | 指令文件是一个指向 Kitfold 库的链接，写入它会改到 Kitfold 自己的数据 | 把这个链接换成普通文件 |

## 应用或撤销没有成功

**应用时**出现“前置检查未通过：… 在预览之后被修改了”（或者“… 已存在”“… 已不再是链接”“… 现在指向 …”）：预览之后，有文件被别的东西改了。Kitfold 在写每个文件之前都会再核对一次，发现不对就把这次已经做的全部退回，不会留下改了一半的状态。按 ⌘R 重新扫描，再预览一次。

**撤销时**出现“前置检查未通过：这些文件在那次应用之后又被修改过，撤销会覆盖较新的修改：…”：那次应用之后，你或别的工具又改过这个文件，Kitfold 不会覆盖较新的修改，所以什么都没撤销。改用一次新的变更，比如把那个格子再点回去，或者在命令行用 `--clear` 清除那条规则。新的变更按文件现在的内容计算，只改涉及的条目，不会覆盖后来的修改。

撤销“移入库”时出现“之后创建的链接仍指向 … 内部：…。请先为这些 Agent 关闭那个技能。”：移入库之后，又有 Agent 链接到了库里的这个技能。先为这些 Agent 关闭它、应用，再撤销。

## 常见疑问

### 为什么打开一个开关，改的却是设置文件，而不是链接？

Kitfold 能用链接时就用链接：把技能链接进 Agent 自己的技能目录，或者把它建的链接收回。但有些情况链接办不到：

- 技能在共享目录里（比如 `~/.agents/skills`），删掉它，读这个目录的其他 Agent 也就没了；
- 技能是经由别的 Agent 的目录看到的（OpenCode 读 `~/.claude/skills`），删链接会连累那个 Agent；
- 技能嵌套在另一个技能里；
- 技能在全局启用，你只想在一个项目里关掉它。

这时 Kitfold 改的是 Agent 自己的设置：

| Agent | 设置 | 全局 | 项目 |
|---|---|---|---|
| Claude Code | `skillOverrides` | `~/.claude/settings.json` | `.claude/settings.local.json` |
| Codex | `[[skills.config]]` | `~/.codex/config.toml`（放在文件末尾一个带标记的区域里） | 不支持，Codex 只认全局的 |
| OpenCode | `permission.skill` | `~/.config/opencode/opencode.json` | 项目里的 `opencode.json` 或 `.opencode/opencode.json` |
| Gemini CLI | `skills.disabled` | `~/.gemini/settings.json` | `.gemini/settings.json` |

而且只改涉及的那一条，文件其余部分一个字节都不动。预览里也只显示这几条，不显示整个文件（里面可能有 API key）。Kitfold 记得哪些条目是它写的：规则清除后，它会把这些条目收回；文件是它新建的，空了就删掉。你自己写的条目它不碰，除非你明确要求相反的结果（比如打开一个被你关掉的技能），这时预览会标“注意”，而且可以撤销。

### 为什么 OpenCode 能看到 Claude Code 的技能？

为了兼容 Claude Code，OpenCode 除了自己的目录，还会读 `~/.claude/skills` 和项目里的 `.claude/skills`。所以凡是链接进 Claude Code 目录的技能，OpenCode 也会加载。矩阵里 OpenCode 那一列的“经由其他 Agent”图标，命令行 `kitfold skills` 里的 `◇`，说的就是这种情况。

想让某个技能只给 Claude Code 用，就在“谁会用到”里为 OpenCode 关闭它。Kitfold 会在 `opencode.json` 里写一条 `permission.skill` 把它隐藏，Claude Code 不受影响。分配时，预览里的 **OpenCode 也会加载“…”** 就是在提醒这件事。

设置了环境变量 `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` 或 `OPENCODE_DISABLE_CLAUDE_CODE`（值为 `1`、`true`、`yes`、`on` 或 `y`）时，OpenCode 不读 `~/.claude/skills` 和项目里的 `.claude/skills`。Kitfold 也会照此显示：OpenCode 的页面上没有这两个目录，相关的提醒也不会出现。不过 Kitfold 只看得到它自己进程里的环境变量：命令行拿到的是你 shell 里的；从访达打开的 App 看不到在 shell 配置文件里 export 的变量。

### 怎么在不碰真实配置的情况下试用？

- **用演示数据。** `make demo DIR=/tmp/kf-demo` 生成一套虚构的 Agent、技能、Profile 和项目。命令行加 `--home /tmp/kf-demo`；App 在 `make build` 之后这样启动：

  ```bash
  KITFOLD_FAKE_HOME=/tmp/kf-demo PATH=/tmp/kf-demo/.local/bin:/usr/bin:/bin .build/debug/KitfoldApp
  ```

  两种方式都只读写那个目录。
- **只看看自己机器上的情况。** `KITFOLD_HOME=/tmp/kf-scratch kitfold status` 让 Kitfold 把自己的数据放到别处，不创建 `~/.kitfold`。只要不加 `--yes`，就只是读。
- **在真实环境里也可以放心试。** 第一次打开 Kitfold，除了创建它自己的 `~/.kitfold`，什么都不改；之后的每个开关都只改草稿，预览确认后才写入；每次应用都能在“历史记录”里撤销。

### 备份在哪？

都在 `~/.kitfold` 里：

| 位置 | 内容 |
|---|---|
| `~/.kitfold/backups/<历史记录 ID>/` | 每次应用前（包括保存 `SKILL.md`），被覆盖或删除的文件的副本。在“历史记录”里展开一条，点“备份”就能在访达中看到 |
| `~/.kitfold/state.sqlite` | 历史记录本身，包括 Kitfold 改过的文件改前改后的内容。撤销靠的是它，不依赖上面的备份目录 |
| `~/.kitfold/backups/profiles/` | Profile 的历史版本，“对比”用的就是它们 |
| `~/.kitfold/backups/trash/` | 删除的 Profile 和技能 |

备份保留多久，在“设置 › 通用”里调（默认“备份保留 30 天”），过期的会在之后应用时清理，`trash` 除外。同一页的“历史记录和备份”一行显示的就是这个位置。

### 怎么切换语言？

- **App：** 打开“设置 › 通用 › 语言”，选“跟随 macOS”或者指定一种语言，界面立刻切换。macOS 自己画的菜单和面板，要下次打开 Kitfold 才跟着变。也可以在“系统设置 › 通用 › 语言与地区”的“应用程序”里为 Kitfold 单独设置，两边是同一个设置。
- **命令行：** 加 `--lang zh-Hans` 或 `--lang en`，或者设环境变量 `KITFOLD_LANG`；都不设就跟随系统语言。

已经写进历史记录的摘要不会跟着变，保持写入时的语言。第一次打开时登记的来源，名称没改过的话会跟着界面语言显示，比如“共享目录（~/.agents/skills）”“Magpie 库”。

---

[← 上一篇：08 命令行](08-command-line.md) · [目录](README.md)
