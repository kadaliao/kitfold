import KitfoldCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var showGitSheet = false
    /// Kept in the model: a skill dropped on an agent in the sidebar goes to this scope.
    var scope: Scope { model.skillsScope }

    enum Mode: CaseIterable {
        case list, matrix

        var label: String {
            switch self {
            case .list: return L("List")
            case .matrix: return L("Matrix")
            }
        }
    }
    enum Filter: CaseIterable {
        case all, library, sources, local, plugins, problems

        var label: String {
            switch self {
            case .all: return L("All")
            case .library: return L("Library")
            case .sources: return L("Sources")
            case .local: return L("Local folders")
            case .plugins: return L("Plugins")
            case .problems: return L("With problems")
            }
        }
    }

    var entries: [SkillEntry] {
        guard let snap = model.snapshot else { return [] }
        let q = search.lowercased()
        return snap.catalog.filter { e in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .library: matchesFilter = e.origin == .library
            case .sources: if case .source = e.origin { matchesFilter = true } else { matchesFilter = false }
            case .local:
                matchesFilter = {
                    if case .agentLocal = e.origin { return true }; if case .external = e.origin { return true }; return false
                }()
            case .plugins: if case .bundled = e.origin { matchesFilter = true } else { matchesFilter = false }
            case .problems: matchesFilter = !e.problems.isEmpty
            }
            return matchesFilter && (q.isEmpty || e.name.lowercased().contains(q) || e.description.lowercased().contains(q))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker(
                    "", selection: Binding(get: { model.skillsMatrix ? Mode.matrix : .list }, set: { model.skillsMatrix = $0 == .matrix })
                ) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented).fixedSize()
                ScopePicker(scope: $model.skillsScope)
                Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.label) } }
                    .fixedSize()
                Spacer()
                TextField(L("Filter skills"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Menu {
                    Button(L("New Skill…")) { model.showNewSkill = true }
                    Button(L("Import Folder…")) { importFolder() }
                    Divider()
                    Button(L("Add Source Folder…")) { addSourceFolder() }
                    Button(L("Add Git Repository…")) { showGitSheet = true }
                } label: {
                    Label(L("Add"), systemImage: "plus")
                }
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()

            if model.skillsMatrix {
                AssignmentMatrix(scope: scope, names: uniqueNames(entries))
            } else {
                HSplitView {
                    List(selection: $model.selectedSkillPath) {
                        ForEach(entries) { e in
                            SkillRow(entry: e, scope: scope).tag(e.path)
                                .draggable(e.name)  // drop onto an agent in the sidebar to assign
                                .contextMenu {
                                    Button(L("Reveal in Finder")) { model.reveal(e.path) }
                                    Divider()
                                    DeleteSkillButton(entry: e)
                                }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 280, idealWidth: 330, maxWidth: 460)
                    .overlay {
                        if entries.isEmpty { ContentUnavailableView.search(text: search) }
                    }

                    Group {
                        if let path = model.selectedSkillPath, let e = model.snapshot?.catalog.first(where: { $0.path == path }) {
                            SkillDetail(entry: e).id(e.path)
                        } else {
                            ContentUnavailableView(
                                L("Select a skill"), systemImage: "sparkles",
                                description: Text(L("Choose which agents and projects get it.")))
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(L("Skills"))
        .sheet(isPresented: $showGitSheet) { GitSourceSheet() }
    }

    func uniqueNames(_ list: [SkillEntry]) -> [String] {
        var seen = Set<String>()
        return list.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = L("Choose a skill folder (it must contain SKILL.md). It's copied into the library.")
        if panel.runModal() == .OK, let url = panel.url { model.importSkillFolder(url) }
    }

    func addSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = L("Choose a folder of skills. Kitfold reads it in place.")
        if panel.runModal() == .OK, let url = panel.url { model.addSourceFolder(url) }
    }
}

struct ScopePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var scope: Scope

    var body: some View {
        Picker("", selection: $scope) {
            Label(L("Global"), systemImage: "globe").tag(Scope.global)
            ForEach(model.draft.projects) { p in
                Label(p.name, systemImage: "folder").tag(Scope.project(p.path))
            }
        }
        .fixedSize()
        .help(L("Which scope the agent dots and the matrix show"))
    }
}

struct SkillRow: View {
    @Environment(AppModel.self) private var model
    let entry: SkillEntry
    let scope: Scope

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.origin.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                    if !entry.problems.isEmpty {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).imageScale(.small)
                    }
                }
                Text(entry.description.isEmpty ? L("No description") : entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 3) {
                    ForEach(model.managedAgents) { a in
                        let c = model.cell(skill: entry.name, agent: a.id, scope: scope)
                        Circle()
                            .fill(c.willBeOn ? a.adapter.tint : Color.secondary.opacity(0.18))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(a.adapter.tint, lineWidth: c.pending ? 1.5 : 0).frame(width: 10, height: 10))
                            .help(c.willBeOn ? L("\(a.adapter.name): on") : L("\(a.adapter.name): off"))
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Agents × scopes grid for one skill: one row per agent, one column per scope (global, then each
/// project), so it stays readable however many agents there are.
struct AvailabilityGrid: View {
    @Environment(AppModel.self) private var model
    let skill: String
    var editable = true

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(model.scopes, id: \.self) { scope in
                        Menu {
                            Button(L("All agents on")) { model.setAll(skill: skill, scope: scope, on: true) }
                            Button(L("All agents off")) { model.setAll(skill: skill, scope: scope, on: false) }
                            Button(L("Clear (leave as found)")) {
                                model.draft.setAll(ResourceRef(.skill, skill), scope: scope, state: nil)
                                model.replan()
                            }
                        } label: {
                            Label(model.projectName(scope), systemImage: scope.isGlobal ? "globe" : "folder").lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .frame(maxWidth: 160)
                        .disabled(!editable)
                        .help(L("Switch it for every agent at once"))
                        .gridColumnAlignment(.center)
                    }
                }
                ForEach(model.managedAgents) { a in
                    GridRow {
                        HStack(spacing: 6) {
                            AgentBadge(adapter: a.adapter, size: 18)
                            Text(a.adapter.name).lineLimit(1)
                        }
                        .frame(minWidth: 150, alignment: .leading)
                        ForEach(model.scopes, id: \.self) { scope in
                            ReachCell(state: model.cell(skill: skill, agent: a.id, scope: scope), tint: a.adapter.tint) {
                                model.toggle(skill: skill, agent: a.id, scope: scope)
                            }
                            .disabled(!editable)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

struct ReachLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legend("checkmark", L("Linked"))
            legend("square.stack.3d.up", L("Shared folder"))
            legend("arrow.turn.down.right", L("Via another agent"))
            legend("arrow.down", L("From global"))
            legend("nosign", L("Off in agent settings"))
            legend("plus", L("Pending"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    func legend(_ s: String, _ t: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: s); Text(t)
        }
    }
}

struct SkillDetail: View {
    @Environment(AppModel.self) private var model
    let entry: SkillEntry
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Card {
                    SectionTitle(
                        title: L("Who gets it"),
                        subtitle: L("Click a cell to switch it. Nothing changes on disk until you review and apply."))
                    if case .bundled = entry.origin {
                        Text(L("Plugin skills are switched on and off in the agent's plugin settings.")).font(.callout).foregroundStyle(
                            .secondary)
                    } else {
                        AvailabilityGrid(skill: entry.name)
                        ReachLegend()
                    }
                }
                loadedFrom
                if !entry.problems.isEmpty || sameName.count > 1 { problems }
                skillFile
            }
            .padding(20)
        }
    }

    var sameName: [SkillEntry] { model.snapshot?.skillEntries(named: entry.name) ?? [] }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name).font(.system(size: 22, weight: .semibold, design: .rounded))
                Pill(
                    text: entry.origin.label, color: entry.origin == .library ? .accentColor : .secondary, systemImage: entry.origin.symbol)
                if case .source(let id) = entry.origin, let s = model.draft.sources.first(where: { $0.id == id }) {
                    Pill(text: s.managedBy.map { "\(s.displayLabel) · \($0)" } ?? s.displayLabel)
                }
                Spacer(minLength: 0)
            }
            if !entry.description.isEmpty {
                Text(entry.description).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6)
            }
            HStack {
                PathLabel(path: entry.path)
                Spacer()
                actions
            }
        }
    }

    @ViewBuilder var actions: some View {
        HStack {
            if entry.origin != .library, entry.origin.isEditable, !entry.origin.isNested {
                Button {
                    model.reviewAdopt(entry)
                } label: {
                    Label(L("Move into Library"), systemImage: "tray.and.arrow.down")
                }
                .help(L("Move this folder into Kitfold's library and leave a link behind, so it can be assigned per agent."))
            }
            Button {
                model.openInEditor(entry.skillFile)
            } label: {
                Label(L("Open"), systemImage: "square.and.pencil")
            }
            DeleteSkillButton(entry: entry, withIcon: true)
        }
        .controlSize(.small)
        .fixedSize()
    }

    var loadedFrom: some View {
        Card {
            SectionTitle(title: L("Where agents load it from"), subtitle: L("Global scope, in each agent's precedence order"))
            let rows = model.managedAgents.flatMap { a in
                (model.snapshot?.exposures(skill: entry.name, agent: a.id, scope: .global) ?? []).map { (a, $0) }
            }
            if rows.isEmpty {
                Text(L("No agent loads it yet.")).foregroundStyle(.secondary).font(.callout)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                let a = item.element.0
                let ex = item.element.1
                HStack(spacing: 8) {
                    AgentBadge(adapter: a.adapter, size: 16)
                    Text(model.ab(ex.observed.entryPath)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    if let t = ex.observed.linkTarget {
                        Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(.tertiary)
                        Text(model.ab(t)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    viaPill(ex)
                }
            }
        }
    }

    func viaPill(_ ex: Exposure) -> some View {
        if case .disabled(let src, let byKitfold) = ex.observed.native {
            return Pill(text: byKitfold ? L("hidden by Kitfold in \(src)") : L("off in \(src)"), color: .secondary, systemImage: "nosign")
        }
        if ex.observed.realPath != entry.path { return Pill(text: L("different folder"), color: .orange) }
        switch ex.via {
        case .link(let owned): return Pill(text: owned ? L("Kitfold link") : L("link"), color: .accentColor)
        case .localFolder: return Pill(text: L("local folder"))
        case .sharedDir: return Pill(text: L("shared folder"), color: .teal)
        case .foreignDir: return Pill(text: L("via another agent"), color: .teal)
        case .bundled: return Pill(text: L("plugin"))
        case .nested(let parent): return Pill(text: L("inside \(parent)"), color: .teal)
        }
    }

    var problems: some View {
        Card {
            SectionTitle(title: L("Problems"))
            ForEach(entry.problems, id: \.self) { p in
                Label(p, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
            }
            if sameName.count > 1 {
                Label(
                    L("\(sameName.count) folders are named “\(entry.name)”. Agents pick one; Kitfold assigns the library copy first."),
                    systemImage: "square.on.square"
                ).font(.callout)
                ForEach(sameName.filter { $0.path != entry.path }) { other in PathLabel(path: other.path) }
            }
        }
    }

    var skillFile: some View {
        Card {
            HStack {
                SectionTitle(title: "SKILL.md")
                if entry.origin.isEditable {
                    if editing {
                        Button(L("Cancel")) { editing = false }
                        Button(L("Save")) {
                            model.saveSkillFile(entry, text: text)
                            editing = false
                        }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(L("Edit")) {
                            text = FS.read(entry.skillFile) ?? ""; editing = true
                        }
                    }
                }
            }
            if editing {
                if let owner = model.workspace?.managingTool(for: entry) {
                    Label(
                        L("\(owner) manages this folder; its next update may replace your edits."), systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 320)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            } else {
                MarkdownView(text: entry.frontmatter.body)
            }
        }
    }
}

/// Skill × agent grid for one scope. The fastest way to see and set everything at once.
struct AssignmentMatrix: View {
    @Environment(AppModel.self) private var model
    let scope: Scope
    let names: [String]
    @State private var onlyActive = false
    static let nameWidth: CGFloat = 240
    static let columnWidth: CGFloat = 92

    var rows: [String] {
        guard onlyActive else { return names }
        return names.filter { n in model.managedAgents.contains { model.cell(skill: n, agent: $0.id, scope: scope).willBeOn } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle(L("Only skills that reach an agent"), isOn: $onlyActive).toggleStyle(.checkbox)
                Spacer()
                ReachLegend()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element) { item in
                            let name = item.element
                            HStack(spacing: 0) {
                                // Opens the skill in the list, where its details are.
                                Button {
                                    model.selectedSkillPath = model.snapshot?.skill(named: name)?.path
                                    model.skillsMatrix = false
                                } label: {
                                    Text(name).lineLimit(1).frame(width: Self.nameWidth, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(L("Show details"))
                                .draggable(name)  // drop onto an agent in the sidebar to assign
                                .contextMenu {
                                    if let e = model.snapshot?.skill(named: name) {
                                        Button(L("Reveal in Finder")) { model.reveal(e.path) }
                                        Divider()
                                        DeleteSkillButton(entry: e)
                                    }
                                }
                                ForEach(model.managedAgents) { a in
                                    ReachCell(state: model.cell(skill: name, agent: a.id, scope: scope), tint: a.adapter.tint) {
                                        model.toggle(skill: name, agent: a.id, scope: scope)
                                    }
                                    .frame(width: Self.columnWidth)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(item.offset % 2 == 0 ? Color.clear : Color.primary.opacity(0.025))
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Text(
                                rows.count == 1
                                    ? L("1 skill · \(model.projectName(scope))") : L("\(rows.count) skills · \(model.projectName(scope))")
                            ).font(.caption).foregroundStyle(.secondary)
                                .frame(width: Self.nameWidth, alignment: .leading)
                            ForEach(model.managedAgents) { a in
                                VStack(spacing: 2) {
                                    AgentBadge(adapter: a.adapter, size: 20)
                                    Text(a.adapter.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.tail)
                                    Text(L("\(a.visibleSkills(in: scope).count) loaded")).font(.caption2.monospacedDigit()).foregroundStyle(
                                        .secondary)
                                }
                                .frame(width: Self.columnWidth)
                                .help(a.adapter.name)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                }
            }
        }
    }
}

/// “Delete…” for a skill, wherever it's listed. Skills Kitfold can't delete get the button disabled,
/// with the reason as its help.
struct DeleteSkillButton: View {
    @Environment(AppModel.self) private var model
    let entry: SkillEntry
    var withIcon = false

    var body: some View {
        Button(role: .destructive) {
            model.reviewDeleteSkill(entry)
        } label: {
            if withIcon { Label(L("Delete…"), systemImage: "trash") } else { Text(L("Delete…")) }
        }
        .disabled(!entry.origin.isDeletable)
        .help(help)
    }

    var help: String {
        switch entry.origin {
        case .bundled: return L("Plugin skills can't be deleted; switch the plugin off in the agent instead")
        case .nested(let parent): return L("\(entry.name) lives inside “\(parent)”; delete that skill instead")
        case .external:
            return L("Take this skill from every agent. Its folder isn't Kitfold's, so it stays where it is. Reviewed first, and undoable.")
        default:
            return L("Take back every link to this skill and move its folder to Kitfold's trash. Reviewed first, and undoable.")
        }
    }
}

struct GitSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Add a Git repository of skills")).font(.headline)
            Text(
                L(
                    "Kitfold makes a shallow clone into ~/.kitfold/sources and reads every folder with a SKILL.md. Nothing is assigned until you choose."
                )
            )
            .font(.callout).foregroundStyle(.secondary)
            TextField("https://github.com/owner/skills.git", text: $url).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                Button(L("Clone")) {
                    model.addGitSource(url); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
