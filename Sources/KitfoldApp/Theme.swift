import KitfoldCore
import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension AgentAdapter {
    var tint: Color { Color(hex: descriptor.tint) }
}

/// The agent's own logo (or a monogram tile for agents without one), its identity everywhere in the app.
struct AgentBadge: View {
    let adapter: AgentAdapter
    var size: CGFloat = 22
    var dimmed = false

    var body: some View {
        Group {
            if let logo = AgentLogo(adapter.id) {
                logo
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(adapter.tint.gradient)
                    .overlay(
                        Text(adapter.descriptor.monogram)
                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.35 : 1)
        .help(adapter.name)
    }
}

/// Small pill label.
struct Pill: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}

/// One cell in an assignment grid: shows how (if at all) a skill reaches an agent, toggles on click.
struct ReachCell: View {
    let state: CellState
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
                    .frame(width: 26, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(stroke, style: StrokeStyle(lineWidth: 1.2, dash: state.pending ? [3, 2] : []))
                    )
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var on: Bool { state.willBeOn }

    private var fill: Color {
        if state.pending { return on ? tint.opacity(0.35) : Color.clear }
        switch state.reach {
        case .kitfoldLink, .otherLink, .localFolder: return tint.opacity(0.9)
        case .shared, .viaOtherAgent, .inherited, .nested: return tint.opacity(0.28)
        case .plugin: return Color.secondary.opacity(0.18)
        case .off, .disabledNatively: return Color.clear
        }
    }

    private var stroke: Color {
        if state.pending { return tint }
        return state.isOn ? Color.clear : Color.secondary.opacity(0.35)
    }

    private var symbol: String {
        if state.pending { return on ? "plus" : "minus" }
        switch state.reach {
        case .kitfoldLink, .otherLink, .localFolder: return "checkmark"
        case .shared: return "square.stack.3d.up"
        case .viaOtherAgent: return "arrow.turn.down.right"
        case .inherited: return "arrow.down"
        case .plugin: return "puzzlepiece.extension"
        case .nested: return "square.3.layers.3d.down.right"
        case .disabledNatively: return "nosign"
        case .off: return ""
        }
    }

    private var symbolColor: Color {
        switch state.reach {
        case .kitfoldLink, .otherLink, .localFolder: return state.pending ? tint : .white
        case .disabledNatively: return .secondary
        default: return state.pending ? tint : tint.opacity(0.95)
        }
    }

    private var helpText: String {
        let pending = state.pending ? (on ? " — will be switched on" : " — will be switched off") : ""
        switch state.reach {
        case .off: return "Not loaded" + pending
        case .kitfoldLink: return "Linked by Kitfold" + pending
        case .otherLink: return "Linked (by another tool or by hand)" + pending
        case .localFolder: return "A real folder in the agent's skills directory" + pending
        case .shared: return "Loaded from a shared folder the agent reads directly" + pending
        case .viaOtherAgent: return "Loaded through another agent's skills folder" + pending
        case .inherited: return "Enabled globally" + pending
        case .plugin: return "From a plugin" + pending
        case .nested: return "Nested inside another skill's folder; the agent loads it as its own skill" + pending
        case .disabledNatively: return "Present but switched off in the agent's own settings" + pending
        }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Card container used across detail views.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct PathLabel: View {
    @Environment(AppModel.self) private var model
    let path: String
    var body: some View {
        HStack(spacing: 4) {
            Text(model.ab(path))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                model.reveal(path)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
    }
}

extension Issue.Severity {
    var symbol: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

struct IssueRow: View {
    let issue: Issue
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.severity.symbol).foregroundStyle(issue.severity.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.callout)
                if !issue.detail.isEmpty {
                    Text(issue.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}

extension SkillOrigin {
    var isNested: Bool { if case .nested = self { return true }; return false }

    var label: String {
        switch self {
        case .library: return "Library"
        case .source: return "Source"
        case .agentLocal: return "Local folder"
        case .external: return "Linked folder"
        case .bundled: return "Plugin"
        case .nested: return "Nested"
        }
    }
    var symbol: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .source: return "tray.full"
        case .agentLocal: return "folder"
        case .external: return "link"
        case .bundled: return "puzzlepiece.extension"
        case .nested: return "square.3.layers.3d.down.right"
        }
    }
}
