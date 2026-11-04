import KitfoldCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var scope: Scope = .global
    @State private var showGitSheet = false

    enum Mode: String, CaseIterable { case list = "List", matrix = "Matrix" }
    enum Filter: String, CaseIterable {
        case all = "All", library = "Library", sources = "Sources", local = "Local folders", plugins = "Plugins", problems = "With problems"
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
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).fixedSize()
                ScopePicker(scope: $scope)
                Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) } }
                    .fixedSize()
                Spacer()
                TextField("Filter skills", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Menu {
                    Button("New Skill…") { model.showNewSkill = true }
                    Button("Import Folder…") { importFolder() }
                    Divider()
                    Button("Add Source Folder…") { addSourceFolder() }
                    Button("Add Git Repository…") { showGitSheet = true }
                } label: {
                    Label("Add", systemImage: "plus")
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
                                "Select a skill", systemImage: "sparkles",
                                description: Text("Choose which agents and projects get it."))
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Skills")
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
        panel.message = "Choose a skill folder (it must contain SKILL.md). It's copied into the library."
        if panel.runModal() == .OK, let url = panel.url { model.importSkillFolder(url) }
    }

    func addSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder of skills. Kitfold reads it in place."
        if panel.runModal() == .OK, let url = panel.url { model.addSourceFolder(url) }
    }
}

struct ScopePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var scope: Scope

    var body: some View {
        Picker("", selection: $scope) {
            Label("Global", systemImage: "globe").tag(Scope.global)
            ForEach(model.draft.projects) { p in
                Label(p.name, systemImage: "folder").tag(Scope.project(p.path))
            }
        }
        .fixedSize()
        .help("Which scope the agent dots and the matrix show")
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
                Text(entry.description.isEmpty ? "No description" : entry.description)
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
                            .help("\(a.adapter.name): \(c.willBeOn ? "on" : "off")")
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Scopes × agents grid for one skill.
struct AvailabilityGrid: View {
    @Environment(AppModel.self) private var model
    let skill: String
    var editable = true

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(model.managedAgents) { a in
                    VStack(spacing: 3) {
                        AgentBadge(adapter: a.adapter, size: 20)
                        Text(a.adapter.descriptor.monogram).font(.caption2).foregroundStyle(.secondary)
                    }
                    .gridColumnAlignment(.center)
                }
                Text("")
            }
            ForEach(model.scopes, id: \.self) { scope in
                GridRow {
                    Label(model.projectName(scope), systemImage: scope.isGlobal ? "globe" : "folder")
                        .lineLimit(1)
                        .frame(minWidth: 120, alignment: .leading)
                    ForEach(model.managedAgents) { a in
                        ReachCell(state: model.cell(skill: skill, agent: a.id, scope: scope), tint: a.adapter.tint) {
                            model.toggle(skill: skill, agent: a.id, scope: scope)
                        }
                        .disabled(!editable)
                    }
                    Menu {
                        Button("All agents on") { model.setAll(skill: skill, scope: scope, on: true) }
                        Button("All agents off") { model.setAll(skill: skill, scope: scope, on: false) }
                        Button("Clear (leave as found)") {
                            model.draft.setAll(ResourceRef(.skill, skill), scope: scope, state: nil)
                            model.replan()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!editable)
                }
            }
        }
    }
}

