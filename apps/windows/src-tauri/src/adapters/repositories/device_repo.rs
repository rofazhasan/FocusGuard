use chrono::Utc;
use rusqlite::params;
use uuid::Uuid;

use crate::domain::device::{DeviceIdentity, DeviceStatus};
use crate::infrastructure::database::Database;

pub struct DeviceRepository {
    db: Database,
}

impl DeviceRepository {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub fn get_device_identity(&self) -> Result<DeviceIdentity, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT device_id, user_id, device_name, platform, client_type, app_version, status, policy_version, public_key_pem 
                     FROM device_state WHERE id = 'current_device'",
                )?;

                let mut rows = stmt.query([])?;
                if let Some(row) = rows.next()? {
                    let did_str: Option<String> = row.get(0)?;
                    let uid_str: Option<String> = row.get(1)?;
                    let name: String = row.get(2)?;
                    let platform: String = row.get(3)?;
                    let client_type: String = row.get(4)?;
                    let app_version: String = row.get(5)?;
                    let status_str: String = row.get(6)?;
                    let pol_ver: u32 = row.get(7)?;
                    let pubkey: String = row.get(8)?;

                    let status = match status_str.as_str() {
                        "PAIRING" => DeviceStatus::Pairing,
                        "PENDING_APPROVAL" => DeviceStatus::PendingApproval,
                        "ACTIVE" => DeviceStatus::Active,
                        "OFFLINE" => DeviceStatus::Offline,
                        "REVOKED" => DeviceStatus::Revoked,
                        _ => DeviceStatus::Unregistered,
                    };

                    Ok(DeviceIdentity {
                        device_id: did_str.and_then(|s| Uuid::parse_str(&s).ok()),
                        user_id: uid_str.and_then(|s| Uuid::parse_str(&s).ok()),
                        device_name: name,
                        platform,
                        client_type,
                        app_version,
                        status,
                        policy_version: pol_ver,
                        public_key_pem: pubkey,
                    })
                } else {
                    Ok(DeviceIdentity::default())
                }
            })
            .map_err(|e| e.to_string())
    }

    pub fn save_device_identity(&self, identity: &DeviceIdentity) -> Result<(), String> {
        self.db
            .with_conn(|conn| {
                conn.execute(
                    "INSERT INTO device_state (id, device_id, user_id, device_name, platform, client_type, app_version, status, policy_version, public_key_pem, updated_at)
                     VALUES ('current_device', ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                     ON CONFLICT(id) DO UPDATE SET
                        device_id = EXCLUDED.device_id,
                        user_id = EXCLUDED.user_id,
                        device_name = EXCLUDED.device_name,
                        status = EXCLUDED.status,
                        policy_version = EXCLUDED.policy_version,
                        public_key_pem = EXCLUDED.public_key_pem,
                        updated_at = EXCLUDED.updated_at",
                    params![
                        identity.device_id.map(|u| u.to_string()),
                        identity.user_id.map(|u| u.to_string()),
                        identity.device_name,
                        identity.platform,
                        identity.client_type,
                        identity.app_version,
                        identity.status.to_string(),
                        identity.policy_version,
                        identity.public_key_pem,
                        Utc::now().to_rfc3339()
                    ],
                )?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }
}
