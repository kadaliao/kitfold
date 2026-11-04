import KitfoldCore
import SwiftUI

struct AgentView: View {
    @Environment(AppModel.self) private var model
    let agentID: AgentID
    @State private var scope: Scope = .global
    @State private var showAdd = false
    @State private var filter = ""
    @State private var expanded: [SkillGroup: Bool] = [:]

    var body: some View {
        if let snap = model.snapshot, let agent = snap.agent(agentID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(agent, snap)
                    skills(agent, snap)
                    profiles(agent)
                    instructions(agent)
                    discovery(agent)
                    let issues = snap.issues(for: agentID).filter { $0.scope == nil || $0.scope == scope }
                    if !issues.isEmpty {
                        Card {
                            SectionTitle(title: "Issues")
                            ForEach(issues) { IssueRow(issue: $0) }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(agent.adapter.name)
            .dropDestination(for: String.self) { names, _ in
                for n in names where !model.cell(skill: n, agent: agentID, scope: scope).willBeOn {
                    model.toggle(skill: n, agent: agentID, scope: scope)
                }
                return true
            }
        }
    }

    // MARK: header

    func header(_ a: AgentState, _ snap: Snapshot) -> some View {
        let inst = a.installation
        let est = snap.contextEstimate(agent: a.id, scope: scope)
        return HStack(alignment: .top, spacing: 14) {
            AgentBadge(adapter: a.adapter, size: 48, dimmed: !a.enabled)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(a.adapter.name).font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(a.adapter.descriptor.vendor).foregroundStyle(.secondary)
                    if let v = inst.version { Pill(text: "v\(v)") }
                }
                if let bin = inst.binaryPath {
                    PathLabel(path: bin)
                } else {
                    Text(inst.configDirExists ? "CLI not found on PATH (config folder exists)" : "Not detected on this Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PathLabel(path: inst.configDir)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    Text("Showing").foregroundStyle(.secondary)
                    ScopePicker(scope: $scope)
                }
                Toggle(
                    "Managed by Kitfold",
                    isOn: Binding(
                        get: { a.enabled },
                        set: { on in
                            var c = model.draft
                            var s = c.agents[a.id.rawValue] ?? AgentSettings()
                            s.enabled = on
                            c.agents[a.id.rawValue] = s
                            model.saveDirect(c)
                        })
                )
                .toggleStyle(.switch)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(est.skillCount) skills · \(est.instructionBytes.formatted(.byteCount(style: .file))) instructions")
                        .font(.callout.monospacedDigit())
                    ContextMeter(tokens: est.approxTokens, tint: a.adapter.tint).frame(width: 220)
                }
            }
        }
    }

    // MARK: skills (agent perspective)

    enum SkillGroup: String, CaseIterable {
        case linked = "Linked into its skills folder"
        case local = "Folders inside its skills folder"
        case shared = "From shared folders"
        case foreign = "Through another agent's folder"
        case nested = "Nested inside other skills"
        case project = "Project skills"
        case plugins = "From plugins"
        case disabled = "Present, but switched off in its settings"
    }

    func group(_ r: Reach) -> SkillGroup {
        let s = r.skill
        if s.native.isDisabled { return .disabled }
        if s.nestedIn != nil { return .nested }
        switch s.root.spec.role {
        case .primary: return !r.inherited && !scope.isGlobal ? .project : (s.isSymlink ? .linked : .local)
        case .shared: return .shared
        case .foreign: return .foreign
        case .bundled: return .plugins
        }
    }

