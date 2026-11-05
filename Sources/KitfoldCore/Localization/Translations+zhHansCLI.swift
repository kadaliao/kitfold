// Simplified Chinese for the kitfold command (Sources/kitfold).
// Keys are the English exactly as written at the call site, with each interpolation as %@.
// Use %1$@, %2$@ … to reorder. Terms follow docs/localization.md.
extension Translations {
    static let zhHansCLI: KeyValuePairs<String, String> = [
        // Arguments and errors
        "%@ needs a value": "%@ 需要一个值",
        "error: ": "错误：",
        "unknown language %@ (known: en, zh-Hans)": "未知的语言 %@（可选：en、zh-Hans）",
        "unknown option %@. Try kitfold help": "未知的选项 %@。运行 kitfold help 查看用法",
        "use either --off or --clear": "--off 和 --clear 只能用一个",

        // Issues and plans
        "… %@ more": "… 还有 %@ 个问题",
        "Nothing to change.": "无需更改。",
        " (caution)": "（注意）",
        "+ link": "+ 链接",
        "- link": "- 链接",
        "+ file": "+ 文件",
        "- file": "- 文件",
        "~ edit": "~ 修改",
        "→ move": "→ 移动",
        "Not written this time": "这次不会写入",
        "Needs attention": "需要注意",
        "Only the assignments are saved. Re-run with --yes to save them.": "只会保存分配，没有文件需要变更。加上 --yes 重新运行即可保存。",
        "Apply 1 file change? Re-run with --yes to apply.": "要应用 1 处文件变更吗？加上 --yes 重新运行即可应用。",
        "Apply %@ file changes? Re-run with --yes to apply.": "要应用 %@ 处文件变更吗？加上 --yes 重新运行即可应用。",
        "Applied.": "已应用。",
        " Undo with: kitfold undo %@": "撤销请运行：kitfold undo %@",
        "no such folder: %@": "找不到目录：%@",
        "usage: kitfold %@": "用法：kitfold %@",
        "unknown agent %@ (known: %@)": "未知的 Agent %@（可选：%@）",

        // status
        "library: %@": "库：%@",
        "1 profile": "1 个 Profile",
        "%@ profiles": "%@ 个 Profile",
        "installed": "已安装",
        "config only": "只有配置",
        "not found": "未找到",
        "1 skill active  ·  ~%@ tokens always loaded  ·  config %@": "1 个技能生效  ·  始终加载约 %@ token  ·  配置 %@",
        "%@ skills active  ·  ~%@ tokens always loaded  ·  config %@": "%@ 个技能生效  ·  始终加载约 %@ token  ·  配置 %@",
        "Issues": "问题",
        "1 warning or error": "1 个警告或错误",
        "%@ warnings or errors": "%@ 个警告或错误",
        "1 note": "1 条提示",
        "%@ notes": "%@ 条提示",
        " (%@, %@)": "（%@，%@）",

        // skills legend
        "● Kitfold link": "● Kitfold 链接",
        "○ other link": "○ 其他链接",
        "■ local folder": "■ 本地目录",
        "◆ shared dir": "◆ 共享目录",
        "◇ via another agent's dir": "◇ 经由其他 Agent 的目录",
        "n nested in another skill": "n 嵌套在其他技能中",
        "P plugin": "P 插件",
        "× disabled in agent settings": "× 已在 Agent 自己的设置中关闭",

        // agents
        "managed": "由 Kitfold 管理",
        "not managed": "未由 Kitfold 管理",
        "skills folders (precedence order):": "技能目录（按优先级）：",
        "instruction files:": "指令文件：",
        "loaded": "已加载",
        "present, not loaded": "存在，未加载",
        "absent": "不存在",

        // profiles
        "No profiles yet.": "还没有 Profile。",

        // apply, assign, profile (transaction summaries, kept in the history)
        "Apply kitfold.json": "应用 kitfold.json",
        "profile %@": "Profile %@",
        "Give %@ to %@": "把 %@ 分配给 %@",
        "Give %@ to %@ in %@": "在 %3$@ 中把 %1$@ 分配给 %2$@",
        "Give %@ to all agents": "把 %@ 分配给所有 Agent",
        "Give %@ to all agents in %@": "在 %2$@ 中把 %1$@ 分配给所有 Agent",
        "Take %@ from %@": "从 %2$@ 收回 %1$@",
        "Take %@ from %@ in %@": "在 %3$@ 中从 %2$@ 收回 %1$@",
        "Take %@ from all agents": "从所有 Agent 收回 %@",
        "Take %@ from all agents in %@": "在 %2$@ 中从所有 Agent 收回 %1$@",
        "Reset %@ for %@": "为 %2$@ 重置 %1$@",
        "Reset %@ for %@ in %@": "在 %3$@ 中为 %2$@ 重置 %1$@",
        "Reset %@ for all agents": "为所有 Agent 重置 %@",
        "Reset %@ for all agents in %@": "在 %2$@ 中为所有 Agent 重置 %1$@",
        "no skill named %@. kitfold skills --all lists them; --force saves the rule anyway.":
            "没有名为 %@ 的技能。kitfold skills --all 会列出所有技能；加 --force 仍会保存这条规则。",
        "no profile with id %@ (known: %@). --force saves the rule anyway.":
            "没有 id 为 %@ 的 Profile（现有：%@）。加 --force 仍会保存这条规则。",
        "not saved: this rule wouldn't change anything. --force saves it anyway.":
            "没有保存：这条规则不会带来任何变化。加 --force 仍会保存。",

        // delete
        "no skill named %@. kitfold skills --all lists them.": "没有名为 %@ 的技能。kitfold skills --all 会列出所有技能。",
        "Delete %@": "删除 %@",

        // history, undo
        " (undone)": "（已撤销）",
        "nothing to undo": "没有可撤销的操作",
        "no transaction %@": "历史记录里没有 %@",
        "Undo “%@” (1 operation)": "撤销“%@”（1 项操作）",
        "Undo “%@” (%@ operations)": "撤销“%@”（%@ 项操作）",
        "Re-run with --yes to undo.": "加上 --yes 重新运行即可撤销。",
        "Undone.": "已撤销。",

        // help
        "flags: --home <dir> (sandbox $HOME), --no-color, --lang en|zh-Hans": "选项：--home <dir>（沙盒 $HOME）、--no-color、--lang en|zh-Hans",
        "unknown command %@. Try kitfold help": "未知的命令 %@。运行 kitfold help 查看用法",
        "primary": "自己的",
        "shared": "共享",
        "foreign": "别的 Agent",
        "bundled": "内置",
    ]
}
