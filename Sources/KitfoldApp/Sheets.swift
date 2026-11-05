import KitfoldCore
import SwiftUI

/// Edit any instruction file. Saving shows the diff first, then applies through the journal (undoable).
struct InstructionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: AppModel.InstructionTarget
    @State private var text = ""
    @State private var original = ""
    @State private var reviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((target.path as NSString).lastPathComponent).font(.title3.weight(.semibold))
                    Text(model.ab(target.path)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(target.agents, id: \.self) { id in
                        if let a = model.snapshot?.agent(id) { AgentBadge(adapter: a.adapter, size: 18) }
                    }
                }
            }
            .padding(16)
            if !ManagedBlock.findAll(in: original).isEmpty {
                Label(
                    L(
                        "Parts of this file are Kitfold profile blocks. Edit those in Profiles; changes made here are detected and won't be overwritten silently."
                    ), systemImage: "person.text.rectangle"
                )
                .font(.caption).foregroundStyle(.purple)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            let foreign = ManagedBlock.foreignBlocks(in: original)
            if !foreign.isEmpty {
                Label(
                    L("Contains blocks written by \(foreign.joined(separator: ", ")). That tool may rewrite them."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption).foregroundStyle(.orange)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()
            if reviewing {
                ScrollView { DiffView(old: original, new: text, oldLabel: L("on disk"), newLabel: L("your edit")).padding(16) }
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
            }
            Divider()
            HStack {
                Text(
                    original.isEmpty && !FS.exists(target.path)
                        ? L("New file") : text.utf8.count.formatted(.byteCount(style: .file).locale(Localization.language.locale))
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                if reviewing {
                    Button(L("Back to Editing")) { reviewing = false }
                    Button(L("Apply")) {
                        guard let ws = model.workspace else { return }
                        let plan = ws.planEdit(path: target.path, newText: text, agents: target.agents, scope: target.scope)
                        model.perform(plan, summary: L("Edit \(model.ab(target.path))"), keepDraft: true)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Review…")) { reviewing = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                        .disabled(text == original)
                }
            }
            .padding(14)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            original = FS.read(target.path) ?? ""
            text = original
        }
    }
}

struct NewItemSheet: View {
    enum Kind { case profile, skill }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .profile ? L("New Profile") : L("New Skill")).font(.title3.weight(.semibold))
            Text(
                kind == .profile
                    ? L("A reusable set of instructions (and skills) you can give to any agent or project.")
                    : L("Creates a SKILL.md in the Kitfold library. It isn't given to any agent until you assign it.")
            )
            .font(.callout).foregroundStyle(.secondary)
            TextField(kind == .profile ? L("Name (e.g. Backend Developer)") : L("Name (e.g. release-notes)"), text: $name)
                .textFieldStyle(.roundedBorder)
            TextField(
                kind == .profile ? L("Short description") : L("When should an agent use it?"), text: $description, axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Create")) {
                    if kind == .profile {
                        model.createProfile(name: name, description: description)
                    } else {
                        model.createSkill(name: name, description: description)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// ⌘K: jump to anything or run an action, keyboard only.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let run: @MainActor () -> Void
    }

    var items: [Item] {
        var out: [Item] = [
            Item(id: "a:review", title: L("Review changes"), subtitle: L("Action"), symbol: "checklist") { model.showReview = true },
            Item(id: "a:rescan", title: L("Rescan"), subtitle: L("Action"), symbol: "arrow.clockwise") { model.rescan() },
            Item(id: "a:profile", title: L("New profile"), subtitle: L("Action"), symbol: "person.text.rectangle") {
                model.showNewProfile = true
            },
            Item(id: "a:skill", title: L("New skill"), subtitle: L("Action"), symbol: "sparkles") { model.showNewSkill = true },
            Item(id: "a:dash", title: L("Dashboard"), subtitle: L("Go to"), symbol: "square.grid.2x2") { model.selection = .dashboard },
            Item(id: "a:history", title: L("History"), subtitle: L("Go to"), symbol: "clock.arrow.circlepath") {
                model.selection = .history
            },
        ]
        for a in model.agents {
            out.append(
                Item(id: "g:" + a.id.rawValue, title: a.adapter.name, subtitle: L("Agent"), symbol: "cpu") {
                    model.selection = .agent(a.id)
                })
        }
        for p in model.draft.projects {
            out.append(
                Item(id: "p:" + p.path, title: p.name, subtitle: L("Project · \(model.ab(p.path))"), symbol: "folder") {
                    model.selection = .project(p.path)
                })
        }
        for p in model.profiles {
            out.append(
                Item(id: "r:" + p.id, title: p.name, subtitle: L("Profile"), symbol: "person.text.rectangle") {
                    model.selectedProfileID = p.id
                    model.selection = .profiles
                })
        }
        for e in model.snapshot?.catalog ?? [] {
            out.append(
                Item(id: "s:" + e.path, title: e.name, subtitle: L("Skill · \(e.origin.label)"), symbol: "sparkles") {
                    model.selectedSkillPath = e.path
                    model.selection = .skills
                })
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(out.prefix(12)) }
        // Match the text as shown, in either language; full-width letters typed through a Chinese input method count too.
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        func starts(_ s: String) -> Bool { s.range(of: q, options: options.union(.anchored)) != nil }
        return out.filter { $0.title.range(of: q, options: options) != nil || $0.subtitle.range(of: q, options: options) != nil }
            .sorted { (starts($0.title) ? 0 : 1) < (starts($1.title) ? 0 : 1) }
            .prefix(40).map { $0 }
    }

    var body: some View {
        let list = items
        ZStack(alignment: .top) {
            Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Search skills, profiles, agents, projects, actions"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit { run(list) }
                }
                .padding(14)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { item in
                                let it = item.element
                                HStack(spacing: 10) {
                                    Image(systemName: it.symbol).frame(width: 18).foregroundStyle(.secondary)
                                    Text(it.title)
                                    Spacer()
                                    Text(it.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    item.offset == index ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    index = item.offset; run(list)
                                }
                                .id(item.offset)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: index) { proxy.scrollTo(index) }
                }
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 24, y: 8)
            .padding(.top, 70)
        }
        .onAppear {
            focused = true; index = 0
        }
        .onChange(of: query) { index = 0 }
        .onKeyPress(.downArrow) {
            index = min(index + 1, max(list.count - 1, 0)); return .handled
        }
        .onKeyPress(.upArrow) {
            index = max(index - 1, 0); return .handled
        }
        .onKeyPress(.escape) {
            close(); return .handled
        }
    }

    func run(_ list: [Item]) {
        guard list.indices.contains(index) else { return }
        let item = list[index]
        close()
        item.run()
    }

    func close() {
        model.showPalette = false
        query = ""
    }
}

