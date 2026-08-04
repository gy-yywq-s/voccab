import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal SQLite wrapper used for both the read-only bundled dictionary and
/// the read-write user store.
public final class Database {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "voccab.database")

    public enum Mode {
        case readOnly
        case readWrite
    }

    public init(path: String, mode: Mode) throws {
        var flags: Int32 = SQLITE_OPEN_FULLMUTEX
        switch mode {
        case .readOnly: flags |= SQLITE_OPEN_READONLY
        case .readWrite: flags |= SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            throw DatabaseError.openFailed(message)
        }
        handle = db
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public enum DatabaseError: Error {
        case openFailed(String)
        case prepareFailed(String, sql: String)
        case stepFailed(String)
    }

    public enum Value {
        case null
        case int(Int64)
        case real(Double)
        case text(String)
    }

    public struct Row {
        fileprivate var values: [String: Value]

        public func int(_ column: String) -> Int {
            if case .int(let v)? = values[column] { return Int(v) }
            if case .real(let v)? = values[column] { return Int(v) }
            return 0
        }

        public func double(_ column: String) -> Double {
            if case .real(let v)? = values[column] { return v }
            if case .int(let v)? = values[column] { return Double(v) }
            return 0
        }

        public func text(_ column: String) -> String {
            if case .text(let v)? = values[column] { return v }
            return ""
        }

        public func optionalDouble(_ column: String) -> Double? {
            switch values[column] {
            case .real(let v)?: return v
            case .int(let v)?: return Double(v)
            default: return nil
            }
        }
    }

    @discardableResult
    public func execute(_ sql: String, _ bindings: [Value] = []) throws -> [Row] {
        try queue.sync {
            guard let handle else { return [] }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(handle)), sql: sql)
            }
            defer { sqlite3_finalize(statement) }
            for (index, value) in bindings.enumerated() {
                let position = Int32(index + 1)
                switch value {
                case .null: sqlite3_bind_null(statement, position)
                case .int(let v): sqlite3_bind_int64(statement, position, v)
                case .real(let v): sqlite3_bind_double(statement, position, v)
                case .text(let v): sqlite3_bind_text(statement, position, v, -1, SQLITE_TRANSIENT)
                }
            }
            var rows: [Row] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                guard code == SQLITE_ROW else {
                    throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(handle)))
                }
                var values: [String: Value] = [:]
                for i in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, i))
                    switch sqlite3_column_type(statement, i) {
                    case SQLITE_INTEGER: values[name] = .int(sqlite3_column_int64(statement, i))
                    case SQLITE_FLOAT: values[name] = .real(sqlite3_column_double(statement, i))
                    case SQLITE_TEXT: values[name] = .text(String(cString: sqlite3_column_text(statement, i)))
                    default: values[name] = .null
                    }
                }
                rows.append(Row(values: values))
            }
            return rows
        }
    }
}
