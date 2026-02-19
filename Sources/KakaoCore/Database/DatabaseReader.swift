import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// Reads KakaoTalk's encrypted SQLite database.
///
/// Note: The system sqlite3 on macOS does NOT include SQLCipher.
/// For encrypted database access, you need to install sqlcipher via Homebrew
/// and link against it. This reader provides the interface — if the database
/// is encrypted and sqlcipher is not available, it will fail with a clear error.
public final class DatabaseReader: @unchecked Sendable {
    private var db: OpaquePointer?
    public let databasePath: String

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    deinit {
        close()
    }

    /// Open the database. If a key is provided, attempts PRAGMA key (requires SQLCipher).
    public func open(key: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw KakaoError.databaseNotFound(databasePath)
        }

        let result = sqlite3_open_v2(
            databasePath,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw KakaoError.databaseOpenFailed(msg)
        }

        if let key {
            // SQLCipher compatibility mode 3
            try exec("PRAGMA cipher_compatibility = 3")
            try exec("PRAGMA key = '\(key)'")

            // Verify the key works by reading a table
            do {
                try exec("SELECT count(*) FROM sqlite_master")
            } catch {
                throw KakaoError.databaseOpenFailed(
                    "PRAGMA key failed — database is encrypted and SQLCipher may not be linked. " +
                    "Install via: brew install sqlcipher"
                )
            }
        }
    }

    public func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    // MARK: - Queries

    /// List all chat rooms.
    public func chats(limit: Int = 50) throws -> [Chat] {
        let sql = """
            SELECT id, type, display_name, member_count, last_message_id,
                   last_message_at, unread_count
            FROM chat_room
            ORDER BY last_message_at DESC
            LIMIT ?
            """
        return try query(sql, bind: [.int(limit)]) { row in
            Chat(
                id: row.int64(0),
                type: Chat.ChatType(rawValue: row.string(1) ?? "unknown") ?? .unknown,
                displayName: row.string(2) ?? "(unknown)",
                memberCount: row.int(3),
                lastMessageId: row.optionalInt64(4),
                lastMessageAt: row.optionalDate(5),
                unreadCount: row.int(6)
            )
        }
    }

    /// Get messages for a chat, optionally filtered by time.
    public func messages(chatId: Int64? = nil, since: Date? = nil, limit: Int = 50) throws -> [Message] {
        var conditions: [String] = []
        var bindings: [SQLValue] = []

        if let chatId {
            conditions.append("m.chat_id = ?")
            bindings.append(.int64(chatId))
        }
        if let since {
            conditions.append("m.created_at >= ?")
            bindings.append(.double(since.timeIntervalSince1970))
        }

        let where_ = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let sql = """
            SELECT m.id, m.chat_id, m.sender_id, m.sender_name, m.message,
                   m.type, m.created_at, m.is_from_me
            FROM chat_logs m
            \(where_)
            ORDER BY m.created_at DESC
            LIMIT ?
            """
        bindings.append(.int(limit))

        return try query(sql, bind: bindings) { row in
            Message(
                id: row.int64(0),
                chatId: row.int64(1),
                senderId: row.int64(2),
                senderName: row.string(3),
                text: row.string(4),
                type: Message.MessageType(rawValue: row.int(5)),
                createdAt: row.date(6),
                isFromMe: row.bool(7)
            )
        }
    }

    /// Full-text search across messages.
    public func search(query: String, limit: Int = 20) throws -> [Message] {
        let sql = """
            SELECT m.id, m.chat_id, m.sender_id, m.sender_name, m.message,
                   m.type, m.created_at, m.is_from_me
            FROM chat_logs m
            WHERE m.message LIKE ?
            ORDER BY m.created_at DESC
            LIMIT ?
            """
        return try self.query(sql, bind: [.string("%\(query)%"), .int(limit)]) { row in
            Message(
                id: row.int64(0),
                chatId: row.int64(1),
                senderId: row.int64(2),
                senderName: row.string(3),
                text: row.string(4),
                type: Message.MessageType(rawValue: row.int(5)),
                createdAt: row.date(6),
                isFromMe: row.bool(7)
            )
        }
    }

    /// Discover the actual database schema (useful for reverse engineering).
    public func schema() throws -> [(name: String, sql: String)] {
        try query(
            "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name",
            bind: []
        ) { row in
            (name: row.string(0) ?? "", sql: row.string(1) ?? "")
        }
    }

    // MARK: - SQLite Helpers

    enum SQLValue {
        case int(Int)
        case int64(Int64)
        case double(Double)
        case string(String)
        case null
    }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw KakaoError.sqlError(msg)
        }
    }

    private func query<T>(_ sql: String, bind: [SQLValue], transform: (Row) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw KakaoError.sqlError("prepare: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bind.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int(stmt, idx, Int32(v))
            case .int64(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .string(let v): sqlite3_bind_text(stmt, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(transform(Row(stmt: stmt!)))
        }
        return results
    }

    struct Row {
        let stmt: OpaquePointer

        func int(_ col: Int32) -> Int {
            Int(sqlite3_column_int(stmt, col))
        }

        func int64(_ col: Int32) -> Int64 {
            sqlite3_column_int64(stmt, col)
        }

        func optionalInt64(_ col: Int32) -> Int64? {
            sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : int64(col)
        }

        func string(_ col: Int32) -> String? {
            guard let ptr = sqlite3_column_text(stmt, col) else { return nil }
            return String(cString: ptr)
        }

        func bool(_ col: Int32) -> Bool {
            sqlite3_column_int(stmt, col) != 0
        }

        func date(_ col: Int32) -> Date {
            let ts = sqlite3_column_double(stmt, col)
            return Date(timeIntervalSince1970: ts)
        }

        func optionalDate(_ col: Int32) -> Date? {
            sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : date(col)
        }
    }
}
