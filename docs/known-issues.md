# 已知问题

写教程时（2026-11-05）逐项试用 App 和 CLI 发现的问题，还没修。按影响从大到小排列；每条写了现象、怎么复现、代码位置和修复思路。修好一条就从这里删掉，记进 [CHANGELOG](../CHANGELOG.md)；如果教程里写了绕过办法，也一并改掉（文中注明了是哪一篇）。

复现一律在沙盒里做：`scripts/demo/make-demo-home.sh <dir>`，然后 `kitfold --home <dir> …` 或 `KITFOLD_FAKE_HOME=<dir> …/KitfoldApp`。

## 一、行为错误，可能丢改动

### 1. App 开着时，CLI 改的分配会被 App 的下一次应用改回去

- **现象**：App 启动时读一次 `kitfold.json` 作为草稿；“重新扫描”不重新读它。这期间用 CLI `assign` / `profile` 改了规则，App 再应用时，会按自己手里的旧草稿写回 `kitfold.json`，并收回 CLI 建的链接。
- **依据**：读代码得出，还没在运行中的 App 里验证。`Workspace.reloadConfig()` 只在 apply / undo 之后调用（`Workspace.swift`）；`AppModel.load()` 之后 `draft` 只在应用、撤销、放弃时更新（`AppModel.swift`）。
- **修复思路**：扫描时比较 `kitfold.json` 的修改时间或哈希，变了就 `reloadConfig()`；草稿和已保存配置一致时直接换成新配置，不一致时提示“配置在外部被修改”，让用户选择保留哪一方。
- **教程**：[08 命令行](tutorials/zh-CN/08-command-line.md) 目前建议“用完 CLI 重开 App”。

### 2. 编辑已分配的 Profile 后，没有待应用栏

- **现象**：保存一个已经分配给 Agent 的 Profile，各 Agent 的指令文件需要更新，但底部不出现待应用栏，菜单 Kitfold › 预览变更…（⌘↩）也是灰的。只能用 ⌘K → 预览变更 去应用。
- **原因**：`AppModel.hasPendingChanges` 只比较草稿和已保存配置的 `rules`，不看计划里有没有文件变更。
- **修复思路**：把“计划里有 `kitfold.json` 以外的变更”也算作待应用；同时让“放弃”在这种情况下不显示（没有草稿可放弃）。注意首次启动时如果磁盘和规则本来就不一致，也会出现这条栏，要确认这是想要的。
- **教程**：[05 用 Profile 管理指令](tutorials/zh-CN/05-profiles.md) 第 4、12 节写了 ⌘K 的绕过办法。

### 3. “保留修改”在预览打开之前就保存了 Profile

- **现象**：某个 Profile 块在 Kitfold 之外被修改后，点“保留修改”，Kitfold 先把修改写回 Profile，再打开预览。此时在预览里点“取消”，Profile 已经变了。
- **位置**：`AppModel.reviewKeepEdit` → `Workspace.adoptDrift`（保存发生在生成计划时）。
- **修复思路**：把“写回 Profile”做成计划里的一项变更（`writeFile` 到库里的 Profile 文件），随应用一起执行、一起撤销。

### 4. 有外部修改的指令文件在应用时被静默跳过

- **现象**：一个指令文件里有 Profile 块被手动改过，这时去应用别的改动，其余改动照常写入，这个文件里的 Profile 块不更新，预览里只在“需要注意”里有一条错误。用户容易以为都应用了。
- **另见**：同一个问题在“健康检查”里是警告，在预览里是错误，级别不一致。
- **修复思路**：预览里把受影响的文件明确列为“这次不会写入”；统一两处的级别。

### 5. CLI 会保存永远不会生效的规则

- **现象**：`kitfold assign no-such-skill codex --yes`、拼错的 Profile id、Codex 的项目级“打开”，都会把规则存进 `kitfold.json`，只在问题里报一条错误。
- **位置**：`Sources/kitfold/main.swift` 的 `assign` / `profile` 分支。
- **修复思路**：技能和 Profile 不存在时直接报错退出（除非加 `--force`）；Codex 项目级规则在规划阶段报错且不保存。

## 二、提示和计数不准

### 6. “X 也会加载 / 将不再加载”的提醒按作用域重复，项目里有时不该出现

- **现象**：有两个项目时，“OpenCode 也会加载 “test-writer””会出现三次（全局各一次加每个项目一次），文字里不写作用域，待应用栏的“N 项待检查”也跟着算三次。OpenCode 在全局已经有规则时，项目作用域里仍然提醒。例：`assign test-writer opencode --off --yes` 之后再 `assign test-writer claude-code`，仍提醒两次；`assign code-review claude-code --off` 时会提醒两次“OpenCode 将不再加载 code-review”。“技能“k8s-debug”不在库中”同样会按作用域重复。
- **位置**：`Planner.noteSharedFolders`，按 `snapshot.scopes` 循环的那一段（`for scope in snapshot.scopes where scope == c.scope || (c.scope.isGlobal && !scope.isGlobal)`）。
- **修复思路**：项目作用域只在规则真的落到项目时提醒，并考虑那个 Agent 在全局已有的规则；同一条提醒按 (技能, Agent) 去重，项目的提醒在文字里写明项目名。
- **教程**：[03 把技能分给指定的 Agent](tutorials/zh-CN/03-assign-skills.md) 第 6 节没有承诺照做后提醒会消失。

