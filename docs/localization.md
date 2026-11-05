# Localization

Kitfold speaks English and Simplified Chinese. The app, the CLI and the messages from the core (health checks, plan summaries, errors) share one set of translations in `Sources/KitfoldCore/Localization/`.

## Which language

1. `KITFOLD_LANG=en|zh-Hans`, or the CLI's `--lang en|zh-Hans`.
2. The app only: the language picked in **Settings › General › Language**. It is stored as the app's own `AppleLanguages`, the same place macOS keeps the per-app language set in **System Settings › General › Language & Region › Applications**, so the two agree.
3. Otherwise the first of the system's preferred languages that Kitfold has (any Chinese gets Simplified Chinese), else English.

The app switches at once. Menus and panels drawn by macOS itself (Edit, Window, open panels) follow at the next launch.

## Writing a string

Write the English at the call site, inside `L(…)`:

```swift
Text(L("Rescan"))
toast = L("Added \(names) to \(agent.name). Review to apply.")
```

- The lookup key is the English with each `\(…)` replaced by `%@` (a literal `%` becomes `%%`). `L("Added \(names) to \(agent.name). Review to apply.")` looks up `"Added %@ to %@. Review to apply."`.
- Pass a one-line string literal, never a variable: `LocalizationTests` reads every `L("…")` in `Sources/` and fails if one has no Chinese, or if a translation is no longer used.
- Write whole sentences. Don't build one from translated pieces, and don't interpolate English words: `"\(isGlobal ? "global" : "project") skills folder"` can't be translated. Use two strings.
- Plurals: `n == 1 ? L("1 change") : L("\(n) changes")`. Chinese uses the same text for both.
- Don't call `L` in a `static let` or another value computed once: it would keep the language it was first read in. Static text such as the notes in `BuiltinAgents` stays English in code and is translated where it's shown, with `Localization.translate(note)`. The test checks those notes too.
- Don't translate anything a program reads: file names, paths, setting keys, managed-block markers, frontmatter, `Issue` keys, ids, agent and product names.
- Dates: format with `Localization.language.locale`, e.g. `date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Localization.language.locale))`. Views also get it as `\.locale`.

Then add the translation to the table for that part of the code (`Translations+zhHans*.swift`), in the order the strings appear in the source:

```swift
"Added %@ to %@. Review to apply.": "已把 %@ 添加给 %@，预览后应用。",
"%@ ignores “%@”": "%1$@ 会忽略“%2$@”",
```

Use `%1$@`, `%2$@`… when the Chinese needs the values in another order (then number every one). `swift test --filter LocalizationTests` lists what's missing or left over, with file and line.

## Style (Chinese)

- Short and plain, like macOS's own Chinese UI: 重新扫描, 取消, 好.
- Full-width punctuation in Chinese sentences (，。：；？！（）). Names in “ ”, as in English.
- A space between Chinese and Latin letters or numbers: `3 个技能`, `Claude Code 的设置`, `写入 settings.json`.
- Keep code, file names and setting keys as they are, in backticks where the English has them.
- Count words: 个技能, 个 Profile, 个 Agent, 个项目, 处文件变更, 项操作, 条规则.

## Glossary

| English | 中文 | Notes |
|---|---|---|
| Agent | Agent | product term, kept |
| Skill / Skills | 技能 | |
| Profile | Profile | product term, kept |
| Library | 库 | "Move into the library" = 移入库 |
| Source (skill source) | 来源 | |
| Dashboard | 概览 | |
| History | 历史记录 | |
| Project | 项目 | |
| Global | 全局 | |
| Scope | 作用域 | |
| Assign / assignment | 分配 | |
| Rule | 规则 | |
| Draft | 草稿 | |
| Pending | 待应用 | |
| Review | 预览 | "Review & Apply…" = 预览并应用… |
| Apply / applied | 应用 / 已应用 | |
| Undo | 撤销 | |
| Discard | 放弃 | |
| Rescan | 重新扫描 | |
| Quick Open | 快速打开 | |
| Matrix | 矩阵 | |
| Load / loaded | 加载 / 已加载 | |
| Effective (what an agent actually loads) | 实际生效 | |
| Visible / hidden | 可见 / 隐藏 | |
| Switch on / off | 打开 / 关闭 | |
| Link / symlink | 链接 / 符号链接 | |
| Folder | 目录 | |
| Shared folder | 共享目录 | |
| Plugin | 插件 | |
| Nested | 嵌套 | |
| Native settings (an agent's own switch) | 原生开关 / Agent 自己的设置 | |
| Instruction file | 指令文件 | |
| Managed block | 托管块 | |
| Edited outside Kitfold | 在 Kitfold 之外被修改 | "Keep the edit" = 保留修改, "Overwrite" = 覆盖 |
| Adopt / move into the library | 移入库 | |
| Import | 导入 | |
| Issue | 问题 | |
| Health | 健康检查 | |
| Needs attention | 需要注意 | |
| Caution | 注意 | a change that touches something Kitfold didn't create |
| Context | 上下文 | |
| Backup | 备份 | |
| Managed by Kitfold | 由 Kitfold 管理 | |
| Settings | 设置 | |
| Installed / config only / not found | 已安装 / 只有配置 / 未找到 | |

Common words, so every table agrees: OK 好 · Cancel 取消 · Save 保存 · Done 完成 · Close 关闭 · Edit 编辑 · Delete 删除 · Remove 移除 · Add 添加 · New 新建 · Open 打开 · Reveal in Finder 在访达中显示 · Copy Path 拷贝路径 · Search 搜索 · All 全部 · None 无 · On / Off 开 / 关 · Clear 清除 · Preview 预览 · Compare 对比 · Version 版本 · Name 名称 · Description 描述 · Order 顺序 · Body 正文 · Warning 警告 · Error 错误 · Note 提示.
