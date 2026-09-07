use chrono::Utc;
use rusqlite::params;
use uuid::Uuid;

use crate::domain::enforcement::EnforcementAction;
use crate::domain::policy::{Policy, PolicyTarget, TargetType};
use crate::domain::usage::normalize_process_name;
use crate::infrastructure::database::Database;

pub struct PolicyRepository {
    db: Database,
}

impl PolicyRepository {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub fn save_policies(&self, policies: &[Policy]) -> Result<(), String> {
        self.db
            .with_conn(|conn| {
                let tx = conn.transaction()?;

                // Clear outdated cached policies and replace atomically
                tx.execute("DELETE FROM cached_policies", [])?;

                for p in policies {
                    let enf_action_str = p.enforcement_action.to_string();
                    let now_str = Utc::now().to_rfc3339();

                    for target in &p.targets {
                        let norm_val = match target.target_type {
                            TargetType::App => normalize_process_name(&target.target_value),
                            _ => target.target_value.to_lowercase(),
                        };

                        tx.execute(
                            "INSERT INTO cached_policies (id, name, limit_seconds, warning_threshold_seconds, enforcement_action, is_enabled, version, target_type, target_value, updated_at)
                             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                            params![
                                p.id.to_string(),
                                p.name,
                                p.limit_seconds,
                                p.warning_threshold_seconds,
                                enf_action_str,
                                if p.is_enabled { 1 } else { 0 },
                                p.version,
                                format!("{:?}", target.target_type).to_uppercase(),
                                norm_val,
                                now_str,
                            ],
                        )?;
                    }
                }

                tx.commit()?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    pub fn get_policy_for_target(&self, target_value: &str) -> Result<Option<Policy>, String> {
        let norm_val = normalize_process_name(target_value);

        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT id, name, limit_seconds, warning_threshold_seconds, enforcement_action, is_enabled, version, target_type, target_value
                     FROM cached_policies WHERE target_value = ?1 AND is_enabled = 1 LIMIT 1",
                )?;

                let mut rows = stmt.query(params![norm_val])?;
                if let Some(row) = rows.next()? {
                    let id_str: String = row.get(0)?;
                    let name: String = row.get(1)?;
                    let limit: u32 = row.get(2)?;
                    let warn: u32 = row.get(3)?;
                    let action_str: String = row.get(4)?;
                    let enabled_int: i32 = row.get(5)?;
                    let version: u32 = row.get(6)?;
                    let ttype_str: String = row.get(7)?;
                    let tval: String = row.get(8)?;

                    let pid = Uuid::parse_str(&id_str).unwrap_or_else(|_| Uuid::new_v4());
                    let action = match action_str.as_str() {
                        "CLOSE_APPLICATION" => EnforcementAction::CloseApplication,
                        "PAUSE_TRACKING" => EnforcementAction::PauseTracking,
                        _ => EnforcementAction::Notify,
                    };

                    let ttype = match ttype_str.as_str() {
                        "WEBSITE" => TargetType::Website,
                        "CATEGORY" => TargetType::Category,
                        _ => TargetType::App,
                    };

                    Ok(Some(Policy {
                        id: pid,
                        user_id: None,
                        name,
                        limit_seconds: limit,
                        warning_threshold_seconds: warn,
                        enforcement_action: action,
                        is_enabled: enabled_int == 1,
                        version,
                        targets: vec![PolicyTarget {
                            id: Uuid::new_v4(),
                            policy_id: pid,
                            target_type: ttype,
                            target_value: tval,
                        }],
                        created_at: Utc::now(),
                        updated_at: Utc::now(),
                    }))
                } else {
                    Ok(None)
                }
            })
            .map_err(|e| e.to_string())
    }

    pub fn list_policies(&self) -> Result<Vec<Policy>, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT id, name, limit_seconds, warning_threshold_seconds, enforcement_action, is_enabled, version, target_type, target_value
                     FROM cached_policies ORDER BY name ASC",
                )?;

                let mut rows = stmt.query([])?;
                let mut list = Vec::new();

                while let Some(row) = rows.next()? {
                    let id_str: String = row.get(0)?;
                    let name: String = row.get(1)?;
                    let limit: u32 = row.get(2)?;
                    let warn: u32 = row.get(3)?;
                    let action_str: String = row.get(4)?;
                    let enabled_int: i32 = row.get(5)?;
                    let version: u32 = row.get(6)?;
                    let ttype_str: String = row.get(7)?;
                    let tval: String = row.get(8)?;

                    let pid = Uuid::parse_str(&id_str).unwrap_or_else(|_| Uuid::new_v4());
                    let action = match action_str.as_str() {
                        "CLOSE_APPLICATION" => EnforcementAction::CloseApplication,
                        "PAUSE_TRACKING" => EnforcementAction::PauseTracking,
                        _ => EnforcementAction::Notify,
                    };

                    let ttype = match ttype_str.as_str() {
                        "WEBSITE" => TargetType::Website,
                        "CATEGORY" => TargetType::Category,
                        _ => TargetType::App,
                    };

                    list.push(Policy {
                        id: pid,
                        user_id: None,
                        name,
                        limit_seconds: limit,
                        warning_threshold_seconds: warn,
                        enforcement_action: action,
                        is_enabled: enabled_int == 1,
                        version,
                        targets: vec![PolicyTarget {
                            id: Uuid::new_v4(),
                            policy_id: pid,
                            target_type: ttype,
                            target_value: tval,
                        }],
                        created_at: Utc::now(),
                        updated_at: Utc::now(),
                    });
                }
                Ok(list)
            })
            .map_err(|e| e.to_string())
    }

    pub fn get_latest_policy_version(&self) -> Result<u32, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare("SELECT COALESCE(MAX(version), 1) FROM cached_policies")?;
                let ver: u32 = stmt.query_row([], |r| r.get(0))?;
                Ok(ver)
            })
            .map_err(|e| e.to_string())
    }
}
