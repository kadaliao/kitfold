// Simplified Chinese for the app's Profiles page, sheets and settings.
// Keys are the English exactly as written at the call site, with each interpolation as %@.
// Use %1$@, %2$@ … to reorder. Terms follow docs/localization.md.
extension Translations {
    static let zhHansAppProfiles: KeyValuePairs<String, String> = [
        // ProfilesView.swift
        "1 skill": "1 个技能",
        "%@ skills": "%@ 个技能",
        "No profiles yet": "还没有 Profile",
        "A profile is a reusable set of instructions plus the skills that go with them — e.g. “Backend Developer” or “Code Reviewer”.":
            "Profile 是一组可复用的指令，外加配套的技能，比如“后端开发”或“代码审查”。",
        "New Profile": "新建 Profile",
        "Select a profile": "选择一个 Profile",
        "Profiles": "Profile",
        "Edit": "编辑",
        "Preview": "预览",
        "Compare": "对比",
        "Name": "名称",
        "Delete…": "删除…",
        "Save": "保存",
        "Short description": "简短描述",
        "Assigned to": "分配给",
        "Profiles are written into each agent's own instruction file, one marked block per profile.":
            "Profile 会写进各 Agent 自己的指令文件，每个 Profile 占一个带标记的块。",
        "Skills that come with it": "附带的技能",
        "Assigning the profile also gives the agent these skills.": "分配这个 Profile 时，Agent 也会得到这些技能。",
        "Order %@": "顺序 %@",
        "When several profiles go to the same agent, lower order comes first.": "多个 Profile 写给同一个 Agent 时，顺序值小的排在前面。",
        "Move “%@” to Kitfold's trash?": "把“%@”移到 Kitfold 的废纸篓？",
        "Move to Trash": "移到废纸篓",
        "Its assignments are removed from the draft; apply to take it out of agent files.":
            "它的分配会从草稿中移除；应用后才会从 Agent 的文件里移除。",
        "Deployed in %@": "已部署到 %@",
        "Saved %@": "保存于 %@",
        "Nothing to compare yet — it hasn't been deployed or saved before.": "还没有可对比的版本：它还没有部署或保存过。",
        "Compare with": "对比对象",
        "This editor": "编辑器中的内容",
        "%@: written to %@": "%@：写入 %@",
        "Add skill": "添加技能",

        "%@: Kitfold doesn't know an instruction file only it reads": "%@：Kitfold 不知道有哪个指令文件只有它读取",
        // Sheets.swift: instruction editor
        "Parts of this file are Kitfold profile blocks. Edit those in Profiles; changes made here are detected and won't be overwritten silently.":
            "这个文件里有 Kitfold 的 Profile 块，请到 Profile 页面编辑它们；在这里做的修改会被检测到，不会被悄悄覆盖。",
        "Contains blocks written by %@. That tool may rewrite them.": "包含 %@ 写入的块，该工具可能会重写它们。",
        "on disk": "磁盘上",
        "your edit": "你的修改",
        "New file": "新文件",
        "Cancel": "取消",
        "Back to Editing": "返回编辑",
        "Apply": "应用",
        "Edit %@": "编辑 %@",
        "Review…": "预览…",

        // Sheets.swift: new profile / skill
        "New Skill": "新建技能",
        "A reusable set of instructions (and skills) you can give to any agent or project.":
            "一组可复用的指令（以及技能），可以分配给任意 Agent 或项目。",
        "Creates a SKILL.md in the Kitfold library. It isn't given to any agent until you assign it.":
            "在 Kitfold 库里创建一个 SKILL.md。在你分配之前，任何 Agent 都不会加载它。",
        "Name (e.g. Backend Developer)": "名称（如“后端开发”）",
        "Name (e.g. release-notes)": "名称（如 release-notes）",
        "When should an agent use it?": "Agent 应该在什么时候使用它？",
        "Create": "创建",

        // Sheets.swift: command palette
        "Review changes": "预览变更",
        "Action": "动作",
        "Rescan": "重新扫描",
        "Dashboard": "概览",
        "Go to": "前往",
        "History": "历史记录",
        "Agent": "Agent",
        "Project · %@": "项目 · %@",
        "Profile": "Profile",
        "Skill · %@": "技能 · %@",
        "Search skills, profiles, agents, projects, actions": "搜索技能、Profile、Agent、项目和动作",

        // Sheets.swift: project page
        "Remove from Kitfold": "从 Kitfold 中移除",
        "Agents load their global setup everywhere. Assignments here add skills and profiles for this project only, in folders only that agent reads. Kitfold keeps its files here out of git via .git/info/exclude.":
            "Agent 在任何地方都会加载全局配置。这里的分配只为这个项目添加技能和 Profile，放在只有对应 Agent 会读的目录里。Kitfold 会通过 .git/info/exclude 让这些文件不进入 git。",
        "1 skill here (%@ project-only)": "这里有 1 个技能（%@ 个仅限本项目）",
        "%@ skills here (%@ project-only)": "这里有 %@ 个技能（%@ 个仅限本项目）",
        "No project instruction files": "没有项目指令文件",
        "Issues in this project": "这个项目的问题",
        "Profiles for this project": "这个项目的 Profile",
        "Skills in this project": "这个项目的技能",
        "No profiles yet.": "还没有 Profile。",

        // Sheets.swift: history
        "No changes yet": "还没有变更",
        "Everything Kitfold applies shows up here and can be undone.": "Kitfold 应用的每项变更都会显示在这里，并且都可以撤销。",
        "Backup": "备份",
        "undo": "撤销",
        "undone": "已撤销",
        "Undo…": "撤销…",
        "Undo “%@”?": "撤销“%@”？",
        "Undo": "撤销",
        "Kitfold checks every file first. If one was changed since, nothing is undone and you'll see which.":
            "Kitfold 会先检查每个文件。如果有文件在此之后被改过，就不会撤销任何内容，并告诉你是哪个文件。",
        "1 operation": "1 项操作",
        "%@ operations": "%@ 项操作",

        // Sheets.swift: settings
        "General": "通用",
        "Agents": "Agent",
        "Sources": "来源",
        "Language": "语言",
        "Same as macOS (%@)": "跟随 macOS（%@）",
        "Menus that come from macOS switch the next time Kitfold opens.": "来自 macOS 的菜单会在下次打开 Kitfold 时切换。",
        "Kitfold folder": "Kitfold 目录",
        "Assignments": "分配",
        "History & backups": "历史记录和备份",
        "Keep Kitfold's project files out of git (.git/info/exclude)": "不让 Kitfold 的项目文件进入 git（.git/info/exclude）",
        "Keep backups for 1 day": "备份保留 1 天",
        "Keep backups for %@ days": "备份保留 %@ 天",
        "Managed by Kitfold": "由 Kitfold 管理",
        "Skill folders Kitfold reads in place": "Kitfold 原地读取的技能目录",
        "The Kitfold library (~/.kitfold/library) is always included. Removing a source never deletes files.":
            "Kitfold 库（~/.kitfold/library）始终包含在内。移除来源不会删除任何文件。",
        "Config folder": "配置目录",
        "Use": "使用",
        // Sheets.swift: settings › agents
        "On this Mac": "这台 Mac 上的",
        "Kitfold lists an agent when its config folder or command is on this Mac, and looks for skills folders of agents it doesn't know.":
            "Agent 的配置目录或命令在这台 Mac 上时，Kitfold 就会列出它；Kitfold 还会找出它不认识的 Agent 的技能目录。",
        "1 more agent Kitfold knows": "另外 1 个 Kitfold 认识的 Agent",
        "%@ more agents Kitfold knows": "另外 %@ 个 Kitfold 认识的 Agent",
        "Not found on this Mac. Switch one on to manage it anyway, for example when its folder is somewhere else.":
            "这台 Mac 上没有找到。打开开关就能照样管理它，比如它的目录在别处时。",
        "Remove this agent from Kitfold (its folders stay)": "从 Kitfold 中移除这个 Agent（它的目录会保留）",
        "Add Agent…": "添加 Agent…",
        "Your own agents": "你自己的 Agent",
        "For an agent Kitfold doesn't know or can't find: tell it where the agent keeps its skills.":
            "Kitfold 不认识或找不到的 Agent：告诉它这个 Agent 把技能放在哪里。",
        "found on this Mac": "在这台 Mac 上找到",
        "added by you": "你添加的",
        "Add an agent": "添加 Agent",
        "Kitfold links skills into the agent's skills folder, and reads what's already there.":
            "Kitfold 会把技能链接进这个 Agent 的技能目录，也会读取目录里已有的技能。",
        "Skills folder": "技能目录",
        "Choose…": "选择…",
        "Skills folder in a project (optional)": "项目里的技能目录（可选）",
        "Choose the folder where the agent looks for skills (each skill is a folder with SKILL.md).":
            "选择这个 Agent 查找技能的目录（每个技能是一个带 SKILL.md 的目录）。",
    ]
}
