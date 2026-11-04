import KitfoldCore
import SwiftUI

/// Every change Kitfold makes goes through this sheet first.
struct ReviewSheet: View {
    enum Mode {
        case draft
        case oneOff(AppModel.ReviewRequest)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    var plan: Plan? {
        switch mode {
        case .draft: return model.plan
        case .oneOff(let r): return r.plan
        }
    }

    var isDraft: Bool {
        if case .draft = mode { return true }
        return false
    }

    var title: String {
        switch mode {
        case .draft: return "Review changes"
        case .oneOff(let r): return r.title
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let plan {
                List {
                    if !plan.changes.isEmpty {
                        Section("Changes") {
                            let ordered =
                                plan.changes.filter { !$0.change.path.hasSuffix("/kitfold.json") }
                                + plan.changes.filter { $0.change.path.hasSuffix("/kitfold.json") }
                            let fileEdits = ordered.filter { $0.isExpandable && !$0.change.path.hasSuffix("/kitfold.json") }.count
                            ForEach(ordered) { c in
                                // Few file edits: show their diffs right away.
                                ChangeRow(change: c, startExpanded: fileEdits <= 3 && !c.change.path.hasSuffix("/kitfold.json"))
                            }
                        }
                    }
                    if !plan.issues.isEmpty {
                        Section("Needs attention — not changed automatically") {
                            ForEach(plan.issues.sorted { $0.severity > $1.severity }) { IssueRow(issue: $0) }
                        }
                    }
                    if plan.changes.isEmpty && plan.issues.isEmpty {
                        Text("Nothing to change.").foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 640)
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold))
                if let plan {
                    let caution = plan.changes.filter { $0.risk == .caution }.count
                    Text(
                        "\(plan.changes.count) change\(plan.changes.count == 1 ? "" : "s")"
                            + (caution > 0 ? " · \(caution) touch files Kitfold didn't create" : "")
                            + (plan.issues.isEmpty ? "" : " · \(plan.issues.count) to check")
                    )
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    var footer: some View {
        HStack {
            Label("Files are backed up first. Any apply can be undone from History.", systemImage: "arrow.uturn.backward.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                if case .oneOff = mode { model.reviewPlan = nil }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Apply") {
                switch mode {
                case .draft: model.applyDraft()
                case .oneOff(let r): model.perform(r.plan, summary: r.summary, keepDraft: true)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            // While a newer plan is being computed, the one on screen may be stale.
            .disabled((plan?.changes.isEmpty ?? true) || (isDraft && model.isPlanning))
        }
        .padding(16)
    }
}

struct ChangeRow: View {
    @Environment(AppModel.self) private var model
    let change: PlannedChange
    @State private var expanded: Bool

    init(change: PlannedChange, startExpanded: Bool = false) {
        self.change = change
        _expanded = State(initialValue: startExpanded && change.isExpandable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.summary)
                    Text(pathText).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let note = change.note { Text(note).font(.caption).foregroundStyle(change.risk == .caution ? .orange : .secondary) }
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(change.agents, id: \.self) { id in
                        if let a = model.snapshot?.agent(id) { AgentBadge(adapter: a.adapter, size: 16) }
                    }
                }
                if change.risk == .caution { Pill(text: "caution", color: .orange, systemImage: "hand.raised") }
                if change.isExpandable {
                    Button {
                        withAnimation(.snappy) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                    .help(change.details == nil ? "Show diff" : "Show the settings that change")
                }
            }
            if expanded, let details = change.details {
                SettingsChangeView(lines: details).padding(.leading, 28)
            } else if expanded, case .writeFile(_, let before, let after) = change.change {
                DiffView(
                    old: before ?? "", new: after ?? "", oldLabel: before == nil ? "(new file)" : "current",
                    newLabel: after == nil ? "(deleted)" : "after apply"
                )
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 3)
    }

    var pathText: String {
        switch change.change {
        case .createSymlink(let p, let t): return "\(model.ab(p)) → \(model.ab(t))"
        case .moveItem(let f, let t): return "\(model.ab(f)) → \(model.ab(t))"
        default: return model.ab(change.change.path)
        }
    }

    var icon: String {
        if change.details != nil { return "slider.horizontal.3" }
        switch change.change {
        case .createSymlink: return "link.badge.plus"
        case .removeSymlink: return "link"
        case .writeFile(_, nil, _): return "doc.badge.plus"
        case .writeFile(_, _, nil): return "trash"
        case .writeFile: return "doc.text"
        case .moveItem: return "arrow.right.doc.on.clipboard"
        }
    }

    var color: Color {
        switch change.change {
        case .createSymlink, .writeFile(_, nil, _): return .green
        case .removeSymlink, .writeFile(_, _, nil): return .red
        default: return .orange
        }
    }
}

extension PlannedChange {
    var isExpandable: Bool { diff != nil || !(details ?? []).isEmpty }
}

/// The entries a settings change adds or removes. The file itself is never shown: agent settings
/// can hold API keys and tokens.
struct SettingsChangeView: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Only these entries change; the rest of the file is kept as is.", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider()
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                let added = item.element.hasPrefix("+")
                Text(item.element)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background((added ? Color.green : Color.red).opacity(0.12))
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .textSelection(.enabled)
    }
}

/// Unified line diff with gutters.
struct DiffView: View {
    let old: String
    let new: String
    var oldLabel = "before"
    var newLabel = "after"

    var body: some View {
        let ops = LineDiff.diff(old, new)
        let stats = LineDiff.stats(ops)
        let hunks = LineDiff.hunks(ops, context: 3)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("\(oldLabel) → \(newLabel)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("+\(stats.added)").foregroundStyle(.green)
                Text("−\(stats.removed)").foregroundStyle(.red)
            }
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider()
            if hunks.isEmpty {
                Text("No differences").font(.caption).foregroundStyle(.secondary).padding(8)
            }
            ForEach(Array(hunks.prefix(30).enumerated()), id: \.offset) { item in
                if item.offset > 0 {
                    Text("⋯").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 8)
                }
                ForEach(Array(item.element.lines.prefix(400).enumerated()), id: \.offset) { line in
                    row(line.element)
                }
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .textSelection(.enabled)
    }

    @ViewBuilder func row(_ op: LineDiff.Op) -> some View {
        switch op {
        case .same(let s):
            Text("  " + s).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
        case .added(let s):
            Text("+ " + s).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                .background(Color.green.opacity(0.13)).foregroundStyle(.primary)
        case .removed(let s):
            Text("− " + s).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                .background(Color.red.opacity(0.12)).foregroundStyle(.primary)
        }
    }
}
