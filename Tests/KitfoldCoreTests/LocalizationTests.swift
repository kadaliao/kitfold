import Foundation
import Testing

@testable import KitfoldCore

@Suite struct LocalizationTests {
    @Test func picksTheFirstPreferredLanguageKitfoldHas() {
        #expect(Language.match(["en-US", "zh-Hans-SG"]) == .english)
        #expect(Language.match(["zh-Hans-CN", "en-US"]) == .simplifiedChinese)
        #expect(Language.match(["zh-Hant-TW"]) == .simplifiedChinese)
        #expect(Language.match(["ja-JP", "zh_CN"]) == .simplifiedChinese)
        #expect(Language.match(["fr-FR", "de"]) == .english)
        #expect(Language.match([]) == .english)
        #expect(Localization.initialLanguage(environment: ["KITFOLD_LANG": "zh-Hans"], preferred: ["en-US"]) == .simplifiedChinese)
        #expect(Localization.initialLanguage(environment: ["KITFOLD_LANG": "xx"], preferred: ["zh-CN"]) == .simplifiedChinese)
        #expect(Localization.initialLanguage(environment: [:], preferred: ["en-GB"]) == .english)
    }

    @Test func interpolationBuildsTheKeyAndTheEnglish() {
        let name = "Codex", n = 3
        let t: LocalizedText = "\(name) sees \(n) skills named “pdf” (100%)"
        #expect(t.key == "%@ sees %@ skills named “pdf” (100%%)")
        #expect(t.english == "Codex sees 3 skills named “pdf” (100%)")
        #expect(t.arguments == ["Codex", "3"])
        // Same rules as the source scanner below.
        #expect(Array(Self.keys(in: #"L("\(name) sees \(n) skills named “pdf” (100%)")"#).keys.keys) == [t.key])
    }

    @Test func fillsTemplates() {
        #expect(LocalizedText.fill("%@ 看到 %@ 个", with: ["Codex", "3"]) == "Codex 看到 3 个")
        #expect(LocalizedText.fill("%2$@ 属于 %1$@", with: ["a", "b"]) == "b 属于 a")
        #expect(LocalizedText.fill("100%% · %@", with: ["x"]) == "100% · x")
        #expect(LocalizedText.fill("%@ %@", with: ["only"]) == "only ")
        #expect(LocalizedText.fill("50% off", with: []) == "50% off")
        #expect(LocalizedText(stringLiteral: "100%").resolved(in: .simplifiedChinese) == "100%")
    }

    // MARK: every string in the app, CLI and core is translated

    @Test func everyStringIsTranslated() throws {
        let scan = try Self.scanSources()
        #expect(scan.problems.isEmpty, "\(scan.problems.joined(separator: "\n"))")
        #expect(scan.keys.count > 0)
        let zh = Translations.zhHans
        let missing = scan.keys.keys.filter { zh[$0] == nil }.sorted()
        let list = missing.map { "  \($0.debugDescription)  (\(scan.keys[$0]!.first!))" }.joined(separator: "\n")
        #expect(missing.isEmpty, "\(missing.count) strings have no Chinese:\n\(list)")
    }

    @Test func noTranslationIsLeftOver() throws {
        let used = Set(try Self.scanSources().keys.keys).union(Self.agentNotes.map { LocalizedText(stringLiteral: $0).key })
        let unused = Translations.zhHans.keys.filter { !used.contains($0) }.sorted()
        #expect(unused.isEmpty, "Not used anywhere:\n\(unused.map { "  \($0.debugDescription)" }.joined(separator: "\n"))")
    }

    @Test func agentNotesAreTranslated() {
        let missing = Self.agentNotes.filter { Translations.zhHans[LocalizedText(stringLiteral: $0).key] == nil }
        #expect(missing.isEmpty, "Agent notes without Chinese:\n\(missing.joined(separator: "\n"))")
    }

