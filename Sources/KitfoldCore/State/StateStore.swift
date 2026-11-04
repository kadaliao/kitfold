import Foundation

/// Something Kitfold placed on disk and therefore may later take back.
public struct Deployment: Hashable, Sendable, Identifiable {
    public var id: String { path }
    public enum Kind: String, Sendable { case symlink, file }
    public var path: String
    public var kind: Kind
    public var target: String?
    public var agents: [AgentID]
    public var scope: Scope
    public var resource: ResourceRef?
    public var txID: String
    public var updatedAt: Date
}

public struct OperationRecord: Hashable, Sendable, Identifiable {
    public var id: Int { seq }
    public var seq: Int
    public var change: FileChange
    public var summary: String
    public var backupPath: String?
    /// Whether Kitfold owned `change.path` before this operation (restored on undo).
    public var ownedBefore: Bool
}

public struct TransactionRecord: Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var summary: String
    public var kind: String  // apply | undo | edit
    public var undoes: String?
    public var undoneBy: String?
    public var operations: [OperationRecord]
    public var canUndo: Bool { undoneBy == nil && !operations.isEmpty }
}

/// `~/.kitfold/state.sqlite`: the deployment ledger and the operation journal.
/// Config (intent) lives in kitfold.json; this is runtime state only.
public final class StateStore: @unchecked Sendable {
    let db: SQLiteDB
    private let lock = NSLock()

    public init(path: String) throws {
        db = try SQLiteDB(path: path)
        try db.exec(
            """
            CREATE TABLE IF NOT EXISTS transactions(
              id TEXT PRIMARY KEY, created_at REAL NOT NULL, summary TEXT NOT NULL, kind TEXT NOT NULL,
              undoes TEXT, undone_by TEXT);
            CREATE TABLE IF NOT EXISTS operations(
              tx_id TEXT NOT NULL REFERENCES transactions(id), seq INTEGER NOT NULL, change_json TEXT NOT NULL,
              summary TEXT NOT NULL, backup_path TEXT, owned_before INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY(tx_id, seq));
            CREATE TABLE IF NOT EXISTS deployments(
              path TEXT PRIMARY KEY, kind TEXT NOT NULL, target TEXT, agents TEXT NOT NULL, scope TEXT NOT NULL,
              resource TEXT, tx_id TEXT NOT NULL, updated_at REAL NOT NULL);
            """)
    }

    // MARK: ledger

    public func deployments() -> [Deployment] {
        lock.withLock {
            ((try? db.query("SELECT * FROM deployments ORDER BY path")) ?? []).compactMap { r -> Deployment? in
                guard let path = r["path"] ?? nil, let kind = (r["kind"] ?? nil).flatMap(Deployment.Kind.init(rawValue:)),
                    let scope = (r["scope"] ?? nil).flatMap(Scope.init(string:))
                else { return nil }
                let res: ResourceRef? = (r["resource"] ?? nil).flatMap { s -> ResourceRef? in
                    let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let k = ResourceKind(rawValue: parts[0]) else { return nil }
                    return ResourceRef(k, parts[1])
                }
                return Deployment(
                    path: path, kind: kind, target: r["target"] ?? nil,
                    agents: ((r["agents"] ?? nil) ?? "").split(separator: ",").map { AgentID(String($0)) },
                    scope: scope, resource: res, txID: (r["tx_id"] ?? nil) ?? "",
                    updatedAt: Date(timeIntervalSince1970: Double((r["updated_at"] ?? nil) ?? "0") ?? 0))
            }
        }
    }

    public func ownedPaths() -> Set<String> { Set(deployments().map(\.path)) }

    // MARK: journal

    func record(_ tx: TransactionRecord, ledger: [(add: Deployment?, remove: String?)]) throws {
        try lock.withLock {
            try db.transaction {
                try db.run(
                    "INSERT INTO transactions(id, created_at, summary, kind, undoes) VALUES(?,?,?,?,?)",
                    [.text(tx.id), .double(tx.createdAt.timeIntervalSince1970), .text(tx.summary), .text(tx.kind), .text(tx.undoes)])
                let enc = JSONEncoder()
                for op in tx.operations {
                    let json = String(decoding: try enc.encode(op.change), as: UTF8.self)
                    try db.run(
                        "INSERT INTO operations(tx_id, seq, change_json, summary, backup_path, owned_before) VALUES(?,?,?,?,?,?)",
                        [
                            .text(tx.id), .int(Int64(op.seq)), .text(json), .text(op.summary), .text(op.backupPath),
                            .int(op.ownedBefore ? 1 : 0),
                        ])
                }
                for entry in ledger {
                    if let p = entry.remove { try db.run("DELETE FROM deployments WHERE path = ?", [.text(p)]) }
                    if let d = entry.add {
                        try db.run(
                            """
                            INSERT OR REPLACE INTO deployments(path, kind, target, agents, scope, resource, tx_id, updated_at)
                            VALUES(?,?,?,?,?,?,?,?)
                            """,
                            [
                                .text(d.path), .text(d.kind.rawValue), .text(d.target),
                                .text(d.agents.map(\.rawValue).joined(separator: ",")),
                                .text(d.scope.description), .text(d.resource?.description), .text(d.txID),
                                .double(d.updatedAt.timeIntervalSince1970),
                            ])
                    }
                }
                if let undone = tx.undoes {
                    try db.run("UPDATE transactions SET undone_by = ? WHERE id = ?", [.text(tx.id), .text(undone)])
                }
            }
        }
    }

    public func transactions(limit: Int = 100) -> [TransactionRecord] {
        let rows = lock.withLock {
            (try? db.query("SELECT * FROM transactions ORDER BY created_at DESC LIMIT ?", [.int(Int64(limit))])) ?? []
        }
        return rows.compactMap { r in (r["id"] ?? nil).flatMap { transaction(id: $0) } }
    }

    public func transaction(id: String) -> TransactionRecord? {
        lock.withLock {
            guard let r = (try? db.query("SELECT * FROM transactions WHERE id = ?", [.text(id)]))?.first else { return nil }
            let ops = ((try? db.query("SELECT * FROM operations WHERE tx_id = ? ORDER BY seq", [.text(id)])) ?? []).compactMap {
                o -> OperationRecord? in
                guard let json = o["change_json"] ?? nil,
                    let change = try? JSONDecoder().decode(FileChange.self, from: Data(json.utf8))
                else { return nil }
                return OperationRecord(
                    seq: Int((o["seq"] ?? nil) ?? "0") ?? 0, change: change, summary: (o["summary"] ?? nil) ?? "",
                    backupPath: o["backup_path"] ?? nil, ownedBefore: ((o["owned_before"] ?? nil) ?? "0") == "1")
            }
            return TransactionRecord(
                id: id, createdAt: Date(timeIntervalSince1970: Double((r["created_at"] ?? nil) ?? "0") ?? 0),
                summary: (r["summary"] ?? nil) ?? "", kind: (r["kind"] ?? nil) ?? "apply",
                undoes: r["undoes"] ?? nil, undoneBy: r["undone_by"] ?? nil, operations: ops)
        }
    }
}
