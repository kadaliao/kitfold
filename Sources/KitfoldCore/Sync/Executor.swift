import Foundation

/// Applies planned changes with preconditions, backups and a journal, and undoes them.
///
/// Guarantees:
/// - Every change re-checks the disk right before it runs (a file must still have the exact
///   content the preview showed; a link must still point where it pointed). If anything moved
///   underneath us, the transaction stops and rolls back what it already did.
/// - Every overwritten or deleted file is copied to `~/.kitfold/backups/<tx>/` first.
/// - Every transaction is journaled with its inverse, so it can be undone later — again with
///   preconditions, so an undo never clobbers edits made after the apply.
public final class Executor: @unchecked Sendable {
    public let env: KitfoldEnvironment
    public let store: StateStore

    public init(env: KitfoldEnvironment, store: StateStore) {
        self.env = env
        self.store = store
    }

    @discardableResult
    public func apply(
        _ changes: [PlannedChange], summary: String, kind: String = "apply", undoes: String? = nil
    ) throws -> TransactionRecord {
        guard !changes.isEmpty else { throw KitfoldError.invalid("Nothing to apply") }
        let txID = Executor.newID()
        let backupDir = env.backupsDir + "/" + txID
        let owned = store.ownedPaths()
        var undoneOps: [OperationRecord] = []
        let undoneTx = undoes.flatMap { store.transaction(id: $0) }
        var done: [(PlannedChange, OperationRecord)] = []

        do {
            for (i, planned) in changes.enumerated() {
                let c = planned.change
                try Executor.check(c)
                var backup: String?
                if case .writeFile(let path, .some(let before), _) = c {
                    backup = backupDir + "/\(i)-" + (path as NSString).lastPathComponent
                    try FS.writePrivate(before, to: backup!)
                }
                try Executor.perform(c)
                // On undo, ownership goes back to what it was before the original operation.
                var ownedBefore = owned.contains(c.path)
                if let original = undoneTx?.operations.first(where: { $0.change.inverse == c }) {
                    ownedBefore = original.ownedBefore
                    undoneOps.append(original)
                }
                done.append(
                    (
                        planned,
                        OperationRecord(
                            seq: i, change: c, summary: planned.summary, backupPath: backup, ownedBefore: ownedBefore,
                            ownership: planned.ownership)
                    ))
            }
        } catch {
            // Roll back in reverse order; report the original error.
            for (_, op) in done.reversed() {
                try? Executor.perform(op.change.inverse)
            }
            throw error
        }

        let tx = TransactionRecord(
            id: txID, createdAt: Date(), summary: summary, kind: kind, undoes: undoes, undoneBy: nil,
            operations: done.map(\.1))
        var ledger: [(add: Deployment?, remove: String?)] = []
        for (planned, op) in done {
            let restoreOwnership = undoes != nil
            switch op.change {
            case .createSymlink(let p, let t):
                let keep = restoreOwnership ? (undoneOps.first { $0.change.inverse == op.change }?.ownedBefore ?? false) : true
                ledger.append(
                    (
                        keep
                            ? Deployment(
                                path: p, kind: .symlink, target: t, agents: planned.agents, scope: planned.scope,
                                resource: planned.resource, txID: txID, updatedAt: Date()) : nil, keep ? nil : p
                    ))
            case .removeSymlink(let p, _):
                ledger.append((nil, p))
            case .writeFile(let p, nil, .some):
                let keep = restoreOwnership ? (undoneOps.first { $0.change.inverse == op.change }?.ownedBefore ?? false) : true
                ledger.append(
                    (
                        keep
                            ? Deployment(
                                path: p, kind: .file, target: nil, agents: planned.agents, scope: planned.scope,
                                resource: planned.resource, txID: txID, updatedAt: Date()) : nil, keep ? nil : p
                    ))
            case .writeFile(let p, _, nil):
                ledger.append((nil, p))
            case .writeFile, .moveItem:
                break
            }
            for edit in op.ownership {
                let skill = edit.skill.isEmpty ? nil : ResourceRef(.skill, edit.skill)
                ledger.append(
                    edit.ownedAfter
                        ? (
                            Deployment(
                                path: edit.key, kind: .setting, target: edit.value, agents: planned.agents, scope: planned.scope,
                                resource: skill, txID: txID, updatedAt: Date()), nil
                        ) : (nil, edit.key))
            }
        }
        do {
            try store.record(tx, ledger: ledger)
        } catch {
            // Without a journal entry the change couldn't be undone: put the files back.
            for (_, op) in done.reversed() { try? Executor.perform(op.change.inverse) }
            throw error
        }
        return tx
    }

