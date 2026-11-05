import AppKit
import KitfoldCore

/// Kitfold's language follows the system unless one is picked for Kitfold alone.
///
/// The choice is stored where macOS keeps a per-app language (`AppleLanguages` in the app's own defaults),
/// so Kitfold's settings and System Settings › General › Language & Region › Applications agree.
/// macOS's own menus and panels pick it up at the next launch; Kitfold's text changes at once.
enum LanguageSettings {
    private static let key = "AppleLanguages"
    private static var domain: String { Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName }

    /// The language picked for Kitfold, or nil to follow the system.
    static var chosen: Language? {
        guard let list = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String] else { return nil }
        return list.first.flatMap(Language.init(tag:))
    }

    /// The system's language, ignoring a choice made for Kitfold. A launch argument
    /// (`-AppleLanguages "(zh-Hans)"`, as the snapshot scripts pass) counts as the system's.
    static var system: Language {
        if let args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? [String] {
            return Language.match(args)
        }
        let global =
            CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String]
        return Language.match(global ?? Locale.preferredLanguages)
    }

    /// `KITFOLD_LANG` (used for screenshots), else the choice, else the system's.
    static var effective: Language {
        if let tag = ProcessInfo.processInfo.environment["KITFOLD_LANG"], let l = Language(tag: tag) { return l }
        return chosen ?? system
    }

    static func choose(_ language: Language?) {
        if let language {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Where the tutorials live, in the current language.
enum Tutorials {
    static var url: URL {
        let folder = Localization.language == .simplifiedChinese ? "zh-CN" : "en"
        return URL(string: "https://github.com/kadaliao/kitfold/blob/main/docs/tutorials/\(folder)/README.md")!
    }
}
