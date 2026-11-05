# Kitfold 教程

Kitfold 能看清每个 Coding Agent（Claude Code、Codex、OpenCode、Gemini CLI）实际加载了哪些技能和指令文件，再让你把技能或 Profile 精确地分给想要的 Agent。功能不算多，但有几个概念需要先弄明白。这套教程从第一次打开讲到排错，每篇几分钟就能读完，截图都来自演示数据。

## 先记住五件事

1. **看的是实际生效。** Kitfold 展示的不只是配置，而是每个 Agent 真正会加载什么、从哪个目录来、为什么。
2. **规则只记录你明确说过的。** 没碰过的技能和 Profile 保持原样，所以第一次打开什么都不会改。
3. **先草稿，后应用。** 拨动开关只改草稿；在预览里看清每一处文件变更，确认后才写入磁盘。
4. **一切都能撤销。** 应用前先备份，历史记录里每一次应用都能撤销。
5. **能用链接就用链接。** 链接藏不住的技能，改 Agent 自己的设置，而且只改那一条。

## 目录

| 篇 | 你会学到 |
|---|---|
| [01 安装与第一次打开](01-getting-started.md) | 构建和启动、第一次打开会发生什么、界面导览、快速打开、切换语言 |
| [02 看懂 Agent 实际加载了什么](02-what-agents-load.md) | Agent 页面上每一组技能、每个图标、每个指令文件是什么意思 |
| [03 把技能分给指定的 Agent](03-assign-skills.md) | 技能详情、矩阵、拖放；只给一个 Agent，或只对一个 Agent 隐藏 |
| [04 预览、应用和撤销](04-review-apply-undo.md) | 待应用栏、预览、需要注意的问题、历史记录和撤销 |
| [05 用 Profile 管理指令](05-profiles.md) | 新建和编辑 Profile、附带技能、分配、对比版本、处理外部修改 |
| [06 按项目配置](06-projects.md) | 添加项目、项目级技能和 Profile、在单个项目里隐藏全局技能 |
| [07 管理技能库](07-skill-library.md) | 新建技能、导入目录、移入库、删除技能、技能来源、技能的常见问题 |
| [08 命令行](08-command-line.md) | `kitfold` 的每个命令、沙盒、在脚本里使用 |
| [09 常见问题与排错](09-troubleshooting.md) | 每种健康检查问题的含义和处理办法，以及常见疑问 |

第一次用，建议按顺序读完 01–04，其余按需查阅。

## 放心地试

教程里的操作都可以先在沙盒里练：`make demo DIR=/tmp/kf-demo` 会生成一套虚构的 Agent、技能、Profile 和项目，然后

```bash
KITFOLD_FAKE_HOME=/tmp/kf-demo PATH=/tmp/kf-demo/.local/bin:/usr/bin:/bin .build/debug/KitfoldApp
.build/debug/kitfold --home /tmp/kf-demo status
```

两种方式都只读写那个目录，不会碰你真实的配置。

## 语言

Kitfold 默认跟随系统语言。想单独指定，在“设置 › 通用 › 语言”里选；命令行用 `--lang zh-Hans` 或环境变量 `KITFOLD_LANG`。详见 [01 安装与第一次打开](01-getting-started.md)。
