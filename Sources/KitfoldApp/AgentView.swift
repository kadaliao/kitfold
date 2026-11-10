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
                    if !agent.state(.global).instructions.isEmpty || !agent.state(scope).instructions.isEmpty {
                        instructions(agent)
                    }
                    discovery(agent)
                    let issues = snap.issues(for: agentID).filter { $0.scope == nil || $0.scope == scope }
                    if !issues.isEmpty {
                        Card {
                            SectionTitle(title: L("Issues"))
                            ForEach(issues) { IssueRow(issue: $0) }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(agent.adapter.name)
            .dropDestination(for: String.self) { names, _ in
                guard let a = model.snapshot?.agent(agentID) else { return false }
                model.drop(skills: names, on: a, scope: scope)
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
                    switch a.adapter.descriptor.source {
                    case .discovered:
                        Pill(text: L("found on this Mac"), color: .teal, systemImage: "sparkle.magnifyingglass")
                            .help(a.adapter.descriptor.notes.map { Localization.translate($0) }.joined(separator: "\n"))
                    case .custom: Pill(text: L("added by you"), color: .teal, systemImage: "person.crop.circle.badge.plus")
                    case .builtin, .catalog: EmptyView()
                    }
                }
                if let bin = inst.binaryPath {
                    PathLabel(path: bin)
                } else {
                    Text(
                        !inst.isDetected
                            ? L("Not detected on this Mac")
                            : !inst.isInstalled
                                ? L(
                                    "Only its folder is here: the app or command wasn't found, so Kitfold doesn't manage it unless you switch it on."
                                )
                                : a.adapter.descriptor.binaryNames.isEmpty || inst.marker != nil
                                    ? L("Found on this Mac") : L("CLI not found on PATH (config folder exists)")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                PathLabel(path: inst.configDir)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    Text(L("Showing")).foregroundStyle(.secondary)
                    ScopePicker(scope: $scope)
                }
                Toggle(
                    L("Managed by Kitfold"),
                    isOn: Binding(
                        get: { a.enabled },
                        set: { on in model.saveSettings { $0.agents[a.id.rawValue, default: AgentSettings()].enabled = on } })
                )
                .toggleStyle(.switch)
                VStack(alignment: .trailing, spacing: 2) {
                    let bytes = est.instructionBytes.formatted(.byteCount(style: .file).locale(Localization.language.locale))
                    Text(est.skillCount == 1 ? L("1 skill · \(bytes) instructions") : L("\(est.skillCount) skills · \(bytes) instructions"))
                        .font(.callout.monospacedDigit())
                    ContextMeter(tokens: est.approxTokens, tint: a.adapter.tint).frame(width: 220)
                }
            }
        }
    }

    // MARK: skills (agent perspective)

    enum SkillGroup: CaseIterable {
        case linked, local, shared, foreign, nested, project, plugins, disabled

        var title: String {
            switch self {
            case .linked: return L("Linked into its skills folder")
            case .local: return L("Folders inside its skills folder")
            case .shared: return L("From shared folders")
            case .foreign: return L("Through another agent's folder")
            case .nested: return L("Nested inside other skills")
            case .project: return L("Project skills")
            case .plugins: return L("From plugins")
            case .disabled: return L("Present, but switched off in its settings")
            }
        }
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

    /// One skill on the agent page: the way it reaches the agent, and the other folders it's also found in.
    struct SkillListing {
        var main: Reach
        var alsoIn: [String]
    }

    /// Each skill once, under the route that wins (the first active one, in precedence order; for a skill
    /// that's switched off, the first place it's found). The other folders are mentioned on its row.
    func listings(_ reach: [Reach]) -> [SkillListing] {
        var byName: [String: [Reach]] = [:]
        for r in reach { byName[r.skill.name, default: []].append(r) }
        return byName.values.map { found in
            let main = found.first(where: { $0.skill.isActive }) ?? found[0]
            var roots: [String] = []
            for r in found where r.skill.root.path != main.skill.root.path && !roots.contains(r.skill.root.path) {
                roots.append(r.skill.root.path)
            }
            return SkillListing(main: main, alsoIn: roots)
        }
    }

    func skills(_ a: AgentState, _ snap: Snapshot) -> some View {
        let reach = a.reachableSkills(in: scope).filter { $0.skill.isReadable }
        let q = filter.lowercased()
        let filtered = reach.filter { q.isEmpty || $0.skill.name.lowercased().contains(q) }
        let groups = Dictionary(grouping: listings(filtered), by: { group($0.main) })
        // Only a managed agent gets what its rules ask for.
        let pendingAdds = model.draft.rules.filter {
            a.enabled && $0.resource.kind == .skill && $0.scope == scope && $0.state == .on
                && ($0.agent == .all || $0.agent == .agent(agentID))
        }.map(\.resource.id).filter { n in !reach.contains { $0.skill.name == n } }
        let subtitle =
            scope.isGlobal
            ? L("What \(a.adapter.name) loads everywhere, grouped by how it gets there. Drop skills here to add them.")
            : L("What \(a.adapter.name) loads in \(model.projectName(scope)), grouped by how it gets there. Drop skills here to add them.")

        return Card {
            HStack {
                SectionTitle(title: L("Skills"), subtitle: subtitle)
                TextField(L("Filter"), text: $filter).textFieldStyle(.roundedBorder).frame(width: 160)
                Button {
                    showAdd = true
                } label: {
                    Label(L("Add"), systemImage: "plus")
                }
                .popover(isPresented: $showAdd, arrowEdge: .bottom) { AddSkillsPopover(agentID: agentID, scope: scope) }
            }
            if !pendingAdds.isEmpty {
                ForEach(pendingAdds, id: \.self) { n in
                    skillRow(name: n, path: nil, a: a, note: L("will be added"))
                }
            }
            ForEach(SkillGroup.allCases, id: \.self) { g in
                if let items = groups[g], !items.isEmpty {
                    DisclosureGroup(isExpanded: Binding(get: { expanded[g] ?? (items.count <= 6) }, set: { expanded[g] = $0 })) {
                        ForEach(items.sorted { $0.main.skill.name < $1.main.skill.name }, id: \.main.skill.id) { item in
                            let r = item.main
                            skillRow(
                                name: r.skill.name, path: r.skill.entryPath, a: a,
                                note: r.skill.isSymlink ? r.skill.linkTarget.map { "→ " + model.ab($0) } : nil,
                                alsoIn: item.alsoIn)
                        }
                    } label: {
                        HStack {
                            Text(g.title).font(.callout.weight(.medium))
                            Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            let roots = Set(items.map { $0.main.skill.root.path })
                            if roots.count == 1, let root = roots.first, g != .plugins, g != .nested {
                                Text(model.ab(root)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    func skillRow(name: String, path: String?, a: AgentState, note: String?, alsoIn: [String] = []) -> some View {
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
            .contextMenu {
                if let e = entry(name: name, path: path) {
                    Button(L("Reveal in Finder")) { model.reveal(e.path) }
                    Divider()
                    DeleteSkillButton(entry: e)
                }
            }
            if let note { Text(note).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            if !alsoIn.isEmpty {
                Text(L("also in \(Localization.list(alsoIn.map(model.ab)))"))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    .help(L("The agent finds the same skill in these folders too."))
            }
            Spacer()
            let native = a.reachableSkills(in: scope).first(where: { $0.skill.name == name })?.skill.native ?? .enabled
            if case .disabled(let src, let byKitfold) = native {
                Text(byKitfold ? L("hidden by Kitfold in \(src)") : L("off in \(src)")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }

    /// The folder this row stands for (resolved), else the library's copy of the name.
    func entry(name: String, path: String?) -> SkillEntry? {
        guard let snap = model.snapshot else { return nil }
        if let path, let real = FS.realPath(path), let e = snap.catalog.first(where: { $0.path == real }) { return e }
        return snap.skill(named: name)
    }

    // MARK: profiles

    func profiles(_ a: AgentState) -> some View {
        Card {
            SectionTitle(title: L("Profiles"), subtitle: profileTarget(a))
            if model.profiles.isEmpty && model.env.flatMap({ a.adapter.primaryInstructionFile(scope, $0) }) != nil {
                HStack {
                    Text(L("No profiles yet.")).foregroundStyle(.secondary)
                    Button(L("Create one…")) { model.showNewProfile = true }.buttonStyle(.link)
                }
            }
            ForEach(model.env.flatMap { a.adapter.primaryInstructionFile(scope, $0) } == nil ? [] : model.profiles) { p in
                let st = model.profileState(p.id, agent: a.id, scope: scope)
                Toggle(isOn: Binding(get: { st.on }, set: { _ in model.toggleProfile(p.id, agent: a.id, scope: scope) })) {
                    HStack {
                        Text(p.name)
                        if !p.skills.isEmpty {
                            Pill(text: p.skills.count == 1 ? L("+1 skill") : L("+\(p.skills.count) skills"), systemImage: "sparkles")
                        }
                        if st.pending { Pill(text: L("pending"), color: .accentColor) }
                        Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    func profileTarget(_ a: AgentState) -> String {
        guard let env = model.env, let f = a.adapter.primaryInstructionFile(scope, env) else {
            return L("Kitfold doesn't know an instruction file that only \(a.adapter.name) reads, so profiles can't be given to it.")
        }
        return L("Kitfold writes assigned profiles to \(model.ab(f)).")
    }

    // MARK: instructions

    func instructions(_ a: AgentState) -> some View {
        Card {
            SectionTitle(title: L("Instruction files"), subtitle: L("In load order. Only loaded files reach the model."))
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
                                Pill(text: L("loaded"), color: .green)
                            } else if f.exists {
                                Pill(text: L("not loaded"), color: .orange)
                            }
                            if f.file.spec.role == .primary { Pill(text: L("Kitfold target"), color: .accentColor) }
                            if f.file.spec.role == .fallback { Pill(text: L("fallback")) }
                            if f.isSymlink { Pill(text: L("symlink"), systemImage: "link") }
                            if f.exists {
                                Text(f.byteCount.formatted(.byteCount(style: .file).locale(Localization.language.locale))).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !f.file.spec.note.isEmpty {
                            Text(Localization.translate(f.file.spec.note)).font(.caption).foregroundStyle(.secondary)
                        }
                        if !f.sharedWith.isEmpty {
                            let names = Localization.list(f.sharedWith.compactMap { model.snapshot?.agent($0)?.adapter.name })
                            Text(L("Also read by \(names)")).font(.caption).foregroundStyle(.orange)
                        }
                        if !f.blocks.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(f.blocks) { b in
                                    Pill(
                                        text: model.snapshot?.profileName(b.profile) ?? b.profile,
                                        color: b.isModifiedOutsideKitfold ? .orange : .purple,
                                        systemImage: b.isModifiedOutsideKitfold ? "pencil.and.outline" : "person.text.rectangle")
                                }
                            }
                        }
                        ForEach(f.driftedBlocks) { b in
                            HStack {
                                Text(L("“\(model.snapshot?.profileName(b.profile) ?? b.profile)” was edited here outside Kitfold.")).font(
                                    .caption)
                                Button(L("Keep edit")) { model.reviewKeepEdit(file: f.file.path, profile: b.profile) }
                                Button(L("Overwrite…")) { model.reviewOverwrite(file: f.file.path) }
                            }
                            .controlSize(.small)
                        }
                        if !f.foreignBlocks.isEmpty {
                            let owners = Localization.list(f.foreignBlocks)
                            Text(L("Contains blocks managed by \(owners) (left untouched)."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(f.exists ? L("Edit") : L("Create")) {
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

    func roleLabel(_ role: SkillRootSpec.Role) -> String {
        switch role {
        case .primary: return L("primary")
        case .shared: return L("shared")
        case .foreign: return L("foreign")
        case .bundled: return L("bundled")
        }
    }

    func discovery(_ a: AgentState) -> some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if let env = model.env {
                        ForEach(a.adapter.skillRoots(scope, env)) { r in
                            HStack(alignment: .top) {
                                Pill(text: roleLabel(r.spec.role), color: r.spec.role == .primary ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.ab(r.path)).font(.caption.monospaced())
                                    Text(Localization.translate(r.spec.note) + (r.spec.verified ? "" : L(" (unverified)"))).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Divider()
                    ForEach(a.adapter.descriptor.notes, id: \.self) { n in
                        Label(Localization.translate(n), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if let url = URL(string: a.adapter.descriptor.docsURL), !a.adapter.descriptor.docsURL.isEmpty {
                        Link(L("Agent documentation"), destination: url).font(.caption)
                    }
                }
                .padding(.top, 6)
            } label: {
                SectionTitle(title: L("How \(a.adapter.name) finds skills"), subtitle: L("Folders scanned, highest precedence first"))
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
            TextField(L("Search skills"), text: $q).textFieldStyle(.roundedBorder)
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
