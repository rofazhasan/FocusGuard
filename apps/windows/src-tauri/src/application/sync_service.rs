use chrono::Utc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use uuid::Uuid;

use crate::domain::device::DeviceStatus;
use crate::domain::enforcement::EnforcementAction;
use crate::domain::policy::{Policy, PolicyTarget, TargetType};
use crate::infrastructure::api::{ApiClient, UsageDelta};
use crate::adapters::repositories::{DeviceRepository, EventRepository, PolicyRepository, UsageRepository};
use super::device_service::DeviceService;

pub struct SyncService {
    device_service: Arc<DeviceService>,
    device_repo: Arc<DeviceRepository>,
    policy_repo: Arc<PolicyRepository>,
    usage_repo: Arc<UsageRepository>,
    event_repo: Arc<EventRepository>,
    api_client: Arc<ApiClient>,
    sync_sequence: AtomicU32,
}

impl SyncService {
    pub fn new(
        device_service: Arc<DeviceService>,
        device_repo: Arc<DeviceRepository>,
        policy_repo: Arc<PolicyRepository>,
        usage_repo: Arc<UsageRepository>,
        event_repo: Arc<EventRepository>,
        api_client: Arc<ApiClient>,
    ) -> Self {
        Self {
            device_service,
            device_repo,
            policy_repo,
            usage_repo,
            event_repo,
            api_client,
            sync_sequence: AtomicU32::new(1),
        }
    }

    pub fn sync_all(&self) -> Result<(), String> {
        let identity = self.device_repo.get_device_identity()?;
        if identity.status == DeviceStatus::Revoked || identity.status == DeviceStatus::Unregistered {
            return Ok(());
        }

        let creds = match self.device_service.get_credentials()? {
            Some(c) => c,
            None => return Ok(()),
        };

        let token = &creds.device_token;
        let device_id = creds.device_id;

        // 1. Heartbeat
        let hb_res = self.api_client.heartbeat(
            &device_id,
            token,
            &identity.app_version,
            identity.policy_version,
        );
        if let Err(e) = hb_res {
            if e == "DEVICE_REVOKED" {
                self.device_service.handle_revocation()?;
                return Err("Device has been revoked".to_string());
            }
        }

        // 2. Policy Sync
        let sync_res = self.api_client.sync_policies(token);
        match sync_res {
            Ok(pol_resp) => {
                if pol_resp.policy_version >= identity.policy_version {
                    let mut domain_policies = Vec::new();
                    for raw in pol_resp.policies {
                        let enf_action = match raw.enforcement_mode.as_deref() {
                            Some("CLOSE_APPLICATION") => EnforcementAction::CloseApplication,
                            Some("PAUSE_TRACKING") => EnforcementAction::PauseTracking,
                            _ => EnforcementAction::Notify,
                        };

                        let pid = Uuid::parse_str(&raw.id).unwrap_or_else(|_| Uuid::new_v4());
                        let targets: Vec<PolicyTarget> = raw
                            .targets
                            .unwrap_or_default()
                            .into_iter()
                            .map(|t| {
                                let ttype = match t.target_type.as_str() {
                                    "WEBSITE" => TargetType::Website,
                                    "CATEGORY" => TargetType::Category,
                                    _ => TargetType::App,
                                };
                                PolicyTarget {
                                    id: Uuid::parse_str(&t.id).unwrap_or_else(|_| Uuid::new_v4()),
                                    policy_id: pid,
                                    target_type: ttype,
                                    target_value: t.target_value,
                                }
                            })
                            .collect();

                        domain_policies.push(Policy {
                            id: pid,
                            user_id: None,
                            name: raw.name,
                            limit_seconds: raw.limit_seconds,
                            warning_threshold_seconds: raw.warning_threshold_seconds.unwrap_or(0),
                            enforcement_action: enf_action,
                            is_enabled: raw.is_enabled,
                            version: raw.version,
                            targets,
                            created_at: Utc::now(),
                            updated_at: Utc::now(),
                        });
                    }

                    self.policy_repo.save_policies(&domain_policies)?;
                    let mut updated_identity = identity.clone();
                    updated_identity.policy_version = pol_resp.policy_version;
                    self.device_repo.save_device_identity(&updated_identity)?;
                }
            }
            Err(e) => {
                if e == "DEVICE_REVOKED" {
                    self.device_service.handle_revocation()?;
                    return Err("Device has been revoked".to_string());
                }
            }
        }

        // 3. Flush Queued Offline Events
        let pending_events = self.event_repo.list_pending_events(50)?;
        if !pending_events.is_empty() {
            let event_ids: Vec<Uuid> = pending_events.iter().map(|e| e.id).collect();
            let batch_res = self.api_client.send_batch_events(&device_id, token, &pending_events);
            match batch_res {
                Ok(resp) => {
                    if resp.success {
                        let _ = self.event_repo.mark_events_synced(&event_ids);
                    }
                }
                Err(e) => {
                    if e == "DEVICE_REVOKED" {
                        self.device_service.handle_revocation()?;
                        return Err("Device has been revoked".to_string());
                    }
                }
            }
        }

        // 4. Flush Daily Usage Deltas
        let today = Utc::now().format("%Y-%m-%d").to_string();
        let usages = self.usage_repo.list_daily_usage(&today)?;
        if !usages.is_empty() {
            let deltas: Vec<UsageDelta> = usages
                .into_iter()
                .map(|u| UsageDelta {
                    target_value: u.target_executable,
                    duration_seconds: u.total_duration_seconds,
                    date: today.clone(),
                })
                .collect();

            let seq = self.sync_sequence.fetch_add(1, Ordering::SeqCst);
            let usage_res = self.api_client.sync_usage(&device_id, token, seq, &deltas);
            if let Err(e) = usage_res {
                if e == "DEVICE_REVOKED" {
                    self.device_service.handle_revocation()?;
                    return Err("Device has been revoked".to_string());
                }
            }
        }

        Ok(())
    }
}
