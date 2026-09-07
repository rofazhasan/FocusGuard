use chrono::{DateTime, Utc};
use rusqlite::params;
use uuid::Uuid;

use crate::domain::usage::{ApplicationTarget, DailyUsage, UsageSession};
use crate::infrastructure::database::Database;

pub struct UsageRepository {
    db: Database,
}

impl UsageRepository {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub fn save_session_checkpoint(&self, session: &UsageSession) -> Result<(), String> {
        self.db
            .with_conn(|conn| {
                conn.execute(
                    "INSERT INTO usage_sessions (id, target_executable, started_at, last_checkpoint_at, ended_at, duration_seconds)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                     ON CONFLICT(id) DO UPDATE SET
                        last_checkpoint_at = EXCLUDED.last_checkpoint_at,
                        ended_at = EXCLUDED.ended_at,
                        duration_seconds = EXCLUDED.duration_seconds",
                    params![
                        session.id.to_string(),
                        session.target_executable,
                        session.started_at.to_rfc3339(),
                        session.last_checkpoint_at.to_rfc3339(),
                        session.ended_at.map(|t| t.to_rfc3339()),
                        session.duration_seconds,
                    ],
                )?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    pub fn close_session(
        &self,
        session_id: &Uuid,
        ended_at: DateTime<Utc>,
        final_duration: u32,
    ) -> Result<(), String> {
        self.db
            .with_conn(|conn| {
                conn.execute(
                    "UPDATE usage_sessions SET ended_at = ?1, last_checkpoint_at = ?1, duration_seconds = ?2
                     WHERE id = ?3",
                    params![
                        ended_at.to_rfc3339(),
                        final_duration,
                        session_id.to_string(),
                    ],
                )?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    /// Finds any unclosed session from a previous run or unexpected crash.
    pub fn find_unclosed_session(&self) -> Result<Option<UsageSession>, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT id, target_executable, started_at, last_checkpoint_at, duration_seconds
                     FROM usage_sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1",
                )?;

                let mut rows = stmt.query([])?;
                if let Some(row) = rows.next()? {
                    let id_str: String = row.get(0)?;
                    let target: String = row.get(1)?;
                    let start_str: String = row.get(2)?;
                    let check_str: String = row.get(3)?;
                    let dur: u32 = row.get(4)?;

                    let sid = Uuid::parse_str(&id_str).unwrap_or_else(|_| Uuid::new_v4());
                    let started_at = DateTime::parse_from_rfc3339(&start_str)
                        .map(|t| t.with_timezone(&Utc))
                        .unwrap_or_else(|_| Utc::now());
                    let last_checkpoint = DateTime::parse_from_rfc3339(&check_str)
                        .map(|t| t.with_timezone(&Utc))
                        .unwrap_or_else(|_| Utc::now());

                    Ok(Some(UsageSession {
                        id: sid,
                        target_executable: target,
                        started_at,
                        last_checkpoint_at: last_checkpoint,
                        ended_at: None,
                        duration_seconds: dur,
                    }))
                } else {
                    Ok(None)
                }
            })
            .map_err(|e| e.to_string())
    }

    pub fn get_daily_usage(&self, date: &str, target_executable: &str) -> Result<u32, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT total_duration_seconds FROM daily_usage WHERE date = ?1 AND target_executable = ?2",
                )?;
                let mut rows = stmt.query(params![date, target_executable])?;
                if let Some(row) = rows.next()? {
                    let sec: u32 = row.get(0)?;
                    Ok(sec)
                } else {
                    Ok(0)
                }
            })
            .map_err(|e| e.to_string())
    }

    pub fn add_daily_usage(
        &self,
        date: &str,
        target_executable: &str,
        delta_seconds: u32,
    ) -> Result<u32, String> {
        self.db
            .with_conn(|conn| {
                conn.execute(
                    "INSERT INTO daily_usage (date, target_executable, total_duration_seconds, updated_at)
                     VALUES (?1, ?2, ?3, ?4)
                     ON CONFLICT(date, target_executable) DO UPDATE SET
                        total_duration_seconds = daily_usage.total_duration_seconds + EXCLUDED.total_duration_seconds,
                        updated_at = EXCLUDED.updated_at",
                    params![
                        date,
                        target_executable,
                        delta_seconds,
                        Utc::now().to_rfc3339(),
                    ],
                )?;

                let mut stmt = conn.prepare(
                    "SELECT total_duration_seconds FROM daily_usage WHERE date = ?1 AND target_executable = ?2",
                )?;
                let total: u32 = stmt.query_row(params![date, target_executable], |r| r.get(0))?;
                Ok(total)
            })
            .map_err(|e| e.to_string())
    }

    pub fn list_daily_usage(&self, date: &str) -> Result<Vec<DailyUsage>, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT date, target_executable, total_duration_seconds, updated_at
                     FROM daily_usage WHERE date = ?1 ORDER BY total_duration_seconds DESC",
                )?;

                let mut rows = stmt.query(params![date])?;
                let mut list = Vec::new();
                while let Some(row) = rows.next()? {
                    let d: String = row.get(0)?;
                    let t: String = row.get(1)?;
                    let dur: u32 = row.get(2)?;
                    let up_str: String = row.get(3)?;
                    let updated_at = DateTime::parse_from_rfc3339(&up_str)
                        .map(|t| t.with_timezone(&Utc))
                        .unwrap_or_else(|_| Utc::now());

                    list.push(DailyUsage {
                        date: d,
                        target_executable: t,
                        total_duration_seconds: dur,
                        updated_at,
                    });
                }
                Ok(list)
            })
            .map_err(|e| e.to_string())
    }

    pub fn register_discovered_app(&self, executable_name: &str, display_name: &str) -> Result<(), String> {
        self.db
            .with_conn(|conn| {
                conn.execute(
                    "INSERT INTO tracked_apps (executable_name, display_name, is_tracked, discovered_at)
                     VALUES (?1, ?2, 1, ?3)
                     ON CONFLICT(executable_name) DO NOTHING",
                    params![executable_name, display_name, Utc::now().to_rfc3339()],
                )?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    pub fn set_app_tracking(&self, executable_name: &str, is_tracked: bool) -> Result<(), String> {
        self.db
            .with_conn(|conn| {
                conn.execute(
                    "UPDATE tracked_apps SET is_tracked = ?1 WHERE executable_name = ?2",
                    params![if is_tracked { 1 } else { 0 }, executable_name],
                )?;
                Ok(())
            })
            .map_err(|e| e.to_string())
    }

    pub fn list_tracked_apps(&self) -> Result<Vec<ApplicationTarget>, String> {
        self.db
            .with_conn(|conn| {
                let mut stmt = conn.prepare(
                    "SELECT executable_name, display_name, is_tracked FROM tracked_apps ORDER BY executable_name ASC",
                )?;
                let mut rows = stmt.query([])?;
                let mut list = Vec::new();
                while let Some(row) = rows.next()? {
                    let exe: String = row.get(0)?;
                    let disp: String = row.get(1)?;
                    let tracked_int: i32 = row.get(2)?;
                    list.push(ApplicationTarget {
                        id: Uuid::new_v4(),
                        executable_name: exe,
                        executable_path: None,
                        display_name: disp,
                        is_tracked: tracked_int == 1,
                    });
                }
                Ok(list)
            })
            .map_err(|e| e.to_string())
    }
}
