import Foundation
import KitfoldCore

// kitfold — command-line front end to the same core the app uses.
//
//   kitfold status                     agents, context size, issues
//   kitfold skills [--all]             skill × agent matrix (what each agent actually loads)
//   kitfold agents                     where each agent looks, which files it loads
//   kitfold plan                       changes needed to match kitfold.json
//   kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--yes]
//   kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--yes]
//   kitfold apply [--yes]              apply the pending plan
//   kitfold history                    applied transactions
//   kitfold undo <tx-id> [--yes]
//
// Global flags: --home <dir> (pretend this is $HOME; for trying things safely), --no-color.

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { fail("\(name) needs a value") }
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

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((red("error: ") + msg + "\n").utf8))
    exit(1)
}

var env = KitfoldEnvironment.current()
if let home = option("--home") {
    let h = FS.standardize(FS.expandTilde(home, home: NSHomeDirectory()))
    env = KitfoldEnvironment(home: h, variables: ["PATH": "/usr/bin:/bin"])
}
let yes = flag("--yes") || flag("-y")
let projectArg = option("--project")
let showAll = flag("--all")
let clearFlag = flag("--clear")
let offFlag = flag("--off")
// Anything else that looks like an option is a typo; never guess (`--of` must not mean "on").
if let unknown = args.first(where: { $0.hasPrefix("-") }) { fail("unknown option \(unknown). Try kitfold help") }
if clearFlag && offFlag { fail("use either --off or --clear") }

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
    if issues.count > limit { print(dim("  … \(issues.count - limit) more")) }
}

