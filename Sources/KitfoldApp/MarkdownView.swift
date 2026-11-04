import SwiftUI

/// Lightweight Markdown preview: headings, lists, quotes, code fences, paragraphs.
/// Inline styling (bold, code, links) via AttributedString.
struct MarkdownView: View {
    let text: String

    enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, Int)
        case numbered(String, String)
        case quote(String)
        case code(String)
        case rule
        case comment(String)
        case table([[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownView.parse(text).enumerated()), id: \.offset) { item in
                view(for: item.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            inline(s).font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let s):
            inline(s).fixedSize(horizontal: false, vertical: true)
        case .bullet(let s, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(s).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).foregroundStyle(.secondary).monospacedDigit()
                inline(s).fixedSize(horizontal: false, vertical: true)
            }
        case .quote(let s):
            inline(s).foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
        case .code(let s):
            ScrollView(.horizontal) {
                Text(s).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        case .comment(let s):
            Text(s).font(.caption.monospaced()).foregroundStyle(.tertiary)
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r in
                        GridRow {
                            ForEach(Array(r.element.enumerated()), id: \.offset) { c in
                                inline(c.element)
                                    .font(r.offset == 0 ? .callout.weight(.semibold) : .callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 320, alignment: .leading)
                            }
                        }
                        if r.offset == 0 { Divider() }
                    }
                }
                .padding(10)
            }
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var para: [String] = []
        var code: [String]?
        var table: [[String]] = []
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table)); table = [] }
        }
        func flush() {
            flushTable()
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.hasPrefix("|") {
                if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] }
                // Skip the |---|:--:| separator row.
                if line.allSatisfy({ "|-: ".contains($0) }) { continue }
                var cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                table.append(cells)
                continue
            }
            flushTable()
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("<!--") { flush(); blocks.append(.comment(line)); continue }
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6, line.dropFirst(level).first == " " {
                    flush()
                    blocks.append(.heading(level, String(line.dropFirst(level + 1))))
                    continue
                }
            }
            if line == "---" || line == "***" { flush(); blocks.append(.rule); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush()
                let indent = raw.prefix(while: { $0 == " " }).count / 2
                blocks.append(.bullet(String(line.dropFirst(2)), indent))
                continue
            }
            if let r = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flush()
                blocks.append(.numbered(String(line[r]).trimmingCharacters(in: .whitespaces), String(line[r.upperBound...])))
                continue
            }
            if line.hasPrefix(">") {
                flush(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue
            }
            para.append(line)
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
