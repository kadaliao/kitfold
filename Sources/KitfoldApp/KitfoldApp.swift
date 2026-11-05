import AppKit
import KitfoldCore
import SwiftUI

@main
struct KitfoldDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Localization.language = LanguageSettings.effective
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        let language = model.language
        WindowGroup("Kitfold") {
            RootView()
                .id(language)
                .environment(\.locale, language.locale)
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .task {
                    if model.workspace == nil { model.load() }
                    await DebugSnapshots.run(model: model)
                }
        }
        .windowToolbarStyle(.unified)
        .commands { KitfoldCommands(model: model) }

        Settings {
            SettingsView()
                .id(language)
                .environment(\.locale, language.locale)
                .environment(model)
                .frame(width: 620, height: 480)
        }
    }
}

/// Kitfold's menu items. Each menu reads `model.language`, so SwiftUI rebuilds it when the language changes.
struct KitfoldCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            let _ = model.language
            Button(L("New Profile…")) { model.showNewProfile = true }.keyboardShortcut("n")
            Button(L("New Skill…")) { model.showNewSkill = true }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Kitfold") {
            let _ = model.language
            Button(L("Quick Open…")) { model.showPalette = true }.keyboardShortcut("k")
            Button(L("Rescan")) { model.rescan() }.keyboardShortcut("r")
            Divider()
            Button(L("Review Changes…")) { model.showReview = true }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.hasPendingChanges)
            Button(L("Discard Changes")) { model.discardDraft() }
                .disabled(!model.hasPendingChanges)
            Divider()
            Button(L("Dashboard")) { model.selection = .dashboard }.keyboardShortcut("1")
            Button(L("Skills")) { model.selection = .skills }.keyboardShortcut("2")
            Button(L("Profiles")) { model.selection = .profiles }.keyboardShortcut("3")
            Button(L("History")) { model.selection = .history }.keyboardShortcut("4")
        }
        CommandGroup(replacing: .help) {
            let _ = model.language
            Button(L("Kitfold Tutorials")) { NSWorkspace.shared.open(Tutorials.url) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched as a bare SwiftPM executable there's no bundle; still behave like a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.hasPendingChanges { PendingBar() }
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isScanning { ProgressView().controlSize(.small) }
                Button {
                    model.rescan()
                } label: {
                    Label(L("Rescan"), systemImage: "arrow.clockwise")
                }
                .help(L("Rescan agents and files (⌘R)"))
                Button {
                    model.showPalette = true
                } label: {
                    Label(L("Quick Open"), systemImage: "magnifyingglass")
                }
                .help(L("Quick Open (⌘K)"))
            }
        }
        .sheet(isPresented: $model.showReview) { ReviewSheet(mode: .draft) }
        .sheet(item: $model.reviewPlan) { req in ReviewSheet(mode: .oneOff(req)) }
        .sheet(item: $model.editingInstruction) { target in InstructionEditor(target: target) }
        .sheet(isPresented: $model.showNewProfile) { NewItemSheet(kind: .profile) }
        .sheet(isPresented: $model.showNewSkill) { NewItemSheet(kind: .skill) }
        .overlay { if model.showPalette { CommandPalette() } }
        .overlay(alignment: .top) { ToastView() }
        .alert(
            L("Something went wrong"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        if model.snapshot == nil {
            VStack(spacing: 12) {
                ProgressView()
                Text(L("Reading your agents…")).foregroundStyle(.secondary)
            }
        } else {
            switch model.selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .skills: SkillsView()
            case .profiles: ProfilesView()
            case .agent(let id): AgentView(agentID: id).id(id)
            case .project(let path): ProjectView(path: path).id(path)
            case .history: HistoryView()
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                Label(L("Dashboard"), systemImage: "square.grid.2x2").tag(SidebarItem.dashboard)
            }
            Section(L("Library")) {
                Label {
                    HStack {
                        Text(L("Skills")); Spacer(); count(model.snapshot?.skillNames.count)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
                .tag(SidebarItem.skills)
                Label {
                    HStack {
                        Text(L("Profiles")); Spacer(); count(model.profiles.count)
                    }
                } icon: {
                    Image(systemName: "person.text.rectangle")
                }
                .tag(SidebarItem.profiles)
            }
            Section(L("Agents")) {
                ForEach(model.agents) { a in
                    HStack(spacing: 8) {
                        AgentBadge(adapter: a.adapter, size: 18, dimmed: !a.enabled)
                        Text(a.adapter.name).foregroundStyle(a.enabled ? .primary : .secondary)
                        Spacer()
                        if let snap = model.snapshot, a.enabled {
                            let issues = snap.issues(for: a.id).filter { $0.severity >= .warning }.count
                            if issues > 0 {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).imageScale(.small)
                            }
                            count(a.visibleSkills(in: .global).count)
                        }
                    }
                    .tag(SidebarItem.agent(a.id))
                    .dropDestination(for: String.self) { names, _ in
                        for n in names where !model.cell(skill: n, agent: a.id, scope: .global).willBeOn {
                            model.toggle(skill: n, agent: a.id, scope: .global)
                        }
                        model.toast = L("Added \(names.joined(separator: ", ")) to \(a.adapter.name) — review to apply.")
                        return true
                    }
                }
            }
            Section {
                ForEach(model.draft.projects) { p in
                    Label(p.name, systemImage: "folder").tag(SidebarItem.project(p.path))
                        .contextMenu {
                            Button(L("Reveal in Finder")) { model.reveal(p.path) }
                            Button(L("Remove from Kitfold"), role: .destructive) { model.removeProject(p.path) }
                        }
                }
                Button {
                    pickProject()
                } label: {
                    Label(L("Add Project…"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } header: {
                Text(L("Projects"))
            }
            Section {
                Label(L("History"), systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder func count(_ n: Int?) -> some View {
        if let n { Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
    }

    func pickProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Add Project")
        panel.message = L("Choose a project folder. Kitfold uses its git root.")
        if panel.runModal() == .OK, let url = panel.url { model.addProject(url) }
    }
}

/// Bottom bar shown while the draft differs from what's applied.
struct PendingBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.dashed").foregroundStyle(.tint)
            if model.isPlanning {
                Text(L("Working out changes…")).foregroundStyle(.secondary)
            } else {
                let n = model.pendingCount
                let issues = model.plan?.issues.filter { $0.severity >= .warning }.count ?? 0
                Text(
                    n == 0
                        ? L("Assignments changed — no files need to change")
                        : n == 1 ? L("1 file change pending") : L("\(n) file changes pending")
                )
                .font(.callout.weight(.medium))
                if issues > 0 { Pill(text: L("\(issues) to check"), color: .orange, systemImage: "exclamationmark.triangle") }
            }
            Spacer()
            Button(L("Discard")) { model.discardDraft() }
            Button(L("Review & Apply…")) { model.showReview = true }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let t = model.toast {
            Text(t)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 2)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: t) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { model.toast = nil }
                }
                .onTapGesture { model.toast = nil }
        }
    }
}
