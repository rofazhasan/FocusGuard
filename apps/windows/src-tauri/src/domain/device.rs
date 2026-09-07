use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DeviceStatus {
    Unregistered,
    Pairing,
    PendingApproval,
    Active,
    Offline,
    Revoked,
}

impl std::fmt::Display for DeviceStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DeviceStatus::Unregistered => write!(f, "UNREGISTERED"),
            DeviceStatus::Pairing => write!(f, "PAIRING"),
            DeviceStatus::PendingApproval => write!(f, "PENDING_APPROVAL"),
            DeviceStatus::Active => write!(f, "ACTIVE"),
            DeviceStatus::Offline => write!(f, "OFFLINE"),
            DeviceStatus::Revoked => write!(f, "REVOKED"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceIdentity {
    pub device_id: Option<Uuid>,
    pub user_id: Option<Uuid>,
    pub device_name: String,
    pub platform: String,
    pub client_type: String,
    pub app_version: String,
    pub status: DeviceStatus,
    pub policy_version: u32,
    pub public_key_pem: String,
}

impl Default for DeviceIdentity {
    fn default() -> Self {
        Self {
            device_id: None,
            user_id: None,
            device_name: "Windows — PC".to_string(),
            platform: "WINDOWS".to_string(),
            client_type: "WINDOWS_AGENT".to_string(),
            app_version: "0.3.0".to_string(),
            status: DeviceStatus::Unregistered,
            policy_version: 1,
            public_key_pem: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceCredentials {
    pub device_id: Uuid,
    pub user_id: Option<Uuid>,
    pub device_token: String,
    pub credential_version: u32,
    pub created_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
}