### 7. 同一次改动，几处数字对不上

- 待应用栏的“N 处文件变更”不算 `kitfold.json`（`AppModel.pendingCount`），预览标题和 CLI 的“要应用 N 处文件变更吗？”算上了，同一个改动显示 1 和 2。
- 待应用栏的“N 项待检查”只算警告和错误，预览标题把提示也算进去。
- 建议统一口径：都不算 `kitfold.json`，都只算警告和错误（或者都写明包含什么）。[04 预览、应用和撤销](tutorials/zh-CN/04-review-apply-undo.md) 目前解释了这个差异。

### 8. 其他不准确的提示

- “A folder named … already exists”建议“导入库”，但导入是拷贝，原目录还在，冲突依旧；而且库里已有同名技能时导入会失败（通常正是这种情况）。应改为建议“移入库”或改名。
- “%@ reaches N skills through two folders”的说明列出了 Agent 读的所有目录，而不只是重复的那两个。
- 删除 Kitfold 自己在项目里新建的设置文件时，也会出现“如果这个文件被提交……”的提示，只应在改动已存在的文件时出现。
- 名称检查实际也接受 `_` 和 `:`，提示却说“只包含小写字母、数字和连字符”（`SkillEntry.isValidName`）。

## 三、界面交互

### 9. 拖放和矩阵

- 把技能拖到侧栏的 Agent 上，总是全局作用域，即使技能页当前选的是某个项目（`KitfoldApp.swift` 侧栏的 `dropDestination`）。
- 拖完即使没有任何变化（Agent 早就有这个技能），也会提示“已添加……”。
- 只有列表模式能拖，矩阵模式不行。
- 在矩阵里点技能名会选中它，但界面上没有任何反馈。

### 10. Agent 页同一个技能列多行

- OpenCode 的页面有 18 行、实际只有 12 个技能：一个技能在几个目录里都能找到，就在每个分组里各列一次。只有“被它自己的设置关闭”这一组去了重。建议每个技能只列在它实际生效的那条途径下，其他途径作为次要信息显示。

### 11. Codex 项目级“关闭”规则在格子上看不出来

- 对 Codex 在项目里关掉一个全局技能（做不到，会有提示），规则仍会保存，但格子还是 ↓，看不出这里有一条规则。建议有规则但无法生效的格子加一个标记。

### 12. 快速打开

- 动作写成“New profile / New skill”，菜单和概览页是“New Profile / New Skill”（中文都是“新建 Profile / 新建技能”，没有差别）。
- “前往”只有概览和历史记录，没有技能和 Profile 页。

### 13. 历史记录和预览里 Profile 用 id，别处用名称

- 例如“通过 Profile “researcher””和“Researcher”混用。CLI 需要 id，但 App 里从不显示 id，也没有 CLI 命令列出 Profile 的 id。建议 App 统一显示名称；CLI 加 `kitfold profiles` 列出 id 和名称。

## 四、CLI

- `kitfold --help` 和 `-h` 报“unknown option”：未知选项的检查在命令分发之前，`case "help", "-h", "--help"` 永远到不了（`main.swift`）。
- `skills --project` / `agents --project` 指向一个不是已添加项目的目录时，输出空结果而不是报错；`help` 里也没写这两个命令接受 `--project`。
- `kitfold history` 不能用 `--project` 过滤（可选）。

## 五、文案和本地化

- 英文复数：`status` 的“1 warnings/errors, 1 notes”，`history` 的“1 ops”，概览的“Scanned … · 1 agents”。
- 中文里 Agent 名称列表用的是英文逗号（“Claude Code, OpenCode 会静默跳过它”）。可以加一个按语言拼接列表的函数（中文用“、”）。
- 中文里用“ ”括起的名称两边会多出空格（“Profile 块 “code-reviewer” 被手动修改了”），因为英文里列表项是带空格拼进去的。
- 首次启动登记的来源名称“Shared (~/.agents/skills)”“Magpie library”存在 `kitfold.json` 里，所以中文界面也显示英文。可以在显示时按来源 id 翻译，或者只在用户没改过名称时翻译。

## 六、和真实 Agent 的差异（待核实）

- OpenCode 设置了 `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` 时不读 `~/.claude/skills`，Kitfold 目前总是假定它会读，相关的计数和提醒会偏多。
- 保存 `SKILL.md` 不经过预览，也不进历史记录（旧版本保留在 `backups/skills/`），所以不能从历史记录撤销。[07 管理技能库](tutorials/zh-CN/07-skill-library.md) 写明了这一点；可以考虑把它也做成一次可撤销的应用。
