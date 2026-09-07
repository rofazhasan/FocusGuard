use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EventType {
    UsageSessionStarted,
    UsageSessionEnded,
    UsageLimitWarning,
    LimitReached,
    EnforcementTriggered,
    EnforcementFailed,
    PolicySynced,
    SyncFailed,
    DeviceStarted,
    DeviceStopped,
    DeviceRevoked,
}

impl std::fmt::Display for EventType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EventType::UsageSessionStarted => write!(f, "USAGE_SESSION_STARTED"),
            EventType::UsageSessionEnded => write!(f, "USAGE_SESSION_ENDED"),
            EventType::UsageLimitWarning => write!(f, "USAGE_LIMIT_WARNING"),
            EventType::LimitReached => write!(f, "LIMIT_REACHED"),
            EventType::EnforcementTriggered => write!(f, "ENFORCEMENT_TRIGGERED"),
            EventType::EnforcementFailed => write!(f, "ENFORCEMENT_FAILED"),
            EventType::PolicySynced => write!(f, "POLICY_SYNCED"),
            EventType::SyncFailed => write!(f, "SYNC_FAILED"),
            EventType::DeviceStarted => write!(f, "DEVICE_STARTED"),
            EventType::DeviceStopped => write!(f, "DEVICE_STOPPED"),
            EventType::DeviceRevoked => write!(f, "DEVICE_REVOKED"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EventSyncStatus {
    Pending,
    Synced,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusGuardEvent {
    pub id: Uuid,
    pub device_id: Uuid,
    pub event_type: EventType,
    pub target: Option<String>,
    pub reason: String,
    pub timestamp: DateTime<Utc>,
    pub sync_status: EventSyncStatus,
    pub metadata: Option<serde_json::Value>,
}

impl FocusGuardEvent {
    pub fn new(
        device_id: Uuid,
        event_type: EventType,
        target: Option<&str>,
        reason: &str,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            device_id,
            event_type,
            target: target.map(|s| s.to_string()),
            reason: reason.to_string(),
            timestamp: Utc::now(),
            sync_status: EventSyncStatus::Pending,
            metadata: None,
        }
    }
}