struct ProjectView: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var showMatrix = true

    var scope: Scope { .project(path) }

    var body: some View {
        if let snap = model.snapshot {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.projectName(scope)).font(.system(size: 22, weight: .semibold, design: .rounded))
                            Spacer()
                            Button(L("Remove from Kitfold")) { model.removeProject(path) }.controlSize(.small)
                        }
                        PathLabel(path: path)
                        Text(
                            L(
                                "Agents load their global setup everywhere. Assignments here add skills and profiles for this project only, in folders only that agent reads. Kitfold keeps its files here out of git via .git/info/exclude."
                            )
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            ForEach(snap.managedAgents) { a in
                                let local = a.state(scope).effectiveSkills.count
                                let est = snap.contextEstimate(agent: a.id, scope: scope)
                                Card {
                                    HStack {
                                        AgentBadge(adapter: a.adapter, size: 22)
                                        Text(a.adapter.name).font(.headline)
                                    }
                                    Text(
                                        est.skillCount == 1
                                            ? L("1 skill here (\(local) project-only)")
                                            : L("\(est.skillCount) skills here (\(local) project-only)")
                                    )
                                    .font(.callout)
                                    let files = a.state(scope).loadedInstructions
                                    ForEach(files) { f in
                                        HStack {
                                            Image(systemName: "doc.text.fill").foregroundStyle(a.adapter.tint)
                                            Text(FS.relativePath(from: path, to: f.file.path)).font(.caption.monospaced())
                                            Spacer()
                                            Button(L("Edit")) {
                                                model.editingInstruction = .init(
                                                    path: f.file.path, agents: [a.id] + f.sharedWith, scope: scope)
                                            }
                                            .controlSize(.mini)
                                        }
                                    }
                                    if files.isEmpty { Text(L("No project instruction files")).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        let issues = snap.issues.filter { $0.scope == scope }
                        if !issues.isEmpty {
                            Card {
                                SectionTitle(title: L("Issues in this project"))
                                ForEach(issues) { IssueRow(issue: $0) }
                            }
                        }
                        Card {
                            SectionTitle(title: L("Profiles for this project"))
                            ProjectProfiles(scope: scope)
                        }
                    }
                    .padding(20)
                }
                .frame(minHeight: showMatrix ? 220 : nil, maxHeight: showMatrix ? 420 : .infinity)
                Divider()
                // Not a DisclosureGroup: it sizes its content to fit, so the matrix would stop scrolling and
                // push the page past the window.
                Button {
                    withAnimation(.snappy) { showMatrix.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showMatrix ? 90 : 0))
                        Text(L("Skills in this project")).font(.headline)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if showMatrix {
                    AssignmentMatrix(scope: scope, names: snap.skillNames)
                        .padding(.horizontal, 16)
                }
            }
            .navigationTitle(model.projectName(scope))
        }
    }
}

