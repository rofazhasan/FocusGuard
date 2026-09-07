use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApplicationTarget {
    pub id: Uuid,
    pub executable_name: String,
    pub executable_path: Option<String>,
    pub display_name: String,
    pub is_tracked: bool,
}

impl ApplicationTarget {
    pub fn new(executable_name: &str, display_name: &str) -> Self {
        Self {
            id: Uuid::new_v4(),
            executable_name: normalize_process_name(executable_name),
            executable_path: None,
            display_name: display_name.to_string(),
            is_tracked: true,
        }
    }
}

pub fn normalize_process_name(name: &str) -> String {
    let trimmed = name.trim().to_lowercase();
    let basename = if let Some(idx) = trimmed.rfind('\\') {
        &trimmed[idx + 1..]
    } else if let Some(idx) = trimmed.rfind('/') {
        &trimmed[idx + 1..]
    } else {
        &trimmed
    };

    if !basename.ends_with(".exe") {
        format!("{}.exe", basename)
    } else {
        basename.to_string()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum UsageState {
    Idle,
    Active,
    Paused,
    Warning,
    LimitReached,
    Restricted,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageSession {
    pub id: Uuid,
    pub target_executable: String,
    pub started_at: DateTime<Utc>,
    pub last_checkpoint_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub duration_seconds: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyUsage {
    pub date: String, // YYYY-MM-DD
    pub target_executable: String,
    pub total_duration_seconds: u32,
    pub updated_at: DateTime<Utc>,
}
