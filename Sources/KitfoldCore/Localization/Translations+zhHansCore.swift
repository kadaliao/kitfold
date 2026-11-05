// Simplified Chinese for KitfoldCore (diagnostics, planner, executor, library, errors).
// Keys are the English exactly as written at the call site, with each interpolation as %@.
// Use %1$@, %2$@ … to reorder. Terms follow docs/localization.md.
extension Translations {
    static let zhHansCore: KeyValuePairs<String, String> = [
        // Diagnostics.swift: health checks
        "“%@” has no SKILL.md": "“%@”没有 SKILL.md",
        "%@ is in a skills folder but isn't a skill.": "%@ 在技能目录里，但不是技能。",
        "%@ ignores “%@”": "%1$@ 会忽略“%2$@”",
        "%@. Add it to %@.": "%@。请在 %@ 中补上。",
        "%@ sees %@ different skills named “%@”": "%@ 看到 %@ 个名为“%@”的不同技能",
        "%@ takes precedence. Also found: %@": "%@ 优先。另外还找到：%@",
        "%@ reaches 1 skill through two folders": "%@ 通过两个目录重复找到 1 个技能",
        "%@ reaches %@ skills through two folders": "%@ 通过两个目录重复找到 %@ 个技能",
        "The same skill folders are found via %@. Some agents list them twice or warn about a conflict.":
            "通过 %@ 找到的是同一批技能目录。有些 Agent 会把它们列出两次，或者提示冲突。",
        "Profile “%@” was edited outside Kitfold": "Profile“%@”在 Kitfold 之外被修改过",
        "%@: Kitfold won't overwrite it until you keep or discard the edit.": "%@：在你保留或放弃这处修改之前，Kitfold 不会覆盖它。",
        "%@ manages part of %@": "%@ 管理着 %@ 的一部分",
        "%@ has a block written by %@. Kitfold leaves it alone.": "%@ 中有一个由 %@ 写入的块，Kitfold 不会动它。",
        "%@ instructions exceed %@ KiB": "%@ 的指令超过 %@ KiB",
        "%@ bytes are loaded; %@ cuts off everything past %@ bytes.": "已加载 %@ 字节；%@ 会截掉 %@ 字节之后的全部内容。",
        "%@ broken skill links in %@": "%2$@ 中有 %1$@ 个失效的技能链接",
        "%@ point to folders that no longer exist. Skipped silently by %@.": "%@ 指向的目录已不存在。%@ 会静默跳过它们。",
        "Broken skill link “%@”": "技能链接“%@”已失效",
        "%@ → %@, which no longer exists. Skipped silently by %@.": "%@ → %@，目标已不存在。%@ 会静默跳过它。",
        "%@: %@": "%@：%@",
        "“%@” contains %@ nested SKILL.md": "“%@”里有 %@ 个嵌套的 SKILL.md",
        "Codex and OpenCode load each nested SKILL.md as a separate skill: %@": "Codex 和 OpenCode 会把每个嵌套的 SKILL.md 当作单独的技能加载：%@",

        // Planner.swift: plan summaries, notes and issues
        "“%@” comes from a plugin": "“%@”来自插件",
        "Plugin skills are managed by the agent's plugin system.": "插件技能由 Agent 自己的插件系统管理。",
        "%@ can't load “%@”": "%@ 无法加载“%@”",
        "%@. Fix %@ first.": "%@。请先修正 %@。",
        "“%@” is switched off in %@'s settings": "“%@”在 %@ 的设置中被关闭了",
        "%@ disables it. Remove that entry to let %@ load it.": "%@ 关闭了它。移除这个设置项，%@ 才能加载它。",
        "%@ has no global skills folder": "%@ 没有全局技能目录",
        "%@ has no project skills folder": "%@ 没有项目技能目录",
        "Link %@ for %@ (via profile “%@”)": "为 %2$@ 链接 %1$@（通过 Profile“%3$@”）",
        "Link %@ for %@ (assigned)": "为 %2$@ 链接 %1$@（已分配）",
        "Another “%@” is also visible: %@": "另一个“%@”也可见：%@",
        "Replace link %@ for %@": "替换 %2$@ 的链接 %1$@",
        "Currently points to %@": "目前指向 %@",
        "A folder named “%@” already exists for %@": "%2$@ 已有名为“%1$@”的目录",
        "%@ is a real folder Kitfold didn't create, so it won't be replaced. If it's a copy of this skill, delete it and apply again; otherwise rename one of the two.":
            "%@ 是一个不由 Kitfold 创建的真实目录，所以不会被替换。如果它只是这个技能的副本，删掉它再应用一次；否则请给其中一个改名。",
        "“%@” stays visible to %@ in this project": "在这个项目中，%2$@ 仍能看到“%1$@”",
        "It's enabled globally (%@).": "它在全局启用（%@）。",
        "Unlink %@ from %@": "为 %2$@ 移除 %1$@ 的链接",
        "This link wasn't created by Kitfold (another tool or by hand). Undo restores it.": "这个链接不是 Kitfold 创建的（来自其他工具或手动创建）。撤销可以恢复它。",
        "“%@” is a real folder in %@'s skills": "“%@”是 %@ 技能目录里的真实目录",
        "%@ isn't a link, so Kitfold won't delete it. Move it into the library first (Move into Library on the Skills page), then it can be switched off.":
            "%@ 不是链接，所以 Kitfold 不会删除它。先把它移入库（技能页上的“移入库”），之后就能关闭它。",
        "“%@” stays visible to %@": "%2$@ 仍能看到“%1$@”",
        "It lives in %@, which %@ reads directly. Move it into the Kitfold library to control it per agent.":
            "它位于 %@，%@ 会直接读取这个目录。把它移入 Kitfold 库，才能按 Agent 分别控制。",
        "%@ also reads %@'s folder %@.": "%@ 也会读取 %@ 的目录 %@。",
        "%@ also reads another agent's folder %@.": "%@ 也会读取另一个 Agent 的目录 %@。",
        "Disable the plugin in %@ instead.": "请改为在 %@ 中停用这个插件。",
        "It's a SKILL.md nested inside “%@” (%@), and %@ loads nested skills on its own. Switch off “%@”, or move the inner file out.":
            "它是嵌套在“%1$@”里的 SKILL.md（%2$@），而 %3$@ 会把嵌套的技能单独加载。请关闭“%4$@”，或者把里面的文件移出来。",
        "Unlink %@ from %@ (no longer assigned)": "为 %2$@ 移除 %1$@ 的链接（已不再分配）",
        "It's assigned to %@ but no folder with that name was found.": "它已分配给 %@，但找不到同名的目录。",
        "It's assigned to %@ in %@ but no folder with that name was found.": "它在 %2$@ 中分配给了 %1$@，但找不到同名的目录。",
        "Profile %@ includes it.": "Profile%@包含它。",
        "Skill “%@” isn't in the library": "技能“%@”不在库中",
        "%@ will load “%@” too": "%@ 也会加载“%@”",
        "%@ will load “%@” too in %@": "在 %3$@ 中，%1$@ 也会加载“%2$@”",
        "%@ also reads %@'s folder %@. Switch “%@” off for %@ to keep it to %@.": "%1$@ 也会读取 %2$@ 的目录 %3$@。要让它只给 %6$@ 用，请为 %5$@ 关闭“%4$@”。",
        "%@ will stop loading “%@”": "%@ 将不再加载“%@”",
        "%@ will stop loading “%@” in %@": "在 %3$@ 中，%1$@ 将不再加载“%2$@”",
        "%@ found it only in %@'s folder %@. Switch “%@” on for %@ to keep it there.":
            "%1$@ 只在 %2$@ 的目录 %3$@ 中找到它。为 %5$@ 打开“%4$@”，它就能继续加载。",
        "Profile “%@” doesn't exist": "Profile“%@”不存在",
        "Remove the assignment or restore the profile file.": "请移除这个分配，或者恢复 Profile 文件。",
        "%@ points into Kitfold's library": "%@ 指向 Kitfold 的库",
        "Writing it would feed Kitfold's output back into its own source. Replace the link with a regular file.":
            "写入它会把 Kitfold 的输出写回它自己的来源。请把这个链接换成普通文件。",
        "%@ won't be written": "这次不会写入 %@",
        "Its block for %@ was edited outside Kitfold. On the agent's page, keep the edit (copy it into the profile) or overwrite it, then apply again.":
            "其中%@的 Profile 块在 Kitfold 之外被修改过。请在 Agent 页面保留修改（写回 Profile）或覆盖它，然后再应用一次。",
        "%@ won't read %@ while %@ exists": "%3$@ 存在时，%1$@ 不会读取 %2$@",
        "%@ replaces %@, so the profile has no effect on %@. Empty or remove the override file, or move its text into a profile.":
            "%@ 会替代 %@，所以这个 Profile 对 %@ 不起作用。请清空或移除这个覆盖文件，或者把其中的内容移到 Profile 里。",
        "Remove Kitfold profiles from %@": "从 %@ 移除 Kitfold 的 Profile",
        "Create %@ with %@": "创建 %@，写入 %@",
        "Update %@ in %@": "更新 %2$@ 中的 %1$@",
        "Read by %@": "由 %@ 读取",
        "Overwrites edits made outside Kitfold": "会覆盖在 Kitfold 之外做的修改",
        "%@ also reads %@": "%@ 也会读取 %@",
        "%@ is shared, so %@ will see %@ too. Agents can't be isolated within one file.": "%@ 是共享的，所以 %@ 也会看到 %@。同一个文件里无法按 Agent 隔离。",
        "%@ will stop reading %@": "%@ 将不再读取 %@",
        "Today %@ falls back to %@ because %@ doesn't exist. Creating it changes that.": "因为 %3$@ 不存在，%1$@ 目前会回退到 %2$@。创建它之后就不会了。",
        "Keep Kitfold's files in %@ out of git": "让 git 忽略 %@ 中 Kitfold 的文件",
        ".git/info/exclude is local to this clone and never committed.": ".git/info/exclude 只对本地这个克隆生效，不会被提交。",

        // NativePlanner.swift: agents' own skill settings
        "Kitfold can't add skill settings to %@": "Kitfold 无法向 %@ 添加技能设置",
        "The file defines `skills.config` in a form that an appended `[[skills.config]]` table would break. Use `[[skills.config]]` tables there to let Kitfold manage it.":
            "这个文件里 `skills.config` 的写法会被追加的 `[[skills.config]]` 表破坏。请在那里改用 `[[skills.config]]` 表，Kitfold 才能管理它。",
        "Kitfold can't read %@": "Kitfold 无法读取 %@",
        "It isn't valid %@, so Kitfold won't edit it. Fix the file, then try again.": "它不是有效的 %@，所以 Kitfold 不会编辑它。请修正文件后再试。",
        "Hide %@ from %@; Let %@ load %@ again": "对 %2$@ 隐藏 %1$@；让 %3$@ 重新加载 %4$@",
        "Hide %@ from %@": "对 %2$@ 隐藏 %1$@",
        "Let %@ load %@ again": "让 %@ 重新加载 %@",
        "Update %@'s skill settings": "更新 %@ 的技能设置",
        "Changes an entry Kitfold didn't write. Undo restores it. If this file is committed, everyone using the repository gets this setting.":
            "会改动一个不是 Kitfold 写入的设置项。撤销可以恢复它。如果这个文件被提交，使用这个仓库的所有人都会得到这项设置。",
        "Changes an entry Kitfold didn't write. Undo restores it.": "会改动一个不是 Kitfold 写入的设置项。撤销可以恢复它。",
        "If this file is committed, everyone using the repository gets this setting.": "如果这个文件被提交，使用这个仓库的所有人都会得到这项设置。",
        "It's enabled globally, and Codex reads `[[skills.config]]` only from $CODEX_HOME/config.toml, so a skill can't be hidden in one project alone. Switch it off globally instead.":
            "它在全局启用，而 Codex 只从 $CODEX_HOME/config.toml 读取 `[[skills.config]]`，所以无法只在一个项目里隐藏技能。请改为在全局关闭它。",
        "%@ has no per-project setting for this.": "%@ 没有针对单个项目的这项设置。",
        "Its settings switch it off.": "它在设置中被关闭了。",
        "%@ switches off every skill (`%@`). Change that setting to load skills.": "%@ 关闭了所有技能（`%@`）。修改这项设置后才能加载技能。",
        "%@ switches it off for every project, and %@ can't switch it back on for one project. Switch it on globally instead.":
            "%@ 对所有项目关闭了它，而 %@ 无法只在一个项目里重新打开它。请改为在全局打开它。",
        "%@ switches it off. Remove that entry to let %@ load it.": "%@ 关闭了它。移除这个设置项，%@ 才能加载它。",

        // Executor.swift: apply and undo
        "Nothing to apply": "没有要应用的更改",
        "transaction %@": "历史记录 %@",
        "Already undone": "已经撤销过了",
        "Undo: %@": "撤销：%@",
        "These files changed after the original apply, so undo would overwrite newer edits: %@": "这些文件在那次应用之后又被修改过，撤销会覆盖较新的修改：%@",
        "Links made later still point into %@: %@. Switch that skill off for those agents first.":
            "之后创建的链接仍指向 %@ 内部：%@。请先为这些 Agent 关闭那个技能。",
        "Undo “%@”": "撤销“%@”",
        "%@ already exists": "%@ 已存在",
        "%@ is no longer a link": "%@ 已不再是链接",
        "%@ now points to %@": "%@ 现在指向 %@",
        "%@ changed since the preview": "%@ 在预览之后被修改了",
        "%@ now exists": "%@ 现在已存在",
        "%@ is gone": "%@ 已不存在",

        // Workspace.swift
        "Save assignments to kitfold.json": "把分配保存到 kitfold.json",
        "Edit %@": "编辑 %@",
        "block %@ in %@": "%2$@ 中的托管块 %1$@",
        "profile %@": "Profile %@",
        "Copy the edit into profile “%@”": "把修改写回 Profile“%@”",
        "Edit SKILL.md of “%@”": "编辑“%@”的 SKILL.md",
        "%@ is already in the library": "%@ 已在库中",
        "Plugin skills can't be moved": "插件技能无法移动",
        "%@ lives inside “%@”; move that skill instead": "%@ 位于“%@”内部，请改为移动那个技能",
        "The library already has a folder named %@": "库中已有名为 %@ 的目录",
        "Move %@ into the Kitfold library": "把 %@ 移入 Kitfold 库",
        "Leave a link at %@": "在 %@ 留下链接",
        "Agents and tools that used the old path keep working.": "使用旧路径的 Agent 和工具可以照常工作。",
        "%@ manages %@": "%@ 管理着 %@",
        "After the move, %@ may treat %@ as replaced by a link. Updates from %@ will no longer reach it.":
            "移动之后，%1$@ 可能会认为 %2$@ 已被换成链接，%3$@ 的更新将不再同步到它。",

        // LibraryStore.swift (the second paragraph of a new SKILL.md, and errors)
        "Skill name is empty": "技能名称为空",
        "A skill named %@ already exists in the library": "库中已有名为 %@ 的技能",
        "Describe when and how to use this skill.": "说明何时以及如何使用这个技能。",
        "%@ has no SKILL.md": "%@ 中没有 SKILL.md",
        "The library already has a skill named %@": "库中已有名为 %@ 的技能",
        "Can't derive a name from %@": "无法从 %@ 得出名称",
        "%@ failed: %@": "%@ 运行失败：%@",

        // FileSystem.swift: KitfoldError
        "Refusing to remove %@: not a symlink": "拒绝移除 %@：它不是符号链接",
        "unlink failed for %@: %@": "无法移除链接 %@：%@",
        "Precondition failed: %@": "前置检查未通过：%@",
        "I/O error: %@": "读写错误：%@",
        "Invalid: %@": "无法完成：%@",
        "Not found: %@": "未找到：%@",

        // Frontmatter.swift: parse errors
        "Frontmatter is not closed with ---": "frontmatter 没有用 --- 结束",
        "Frontmatter has no readable keys": "frontmatter 中没有可读的键",
        "Unreadable frontmatter line: %@": "无法读取的 frontmatter 行：%@",

        // Config.swift: sources found on first launch
        "Shared (~/.agents/skills)": "共享目录（~/.agents/skills）",
        "Magpie library": "Magpie 库",

        // Resources.swift: a skill folder's problems
        "SKILL.md has no frontmatter (name/description)": "SKILL.md 没有 frontmatter（name/description）",
        "Missing description — agents use it to decide when to load the skill": "缺少描述：Agent 靠它判断何时加载这个技能",
        "Name “%@” should be at most 64 characters: lowercase letters, digits, “-”, “_” or “:”":
            "名称“%@”最多 64 个字符，只能包含小写字母、数字、“-”“_”或“:”",

        // SQLite.swift
        "Can't open database %@: %@": "无法打开数据库 %@：%@",

        // BundledSkills.swift: where a plugin skill comes from
        "Plugin %@": "插件 %@",
        "Extension %@": "扩展 %@",
    ]
}
