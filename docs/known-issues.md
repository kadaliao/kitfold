# 已知问题

还没修的问题。每条写现象、怎么复现、代码位置和修复思路，按影响从大到小排列。修好一条就从这里删掉，记进 [CHANGELOG](../CHANGELOG.md)；如果教程里写了绕过办法，也一并改掉。

复现一律在沙盒里做：`scripts/demo/make-demo-home.sh <dir>`，然后 `kitfold --home <dir> …` 或 `KITFOLD_FAKE_HOME=<dir> …/KitfoldApp`。

写教程时（2026-11-05）发现的问题都已修好，见 CHANGELOG 的 0.2.0 部分；对应的回归测试在 `Tests/KitfoldCoreTests/TutorialFindingsTests.swift`。

## 界面交互

### 1. Agent 页说“把技能拖到这里”，但拖不过来

- **现象**：Agent 页技能卡片的说明写着“把技能拖到这里即可添加”，页面也接收拖放（`AgentView.swift` 的 `dropDestination`）。但能拖的技能只在技能页上，App 只有一个窗口（`CommandGroup(replacing: .newItem)` 去掉了“新建窗口”），所以没法同时看到技能页和 Agent 页。还没在运行中的 App 里试过从别的 App 拖文字进来。
- **修复思路**：去掉 Agent 页的拖放和这句说明，只保留拖到侧栏；或者在 Agent 页加一个能拖的技能列表。
- **教程**：[02 看懂 Agent 实际加载了什么](tutorials/zh-CN/02-what-agents-load.md) 第 4 节（英文版同）写了可以拖到 Agent 页。
