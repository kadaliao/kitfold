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

## 下一步

1. **原生开关写入**：直接写 Claude `skillOverrides`（项目级写 `settings.local.json`）、Codex `[[skills.config]]`（托管 TOML 段）、OpenCode `permission.skill`、Gemini `skills.disabled`。
   - 效果：放在共享目录里的技能也能对单个 Agent 隐藏；"全局开、某项目关"在 Claude 上真正生效；可以提供 `name-only` 这类上下文瘦身模式。
   - 安全要求：只改动对应的那个键，其余内容逐字节保留；保留文件原有权限；预览里只显示语义层面的变化，不展示配置文件原文（里面可能有密钥）；备份文件权限设为 600。
2. **OpenCode/Codex 项目级 Profile 隔离**：用 OpenCode 的 `instructions[]` 指向 Kitfold 自己的文件，避免和 Codex 共用 AGENTS.md。
3. **FSEvents 监听**：取代手动重新扫描，实时提示外部修改和断链；只在窗口打开时运行，不常驻后台。
4. **CLI `--json` 和 `kitfold check`**：有漂移时返回非零退出码，方便 CI，也方便以后接跨平台外壳。
5. **Git 源更新**：pull 时检测本地修改，冲突时让用户选择保留哪一方。

## 以后

- 更多 Agent：Antigravity CLI、Cursor、Amp……每个只需新增一个描述，见 [adding-an-agent](adding-an-agent.md)。
- 在设置里用 JSON 自定义 Agent。
- 签名、公证、自动更新，以及预编译的发布包。
- Windows / Linux：核心库与界面无关，可以复用；界面需要另做（详见 [architecture §1](architecture.md)）。
