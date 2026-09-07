use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::device::DeviceStatus;
use super::enforcement::EnforcementAction;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TargetType {
    App,
    Website,
    Category,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyTarget {
    pub id: Uuid,
    pub policy_id: Uuid,
    pub target_type: TargetType,
    pub target_value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Policy {
    pub id: Uuid,
    pub user_id: Option<Uuid>,
    pub name: String,
    pub limit_seconds: u32,
    pub warning_threshold_seconds: u32,
    pub enforcement_action: EnforcementAction,
    pub is_enabled: bool,
    pub version: u32,
    pub targets: Vec<PolicyTarget>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PolicyDecision {
    Allow,
    Warn,
    LimitReached,
    Enforce,
    Revoked,
}

impl std::fmt::Display for PolicyDecision {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PolicyDecision::Allow => write!(f, "ALLOW"),
            PolicyDecision::Warn => write!(f, "WARN"),
            PolicyDecision::LimitReached => write!(f, "LIMIT_REACHED"),
            PolicyDecision::Enforce => write!(f, "ENFORCE"),
            PolicyDecision::Revoked => write!(f, "REVOKED"),
        }
    }
}

/// Pure deterministic policy evaluation function.
/// Completely isolated from system calls and network states.
pub fn evaluate(
    usage_seconds: u32,
    daily_limit_seconds: u32,
    warning_threshold_seconds: u32,
    device_state: &DeviceStatus,
) -> PolicyDecision {
    // Invariant: Revoked devices unconditionally lose active policy authority
    if *device_state == DeviceStatus::Revoked {
        return PolicyDecision::Revoked;
    }

    // Zero limit implies unconstrained usage
    if daily_limit_seconds == 0 {
        return PolicyDecision::Allow;
    }

    if usage_seconds > daily_limit_seconds {
        PolicyDecision::Enforce
    } else if usage_seconds == daily_limit_seconds {
        PolicyDecision::LimitReached
    } else if warning_threshold_seconds > 0 && usage_seconds >= warning_threshold_seconds {
        PolicyDecision::Warn
    } else {
        PolicyDecision::Allow
    }
}
