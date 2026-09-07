import Foundation
import SQLite3

public final class DatabaseManager: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public let databasePath: String

    public init(path: String) throws {
        self.databasePath = path
        try openDatabase()
        try applyPragmas()
        try runMigrations()
    }

    deinit {
        closeDatabase()
    }

    public static func inMemory() throws -> DatabaseManager {
        return try DatabaseManager(path: ":memory:")
    }

    public static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let focusGuardDir = appSupport.appendingPathComponent("FocusGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: focusGuardDir, withIntermediateDirectories: true)
        return focusGuardDir.appendingPathComponent("focusguard.sqlite").path
    }

    private func openDatabase() throws {
        if sqlite3_open(databasePath, &db) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "FocusGuard.SQLite", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to open SQLite database: \(errmsg)"])
        }
        sqlite3_busy_timeout(db, 5000)
    }

    private func applyPragmas() throws {
        try execute(sql: "PRAGMA journal_mode = WAL;")
        try execute(sql: "PRAGMA synchronous = NORMAL;")
        try execute(sql: "PRAGMA foreign_keys = ON;")
    }

    private func runMigrations() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS device_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            device_id TEXT,
            device_name TEXT NOT NULL,
            platform TEXT NOT NULL,
            client_type TEXT NOT NULL,
            os_version TEXT NOT NULL,
            app_version TEXT NOT NULL,
            status TEXT NOT NULL,
            public_key TEXT,
            registered_at TEXT
        );

        CREATE TABLE IF NOT EXISTS usage_sessions (
            id TEXT PRIMARY KEY,
            target_id TEXT,
            bundle_identifier TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            date TEXT NOT NULL,
            is_closed INTEGER NOT NULL DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_sessions_bundle_date ON usage_sessions (bundle_identifier, date);
        CREATE INDEX IF NOT EXISTS idx_sessions_closed ON usage_sessions (is_closed);

        CREATE TABLE IF NOT EXISTS daily_usage (
            date TEXT NOT NULL,
            bundle_identifier TEXT NOT NULL,
            total_seconds INTEGER NOT NULL DEFAULT 0,
            last_updated TEXT NOT NULL,
            PRIMARY KEY (date, bundle_identifier)
        );

        CREATE TABLE IF NOT EXISTS pending_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            device_id TEXT NOT NULL,
            target TEXT NOT NULL,
            reason TEXT,
            timestamp INTEGER NOT NULL,
            metadata TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'PENDING'
        );

        CREATE INDEX IF NOT EXISTS idx_events_status ON pending_events (status);

        CREATE TABLE IF NOT EXISTS sync_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cached_policies (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            name TEXT NOT NULL,
            limit_seconds INTEGER NOT NULL,
            warning_threshold_seconds INTEGER NOT NULL DEFAULT 0,
            enforcement_action TEXT NOT NULL DEFAULT 'NOTIFY',
            is_enabled INTEGER NOT NULL DEFAULT 1,
            version INTEGER NOT NULL DEFAULT 1,
            targets_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_policies_enabled ON cached_policies (is_enabled);
        """
        try execute(sql: schema)
    }

    public func execute(sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let msg = errmsg != nil ? String(cString: errmsg!) : "Unknown error"
            sqlite3_free(errmsg)
            throw NSError(domain: "FocusGuard.SQLite", code: 500, userInfo: [NSLocalizedDescriptionKey: "SQLite execute error: \(msg) in query: \(sql)"])
        }
    }

    public func executeWithLock<T>(_ block: (OpaquePointer?) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block(db)
    }

    public func closeDatabase() {
        lock.lock()
        defer { lock.unlock() }
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
}
