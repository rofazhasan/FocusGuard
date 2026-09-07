import Foundation
import SQLite3

public final class EventQueueRepository: @unchecked Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func enqueueEvent(_ event: EventEnvelope) throws {
        try dbManager.executeWithLock { db in
            let sql = """
            INSERT INTO pending_events (id, event_type, device_id, target, reason, timestamp, metadata, retry_count, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO NOTHING;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare enqueueEvent"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (event.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (event.eventType.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (event.deviceId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (event.target as NSString).utf8String, -1, nil)

            if let r = event.reason {
                sqlite3_bind_text(stmt, 5, (r as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }

            sqlite3_bind_int64(stmt, 6, event.timestamp)

            if let meta = event.metadata, let data = try? JSONSerialization.data(withJSONObject: meta), let str = String(data: data, encoding: .utf8) {
                sqlite3_bind_text(stmt, 7, (str as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 7)
            }

            sqlite3_bind_int(stmt, 8, Int32(event.retryCount))
            sqlite3_bind_text(stmt, 9, (event.status as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to enqueue event: \(errmsg)"])
            }
        }
    }

    public func getPendingEvents(limit: Int = 50) throws -> [EventEnvelope] {
        return try dbManager.executeWithLock { db in
            let sql = "SELECT id, event_type, device_id, target, reason, timestamp, metadata, retry_count, status FROM pending_events WHERE status = 'PENDING' ORDER BY timestamp ASC LIMIT ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getPendingEvents"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            var events: [EventEnvelope] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let typeStr = String(cString: sqlite3_column_text(stmt, 1))
                let devId = String(cString: sqlite3_column_text(stmt, 2))
                let target = String(cString: sqlite3_column_text(stmt, 3))
                let reason = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                let ts = sqlite3_column_int64(stmt, 5)
                let metaStr = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
                let retries = Int(sqlite3_column_int(stmt, 7))
                let status = String(cString: sqlite3_column_text(stmt, 8))

                var metaDict: [String: String]? = nil
                if let str = metaStr, let data = str.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    metaDict = dict
                }

                let envelope = EventEnvelope(
                    id: id,
                    eventType: EventType(rawValue: typeStr) ?? .usageSessionStarted,
                    deviceId: devId,
                    target: target,
                    reason: reason,
                    timestamp: ts,
                    metadata: metaDict,
                    retryCount: retries,
                    status: status
                )
                events.append(envelope)
            }
            return events
        }
    }

    public func markEventsSynced(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbManager.executeWithLock { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = "UPDATE pending_events SET status = 'SYNCED' WHERE id IN (\(placeholders));"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare markEventsSynced"])
            }
            defer { sqlite3_finalize(stmt) }

            for (idx, id) in ids.enumerated() {
                sqlite3_bind_text(stmt, Int32(idx + 1), (id as NSString).utf8String, -1, nil)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to mark events synced: \(errmsg)"])
            }
        }
    }

    public func incrementRetryCount(id: String) throws {
        try dbManager.executeWithLock { db in
            let sql = "UPDATE pending_events SET retry_count = retry_count + 1 WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare incrementRetryCount"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to increment retry count: \(errmsg)"])
            }
        }
    }

    public func getPendingEventCount() throws -> Int {
        return try dbManager.executeWithLock { db in
            let sql = "SELECT COUNT(*) FROM pending_events WHERE status = 'PENDING';"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.EventRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getPendingEventCount"])
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }
}
