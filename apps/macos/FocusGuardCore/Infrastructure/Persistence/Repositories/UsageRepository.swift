import Foundation
import SQLite3

public final class UsageRepository: @unchecked Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func insertUsageSession(_ session: UsageSession) throws {
        try dbManager.executeWithLock { db in
            let sql = """
            INSERT INTO usage_sessions (id, target_id, bundle_identifier, started_at, ended_at, duration_seconds, date, is_closed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insertUsageSession"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (session.id.uuidString as NSString).utf8String, -1, nil)
            if let tId = session.targetId {
                sqlite3_bind_text(stmt, 2, (tId.uuidString as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, (session.bundleIdentifier as NSString).utf8String, -1, nil)

            let startStr = ISO8601DateFormatter().string(from: session.startedAt)
            sqlite3_bind_text(stmt, 4, (startStr as NSString).utf8String, -1, nil)

            if let ended = session.endedAt {
                let endStr = ISO8601DateFormatter().string(from: ended)
                sqlite3_bind_text(stmt, 5, (endStr as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }

            sqlite3_bind_int(stmt, 6, Int32(session.durationSeconds))
            sqlite3_bind_text(stmt, 7, (session.date as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 8, session.isClosed ? 1 : 0)

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to insert usage session: \(errmsg)"])
            }
        }
    }

    public func updateSessionDuration(id: UUID, durationSeconds: Int, endedAt: Date? = nil, isClosed: Bool = false) throws {
        try dbManager.executeWithLock { db in
            let sql = """
            UPDATE usage_sessions
            SET duration_seconds = ?,
                ended_at = ?,
                is_closed = ?
            WHERE id = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare updateSessionDuration"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(durationSeconds))
            if let ended = endedAt {
                let endStr = ISO8601DateFormatter().string(from: ended)
                sqlite3_bind_text(stmt, 2, (endStr as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_int(stmt, 3, isClosed ? 1 : 0)
            sqlite3_bind_text(stmt, 4, (id.uuidString as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to update session duration: \(errmsg)"])
            }
        }
    }

    public func getOpenSessions() throws -> [UsageSession] {
        return try dbManager.executeWithLock { db in
            let sql = "SELECT id, target_id, bundle_identifier, started_at, ended_at, duration_seconds, date, is_closed FROM usage_sessions WHERE is_closed = 0;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getOpenSessions"])
            }
            defer { sqlite3_finalize(stmt) }

            var sessions: [UsageSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = String(cString: sqlite3_column_text(stmt, 0))
                let targetIdStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let bundleId = String(cString: sqlite3_column_text(stmt, 2))
                let startedStr = String(cString: sqlite3_column_text(stmt, 3))
                let endedStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                let duration = Int(sqlite3_column_int(stmt, 5))
                let dateStr = String(cString: sqlite3_column_text(stmt, 6))
                let isClosed = sqlite3_column_int(stmt, 7) == 1

                let startedAt = ISO8601DateFormatter().date(from: startedStr) ?? Date()
                let endedAt = endedStr != nil ? ISO8601DateFormatter().date(from: endedStr!) : nil

                let session = UsageSession(
                    id: UUID(uuidString: idStr) ?? UUID(),
                    targetId: targetIdStr != nil ? UUID(uuidString: targetIdStr!) : nil,
                    bundleIdentifier: bundleId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: duration,
                    date: dateStr,
                    isClosed: isClosed
                )
                sessions.append(session)
            }
            return sessions
        }
    }

    public func incrementDailyUsage(date: String, bundleIdentifier: String, deltaSeconds: Int) throws {
        try dbManager.executeWithLock { db in
            let sql = """
            INSERT INTO daily_usage (date, bundle_identifier, total_seconds, last_updated)
            VALUES (?, ?, ?, ?)
            ON CONFLICT (date, bundle_identifier) DO UPDATE SET
                total_seconds = daily_usage.total_seconds + excluded.total_seconds,
                last_updated = excluded.last_updated;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare incrementDailyUsage"])
            }
            defer { sqlite3_finalize(stmt) }

            let cleanBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let nowStr = ISO8601DateFormatter().string(from: Date())

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (cleanBundle as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 3, Int32(deltaSeconds))
            sqlite3_bind_text(stmt, 4, (nowStr as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to increment daily usage: \(errmsg)"])
            }
        }
    }

    public func getDailyUsage(date: String, bundleIdentifier: String) throws -> Int {
        return try dbManager.executeWithLock { db in
            let sql = "SELECT total_seconds FROM daily_usage WHERE date = ? AND bundle_identifier = ? LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getDailyUsage"])
            }
            defer { sqlite3_finalize(stmt) }

            let cleanBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (cleanBundle as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    public func getAllDailyUsage(date: String) throws -> [DailyUsageRecord] {
        return try dbManager.executeWithLock { db in
            let sql = "SELECT date, bundle_identifier, total_seconds, last_updated FROM daily_usage WHERE date = ? ORDER BY total_seconds DESC;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getAllDailyUsage"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)

            var records: [DailyUsageRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let d = String(cString: sqlite3_column_text(stmt, 0))
                let bundle = String(cString: sqlite3_column_text(stmt, 1))
                let secs = Int(sqlite3_column_int(stmt, 2))
                let updatedStr = String(cString: sqlite3_column_text(stmt, 3))
                let updatedDate = ISO8601DateFormatter().date(from: updatedStr) ?? Date()

                records.append(DailyUsageRecord(
                    date: d,
                    bundleIdentifier: bundle,
                    totalSeconds: secs,
                    lastUpdated: updatedDate
                ))
            }
            return records
        }
    }

    public func getRecentSessions(limit: Int = 20) throws -> [UsageSession] {
        return try dbManager.executeWithLock { db in
            let sql = """
            SELECT id, target_id, bundle_identifier, started_at, ended_at, duration_seconds, date, is_closed
            FROM usage_sessions
            ORDER BY started_at DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.UsageRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getRecentSessions"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            var sessions: [UsageSession] = []
            let formatter = ISO8601DateFormatter()

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCStr = sqlite3_column_text(stmt, 0),
                      let id = UUID(uuidString: String(cString: idCStr)) else {
                    continue
                }

                var targetId: UUID? = nil
                if let tCStr = sqlite3_column_text(stmt, 1) {
                    targetId = UUID(uuidString: String(cString: tCStr))
                }

                let bundle = String(cString: sqlite3_column_text(stmt, 2))
                let startedStr = String(cString: sqlite3_column_text(stmt, 3))
                let startedAt = formatter.date(from: startedStr) ?? Date()

                var endedAt: Date? = nil
                if let endedCStr = sqlite3_column_text(stmt, 4) {
                    endedAt = formatter.date(from: String(cString: endedCStr))
                }

                let duration = Int(sqlite3_column_int(stmt, 5))
                let date = String(cString: sqlite3_column_text(stmt, 6))
                let isClosed = sqlite3_column_int(stmt, 7) == 1

                sessions.append(UsageSession(
                    id: id,
                    targetId: targetId,
                    bundleIdentifier: bundle,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: duration,
                    date: date,
                    isClosed: isClosed
                ))
            }
            return sessions
        }
    }
}