struct ProjectProfiles: View {
    @Environment(AppModel.self) private var model
    let scope: Scope

    var body: some View {
        if model.profiles.isEmpty {
            Text(L("No profiles yet.")).foregroundStyle(.secondary)
        }
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(model.managedAgents) { a in AgentBadge(adapter: a.adapter, size: 18).gridColumnAlignment(.center) }
            }
            ForEach(model.profiles) { p in
                GridRow {
                    Text(p.name)
                    ForEach(model.managedAgents) { a in
                        let st = model.profileState(p.id, agent: a.id, scope: scope)
                        ReachCell(
                            state: CellState(
                                reach: st.on && !st.pending ? .kitfoldLink : .off,
                                rule: st.on ? .on : (st.pending ? .off : nil), pending: st.pending),
                            tint: a.adapter.tint
                        ) { model.toggleProfile(p.id, agent: a.id, scope: scope) }
                    }
                }
            }
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirm: TransactionRecord?

    var body: some View {
        let history = model.history
        List {
            if history.isEmpty {
                ContentUnavailableView(
                    L("No changes yet"), systemImage: "clock.arrow.circlepath",
                    description: Text(L("Everything Kitfold applies shows up here and can be undone.")))
            }
            ForEach(history) { tx in
                DisclosureGroup {
                    ForEach(tx.operations) { op in
                        HStack {
                            Text(op.summary).font(.callout)
                            Spacer()
                            if let b = op.backupPath {
                                Button(L("Backup")) { model.reveal(b) }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(tx.summary).font(.body.weight(.medium))
                                if tx.kind == "undo" { Pill(text: L("undo"), systemImage: "arrow.uturn.backward") }
                                if tx.undoneBy != nil { Pill(text: L("undone"), color: .secondary) }
                            }
                            Text(details(tx))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if tx.canUndo {
                            Button(L("Undo…")) { confirm = tx }.controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
        .navigationTitle(L("History"))
        .confirmationDialog(
            L("Undo “\(confirm?.summary ?? "")”?"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })
        ) {
            Button(L("Undo")) { if let c = confirm { model.undo(c) } }
        } message: {
            Text(L("Kitfold checks every file first. If one was changed since, nothing is undone and you'll see which."))
        }
    }

    /// "5 Nov 2026, 14:03:07 · 3 operations", in the app's language.
    func details(_ tx: TransactionRecord) -> String {
        let when = tx.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: Localization.language.locale))
        let n = tx.operations.count
        return when + " · " + (n == 1 ? L("1 operation") : L("\(n) operations"))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            general.tabItem { Label(L("General"), systemImage: "gearshape") }
            agents.tabItem { Label(L("Agents"), systemImage: "cpu") }
            sources.tabItem { Label(L("Sources"), systemImage: "tray.full") }
        }
        .padding(20)
    }

    var general: some View {
        Form {
            Section {
                Picker(L("Language"), selection: Binding(get: { LanguageSettings.chosen }, set: { model.setLanguage($0) })) {
                    Text(L("Same as macOS (\(LanguageSettings.system.nativeName))")).tag(Language?.none)
                    ForEach(Language.allCases) { l in Text(l.nativeName).tag(Language?.some(l)) }
                }
            } footer: {
                Text(L("Menus that come from macOS switch the next time Kitfold opens."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let env = model.env {
                LabeledContent(L("Kitfold folder")) { PathLabel(path: env.kitfoldHome) }
                LabeledContent(L("Assignments")) { PathLabel(path: env.configFile) }
                LabeledContent(L("History & backups")) { PathLabel(path: env.backupsDir) }
            }
            Toggle(
                L("Keep Kitfold's project files out of git (.git/info/exclude)"),
                isOn: Binding(
                    get: { model.draft.preferences.gitExcludeProjectFiles },
                    set: { v in
                        var c = model.draft; c.preferences.gitExcludeProjectFiles = v; model.saveDirect(c)
                    }))
            let days = model.draft.preferences.backupRetentionDays
            Stepper(
                days == 1 ? L("Keep backups for 1 day") : L("Keep backups for \(days) days"),
                value: Binding(
                    get: { model.draft.preferences.backupRetentionDays },
                    set: { v in
                        var c = model.draft; c.preferences.backupRetentionDays = v; model.saveDirect(c)
                    }), in: 1...365)
        }
        .formStyle(.grouped)
    }

    var agents: some View {
        Form {
            ForEach(model.agents) { a in
                Section {
                    Toggle(
                        L("Managed by Kitfold"),
                        isOn: Binding(
                            get: { a.enabled },
                            set: { on in
                                var c = model.draft
                                var s = c.agents[a.id.rawValue] ?? AgentSettings()
                                s.enabled = on
                                c.agents[a.id.rawValue] = s
                                model.saveDirect(c)
                            }))
                    ConfigDirField(agent: a)
                } header: {
                    HStack {
                        AgentBadge(adapter: a.adapter, size: 16); Text(a.adapter.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    var sources: some View {
        Form {
            Section(L("Skill folders Kitfold reads in place")) {
                ForEach(model.draft.sources) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.label)
                            Text(s.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let m = s.managedBy { Pill(text: m) }
                        Spacer()
                        Button(role: .destructive) {
                            model.removeSource(s.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Text(L("The Kitfold library (~/.kitfold/library) is always included. Removing a source never deletes files."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct ConfigDirField: View {
    @Environment(AppModel.self) private var model
    let agent: AgentState
    @State private var text = ""

    var body: some View {
        HStack {
            TextField(L("Config folder"), text: $text, prompt: Text(agent.adapter.descriptor.configDir))
            Button(L("Use")) {
                var c = model.draft
                var s = c.agents[agent.id.rawValue] ?? AgentSettings()
                s.configDir = text.isEmpty ? nil : text
                c.agents[agent.id.rawValue] = s
                model.saveDirect(c)
            }
        }
        .onAppear { text = model.draft.agents[agent.id.rawValue]?.configDir ?? "" }
    }
}
