import KitfoldCore
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var showAllIssues = false

    var body: some View {
        if let snap = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(snap)
                    agentCards(snap)
                    HStack(alignment: .top, spacing: 16) {
                        health(snap)
                        library(snap)
                            .frame(width: 280)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Dashboard")
        }
    }

    func header(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("One library. Every agent. Your rules.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(
                "Scanned \(snap.scannedAt.formatted(date: .omitted, time: .shortened)) · \(snap.managedAgents.count) agents · \(snap.skillNames.count) skills · \(snap.profiles.count) profiles · \(snap.config.projects.count) projects"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    func agentCards(_ snap: Snapshot) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            ForEach(snap.agents) { a in
                Button {
                    model.selection = .agent(a.id)
                } label: {
                    AgentCard(agent: a, snap: snap)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func health(_ snap: Snapshot) -> some View {
        let important = snap.issues.filter { $0.severity >= .warning }
        let shown = showAllIssues ? snap.issues : important
        return Card {
            HStack {
                SectionTitle(
                    title: "Health",
                    subtitle: important.isEmpty
                        ? "No problems found." : "\(important.count) \(important.count == 1 ? "thing" : "things") worth a look")
                Toggle("Show notes", isOn: $showAllIssues).toggleStyle(.switch).controlSize(.small)
            }
            if shown.isEmpty {
                Label("Everything checks out.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
            ForEach(shown.prefix(40)) { issue in
                HStack(alignment: .top) {
                    IssueRow(issue: issue)
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(issue.affectedAgents, id: \.self) { id in
                            if let ag = snap.agent(id) { AgentBadge(adapter: ag.adapter, size: 16) }
                        }
                    }
                }
                .padding(.vertical, 2)
                Divider()
            }
            if shown.count > 40 { Text("… and \(shown.count - 40) more").font(.caption).foregroundStyle(.secondary) }
        }
    }

    func library(_ snap: Snapshot) -> some View {
        let counts = Dictionary(grouping: snap.catalog, by: { $0.origin.label }).mapValues(\.count)
        return VStack(spacing: 14) {
            Card {
                SectionTitle(title: "Skill folders", subtitle: "Where skills live on this Mac")
                ForEach(["Library", "Source", "Local folder", "Linked folder", "Nested", "Plugin"], id: \.self) { k in
                    if let n = counts[k] {
                        HStack {
                            Text(k); Spacer(); Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                Divider()
                ForEach(snap.config.sources) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.label).font(.callout)
                            if let m = s.managedBy { Pill(text: m) }
                        }
                        Text(s.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            Card {
                SectionTitle(title: "Quick actions")
                Button {
                    model.showNewProfile = true
                } label: {
                    Label("New Profile", systemImage: "person.text.rectangle")
                }
                Button {
                    model.showNewSkill = true
                } label: {
                    Label("New Skill", systemImage: "sparkles")
                }
                Button {
                    model.selection = .skills
                } label: {
                    Label("Assign skills", systemImage: "square.grid.3x3")
                }
            }
            .buttonStyle(.link)
        }
    }
}

struct AgentCard: View {
    @Environment(AppModel.self) private var model
    let agent: AgentState
    let snap: Snapshot

    var body: some View {
        let est = snap.contextEstimate(agent: agent.id, scope: .global)
        let issues = snap.issues(for: agent.id).filter { $0.severity >= .warning }
        let inst = agent.installation
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentBadge(adapter: agent.adapter, size: 30, dimmed: !agent.enabled)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.adapter.name).font(.headline)
                    Text(statusText(inst)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(est.skillCount)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("skills loaded").foregroundStyle(.secondary).font(.callout)
            }
            ContextMeter(tokens: est.approxTokens, tint: agent.adapter.tint)
            HStack(spacing: 6) {
                let files = agent.state(.global).loadedInstructions
                Pill(text: "\(files.count) instruction file\(files.count == 1 ? "" : "s")", systemImage: "doc.text")
                if !issues.isEmpty { Pill(text: "\(issues.count)", color: .orange, systemImage: "exclamationmark.triangle.fill") }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(agent.adapter.tint.opacity(agent.enabled ? 0.9 : 0.2))
                .frame(height: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .contentShape(Rectangle())
    }

    func statusText(_ i: AgentInstallation) -> String {
        if let v = i.version { return "v\(v) · \(model.ab(i.configDir))" }
        if i.binaryPath != nil { return "Installed · \(model.ab(i.configDir))" }
        if i.configDirExists { return "Config found, CLI not on PATH" }
        return "Not detected"
    }
}

/// Always-loaded context (skill descriptions + instruction files) on a soft log scale.
struct ContextMeter: View {
    let tokens: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.gradient).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text("≈ \(tokens.formatted()) tokens always in context")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .help(
            "Skill names + descriptions are listed to the model in every session, plus the instruction files. Estimate: 4 bytes per token.")
    }

    var fraction: CGFloat { min(1, log10(Double(max(tokens, 1))) / log10(40_000)) }
    var color: Color { tokens > 15_000 ? .orange : tint }
}
