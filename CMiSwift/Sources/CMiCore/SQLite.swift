import Foundation
import SQLite3

// A minimal wrapper around the SQLite C API. Not thread safe: `Database` serializes access.

struct SQLiteError: Error, CustomStringConvertible {
    var code: Int32
    var message: String
    var description: String { "SQLite error \(code): \(message)" }
}

enum SQLValue {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null
}

protocol SQLBindable {
    var sqlValue: SQLValue { get }
}

extension Int64: SQLBindable { var sqlValue: SQLValue { .integer(self) } }
extension Int: SQLBindable { var sqlValue: SQLValue { .integer(Int64(self)) } }
extension Double: SQLBindable { var sqlValue: SQLValue { .real(self) } }
extension String: SQLBindable { var sqlValue: SQLValue { .text(self) } }
/// Django stores booleans as 0/1.
extension Bool: SQLBindable { var sqlValue: SQLValue { .integer(self ? 1 : 0) } }
extension Day: SQLBindable { var sqlValue: SQLValue { .text(description) } }
extension Optional: SQLBindable where Wrapped: SQLBindable {
    var sqlValue: SQLValue { self?.sqlValue ?? .null }
}

/// One result row. Only valid inside the `query` callback.
struct Row {
    fileprivate let statement: OpaquePointer

    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func bool(_ column: Int32) -> Bool { sqlite3_column_int64(statement, column) != 0 }
    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    func optionalInt64(_ column: Int32) -> Int64? { isNull(column) ? nil : int64(column) }
    func optionalString(_ column: Int32) -> String? { isNull(column) ? nil : string(column) }
    /// Empty string for NULL.
    func string(_ column: Int32) -> String {
        guard let text = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: text)
    }
}

final class SQLiteConnection {
    private let handle: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close(handle)
            throw SQLiteError(code: result, message: message)
        }
        self.handle = handle
        // The Django app may have the file open too.
        sqlite3_busy_timeout(handle, 5000)
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Runs one or more statements without parameters.
    func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    /// Runs a single statement. Returns the number of changed rows.
    @discardableResult
    func run(_ sql: String, _ arguments: [any SQLBindable] = []) throws -> Int {
        try withStatement(sql, arguments) { statement in
            let result = sqlite3_step(statement)
            try check(result)
            return Int(sqlite3_changes(handle))
        }
    }

    /// Runs an INSERT and returns the new row id, or nil if no row was inserted (`INSERT OR IGNORE`).
    func insert(_ sql: String, _ arguments: [any SQLBindable]) throws -> Int64? {
        try run(sql, arguments) > 0 ? sqlite3_last_insert_rowid(handle) : nil
    }

    func query<T>(_ sql: String, _ arguments: [any SQLBindable] = [], _ map: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, arguments) { statement in
            var rows: [T] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return rows }
                guard result == SQLITE_ROW else { try check(result); return rows }
                rows.append(try map(Row(statement: statement)))
            }
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, _ arguments: [any SQLBindable], _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        guard let statement else { throw SQLiteError(code: SQLITE_MISUSE, message: "empty statement: \(sql)") }
        defer { sqlite3_finalize(statement) }
        for (offset, argument) in arguments.enumerated() {
            let index = Int32(offset + 1)
            switch argument.sqlValue {
            case .integer(let value): try check(sqlite3_bind_int64(statement, index, value))
            case .real(let value): try check(sqlite3_bind_double(statement, index, value))
            case .text(let value): try check(sqlite3_bind_text(statement, index, value, -1, sqliteTransient))
            case .null: try check(sqlite3_bind_null(statement, index))
            }
        }
        return try body(statement)
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK || result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(handle)))
        }
    }
}

/// Tells SQLite to copy bound strings.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
