import Foundation
import KitfoldCore

// kitfold — command-line front end to the same core the app uses.
//
//   kitfold status [--all]             agents on this Mac (--all: every agent Kitfold knows), context size, issues
//   kitfold skills [--all] [--project <path>]   skill × agent matrix (what each agent actually loads)
//   kitfold agents [--all] [--project <path>]  where each agent looks, which files it loads
//   kitfold profiles                   profile ids and names
//   kitfold plan                       changes needed to match kitfold.json
//   kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
//   kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
//   kitfold delete <skill> [--yes]     take a skill from every agent and move its folder to Kitfold's trash
//   kitfold clean [--yes]              remove broken skill links from the agents' folders
//   kitfold apply [--yes]              apply the pending plan
//   kitfold history [--project <path>] applied transactions
//   kitfold undo <tx-id> [--yes]
//
// Global flags: --home <dir> (pretend this is $HOME; for trying things safely), --no-color,
// --lang en|zh-Hans (default: KITFOLD_LANG, else the system's language).

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { fail(L("\(name) needs a value")) }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

let useColor = !flag("--no-color") && isatty(1) == 1
func c(_ s: String, _ code: String) -> String { useColor ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
func dim(_ s: String) -> String { c(s, "2") }
func bold(_ s: String) -> String { c(s, "1") }
func red(_ s: String) -> String { c(s, "31") }
func green(_ s: String) -> String { c(s, "32") }
func yellow(_ s: String) -> String { c(s, "33") }

/// Terminal columns `s` takes: East Asian wide and full-width characters (CJK) take two.
func displayWidth(_ s: String) -> Int {
    s.reduce(0) { n, ch in n + (ch.unicodeScalars.first.map(isWide) == true ? 2 : 1) }
}
func isWide(_ u: Unicode.Scalar) -> Bool {
    switch u.value {
    case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1F64F,
        0x1F900...0x1F9FF, 0x20000...0x3FFFD:
        return true
    default: return false
    }
}
/// `s` padded with spaces (or cut) to `width` columns: `padding(toLength:)` for the terminal.
func pad(_ s: String, _ width: Int) -> String {
    var out = ""
    var used = 0
    for ch in s {
        let w = displayWidth(String(ch))
        if used + w > width { break }
        out.append(ch)
        used += w
    }
    return out + String(repeating: " ", count: width - used)
}

func fail(_ msg: String) -> Never {
    fflush(stdout)  // what was printed before explains the error
    FileHandle.standardError.write(Data((red(L("error: ")) + msg + "\n").utf8))
    exit(1)
}

// Messages follow the system's language; KITFOLD_LANG or --lang picks one.
if let tag = option("--lang") {
    guard let language = Language(tag: tag) else { fail(L("unknown language \(tag) (known: en, zh-Hans)")) }
    Localization.language = language
}

var env = KitfoldEnvironment.current()
if let home = option("--home") {
    let h = FS.standardize(FS.expandTilde(home, home: NSHomeDirectory()))
    // A sandbox: no PATH or folder variables from the real environment, only switches that change what an agent reads.
    var variables = ["PATH": "/usr/bin:/bin"]
    for key in BuiltinAgents.openCodeSkipsClaude { variables[key] = ProcessInfo.processInfo.environment[key] }
    env = KitfoldEnvironment(home: h, variables: variables)
}
let yes = flag("--yes") || flag("-y")
let projectArg = option("--project")
let showAll = flag("--all")
let clearFlag = flag("--clear")
let offFlag = flag("--off")
let force = flag("--force")
let wantsHelp = flag("--help") || flag("-h")
// Anything else that looks like an option is a typo; never guess (`--of` must not mean "on").
if let unknown = args.first(where: { $0.hasPrefix("-") }) { fail(L("unknown option \(unknown). Try kitfold help")) }
if clearFlag && offFlag { fail(L("use either --off or --clear")) }

let ws: Workspace
do { ws = try Workspace(env: env) } catch { fail("\(error)") }
func ab(_ p: String) -> String { env.abbreviate(p) }

func printIssues(_ issues: [Issue], limit: Int = 50) {
    for i in issues.prefix(limit) {
        let mark: String
        switch i.severity {
        case .error: mark = red("✗")
        case .warning: mark = yellow("!")
        case .info: mark = dim("·")
        }
        print("  \(mark) \(i.title)")
        if !i.detail.isEmpty { print("    " + dim(i.detail)) }
    }
    if issues.count > limit { print(dim("  " + L("… \(issues.count - limit) more"))) }
}

func printPlan(_ plan: Plan) {
    if plan.changes.isEmpty { print(green(L("Nothing to change."))) }
    for ch in plan.changes {
        let risk = ch.risk == .caution ? yellow(L(" (caution)")) : ""
        let verb: String
        switch ch.change {
        case .createSymlink(let p, let t): verb = green(L("+ link") + " ") + "\(ab(p)) → \(ab(t))"
        case .removeSymlink(let p, _): verb = red(L("- link") + " ") + ab(p)
        case .writeFile(let p, nil, _): verb = green(L("+ file") + " ") + ab(p)
        case .writeFile(let p, _, nil): verb = red(L("- file") + " ") + ab(p)
        case .writeFile(let p, _, _): verb = yellow(L("~ edit") + " ") + ab(p)
        case .moveItem(let f, let t): verb = yellow(L("→ move") + " ") + "\(ab(f)) → \(ab(t))"
        }
        print("  \(verb)\(risk)")
        print("    " + dim(ch.summary + (ch.note.map { " — \($0)" } ?? "")))
        // Settings files: only the entries involved, never the file (it may hold secrets).
        for line in ch.details ?? [] { print(line.hasPrefix("+") ? green("    \(line)") : red("    \(line)")) }
        // kitfold.json's own diff is noise here: the summary lines above say what changed.
        if let d = ch.diff, case .writeFile(let p, .some, .some) = ch.change, p != env.configFile {
            for h in LineDiff.hunks(d, context: 1).prefix(3) {
                for l in h.lines.prefix(12) {
                    switch l {
                    case .same(let s): print(dim("      \(s)"))
                    case .added(let s): print(green("    + \(s)"))
                    case .removed(let s): print(red("    - \(s)"))
                    }
                }
            }
        }
    }
    if !plan.notWritten.isEmpty {
        print(bold("\n" + L("Not written this time")))
        printIssues(plan.notWritten)
    }
    if !plan.otherIssues.isEmpty {
        print(bold("\n" + L("Needs attention")))
        printIssues(plan.otherIssues)
    }
}

func confirmAndApply(_ plan: Plan, summary: String) {
    printPlan(plan)
    guard !plan.changes.isEmpty else { return }
    if !yes {
        let n = plan.fileChanges.count
        print(
            "\n"
                + (n == 0
                    ? L("Only the assignments are saved. Re-run with --yes to save them.")
                    : n == 1
                        ? L("Apply 1 file change? Re-run with --yes to apply.") : L("Apply \(n) file changes? Re-run with --yes to apply."))
        )
        return
    }
    do {
        if let tx = try ws.apply(plan, summary: summary) {
            print(green("\n" + L("Applied.")) + L(" Undo with: kitfold undo \(tx.id)"))
        }
    } catch { fail("\(error)") }
}

func scope() -> Scope {
    guard let p = projectArg else { return .global }
    let abs = FS.absolute(FS.expandTilde(p, home: env.home), relativeTo: FileManager.default.currentDirectoryPath)
    guard FS.isDirectoryFollowing(abs) else { fail(L("no such folder: \(p)")) }
    return .project(FS.gitRoot(from: abs) ?? abs)
}

/// `config` with the `--project` folder in its projects, so any folder can be looked at or assigned to.
func including(_ sc: Scope, in config: KitfoldConfig) -> KitfoldConfig {
    var c = config
    if case .project(let p) = sc, !c.projects.contains(where: { $0.path == p }) { c.projects.append(ProjectConfig(path: p)) }
    return c
}

func scan(_ config: KitfoldConfig, probeVersions: Bool = false) -> Snapshot {
    Scanner(env: env, adapters: ws.adapters).scan(
        config: config, ownedPaths: ws.store.ownedPaths(), ownedSettings: ws.store.ownedSettings(), probeVersions: probeVersions)
}

/// Commands take a fixed number of arguments; extra ones are mistakes.
func expectArgs(_ n: ClosedRange<Int>, usage: String) {
    if !n.contains(args.count) { fail(L("usage: kitfold \(usage)")) }
}

func roleLabel(_ role: SkillRootSpec.Role) -> String {
    switch role {
    case .primary: return L("primary")
    case .shared: return L("shared")
    case .foreign: return L("foreign")
    case .bundled: return L("bundled")
    }
}

/// Every agent: the known ones, the user's own and the ones found on this Mac.
let allAdapters = Scanner(env: env, adapters: ws.adapters).adapters(for: ws.config, env: env)

/// Agents worth listing: the ones Kitfold manages and the ones on this Mac (all of them with --all).
func listed(_ snap: Snapshot) -> [AgentState] {
    showAll ? snap.agents : snap.agents.filter { $0.enabled || $0.installation.isDetected }
}

func selector(_ s: String) -> AgentSelector {
    if s == "*" || s == "all" { return .all }
    guard allAdapters.contains(where: { $0.id.rawValue == s }) else {
        let known = Localization.list(["*"] + allAdapters.map(\.id.rawValue))
        fail(L("unknown agent \(s) (known: \(known))"))
    }
    return .agent(AgentID(s))
}

/// What one more line says about agents left out of a list.
func printHidden(_ snap: Snapshot, shown: Int) {
    let hidden = snap.agents.count - shown
    guard hidden > 0 else { return }
    print(
        dim(
            hidden == 1
                ? L("1 more agent Kitfold knows isn't on this Mac (--all lists it).")
                : L("\(hidden) more agents Kitfold knows aren't on this Mac (--all lists them).")))
}

let command = wantsHelp ? "help" : (args.first ?? "status")
if !args.isEmpty && !wantsHelp { args.removeFirst() }

switch command {
case "status":
    expectArgs(0...0, usage: "status [--all]")
    let snap = ws.scan()
    let librarySkills = snap.catalog.filter { $0.origin == .library }.count
    let profileCount = snap.profiles.count
    let library = Localization.list([
        librarySkills == 1 ? L("1 skill") : L("\(librarySkills) skills"),
        profileCount == 1 ? L("1 profile") : L("\(profileCount) profiles"),
    ])
    print(bold("Kitfold") + dim("  \(ab(env.kitfoldHome))  ·  " + L("library: \(library)")))
    print()
    let agents = listed(snap)
    let nameWidth = (agents.map { displayWidth($0.adapter.name) }.max() ?? 10) + 1
    for a in agents {
        let inst = a.installation
        let state =
            inst.binaryPath != nil || inst.marker != nil
            ? green(L("installed"))
            : inst.isInstalled ? yellow(L("config only")) : inst.isDetected ? yellow(L("folder only")) : dim(L("not found"))
        let est = snap.contextEstimate(agent: a.id, scope: .global)
        let notes = [
            a.enabled ? nil : dim(L("not managed")), a.adapter.descriptor.source == .discovered ? c(L("found on this Mac"), "36") : nil,
        ]
        let labels = notes.compactMap { $0 }
        print(
            "\(bold(pad(a.adapter.name, nameWidth))) \(state) \(dim(inst.version ?? ""))"
                + (labels.isEmpty ? "" : " " + labels.joined(separator: dim(" · "))))
        let config = ab(inst.configDir)
        print(
            dim(
                "  "
                    + (est.skillCount == 1
                        ? L("1 skill active  ·  ~\(est.approxTokens) tokens always loaded  ·  config \(config)")
                        : L("\(est.skillCount) skills active  ·  ~\(est.approxTokens) tokens always loaded  ·  config \(config)"))))
    }
    printHidden(snap, shown: agents.count)
    let issues = snap.issues.filter { $0.severity >= .warning }
    let notes = snap.issues.count - issues.count
    let problems = issues.count == 1 ? L("1 warning or error") : L("\(issues.count) warnings or errors")
    let noteCount = notes == 1 ? L("1 note") : L("\(notes) notes")
    print(bold("\n" + L("Issues")) + dim(L(" (\(problems), \(noteCount))")))
    printIssues(issues, limit: 25)

case "skills":
    expectArgs(0...0, usage: "skills [--all] [--project <path>]")
    let sc = scope()
    let snap = scan(including(sc, in: ws.config))
    let agents = snap.managedAgents
    let width = min(40, (snap.skillNames.map(displayWidth).max() ?? 10) + 2)
    // Columns are headed by each agent's two letters; say whose they are.
    print(dim(Localization.list(agents.map { "\($0.adapter.descriptor.monogram) \($0.adapter.name)" })))
    print(
        String(repeating: " ", count: width)
            + agents.map { pad($0.adapter.descriptor.monogram, 4) }.joined())
    for name in snap.skillNames {
        var cells: [String] = []
        var any = false
        for a in agents {
            let ex = snap.exposures(skill: name, agent: a.id, scope: sc)
            let active = ex.filter(\.isActive)
            if let e = active.first {
                any = true
                switch e.via {
                case .link(let owned): cells.append(owned ? green("●") : green("○"))
                case .localFolder: cells.append(green("■"))
                case .sharedDir: cells.append(c("◆", "36"))
                case .foreignDir: cells.append(c("◇", "36"))
                case .bundled: cells.append(dim("P"))
                case .nested: cells.append(c("n", "36"))
                }
            } else if !ex.isEmpty {
                cells.append(dim("×"))
            } else {
                cells.append(dim("·"))
            }
        }
        if any || showAll {
            print(pad(name, width) + cells.map { $0 + "   " }.joined())
        }
    }
    let legend = [
        L("● Kitfold link"), L("○ other link"), L("■ local folder"), L("◆ shared dir"), L("◇ via another agent's dir"),
        L("n nested in another skill"), L("P plugin"), L("× disabled in agent settings"),
    ]
    print(dim("\n" + legend.joined(separator: "  ")))

case "agents":
    expectArgs(0...0, usage: "agents [--all] [--project <path>]")
    let sc = scope()
    let snap = scan(including(sc, in: ws.config), probeVersions: true)
    let agents = listed(snap)
    for a in agents {
        let found = a.installation.isDetected ? "" : "  " + L("not found on this Mac")
        print(bold(a.adapter.name) + dim("  \(a.id)  " + (a.enabled ? L("managed") : L("not managed")) + found))
        print(dim("  " + L("skills folders (precedence order):")))
        for r in a.adapter.skillRoots(sc, env) {
            let n = a.state(sc).skills.filter { $0.root.path == r.path }.count
            print("    \(pad(roleLabel(r.spec.role), 10)) \(ab(r.path)) \(dim("(\(n))"))")
        }
        print(dim("  " + L("instruction files:")))
        for f in a.state(sc).instructions {
            let mark = f.isLoaded ? green(L("loaded")) : (f.exists ? yellow(L("present, not loaded")) : dim(L("absent")))
            let kf = f.blocks.isEmpty ? "" : c(" [kitfold: \(f.blocks.map(\.profile).joined(separator: ","))]", "35")
            print("    \(ab(f.file.path)) \(mark)\(kf)")
        }
        for n in a.adapter.descriptor.notes { print(dim("  " + Localization.translate(n))) }
        print()
    }
    printHidden(snap, shown: agents.count)

case "profiles":
    expectArgs(0...0, usage: "profiles")
    let snap = ws.scan(probeVersions: false)
    if snap.profiles.isEmpty { print(dim(L("No profiles yet."))) }
    let width = min(30, (snap.profiles.map { displayWidth($0.id) }.max() ?? 10) + 2)
    for p in snap.profiles.sorted(by: { $0.id < $1.id }) {
        print(pad(p.id, width) + p.name + (p.description.isEmpty ? "" : dim("  " + p.description)))
    }

case "plan":
    expectArgs(0...0, usage: "plan")
    let snap = ws.scan(probeVersions: false)
    printPlan(ws.plan(ws.config, snapshot: snap))

case "apply":
    expectArgs(0...0, usage: "apply")
    let snap = ws.scan(probeVersions: false)
    confirmAndApply(ws.plan(ws.config, snapshot: snap), summary: L("Apply kitfold.json"))

case "assign", "profile":
    expectArgs(2...2, usage: "\(command) <name> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]")
    let kind: ResourceKind = command == "assign" ? .skill : .profile
    let ref = ResourceRef(kind, args[0])
    let sel = selector(args[1])
    let state: RuleState? = clearFlag ? nil : (offFlag ? .off : .on)
    let sc = scope()
    var draft = including(sc, in: ws.config)
    if sel == .all { draft.setAll(ref, scope: sc, state: state) } else { draft.setRule(ref, agent: sel, scope: sc, state: state) }
    let snap = scan(draft)
    // nil: all agents. They get sentences of their own: Chinese puts a space before an agent's name, not before 所有 Agent.
    let who: String? = {
        guard case .agent(let id) = sel else { return nil }
        return allAdapters.first { $0.id == id }?.name ?? id.rawValue
    }()
    // The history shows names, as the app does; the id is only what's typed.
    let what = kind == .profile ? L("profile \(snap.profileName(ref.id))") : ref.id
    let project = sc.projectPath.map { ($0 as NSString).lastPathComponent }
    let summary: String
    switch (state, who, project) {
    case (.on, let w?, nil): summary = L("Give \(what) to \(w)")
    case (.on, let w?, let p?): summary = L("Give \(what) to \(w) in \(p)")
    case (.on, nil, nil): summary = L("Give \(what) to all agents")
    case (.on, nil, let p?): summary = L("Give \(what) to all agents in \(p)")
    case (.off, let w?, nil): summary = L("Take \(what) from \(w)")
    case (.off, let w?, let p?): summary = L("Take \(what) from \(w) in \(p)")
    case (.off, nil, nil): summary = L("Take \(what) from all agents")
    case (.off, nil, let p?): summary = L("Take \(what) from all agents in \(p)")
    case (nil, let w?, nil): summary = L("Reset \(what) for \(w)")
    case (nil, let w?, let p?): summary = L("Reset \(what) for \(w) in \(p)")
    case (nil, nil, nil): summary = L("Reset \(what) for all agents")
    case (nil, nil, let p?): summary = L("Reset \(what) for all agents in \(p)")
    }
    let plan = ws.plan(draft, snapshot: snap)
    // A rule that can never take effect would sit in kitfold.json doing nothing (a typo, a profile's
    // name instead of its id, a switch the agent can't make). Clearing one is always allowed.
    if state != nil && !force && draft != ws.config {
        if kind == .skill && snap.skill(named: ref.id) == nil {
            fail(L("no skill named \(ref.id). kitfold skills --all lists them; --force saves the rule anyway."))
        }
        if kind == .profile && snap.profile(ref.id) == nil {
            let known = Localization.list(snap.profiles.map(\.id).sorted())
            fail(L("no profile with id \(ref.id) (known: \(known)). --force saves the rule anyway."))
        }
        let agents: Set<AgentID> = {
            if case .agent(let id) = sel { return [id] }
            return Set(snap.managedAgents.map(\.id))
        }()
        let blockers = plan.issues(about: ref, agents: agents, scope: sc)
        if !blockers.isEmpty && !plan.changes.contains(where: { $0.change.path != env.configFile }) {
            printIssues(blockers)
            fail(L("not saved: this rule wouldn't change anything. --force saves it anyway."))
        }
    }
    confirmAndApply(plan, summary: summary)

case "delete":
    expectArgs(1...1, usage: "delete <skill> [--yes]")
    let snap = ws.scan(probeVersions: false)
    // The library's copy first, as everywhere else; the plan says when another folder has the name too.
    guard let entry = snap.skill(named: args[0]) else { fail(L("no skill named \(args[0]). kitfold skills --all lists them.")) }
    do {
        confirmAndApply(try ws.planSkillDelete(entry, snapshot: snap), summary: L("Delete \(entry.name)"))
    } catch { fail("\(error)") }

case "clean":
    expectArgs(0...0, usage: "clean [--yes]")
    let snap = ws.scan(probeVersions: false)
    let plan = ws.planRemoveBrokenLinks(snapshot: snap)
    if plan.changes.isEmpty { print(green(L("No broken skill links."))); exit(0) }
    confirmAndApply(plan, summary: L("Remove broken skill links"))

case "history":
    expectArgs(0...0, usage: "history [--project <path>]")
    // A project's history: the applies that touched a file inside it.
    let root = scope().projectPath
    for tx in ws.history() where root == nil || tx.operations.contains(where: { FS.isInside($0.change.path, root!) }) {
        let undone = tx.undoneBy != nil ? dim(L(" (undone)")) : ""
        let n = tx.operations.count
        print("\(tx.id)  \(tx.summary)\(undone)  " + dim(n == 1 ? L("1 operation") : L("\(n) operations")))
    }

case "undo":
    expectArgs(0...1, usage: "undo [<tx-id>] [--yes]")
    // The newest apply that's still in effect (undoing an undo would redo it).
    guard let id = args.first ?? ws.history().first(where: { $0.canUndo && $0.kind != "undo" })?.id else { fail(L("nothing to undo")) }
    guard let tx = ws.store.transaction(id: id) else { fail(L("no transaction \(id)")) }
    print(
        tx.operations.count == 1
            ? L("Undo “\(tx.summary)” (1 operation)") : L("Undo “\(tx.summary)” (\(tx.operations.count) operations)"))
    for op in tx.operations.reversed() { print(dim("  \(op.summary)")) }
    if !yes { print("\n" + L("Re-run with --yes to undo.")); exit(0) }
    do { try ws.undo(id); print(green(L("Undone."))) } catch { fail("\(error)") }

case "help", "-h", "--help":
    print(
        """
        kitfold status [--all] | plan | apply [--yes] | profiles
        kitfold skills [--all] [--project <path>] | agents [--all] [--project <path>]
        kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
        kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
        kitfold delete <skill> [--yes] | clean [--yes]
        kitfold history [--project <path>] | undo [<tx-id>] [--yes]
        """)
    print(L("flags: --home <dir> (sandbox $HOME), --no-color, --lang en|zh-Hans"))

default:
    fail(L("unknown command \(command). Try kitfold help"))
}