    func uniqueByName(_ items: [Reach]) -> [Reach] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.skill.name).inserted }
    }

    func skills(_ a: AgentState, _ snap: Snapshot) -> some View {
        let reach = a.reachableSkills(in: scope).filter { $0.skill.isReadable }
        let q = filter.lowercased()
        let filtered = reach.filter { q.isEmpty || $0.skill.name.lowercased().contains(q) }
        let groups = Dictionary(grouping: filtered, by: group)
        let pendingAdds = model.draft.rules.filter {
            $0.resource.kind == .skill && $0.scope == scope && $0.state == .on && ($0.agent == .all || $0.agent == .agent(agentID))
        }.map(\.resource.id).filter { n in !reach.contains { $0.skill.name == n } }

        return Card {
            HStack {
                SectionTitle(
                    title: "Skills",
                    subtitle:
                        "What \(a.adapter.name) loads \(scope.isGlobal ? "everywhere" : "in \(model.projectName(scope))"), grouped by how it gets there. Drop skills here to add them."
                )
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 160)
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .popover(isPresented: $showAdd, arrowEdge: .bottom) { AddSkillsPopover(agentID: agentID, scope: scope) }
            }
            if !pendingAdds.isEmpty {
                ForEach(pendingAdds, id: \.self) { n in
                    skillRow(name: n, path: nil, a: a, note: "will be added")
                }
            }
            ForEach(SkillGroup.allCases, id: \.self) { g in
                // A switched-off skill is off however many folders it's found in: list it once.
                if let all = groups[g], case let items = g == .disabled ? uniqueByName(all) : all, !items.isEmpty {
                    DisclosureGroup(isExpanded: Binding(get: { expanded[g] ?? (items.count <= 6) }, set: { expanded[g] = $0 })) {
                        ForEach(items.sorted { $0.skill.name < $1.skill.name }, id: \.skill.id) { r in
                            skillRow(
                                name: r.skill.name, path: r.skill.entryPath, a: a,
                                note: r.skill.isSymlink ? r.skill.linkTarget.map { "→ " + model.ab($0) } : nil)
                        }
                    } label: {
                        HStack {
                            Text(g.rawValue).font(.callout.weight(.medium))
                            Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            let roots = Set(items.map { $0.skill.root.path })
                            if roots.count == 1, let root = roots.first, g != .plugins, g != .nested {
                                Text(model.ab(root)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    func skillRow(name: String, path: String?, a: AgentState, note: String?) -> some View {
        let c = model.cell(skill: name, agent: a.id, scope: scope)
        return HStack(spacing: 8) {
            ReachCell(state: c, tint: a.adapter.tint) { model.toggle(skill: name, agent: a.id, scope: scope) }
            Button {
                model.selectedSkillPath = model.snapshot?.skill(named: name)?.path
                model.selection = .skills
            } label: {
                Text(name).lineLimit(1)
            }
            .buttonStyle(.plain)
            if let note { Text(note).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            Spacer()
            let native = a.reachableSkills(in: scope).first(where: { $0.skill.name == name })?.skill.native ?? .enabled
            if case .disabled(let src, let byKitfold) = native {
                Text(byKitfold ? "hidden by Kitfold in \(src)" : "off in \(src)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }

    // MARK: profiles

    func profiles(_ a: AgentState) -> some View {
        Card {
            SectionTitle(title: "Profiles", subtitle: profileTarget(a))
            if model.profiles.isEmpty {
                HStack {
                    Text("No profiles yet.").foregroundStyle(.secondary)
                    Button("Create one…") { model.showNewProfile = true }.buttonStyle(.link)
                }
            }
            ForEach(model.profiles) { p in
                let st = model.profileState(p.id, agent: a.id, scope: scope)
                Toggle(isOn: Binding(get: { st.on }, set: { _ in model.toggleProfile(p.id, agent: a.id, scope: scope) })) {
                    HStack {
                        Text(p.name)
                        if !p.skills.isEmpty { Pill(text: "+\(p.skills.count) skills", systemImage: "sparkles") }
                        if st.pending { Pill(text: "pending", color: .accentColor) }
                        Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    func profileTarget(_ a: AgentState) -> String {
        guard let env = model.env, let f = a.adapter.primaryInstructionFile(scope, env) else { return "" }
        return "Kitfold writes assigned profiles to \(model.ab(f))."
    }

    // MARK: instructions

    func instructions(_ a: AgentState) -> some View {
        Card {
            SectionTitle(title: "Instruction files", subtitle: "In load order. Only loaded files reach the model.")
            let files = (scope.isGlobal ? [] : a.state(.global).instructions.filter(\.isLoaded)) + a.state(scope).instructions
            ForEach(files) { f in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: f.isLoaded ? "doc.text.fill" : (f.exists ? "doc.text" : "doc"))
                        .foregroundStyle(f.isLoaded ? a.adapter.tint : .secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(model.ab(f.file.path)).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            if f.isLoaded {
                                Pill(text: "loaded", color: .green)
                            } else if f.exists {
                                Pill(text: "not loaded", color: .orange)
                            }
                            if f.file.spec.role == .primary { Pill(text: "Kitfold target", color: .accentColor) }
                            if f.file.spec.role == .fallback { Pill(text: "fallback") }
                            if f.isSymlink { Pill(text: "symlink", systemImage: "link") }
                            if f.exists { Text(f.byteCount.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary) }
                        }
                        if !f.file.spec.note.isEmpty { Text(f.file.spec.note).font(.caption).foregroundStyle(.secondary) }
                        if !f.sharedWith.isEmpty {
                            Text(
                                "Also read by "
                                    + f.sharedWith.compactMap { model.snapshot?.agent($0)?.adapter.name }.joined(separator: ", ")
                            )
                            .font(.caption).foregroundStyle(.orange)
                        }
                        if !f.blocks.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(f.blocks) { b in
                                    Pill(
                                        text: b.profile, color: b.isModifiedOutsideKitfold ? .orange : .purple,
                                        systemImage: b.isModifiedOutsideKitfold ? "pencil.and.outline" : "person.text.rectangle")
                                }
                            }
                        }
                        ForEach(f.driftedBlocks) { b in
                            HStack {
                                Text("“\(b.profile)” was edited here outside Kitfold.").font(.caption)
                                Button("Keep edit") { model.reviewKeepEdit(file: f.file.path, profile: b.profile) }
                                Button("Overwrite…") { model.reviewOverwrite(file: f.file.path) }
                            }
                            .controlSize(.small)
                        }
                        if !f.foreignBlocks.isEmpty {
                            Text("Contains blocks managed by \(f.foreignBlocks.joined(separator: ", ")) (left untouched).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(f.exists ? "Edit" : "Create") {
                        model.editingInstruction = .init(path: f.file.path, agents: [a.id] + f.sharedWith, scope: f.file.scope)
                    }
                    .controlSize(.small)
                    .disabled(f.file.path.hasPrefix("/Library/"))
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: discovery

    func discovery(_ a: AgentState) -> some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if let env = model.env {
                        ForEach(a.adapter.skillRoots(scope, env)) { r in
                            HStack(alignment: .top) {
                                Pill(text: r.spec.role.rawValue, color: r.spec.role == .primary ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.ab(r.path)).font(.caption.monospaced())
                                    Text(r.spec.note + (r.spec.verified ? "" : " (unverified)")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Divider()
                    ForEach(a.adapter.descriptor.notes, id: \.self) { n in
                        Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Agent documentation", destination: URL(string: a.adapter.descriptor.docsURL)!).font(.caption)
                }
                .padding(.top, 6)
            } label: {
                SectionTitle(title: "How \(a.adapter.name) finds skills", subtitle: "Folders scanned, highest precedence first")
            }
        }
    }
}

/// Searchable list of library skills to add to one agent.
struct AddSkillsPopover: View {
    @Environment(AppModel.self) private var model
    let agentID: AgentID
    let scope: Scope
    @State private var q = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search skills", text: $q).textFieldStyle(.roundedBorder)
            List {
                ForEach(candidates, id: \.self) { name in
                    Button {
                        model.toggle(skill: name, agent: agentID, scope: scope)
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if model.cell(skill: name, agent: agentID, scope: scope).willBeOn {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
        .padding(12)
        .frame(width: 320, height: 380)
    }

    var candidates: [String] {
        let names =
            model.snapshot?.catalog.filter {
                if case .bundled = $0.origin { return false }; return true
            }.map(\.name) ?? []
        let unique = Array(Set(names)).sorted()
        return q.isEmpty ? unique : unique.filter { $0.localizedCaseInsensitiveContains(q) }
    }
}
