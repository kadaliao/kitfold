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
        "Needs attention": "需要注意",
        "Apply %@ change(s)? Re-run with --yes to apply.": "要应用 %@ 处文件变更吗？加上 --yes 重新运行即可应用。",
        "Applied.": "已应用。",
        " Undo with: kitfold undo %@": "撤销请运行：kitfold undo %@",
        "no such folder: %@": "找不到目录：%@",
        "usage: kitfold %@": "用法：kitfold %@",
        "unknown agent %@ (known: %@, *)": "未知的 Agent %@（可选：%@, *）",

        // status
        "library: %@ skills, %@ profiles": "库：%@ 个技能，%@ 个 Profile",
        "installed": "已安装",
        "config only": "只有配置",
        "not found": "未找到",
        "%@ skills active  ·  ~%@ tokens always loaded  ·  config %@": "%@ 个技能生效  ·  始终加载约 %@ token  ·  配置 %@",
        "Issues": "问题",
        " (%@ warnings/errors, %@ notes)": "（%@ 个警告或错误，%@ 条提示）",

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

        // history, undo
        " (undone)": "（已撤销）",
        "%@ ops": "%@ 项操作",
        "nothing to undo": "没有可撤销的操作",
        "no transaction %@": "历史记录里没有 %@",
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