    /// Undo a transaction by applying its inverse operations in reverse order. `adjust` may rewrite
    /// an inverse change first (Workspace uses it to merge kitfold.json instead of restoring it).
    @discardableResult
    public func undo(_ txID: String, adjust: (PlannedChange) -> PlannedChange = { $0 }) throws -> TransactionRecord {
        guard let tx = store.transaction(id: txID) else { throw KitfoldError.notFound("transaction \(txID)") }
        guard tx.undoneBy == nil else { throw KitfoldError.invalid("Already undone") }
        let deployments = Dictionary(store.deployments().map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let inverse = tx.operations.reversed().map { op in
            let original = op.ownership.first.flatMap { deployments[$0.key] }
            return PlannedChange(
                op.change.inverse, summary: "Undo: " + op.summary, agents: original?.agents ?? [], scope: original?.scope ?? .global,
                ownership: op.ownership.reversed().map(\.inverse))
        }.map(adjust)
        // Dry-run every precondition first so an undo is all-or-nothing in the common case.
        var conflicts: [String] = []
        var simulated: [String: FS.Kind] = [:]
        for c in inverse {
            do { try Executor.check(c.change, simulated: simulated) } catch { conflicts.append(env.abbreviate(c.change.path)) }
            simulated[c.change.path] = Executor.kindAfter(c.change)
            if case .moveItem(let from, _) = c.change { simulated[from] = .missing }
        }
        guard conflicts.isEmpty else {
            throw KitfoldError.precondition(
                "These files changed after the original apply, so undo would overwrite newer edits: " + conflicts.joined(separator: ", "))
        }
        // Moving a skill back out of the library must not strand links made to it since.
        let removedByUndo = Set(
            inverse.compactMap { c -> String? in
                if case .removeSymlink(let p, _) = c.change { return p }
                return nil
            })
        for c in inverse {
            guard case .moveItem(let from, _) = c.change else { continue }
            let dependents = store.deployments().filter { d in
                guard d.kind == .symlink, let t = d.target, !removedByUndo.contains(d.path) else { return false }
                return FS.isInside(FS.absolute(t, relativeTo: (d.path as NSString).deletingLastPathComponent), from)
            }
            if !dependents.isEmpty {
                throw KitfoldError.precondition(
                    "Links made later still point into \(env.abbreviate(from)): "
                        + dependents.map { env.abbreviate($0.path) }.joined(separator: ", ")
                        + ". Switch that skill off for those agents first.")
            }
        }
        return try apply(inverse, summary: "Undo “\(tx.summary)”", kind: "undo", undoes: tx.id)
    }

    // MARK: primitives

    static func check(_ c: FileChange, simulated: [String: FS.Kind] = [:]) throws {
        let kind = simulated[c.path] ?? FS.kind(c.path)
        switch c {
        case .createSymlink(let p, _):
            guard kind == .missing else { throw KitfoldError.precondition("\(p) already exists") }
        case .removeSymlink(let p, let target):
            guard case .symlink = kind else { throw KitfoldError.precondition("\(p) is no longer a link") }
            // `target` may be relative (stored as found); compare resolved destinations.
            let expected = FS.absolute(target, relativeTo: (p as NSString).deletingLastPathComponent)
            if simulated[p] == nil, !target.isEmpty, let dest = FS.linkDestination(p), dest != expected {
                throw KitfoldError.precondition("\(p) now points to \(dest)")
            }
        case .writeFile(let p, let before, _):
            if simulated[p] != nil { return }
            if let before {
                guard FS.read(p) == before else { throw KitfoldError.precondition("\(p) changed since the preview") }
            } else {
                guard kind == .missing else { throw KitfoldError.precondition("\(p) now exists") }
            }
        case .moveItem(let from, let to):
            guard kind == .missing else { throw KitfoldError.precondition("\(to) already exists") }
            if simulated[from] == nil, FS.kind(from) == .missing { throw KitfoldError.precondition("\(from) is gone") }
        }
    }

    static func kindAfter(_ c: FileChange) -> FS.Kind {
        switch c {
        case .createSymlink(_, let t): return .symlink(target: t)
        case .removeSymlink: return .missing
        case .writeFile(_, _, let after): return after == nil ? .missing : .file
        case .moveItem: return .directory
        }
    }

    static func perform(_ c: FileChange) throws {
        switch c {
        case .createSymlink(let p, let t): try FS.createSymlink(at: p, to: t)
        case .removeSymlink(let p, _): try FS.removeSymlink(at: p)
        case .writeFile(let p, _, let after):
            if let after {
                try FS.write(after, to: p)
            } else if FS.exists(p) {
                try FileManager.default.removeItem(atPath: p)
            }
        case .moveItem(let from, let to):
            try FileManager.default.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try FileManager.default.moveItem(atPath: from, toPath: to)
        }
    }

    static func newID() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date()) + "-" + String(UUID().uuidString.prefix(6)).lowercased()
    }

    /// Delete backup folders older than `days`.
    public func pruneBackups(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for name in FS.children(env.backupsDir) where name != "trash" {
            let p = env.backupsDir + "/" + name
            if let d = FS.modificationDate(p), d < cutoff { try? FileManager.default.removeItem(atPath: p) }
        }
    }
}