    @Test func tablesAgree() {
        var seen: [String: (part: String, value: String)] = [:]
        var problems: [String] = []
        for part in Translations.zhHansParts {
            var inPart = Set<String>()
            for (k, v) in part.pairs {
                if !inPart.insert(k).inserted { problems.append("\(part.name): \(k.debugDescription) appears twice") }
                if let other = seen[k], other.value != v {
                    problems.append(
                        "\(k.debugDescription): \(other.part) says \(other.value.debugDescription), \(part.name) says \(v.debugDescription)"
                    )
                }
                if seen[k] == nil { seen[k] = (part.name, v) }
                if v.trimmingCharacters(in: .whitespaces).isEmpty && !k.trimmingCharacters(in: .whitespaces).isEmpty {
                    problems.append("\(part.name): \(k.debugDescription) has an empty translation")
                }
                let want = LocalizedText.placeholders(in: k).count
                let got = LocalizedText.placeholders(in: v)
                if !got.positional.isEmpty {
                    if got.count > 0 || got.positional != Set(1...max(want, 1)) || want == 0 {
                        problems.append("\(part.name): \(k.debugDescription) → \(v.debugDescription): use %1$@…%\(want)$@, each once")
                    }
                } else if got.count != want {
                    problems.append("\(part.name): \(k.debugDescription) has \(want) placeholders, \(v.debugDescription) has \(got.count)")
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    // MARK: source scanning

    static var agentNotes: [String] {
        BuiltinAgents.all.flatMap { d in
            d.skillRoots.map(\.note) + d.instructionFiles.map(\.note) + d.notes
        }.filter { !$0.isEmpty }
    }

    struct Scan {
        var keys: [String: [String]] = [:]  // key → "file:line"
        var problems: [String] = []
    }

    static var sourcesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    static func scanSources() throws -> Scan {
        var scan = Scan()
        let files = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" && !url.path.contains("/Localization/") {
            let text = try String(contentsOf: url, encoding: .utf8)
            let found = keys(in: text, file: url.lastPathComponent)
            for (k, locs) in found.keys { scan.keys[k, default: []] += locs }
            scan.problems += found.problems
        }
        return scan
    }

    /// Every `L("…")` in `text`, keyed the way `LocalizedText` keys it.
    static func keys(in text: String, file: String = "test") -> Scan {
        let c = Array(text)
        var scan = Scan()
        var line = 1
        var i = 0
        func isIdent(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "_" || ch == "." }
        while i + 1 < c.count {
            if c[i] == "\n" { line += 1 }
            guard c[i] == "L", c[i + 1] == "(", i == 0 || !isIdent(c[i - 1]) else {
                i += 1
                continue
            }
            let at = "\(file):\(line)"
            // swift-format may break a long call after `L(`.
            var j = i + 2
            while j < c.count, c[j] == " " || c[j] == "\n" { j += 1 }
            guard j < c.count, c[j] == "\"", !(j + 2 < c.count && c[j + 1] == "\"" && c[j + 2] == "\"") else {
                scan.problems.append("\(at): L( must be followed by a one-line string literal")
                i += 2
                continue
            }
            guard let (key, end) = literal(c, j) else {
                scan.problems.append("\(at): can't read the string after L(")
                i += 2
                continue
            }
            scan.keys[key, default: []].append(at)
            line += c[i..<end].filter { $0 == "\n" }.count
            i = end
        }
        return scan
    }

    /// The string literal opening at `c[start]` (a quote): its key, and the index after the closing quote.
    static func literal(_ c: [Character], _ start: Int) -> (String, Int)? {
        var key = ""
        var i = start + 1
        while i < c.count {
            let ch = c[i]
            if ch == "\"" { return (key, i + 1) }
            if ch == "\n" { return nil }
            if ch == "\\" {
                guard i + 1 < c.count else { return nil }
                switch c[i + 1] {
                case "(":
                    guard let end = skipInterpolation(c, i + 2) else { return nil }
                    key += "%@"
                    i = end
                case "n": key += "\n"; i += 2
                case "t": key += "\t"; i += 2
                case "0": key += "\0"; i += 2
                case "\"", "\\", "'": key.append(c[i + 1]); i += 2
                case "u":
                    guard let close = c[(i + 2)...].firstIndex(of: "}"),
                        let v = UInt32(String(c[(i + 3)..<close]), radix: 16), let scalar = Unicode.Scalar(v)
                    else { return nil }
                    key += String(scalar) == "%" ? "%%" : String(scalar)
                    i = close + 1
                default: return nil
                }
                continue
            }
            key += ch == "%" ? "%%" : String(ch)
            i += 1
        }
        return nil
    }

    /// From just inside `\(`, past the matching `)`; string literals inside are skipped whole.
    static func skipInterpolation(_ c: [Character], _ start: Int) -> Int? {
        var depth = 1
        var i = start
        while i < c.count {
            switch c[i] {
            case "\"":
                guard let (_, end) = literal(c, i) else { return nil }
                i = end
                continue
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return i + 1 }
            default: break
            }
            i += 1
        }
        return nil
    }
}