func printPlan(_ plan: Plan) {
    if plan.changes.isEmpty { print(green("Nothing to change.")) }
    for ch in plan.changes {
        let risk = ch.risk == .caution ? yellow(" (caution)") : ""
        let verb: String
        switch ch.change {
        case .createSymlink(let p, let t): verb = green("+ link ") + "\(ab(p)) → \(ab(t))"
        case .removeSymlink(let p, _): verb = red("- link ") + ab(p)
        case .writeFile(let p, nil, _): verb = green("+ file ") + ab(p)
        case .writeFile(let p, _, nil): verb = red("- file ") + ab(p)
        case .writeFile(let p, _, _): verb = yellow("~ edit ") + ab(p)
        case .moveItem(let f, let t): verb = yellow("→ move ") + "\(ab(f)) → \(ab(t))"
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
    if !plan.issues.isEmpty {
        print(bold("\nNeeds attention"))
        printIssues(plan.issues)
    }
}

func confirmAndApply(_ plan: Plan, summary: String) {
    printPlan(plan)
    guard !plan.changes.isEmpty else { return }
    if !yes {
        print("\nApply \(plan.changes.count) change(s)? Re-run with --yes to apply.")
        return
    }
    do {
        if let tx = try ws.apply(plan, summary: summary) {
            print(green("\nApplied.") + " Undo with: kitfold undo \(tx.id)")
        }
    } catch { fail("\(error)") }
}

func scope() -> Scope {
    guard let p = projectArg else { return .global }
    let abs = FS.absolute(FS.expandTilde(p, home: env.home), relativeTo: FileManager.default.currentDirectoryPath)
    guard FS.isDirectoryFollowing(abs) else { fail("no such folder: \(p)") }
    return .project(FS.gitRoot(from: abs) ?? abs)
}

/// Commands take a fixed number of arguments; extra ones are mistakes.
func expectArgs(_ n: ClosedRange<Int>, usage: String) {
    if !n.contains(args.count) { fail("usage: kitfold \(usage)") }
}

func selector(_ s: String) -> AgentSelector {
    if s == "*" || s == "all" { return .all }
    guard ws.adapters.contains(where: { $0.id.rawValue == s }) else {
        fail("unknown agent \(s) (known: \(ws.adapters.map(\.id.rawValue).joined(separator: ", ")), *)")
    }
    return .agent(AgentID(s))
}

let command = args.first ?? "status"
if !args.isEmpty { args.removeFirst() }

switch command {
case "status":
    expectArgs(0...0, usage: "status")
    let snap = ws.scan()
    print(
        bold("Kitfold")
            + dim(
                "  \(ab(env.kitfoldHome))  ·  library: \(snap.catalog.filter { $0.origin == .library }.count) skills, \(snap.profiles.count) profiles"
            ))
    print()
    for a in snap.agents {
        let inst = a.installation
        let state = inst.binaryPath != nil ? green("installed") : (inst.configDirExists ? yellow("config only") : dim("not found"))
        let est = snap.contextEstimate(agent: a.id, scope: .global)
        print("\(bold(a.adapter.name.padding(toLength: 12, withPad: " ", startingAt: 0))) \(state) \(dim(inst.version ?? ""))")
        print(dim("  \(est.skillCount) skills active  ·  ~\(est.approxTokens) tokens always loaded  ·  config \(ab(inst.configDir))"))
    }
    let issues = snap.issues.filter { $0.severity >= .warning }
    print(bold("\nIssues") + dim(" (\(issues.count) warnings/errors, \(snap.issues.count - issues.count) notes)"))
    printIssues(issues, limit: 25)

case "skills":
    expectArgs(0...0, usage: "skills [--all] [--project <path>]")
    let snap = ws.scan(probeVersions: false)
    let sc = scope()
    let agents = snap.managedAgents
    let width = min(40, (snap.skillNames.map(\.count).max() ?? 10) + 2)
    print(
        String(repeating: " ", count: width)
            + agents.map { $0.adapter.descriptor.monogram.padding(toLength: 4, withPad: " ", startingAt: 0) }.joined())
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
            print(name.padding(toLength: width, withPad: " ", startingAt: 0) + cells.map { $0 + "   " }.joined())
        }
    }
    print(
        dim(
            "\n● Kitfold link  ○ other link  ■ local folder  ◆ shared dir  ◇ via another agent's dir  n nested in another skill  P plugin  × disabled in agent settings"
        ))

case "agents":
    expectArgs(0...0, usage: "agents")
    let snap = ws.scan()
    let sc = scope()
    for a in snap.agents {
        print(bold(a.adapter.name) + dim("  \(a.enabled ? "managed" : "not managed")"))
        print(dim("  skills folders (precedence order):"))
        for r in a.adapter.skillRoots(sc, env) {
            let n = a.state(sc).skills.filter { $0.root.path == r.path }.count
            print("    \(r.spec.role.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(ab(r.path)) \(dim("(\(n))"))")
        }
        print(dim("  instruction files:"))
        for f in a.state(sc).instructions {
            let mark = f.isLoaded ? green("loaded") : (f.exists ? yellow("present, not loaded") : dim("absent"))
            let kf = f.blocks.isEmpty ? "" : c(" [kitfold: \(f.blocks.map(\.profile).joined(separator: ","))]", "35")
            print("    \(ab(f.file.path)) \(mark)\(kf)")
        }
        print()
    }

case "plan":
    expectArgs(0...0, usage: "plan")
    let snap = ws.scan(probeVersions: false)
    printPlan(ws.plan(ws.config, snapshot: snap))

case "apply":
    expectArgs(0...0, usage: "apply")
    let snap = ws.scan(probeVersions: false)
    confirmAndApply(ws.plan(ws.config, snapshot: snap), summary: "Apply kitfold.json")

case "assign", "profile":
    expectArgs(2...2, usage: "\(command) <name> <agent|*> [--off|--clear] [--project <path>] [--yes]")
    let kind: ResourceKind = command == "assign" ? .skill : .profile
    let ref = ResourceRef(kind, args[0])
    let sel = selector(args[1])
    let state: RuleState? = clearFlag ? nil : (offFlag ? .off : .on)
    var draft = ws.config
    let sc = scope()
    if case .project(let p) = sc, !draft.projects.contains(where: { $0.path == p }) { draft.projects.append(ProjectConfig(path: p)) }
    if sel == .all { draft.setAll(ref, scope: sc, state: state) } else { draft.setRule(ref, agent: sel, scope: sc, state: state) }
    let snap = Scanner(env: env, adapters: ws.adapters).scan(
        config: draft, ownedPaths: ws.store.ownedPaths(), ownedSettings: ws.store.ownedSettings(), probeVersions: false)
    let who: String = {
        if case .agent(let id) = sel { return ws.adapters.first { $0.id == id }?.name ?? id.rawValue }
        return "all agents"
    }()
    let what = kind == .profile ? "profile \(ref.id)" : ref.id
    let whereText = sc.isGlobal ? "" : " in \((sc.projectPath! as NSString).lastPathComponent)"
    let summary: String
    switch state {
    case .on: summary = "Give \(what) to \(who)\(whereText)"
    case .off: summary = "Take \(what) from \(who)\(whereText)"
    case nil: summary = "Reset \(what) for \(who)\(whereText)"
    }
    confirmAndApply(ws.plan(draft, snapshot: snap), summary: summary)

case "history":
    expectArgs(0...0, usage: "history")
    for tx in ws.history() {
        let undone = tx.undoneBy != nil ? dim(" (undone)") : ""
        print("\(tx.id)  \(tx.summary)\(undone)  \(dim("\(tx.operations.count) ops"))")
    }

case "undo":
    expectArgs(0...1, usage: "undo [<tx-id>] [--yes]")
    // The newest apply that's still in effect (undoing an undo would redo it).
    guard let id = args.first ?? ws.history().first(where: { $0.canUndo && $0.kind != "undo" })?.id else { fail("nothing to undo") }
    guard let tx = ws.store.transaction(id: id) else { fail("no transaction \(id)") }
    print("Undo “\(tx.summary)” (\(tx.operations.count) operations)")
    for op in tx.operations.reversed() { print(dim("  \(op.summary)")) }
    if !yes { print("\nRe-run with --yes to undo."); exit(0) }
    do { try ws.undo(id); print(green("Undone.")) } catch { fail("\(error)") }

case "help", "-h", "--help":
    print(
        """
        kitfold status | skills [--all] | agents | plan | apply [--yes]
        kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--yes]
        kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--yes]
        kitfold history | undo [<tx-id>] [--yes]
        flags: --home <dir> (sandbox $HOME), --no-color
        """)

default:
    fail("unknown command \(command). Try kitfold help")
}
