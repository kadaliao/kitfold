import KitfoldCore
import SwiftUI

struct ProfilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            List(selection: $model.selectedProfileID) {
                ForEach(model.profiles) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(.body.weight(.medium))
                        if !p.description.isEmpty {
                            Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        HStack(spacing: 3) {
                            ForEach(model.managedAgents) { a in
                                let on = model.scopes.contains { model.profileState(p.id, agent: a.id, scope: $0).on }
                                if on { AgentBadge(adapter: a.adapter, size: 14) }
                            }
                            if !p.skills.isEmpty {
                                Pill(
                                    text: p.skills.count == 1 ? L("1 skill") : L("\(p.skills.count) skills"), systemImage: "sparkles")
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(p.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if model.profiles.isEmpty {
                    ContentUnavailableView {
                        Label(L("No profiles yet"), systemImage: "person.text.rectangle")
                    } description: {
                        Text(
                            L(
                                "A profile is a reusable set of instructions plus the skills that go with them — e.g. “Backend Developer” or “Code Reviewer”."
                            ))
                    } actions: {
                        Button(L("New Profile")) { model.showNewProfile = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        model.showNewProfile = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 300)  // last, so the bottom bar's Spacer can't widen the column

            Divider()

            Group {
                if let id = model.selectedProfileID, let p = model.profiles.first(where: { $0.id == id }) {
                    ProfileEditor(original: p).id(p.id + (p.modifiedAt?.description ?? ""))
                } else {
                    ContentUnavailableView(L("Select a profile"), systemImage: "person.text.rectangle")
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("Profiles"))
    }
}

struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    let original: ProfileEntry
    @State private var p: ProfileEntry
    @State private var tab: Tab = .edit
    @State private var compareWith: String = ""
    @State private var confirmDelete = false

    enum Tab: CaseIterable {
        case edit, preview, compare

        var title: String {
            switch self {
            case .edit: return L("Edit")
            case .preview: return L("Preview")
            case .compare: return L("Compare")
            }
        }
    }

    init(original: ProfileEntry) {
        self.original = original
        _p = State(initialValue: original)
    }

    var dirty: Bool { p != original }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    TextField(L("Name"), text: $p.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .textFieldStyle(.plain)
                    Spacer()
                    Button(L("Delete…"), role: .destructive) { confirmDelete = true }
                    Button(L("Save")) { model.saveProfile(p) }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .disabled(!dirty)
                }
                TextField(L("Short description"), text: $p.description).textFieldStyle(.roundedBorder)

                Card {
                    SectionTitle(
                        title: L("Assigned to"),
                        subtitle: L("Profiles are written into each agent's own instruction file, one marked block per profile."))
                    ProfileGrid(profileID: p.id)
                }

                Card {
                    SectionTitle(
                        title: L("Skills that come with it"), subtitle: L("Assigning the profile also gives the agent these skills."))
                    SkillChips(skills: $p.skills)
                }

                Card {
                    HStack {
                        Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.title) } }
                            .pickerStyle(.segmented).fixedSize()
                        Spacer()
                        Stepper(L("Order \(p.order)"), value: $p.order, in: 0...999, step: 10)
                            .help(L("When several profiles go to the same agent, lower order comes first."))
                            .fixedSize()
                    }
                    switch tab {
                    case .edit:
                        TextEditor(text: $p.body)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 340)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    case .preview:
                        MarkdownView(text: p.body)
                    case .compare:
                        compare
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog(L("Move “\(p.name)” to Kitfold's trash?"), isPresented: $confirmDelete) {
            Button(L("Move to Trash"), role: .destructive) { model.deleteProfile(p.id) }
        } message: {
            Text(L("Its assignments are removed from the draft; apply to take it out of agent files."))
        }
    }

    /// Compare the current text with the deployed copies and saved versions.
    struct CompareOption: Identifiable {
        var id: String
        var label: String
        var text: String
    }

    var compare: some View {
        var options: [CompareOption] = deployedCopies().map { file, body in
            CompareOption(id: "deployed:" + file, label: L("Deployed in \(model.ab(file))"), text: body)
        }
        for v in model.versionHistory(profile: p.id) {
            let when = v.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Localization.language.locale))
            options.append(
                CompareOption(
                    id: "version:" + v.path,
                    label: L("Saved \(when)"),
                    text: ProfileEntry.read(path: v.path)?.body ?? ""))
        }
        let selected = options.first { $0.id == compareWith } ?? options.first
        return VStack(alignment: .leading, spacing: 8) {
            if options.isEmpty {
                Text(L("Nothing to compare yet — it hasn't been deployed or saved before.")).foregroundStyle(.secondary)
            } else {
                Picker(L("Compare with"), selection: Binding(get: { selected?.id ?? "" }, set: { compareWith = $0 })) {
                    ForEach(options) { Text($0.label).tag($0.id) }
                }
                .fixedSize()
                if let s = selected {
                    DiffView(old: s.text, new: p.body, oldLabel: s.label, newLabel: L("This editor"))
                }
            }
        }
    }

    func deployedCopies() -> [(String, String)] {
        guard let snap = model.snapshot else { return [] }
        var seen = Set<String>()
        var out: [(String, String)] = []
        for a in snap.agents {
            for scope in snap.scopes {
                for f in a.state(scope).instructions {
                    for b in f.blocks where b.profile == p.id && seen.insert(f.file.path).inserted {
                        out.append((f.file.path, b.body))
                    }
                }
            }
        }
        return out
    }
}

struct ProfileGrid: View {
    @Environment(AppModel.self) private var model
    let profileID: String

    var body: some View {
        ScrollView(.horizontal) { grid.padding(.bottom, 4) }
    }

    var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(model.managedAgents) { a in AgentBadge(adapter: a.adapter, size: 20).gridColumnAlignment(.center) }
            }
            ForEach(model.scopes, id: \.self) { scope in
                GridRow {
                    Label(model.projectName(scope), systemImage: scope.isGlobal ? "globe" : "folder").lineLimit(1)
                    ForEach(model.managedAgents) { a in
                        let st = model.profileState(profileID, agent: a.id, scope: scope)
                        ReachCell(
                            state: CellState(
                                reach: st.on && !st.pending ? .kitfoldLink : .off,
                                rule: st.on ? .on : (st.pending ? .off : nil), pending: st.pending),
                            tint: a.adapter.tint
                        ) {
                            model.toggleProfile(profileID, agent: a.id, scope: scope)
                        }
                        .disabled(!canWrite(a, scope) && !st.on)
                        .help(targetHelp(a, scope))
                    }
                }
            }
        }
    }

    func canWrite(_ a: AgentState, _ scope: Scope) -> Bool {
        model.env.flatMap { a.adapter.primaryInstructionFile(scope, $0) } != nil
    }

    func targetHelp(_ a: AgentState, _ scope: Scope) -> String {
        guard let env = model.env, let f = a.adapter.primaryInstructionFile(scope, env) else {
            return L("\(a.adapter.name): Kitfold doesn't know an instruction file only it reads")
        }
        return L("\(a.adapter.name): written to \(model.ab(f))")
    }
}

/// Token-style editor for a list of skill names, with suggestions from the catalog.
struct SkillChips: View {
    @Environment(AppModel.self) private var model
    @Binding var skills: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(skills, id: \.self) { s in
                HStack(spacing: 4) {
                    Text(s)
                    Button {
                        skills.removeAll { $0 == s }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Menu {
                ForEach(model.snapshot?.skillNames.filter { !skills.contains($0) } ?? [], id: \.self) { n in
                    Button(n) { skills.append(n) }
                }
            } label: {
                Label(L("Add skill"), systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
