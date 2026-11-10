// Simplified Chinese for checking and installing updates (Update/Updates.swift, the app's update
// sheet and settings, and `kitfold version` / `kitfold update`).
// Keys are the English exactly as written at the call site, with each interpolation as %@.
// Use %1$@, %2$@ … to reorder. Terms follow docs/localization.md.
extension Translations {
    static let zhHansUpdates: KeyValuePairs<String, String> = [
        // Updates.swift
        "Couldn't reach GitHub: %@": "连不上 GitHub：%@",
        "GitHub's answer about the latest release couldn't be read.": "读不懂 GitHub 返回的最新版本信息。",
        "The latest release has no Kitfold disk image.": "最新版本里没有 Kitfold 的磁盘映像。",
        "The download doesn't match the release's SHA-256 checksum, so it wasn't installed.":
            "下载的文件和这个版本公布的 SHA-256 校验值对不上，所以没有安装。",
        "macOS is running Kitfold from a temporary location. Move it to Applications, open it from there, and try again.":
            "macOS 正从一个临时位置运行 Kitfold。请把它移到“应用程序”，从那里打开后再试一次。",
        "Kitfold is running from a disk image. Copy it to Applications, open it from there, and try again.":
            "Kitfold 正从磁盘映像里运行。请把它拷到“应用程序”，从那里打开后再试一次。",
        "This copy of Kitfold isn't a signed release (a development build), so it can't update itself.":
            "这份 Kitfold 不是签名的正式版本（是开发构建），没法自己更新。",
        "Kitfold can't replace itself in %@: you don't have permission to change it there.": "Kitfold 没法替换 %@ 里的自己：你没有修改那里的权限。",
        "This copy of Kitfold isn't signed.": "这份 Kitfold 没有签名。",
        "Downloading Kitfold %@…": "正在下载 Kitfold %@…",
        "Checking the new version…": "正在检查新版本…",
        "The disk image has no Kitfold.app.": "磁盘映像里没有 Kitfold.app。",
        "Installing…": "正在安装…",
        "The downloaded app isn't version %@.": "下载的 App 不是 %@ 版。",
        "The downloaded app isn't signed by the same developer as this one.": "下载的 App 和这份不是同一个开发者签名的。",
        "The downloaded app isn't notarized by Apple.": "下载的 App 没有经过 Apple 公证。",
        "%@ failed: %@": "%@ 运行失败：%@",

        // UpdateView.swift
        "Getting ready…": "正在准备…",
        "Checking for updates…": "正在检查更新…",
        "Cancel": "取消",
        "Kitfold %@ is the latest version.": "Kitfold %@ 已是最新版本。",
        "You have the latest version.": "已是最新版本。",
        "OK": "好",
        "Updating Kitfold": "正在更新 Kitfold",
        "Kitfold reopens by itself when it's done.": "完成后 Kitfold 会自己重新打开。",
        "The update didn't go through": "更新没有完成",
        "Nothing was changed. You can download the new version from GitHub instead.": "什么都没改。你也可以从 GitHub 下载新版本。",
        "Open the Download Page": "打开下载页面",
        "Kitfold %@ is available": "Kitfold %@ 可以更新了",
        "You have %@.": "你现在用的是 %@。",
        "Released %@.": "发布于 %@。",
        "Switches you haven't applied are lost when Kitfold reopens.": "还没应用的开关，在 Kitfold 重新打开后会丢失。",
        "Skip This Version": "跳过这个版本",
        "Later": "以后再说",
        "Install and Reopen": "安装并重新打开",

        // KitfoldApp.swift
        "Check for Updates…": "检查更新…",
        "See what's new and install it": "看看有什么新内容并安装",

        // Sheets.swift: settings › general
        "Check for updates automatically": "自动检查更新",
        "Version": "版本",
        "development build": "开发构建",
        "Check Now": "立即检查",
        "Once a day Kitfold asks GitHub whether a newer release is out. Nothing about you or your setup is sent.":
            "Kitfold 每天问一次 GitHub 有没有新版本，不会发送任何关于你或你的配置的信息。",

        // kitfold version / update
        "Kitfold (development build)": "Kitfold（开发构建）",
        "This kitfold isn't inside an installed Kitfold.app (a development build). The latest release is %@: %@":
            "这个 kitfold 不在已安装的 Kitfold.app 里（是开发构建）。最新版本是 %1$@：%2$@",
        " (you have %@)": "（你现在用的是 %@）",
        "Download it from %@.": "请从 %@ 下载。",
        "Re-run with --yes to install it in place of %@.": "加上 --yes 重新运行，就会安装它并替换 %@。",
        "Installed Kitfold %@ in %@.": "已把 Kitfold %1$@ 安装到 %2$@。",
        "If the app is open, quit it and open it again.": "如果 App 开着，请退出后重新打开。",
    ]
}
