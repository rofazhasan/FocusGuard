import Foundation
import SQLite3

public protocol PolicyRepositoryProtocol: Sendable {
    func savePolicy(_ policy: Policy) throws
    func savePolicies(_ policies: [Policy]) throws
    func getPolicy(id: UUID) throws -> Policy?
    func getAllPolicies() throws -> [Policy]
    func getActivePolicies() throws -> [Policy]
    func deletePolicy(id: UUID) throws
    func clearAllPolicies() throws
    func findPolicy(for bundleIdentifier: String) throws -> Policy?
}

public final class PolicyRepository: PolicyRepositoryProtocol, @unchecked Sendable {
    private let dbManager: DatabaseManager
    private let isoFormatter = ISO8601DateFormatter()

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func savePolicy(_ policy: Policy) throws {
        try savePolicies([policy])
    }

    public func savePolicies(_ policies: [Policy]) throws {
        try dbManager.executeWithLock { db in
            let sql = """
            INSERT INTO cached_policies (
                id, user_id, name, limit_seconds, warning_threshold_seconds,
                enforcement_action, is_enabled, version, targets_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                user_id = excluded.user_id,
                name = excluded.name,
                limit_seconds = excluded.limit_seconds,
                warning_threshold_seconds = excluded.warning_threshold_seconds,
                enforcement_action = excluded.enforcement_action,
                is_enabled = excluded.is_enabled,
                version = excluded.version,
                targets_json = excluded.targets_json,
                updated_at = excluded.updated_at;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare savePolicies: \(errmsg)"])
            }
            defer { sqlite3_finalize(stmt) }

            for policy in policies {
                sqlite3_reset(stmt)

                let idStr = policy.id.uuidString
                let userIdStr = policy.userId?.uuidString
                let targetsData = (try? JSONEncoder().encode(policy.targets)) ?? Data("[]".utf8)
                let targetsJson = String(data: targetsData, encoding: .utf8) ?? "[]"
                let createdAtStr = isoFormatter.string(from: policy.createdAt)
                let updatedAtStr = isoFormatter.string(from: policy.updatedAt)

                sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
                if let uId = userIdStr {
                    sqlite3_bind_text(stmt, 2, (uId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_text(stmt, 3, (policy.name as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 4, Int32(policy.limitSeconds))
                sqlite3_bind_int(stmt, 5, Int32(policy.warningThresholdSeconds))
                sqlite3_bind_text(stmt, 6, (policy.enforcementAction.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 7, policy.isEnabled ? 1 : 0)
                sqlite3_bind_int(stmt, 8, Int32(policy.version))
                sqlite3_bind_text(stmt, 9, (targetsJson as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 10, (createdAtStr as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 11, (updatedAtStr as NSString).utf8String, -1, nil)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let errmsg = String(cString: sqlite3_errmsg(db))
                    throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to execute savePolicy: \(errmsg)"])
                }
            }
        }
    }

    public func getPolicy(id: UUID) throws -> Policy? {
        try dbManager.executeWithLock { db in
            let sql = """
            SELECT id, user_id, name, limit_seconds, warning_threshold_seconds,
                   enforcement_action, is_enabled, version, targets_json, created_at, updated_at
            FROM cached_policies WHERE id = ? LIMIT 1;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getPolicy"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return parsePolicy(from: stmt)
            }
            return nil
        }
    }

    public func getAllPolicies() throws -> [Policy] {
        try dbManager.executeWithLock { db in
            let sql = """
            SELECT id, user_id, name, limit_seconds, warning_threshold_seconds,
                   enforcement_action, is_enabled, version, targets_json, created_at, updated_at
            FROM cached_policies ORDER BY created_at DESC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getAllPolicies"])
            }
            defer { sqlite3_finalize(stmt) }

            var results: [Policy] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let policy = parsePolicy(from: stmt) {
                    results.append(policy)
                }
            }
            return results
        }
    }

    public func getActivePolicies() throws -> [Policy] {
        try dbManager.executeWithLock { db in
            let sql = """
            SELECT id, user_id, name, limit_seconds, warning_threshold_seconds,
                   enforcement_action, is_enabled, version, targets_json, created_at, updated_at
            FROM cached_policies WHERE is_enabled = 1 ORDER BY created_at DESC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare getActivePolicies"])
            }
            defer { sqlite3_finalize(stmt) }

            var results: [Policy] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let policy = parsePolicy(from: stmt) {
                    results.append(policy)
                }
            }
            return results
        }
    }

    public func deletePolicy(id: UUID) throws {
        try dbManager.executeWithLock { db in
            let sql = "DELETE FROM cached_policies WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare deletePolicy"])
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                let errmsg = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "FocusGuard.PolicyRepo", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to execute deletePolicy: \(errmsg)"])
            }
        }
    }

    public func clearAllPolicies() throws {
        try dbManager.execute(sql: "DELETE FROM cached_policies;")
    }

    public func findPolicy(for bundleIdentifier: String) throws -> Policy? {
        let activePolicies = try getActivePolicies()
        for policy in activePolicies {
            for target in policy.targets {
                if PolicyEngine.matchesTarget(policyTarget: target, candidateBundleId: bundleIdentifier) {
                    return policy
                }
            }
        }
        return nil
    }

    private func parsePolicy(from stmt: OpaquePointer?) -> Policy? {
        guard let stmt = stmt else { return nil }

        guard let idCStr = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idCStr)) else {
            return nil
        }

        var userId: UUID? = nil
        if let userCStr = sqlite3_column_text(stmt, 1) {
            userId = UUID(uuidString: String(cString: userCStr))
        }

        let name = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        let limitSeconds = Int(sqlite3_column_int(stmt, 3))
        let warningThresholdSeconds = Int(sqlite3_column_int(stmt, 4))
        let enforcementStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "NOTIFY"
        let isEnabled = sqlite3_column_int(stmt, 6) == 1
        let version = Int(sqlite3_column_int(stmt, 7))

        var targets: [PolicyTarget] = []
        if let targetsCStr = sqlite3_column_text(stmt, 8) {
            let jsonString = String(cString: targetsCStr)
            if let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([PolicyTarget].self, from: data) {
                targets = decoded
            }
        }

        let createdAt = sqlite3_column_text(stmt, 9).flatMap {
            isoFormatter.date(from: String(cString: $0))
        } ?? Date()

        let updatedAt = sqlite3_column_text(stmt, 10).flatMap {
            isoFormatter.date(from: String(cString: $0))
        } ?? Date()

        let action = EnforcementAction(rawValue: enforcementStr) ?? .notify

        return Policy(
            id: id,
            userId: userId,
            name: name,
            limitSeconds: limitSeconds,
            warningThresholdSeconds: warningThresholdSeconds,
            enforcementAction: action,
            isEnabled: isEnabled,
            version: version,
            targets: targets,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
