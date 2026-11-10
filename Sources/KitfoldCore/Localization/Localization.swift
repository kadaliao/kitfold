import Foundation
import Synchronization

/// The languages Kitfold's own text comes in.
public enum Language: String, CaseIterable, Sendable, Codable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }

    /// The first language in `preferred` that Kitfold has, the way macOS picks an app's localization.
    /// Tags look like "en-US", "zh-Hans-CN" or "zh_TW". Any Chinese gets Simplified Chinese; nothing known gets English.
    public static func match(_ preferred: [String]) -> Language {
        preferred.lazy.compactMap(Language.init(tag:)).first ?? .english
    }

    /// nil for a language Kitfold doesn't have.
    public init?(tag: String) {
        let base = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""
        switch base {
        case "en": self = .english
        case "zh": self = .simplifiedChinese
        default: return nil
        }
    }

    /// The language's name in that language, for pickers.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    /// For dates and numbers: this language, with the user's region and formats.
    public var locale: Locale {
        var c = Locale.Components(locale: .autoupdatingCurrent)
        c.languageComponents = Locale.Language.Components(identifier: rawValue)
        return Locale(components: c)
    }
}

/// Which language `L(_:)` returns. Front ends set it at launch; it starts as `KITFOLD_LANG`, else the system's languages.
public enum Localization {
    private static let current = Mutex(initialLanguage())

    public static var language: Language {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    /// `KITFOLD_LANG` (en, zh-Hans…) wins; otherwise the first of the system's preferred languages that Kitfold has.
    public static func initialLanguage(
        environment: [String: String] = ProcessInfo.processInfo.environment, preferred: [String] = Locale.preferredLanguages
    ) -> Language {
        if let tag = environment["KITFOLD_LANG"], let l = Language(tag: tag) { return l }
        return Language.match(preferred)
    }

    /// Names listed in a sentence: “a, b, c” in English, “a、b、c” in Chinese.
    public static func list(_ items: [String], in language: Language = Localization.language) -> String {
        items.joined(separator: language == .simplifiedChinese ? "、" : ", ")
    }

    /// Sentences run together: a space between them in English, none in Chinese.
    public static func sentences(_ parts: [String], in language: Language = Localization.language) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: language == .simplifiedChinese ? "" : " ")
    }

    /// Text that isn't written at a call site, such as the notes in `BuiltinAgents`: looked up as is.
    public static func translate(_ english: String, in language: Language = Localization.language) -> String {
        LocalizedText(stringLiteral: english).resolved(in: language)
    }
}

/// Kitfold's text in the current language. Write the English inline, with interpolations:
///
///     L("\(agent.name) ignores “\(skill)”")
///
/// The lookup key is the English with each interpolation as `%@`. A translation may reorder them with `%1$@`, `%2$@`.
/// Pass a string literal every time (no variables): a test reads every `L(…)` in Sources and checks it is translated.
public func L(_ text: LocalizedText) -> String { text.resolved(in: Localization.language) }

public struct LocalizedText: ExpressibleByStringInterpolation, Sendable, Hashable {
    /// The English with every interpolation replaced by `%@` and every literal `%` written `%%`.
    public let key: String
    public let english: String
    public let arguments: [String]

    public init(stringLiteral value: String) {
        key = value.replacingOccurrences(of: "%", with: "%%")
        english = value
        arguments = []
    }

    public init(stringInterpolation s: StringInterpolation) {
        key = s.key
        english = s.english
        arguments = s.arguments
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = "", english = "", arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + 2 * interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
            english += literal
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            let s = "\(value)"
            key += "%@"
            english += s
            arguments.append(s)
        }
    }

    public func resolved(in language: Language) -> String {
        guard let template = Translations.table(for: language)[key] else { return english }
        return Self.fill(template, with: arguments)
    }

    /// `%@` takes the next argument, `%2$@` the second, `%%` is a percent sign. Anything else stays as written.
    static func fill(_ template: String, with arguments: [String]) -> String {
        var out = ""
        var next = 0
        var i = template.startIndex
        while i < template.endIndex {
            let ch = template[i]
            guard ch == "%", let j = template.index(i, offsetBy: 1, limitedBy: template.endIndex), j < template.endIndex else {
                out.append(ch)
                i = template.index(after: i)
                continue
            }
            if template[j] == "%" {
                out.append("%")
                i = template.index(after: j)
            } else if template[j] == "@" {
                out += next < arguments.count ? arguments[next] : ""
                next += 1
                i = template.index(after: j)
            } else if let (n, end) = positional(template, from: j), n >= 1 {
                out += n <= arguments.count ? arguments[n - 1] : ""
                i = end
            } else {
                out.append(ch)
                i = j
            }
        }
        return out
    }

    /// `2$@` starting at `i`: the number and the index after `@`.
    static func positional(_ s: String, from i: String.Index) -> (Int, String.Index)? {
        var j = i
        var digits = ""
        while j < s.endIndex, s[j].isASCII, s[j].isNumber {
            digits.append(s[j])
            j = s.index(after: j)
        }
        guard !digits.isEmpty, j < s.endIndex, s[j] == "$" else { return nil }
        let at = s.index(after: j)
        guard at < s.endIndex, s[at] == "@", let n = Int(digits) else { return nil }
        return (n, s.index(after: at))
    }

    /// How many arguments a template uses, and whether it numbers them (`%1$@`). For tests.
    static func placeholders(in template: String) -> (count: Int, positional: Set<Int>) {
        var count = 0
        var numbered = Set<Int>()
        var i = template.startIndex
        while i < template.endIndex {
            guard template[i] == "%", let j = template.index(i, offsetBy: 1, limitedBy: template.endIndex), j < template.endIndex
            else {
                i = template.index(after: i)
                continue
            }
            if template[j] == "%" {
                i = template.index(after: j)
            } else if template[j] == "@" {
                count += 1
                i = template.index(after: j)
            } else if let (n, end) = positional(template, from: j) {
                numbered.insert(n)
                i = end
            } else {
                i = j
            }
        }
        return (count, numbered)
    }
}

/// Translation tables, keyed by `LocalizedText.key`. Each part of the code base keeps its own table
/// (`Translations+zhHans*.swift`) so they can be edited independently; a key may appear in two tables only with the same text.
enum Translations {
    static func table(for language: Language) -> [String: String] {
        switch language {
        case .english: return [:]
        case .simplifiedChinese: return zhHans
        }
    }

    static let zhHansParts: [(name: String, pairs: KeyValuePairs<String, String>)] = [
        ("core", zhHansCore), ("agents", zhHansAgents), ("cli", zhHansCLI),
        ("app", zhHansApp), ("app-skills", zhHansAppSkills), ("app-profiles", zhHansAppProfiles), ("updates", zhHansUpdates),
    ]

    static let zhHans: [String: String] = {
        var out: [String: String] = [:]
        for part in zhHansParts {
            for (k, v) in part.pairs where out[k] == nil { out[k] = v }
        }
        return out
    }()
}
