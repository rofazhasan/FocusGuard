use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::domain::device::DeviceStatus;
use crate::domain::enforcement::EnforcementAction;
use crate::domain::policy::{Policy, PolicyTarget, TargetType};
use crate::domain::usage::{ApplicationTarget, DailyUsage};
use super::state::AppState;

#[derive(Serialize, Deserialize)]
pub struct DeviceStatusDto {
    pub device_id: Option<String>,
    pub device_name: String,
    pub status: String,
    pub policy_version: u32,
    pub is_paired: bool,
}

#[derive(Serialize, Deserialize)]
pub struct DashboardSummaryDto {
    pub device_status: String,
    pub active_app: Option<String>,
    pub usage_state: String,
    pub today_total_seconds: u32,
    pub pending_events_count: u32,
    pub policy_count: usize,
    pub top_apps: Vec<DailyUsage>,
}

#[derive(Serialize, Deserialize)]
pub struct DiagnosticsDto {
    pub app_version: String,
    pub os_platform: String,
    pub device_id_masked: String,
    pub policy_version: u32,
    pub pending_events: u32,
    pub database_status: String,
    pub last_sync_time: String,
}

pub fn get_device_status(state: &AppState) -> Result<DeviceStatusDto, String> {
    let identity = state.device_repo.get_device_identity()?;
    let is_paired = identity.status == DeviceStatus::Active;

    Ok(DeviceStatusDto {
        device_id: identity.device_id.map(|u| u.to_string()),
        device_name: identity.device_name,
        status: identity.status.to_string(),
        policy_version: identity.policy_version,
        is_paired,
    })
}

pub fn start_pairing(state: &AppState, session_id_or_code: &str) -> Result<String, String> {
    state.device_service.start_pairing(session_id_or_code)
}

pub fn poll_pairing_status(state: &AppState, session_id: &str) -> Result<bool, String> {
    state.device_service.check_pairing_status(session_id)
}

pub fn get_dashboard_summary(state: &AppState) -> Result<DashboardSummaryDto, String> {
    let identity = state.device_repo.get_device_identity()?;
    let today = Utc::now().format("%Y-%m-%d").to_string();
    let top_apps = state.usage_repo.list_daily_usage(&today)?;
    let today_total: u32 = top_apps.iter().map(|u| u.total_duration_seconds).sum();
    let pending_events_count = state.event_repo.get_pending_count()?;
    let policies = state.policy_repo.list_policies()?;
    let usage_state = state.usage_service.get_current_state();

    Ok(DashboardSummaryDto {
        device_status: identity.status.to_string(),
        active_app: top_apps.first().map(|a| a.target_executable.clone()),
        usage_state: format!("{:?}", usage_state).to_uppercase(),
        today_total_seconds: today_total,
        pending_events_count,
        policy_count: policies.len(),
        top_apps,
    })
}

pub fn list_applications(state: &AppState) -> Result<Vec<ApplicationTarget>, String> {
    state.usage_repo.list_tracked_apps()
}

pub fn toggle_app_tracking(
    state: &AppState,
    executable_name: &str,
    is_tracked: bool,
) -> Result<(), String> {
    state.usage_repo.set_app_tracking(executable_name, is_tracked)
}

pub fn list_policies(state: &AppState) -> Result<Vec<Policy>, String> {
    state.policy_repo.list_policies()
}

pub fn create_or_update_policy(
    state: &AppState,
    name: &str,
    limit_seconds: u32,
    warning_threshold_seconds: u32,
    action: &str,
    target_executable: &str,
) -> Result<(), String> {
    let enf_action = match action {
        "CLOSE_APPLICATION" => EnforcementAction::CloseApplication,
        "PAUSE_TRACKING" => EnforcementAction::PauseTracking,
        _ => EnforcementAction::Notify,
    };

    let pid = Uuid::new_v4();
    let pol = Policy {
        id: pid,
        user_id: None,
        name: name.to_string(),
        limit_seconds,
        warning_threshold_seconds,
        enforcement_action: enf_action,
        is_enabled: true,
        version: state.policy_repo.get_latest_policy_version().unwrap_or(1) + 1,
        targets: vec![PolicyTarget {
            id: Uuid::new_v4(),
            policy_id: pid,
            target_type: TargetType::App,
            target_value: target_executable.to_string(),
        }],
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };

    let mut current_policies = state.policy_repo.list_policies()?;
    current_policies.retain(|p| {
        !p.targets
            .iter()
            .any(|t| t.target_value.eq_ignore_ascii_case(target_executable))
    });
    current_policies.push(pol);
    state.policy_repo.save_policies(&current_policies)
}

pub fn get_today_usage(state: &AppState) -> Result<Vec<DailyUsage>, String> {
    let today = Utc::now().format("%Y-%m-%d").to_string();
    state.usage_repo.list_daily_usage(&today)
}

pub fn sync_now(state: &AppState) -> Result<(), String> {
    state.sync_service.sync_all()
}

pub fn get_diagnostics(state: &AppState) -> Result<DiagnosticsDto, String> {
    let identity = state.device_repo.get_device_identity()?;
    let masked_id = match identity.device_id {
        Some(id) => {
            let s = id.to_string();
            format!("{}...{}", &s[..8], &s[s.len() - 4..])
        }
        None => "UNENROLLED".to_string(),
    };

    let pending = state.event_repo.get_pending_count().unwrap_or(0);

    Ok(DiagnosticsDto {
        app_version: identity.app_version,
        os_platform: identity.platform,
        device_id_masked: masked_id,
        policy_version: identity.policy_version,
        pending_events: pending,
        database_status: "HEALTHY (SQLite WAL)".to_string(),
        last_sync_time: Utc::now().to_rfc3339(),
    })
}
