import Foundation
import SQLite3

public final class DeviceRepository: @unchecked Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func saveDeviceIdentity(_ identity: DeviceIdentity) throws {
        try dbManager.executeWithLock { db in
            let sql = """
            INSERT INTO device_state (id, device_id, device_name, platform, client_type, os_version, app_version, status, public_key, registered_at)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                device_id = excluded.device_id,
                device_name = excluded.device_name,
                platform = excluded.platform,
                client_type = excluded.client_type,
                os_version = excluded.os_version,
                app_version = excluded.app_version,
                status = excluded.status,
                public_key = excluded.public_key,
                registered_at = excluded.registered_at;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.DeviceRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare saveDeviceIdentity"])
            }
            defer { sqlite3_finalize(stmt) }

            let deviceIdStr = identity.deviceId?.uuidString
            if let dId = deviceIdStr {
                sqlite3_bind_text(stmt, 1, (dId as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, (identity.deviceName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (identity.platform as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (identity.clientType as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (identity.osVersion as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (identity.appVersion as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 7, (identity.status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 8, (identity.publicKeyPem as NSString).utf8String, -1, nil)

            if let regDate = identity.registeredAt {
                let dateStr = ISO8601DateFormatter().string(from: regDate)
                sqlite3_bind_text(stmt, 9, (dateStr as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 9)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.DeviceRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to execute saveDeviceIdentity: \(errmsg)"])
            }
        }
    }

    public func getDeviceIdentity() throws -> DeviceIdentity? {
        return try dbManager.executeWithLock { db in
            let sql = "SELECT device_id, device_name, platform, client_type, os_version, app_version, status, public_key, registered_at FROM device_state WHERE id = 1 LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.DeviceRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getDeviceIdentity"])
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                let deviceIdText = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                let deviceName = String(cString: sqlite3_column_text(stmt, 1))
                let platform = String(cString: sqlite3_column_text(stmt, 2))
                let clientType = String(cString: sqlite3_column_text(stmt, 3))
                let osVersion = String(cString: sqlite3_column_text(stmt, 4))
                let appVersion = String(cString: sqlite3_column_text(stmt, 5))
                let statusStr = String(cString: sqlite3_column_text(stmt, 6))
                let publicKey = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

                var regDate: Date? = nil
                if let regText = sqlite3_column_text(stmt, 8) {
                    regDate = ISO8601DateFormatter().date(from: String(cString: regText))
                }

                return DeviceIdentity(
                    deviceId: deviceIdText != nil ? UUID(uuidString: deviceIdText!) : nil,
                    deviceName: deviceName,
                    platform: platform,
                    clientType: clientType,
                    osVersion: osVersion,
                    appVersion: appVersion,
                    status: DeviceState(rawValue: statusStr) ?? .unregistered,
                    publicKeyPem: publicKey,
                    registeredAt: regDate
                )
            }
            return nil
        }
    }

    public func updateStatus(_ status: DeviceState) throws {
        try dbManager.executeWithLock { db in
            let sql = "UPDATE device_state SET status = ? WHERE id = 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.DeviceRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare updateStatus"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (status.rawValue as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.DeviceRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to execute updateStatus: \(errmsg)"])
            }
        }
    }
}