struct ReachLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legend("checkmark", "Linked")
            legend("square.stack.3d.up", "Shared folder")
            legend("arrow.turn.down.right", "Via another agent")
            legend("arrow.down", "From global")
            legend("nosign", "Off in agent settings")
            legend("plus", "Pending")
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
                        title: "Who gets it", subtitle: "Click a cell to switch it. Nothing changes on disk until you review and apply.")
                    if case .bundled = entry.origin {
                        Text("Plugin skills are switched on and off in the agent's plugin settings.").font(.callout).foregroundStyle(
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
                    Pill(text: s.managedBy.map { "\(s.label) · \($0)" } ?? s.label)
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
                    Label("Move into Library", systemImage: "tray.and.arrow.down")
                }
                .help("Move this folder into Kitfold's library and leave a link behind, so it can be assigned per agent.")
            }
            Button {
                model.openInEditor(entry.skillFile)
            } label: {
                Label("Open", systemImage: "square.and.pencil")
            }
        }
        .controlSize(.small)
        .fixedSize()
    }

    var loadedFrom: some View {
        Card {
            SectionTitle(title: "Where agents load it from", subtitle: "Global scope, in each agent's precedence order")
            let rows = model.managedAgents.flatMap { a in
                (model.snapshot?.exposures(skill: entry.name, agent: a.id, scope: .global) ?? []).map { (a, $0) }
            }
            if rows.isEmpty {
                Text("No agent loads it yet.").foregroundStyle(.secondary).font(.callout)
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
        if case .disabled(let src) = ex.observed.native { return Pill(text: "off in \(src)", color: .secondary, systemImage: "nosign") }
        if ex.observed.realPath != entry.path { return Pill(text: "different folder", color: .orange) }
        switch ex.via {
        case .link(let owned): return Pill(text: owned ? "Kitfold link" : "link", color: .accentColor)
        case .localFolder: return Pill(text: "local folder")
        case .sharedDir: return Pill(text: "shared folder", color: .teal)
        case .foreignDir: return Pill(text: "via another agent", color: .teal)
        case .bundled: return Pill(text: "plugin")
        case .nested(let parent): return Pill(text: "inside \(parent)", color: .teal)
        }
    }

    var problems: some View {
        Card {
            SectionTitle(title: "Problems")
            ForEach(entry.problems, id: \.self) { p in
                Label(p, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
            }
            if sameName.count > 1 {
                Label(
                    "\(sameName.count) folders are named “\(entry.name)”. Agents pick one; Kitfold assigns the library copy first.",
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
                        Button("Cancel") { editing = false }
                        Button("Save") {
                            model.saveSkillFile(entry, text: text)
                            editing = false
                        }
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Edit") {
                            text = FS.read(entry.skillFile) ?? ""; editing = true
                        }
                    }
                }
            }
            if editing {
                if case .source(let id) = entry.origin, let owner = model.draft.sources.first(where: { $0.id == id })?.managedBy {
                    Label("\(owner) manages this folder; its next update may replace your edits.", systemImage: "exclamationmark.triangle")
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

    var rows: [String] {
        guard onlyActive else { return names }
        return names.filter { n in model.managedAgents.contains { model.cell(skill: n, agent: $0.id, scope: scope).willBeOn } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Only skills that reach an agent", isOn: $onlyActive).toggleStyle(.checkbox)
                Spacer()
                ReachLegend()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element) { item in
                            let name = item.element
                            HStack(spacing: 0) {
                                Button {
                                    model.selectedSkillPath = model.snapshot?.skill(named: name)?.path
                                } label: {
                                    Text(name).lineLimit(1).frame(width: 260, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                ForEach(model.managedAgents) { a in
                                    ReachCell(state: model.cell(skill: name, agent: a.id, scope: scope), tint: a.adapter.tint) {
                                        model.toggle(skill: name, agent: a.id, scope: scope)
                                    }
                                    .frame(width: 104)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(item.offset % 2 == 0 ? Color.clear : Color.primary.opacity(0.025))
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Text("\(rows.count) skills · \(model.projectName(scope))").font(.caption).foregroundStyle(.secondary)
                                .frame(width: 260, alignment: .leading)
                            ForEach(model.managedAgents) { a in
                                VStack(spacing: 2) {
                                    AgentBadge(adapter: a.adapter, size: 20)
                                    Text(a.adapter.name).font(.caption.weight(.medium)).lineLimit(1)
                                    Text("\(a.visibleSkills(in: scope).count) loaded").font(.caption2.monospacedDigit()).foregroundStyle(
                                        .secondary)
                                }
                                .frame(width: 104)
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

struct GitSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Git repository of skills").font(.headline)
            Text(
                "Kitfold makes a shallow clone into ~/.kitfold/sources and reads every folder with a SKILL.md. Nothing is assigned until you choose."
            )
            .font(.callout).foregroundStyle(.secondary)
            TextField("https://github.com/owner/skills.git", text: $url).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Clone") {
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
