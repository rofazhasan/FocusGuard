use chrono::{DateTime, Utc};
use rusqlite::params;
use uuid::Uuid;

use crate::domain::events::{EventSyncStatus, EventType, FocusGuardEvent};
use crate::infrastructure::database::Database;

pub struct EventRepository {
    db: Database,
}

impl EventRepository {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub fn enqueue_event(&self, event: &FocusGuardEvent) -> Result<(), String> {
        let meta_str = event.metadata.as_ref().map(|m| m.to_string());

        self.db
            .with_conn(|conn| {
                conn.execute(
                    "INSERT INTO pending_events (id, device_id, event_type, target, reason, timestamp, sync_status, metadata_json)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'PENDING', ?7)",
                    params![
                        event.id.to_string(),
                        event.device_id.to_string(),
                        event.event_type.to_string(),
                        event.target,
                        event.reason,
                        event.timestamp.to_rfc3339(),
                        meta_str,
                    ],
                )?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    pub fn list_pending_events(&self, limit: u32) -> Result<Vec<FocusGuardEvent>, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT id, device_id, event_type, target, reason, timestamp, sync_status, metadata_json
                     FROM pending_events WHERE sync_status = 'PENDING' ORDER BY timestamp ASC LIMIT ?1",
                )?;

                let mut rows = stmt.query(params![limit])?;
                let mut list = Vec::new();

                while let Some(row) = rows.next()? {
                    let id_str: String = row.get(0)?;
                    let did_str: String = row.get(1)?;
                    let type_str: String = row.get(2)?;
                    let target: Option<String> = row.get(3)?;
                    let reason: String = row.get(4)?;
                    let time_str: String = row.get(5)?;
                    let _status_str: String = row.get(6)?;
                    let meta_str: Option<String> = row.get(7)?;

                    let id = Uuid::parse_str(&id_str).unwrap_or_else(|_| Uuid::new_v4());
                    let did = Uuid::parse_str(&did_str).unwrap_or_else(|_| Uuid::new_v4());
                    let timestamp = DateTime::parse_from_rfc3339(&time_str)
                        .map(|t| t.with_timezone(&Utc))
                        .unwrap_or_else(|_| Utc::now());

                    let event_type = match type_str.as_str() {
                        "USAGE_SESSION_STARTED" => EventType::UsageSessionStarted,
                        "USAGE_SESSION_ENDED" => EventType::UsageSessionEnded,
                        "USAGE_LIMIT_WARNING" => EventType::UsageLimitWarning,
                        "LIMIT_REACHED" => EventType::LimitReached,
                        "ENFORCEMENT_TRIGGERED" => EventType::EnforcementTriggered,
                        "ENFORCEMENT_FAILED" => EventType::EnforcementFailed,
                        "POLICY_SYNCED" => EventType::PolicySynced,
                        "SYNC_FAILED" => EventType::SyncFailed,
                        "DEVICE_STARTED" => EventType::DeviceStarted,
                        "DEVICE_STOPPED" => EventType::DeviceStopped,
                        "DEVICE_REVOKED" => EventType::DeviceRevoked,
                        _ => EventType::UsageSessionEnded,
                    };

                    let metadata = meta_str.and_then(|s| serde_json::from_str(&s).ok());

                    list.push(FocusGuardEvent {
                        id,
                        device_id: did,
                        event_type,
                        target,
                        reason,
                        timestamp,
                        sync_status: EventSyncStatus::Pending,
                        metadata,
                    });
                }

                Ok(list)
            })
            .map_err(|e| e.to_string())
    }

    pub fn mark_events_synced(&self, event_ids: &[Uuid]) -> Result<(), String> {
        if event_ids.is_empty() {
            return Ok(());
        }

        self.db
            .with_conn(|conn| {
                let tx = conn.transaction()?;
                for id in event_ids {
                    tx.execute(
                        "UPDATE pending_events SET sync_status = 'SYNCED' WHERE id = ?1",
                        params![id.to_string()],
                    )?;
                }
                tx.commit()?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    pub fn get_pending_count(&self) -> Result<u32, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare("SELECT COUNT(*) FROM pending_events WHERE sync_status = 'PENDING'")?;
                let count: u32 = stmt.query_row([], |r| r.get(0))?;
                Ok(count)
            })
            .map_err(|e| e.to_string())
    }
}
