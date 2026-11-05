import Foundation
import SQLite3

/// Minimal SQLite wrapper (system libsqlite3, no dependencies).
final class SQLiteDB {
    private var handle: OpaquePointer?
    /// SQLITE_TRANSIENT: SQLite copies bound strings.
    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    init(path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw KitfoldError.io(L("Can't open database \(path): \(lastError)"))
        }
        try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=3000;")
    }

    deinit { sqlite3_close_v2(handle) }

    var lastError: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle" }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? lastError
            sqlite3_free(err)
            throw KitfoldError.io("SQL failed: \(msg)")
        }
    }

    enum Value {
        case text(String?)
        case int(Int64)
        case double(Double)
    }

    func run(_ sql: String, _ params: [Value] = []) throws {
        _ = try query(sql, params)
    }

    /// Returns rows as column-name → string (nil for NULL).
    @discardableResult
    func query(_ sql: String, _ params: [Value] = []) throws -> [[String: String?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw KitfoldError.io("SQL prepare failed: \(lastError) — \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s):
                if let s { sqlite3_bind_text(stmt, idx, s, -1, SQLiteDB.transient) } else { sqlite3_bind_null(stmt, idx) }
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            }
        }
        var rows: [[String: String?]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw KitfoldError.io("SQL step failed: \(lastError)") }
            var row: [String: String?] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                if sqlite3_column_type(stmt, c) == SQLITE_NULL {
                    row[name] = .some(nil)
                } else {
                    row[name] = String(cString: sqlite3_column_text(stmt, c))
                }
            }
            rows.append(row)
        }
        return rows
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let r = try body()
            try exec("COMMIT")
            return r
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}
