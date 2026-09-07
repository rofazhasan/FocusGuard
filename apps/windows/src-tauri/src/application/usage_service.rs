use chrono::Utc;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

use crate::domain::device::DeviceStatus;
use crate::domain::events::{EventType, FocusGuardEvent};
use crate::domain::policy::{evaluate, PolicyDecision};
use crate::domain::usage::{normalize_process_name, UsageSession, UsageState};
use crate::infrastructure::windows::{ForegroundAppProvider, IdleDetector};
use crate::adapters::repositories::{DeviceRepository, EventRepository, PolicyRepository, UsageRepository};
use super::enforcement_service::EnforcementService;

pub struct UsageService {
    usage_repo: Arc<UsageRepository>,
    policy_repo: Arc<PolicyRepository>,
    device_repo: Arc<DeviceRepository>,
    event_repo: Arc<EventRepository>,
    foreground_provider: Arc<dyn ForegroundAppProvider>,
    idle_detector: Arc<dyn IdleDetector>,
    enforcement_service: Arc<EnforcementService>,
    current_session: Arc<Mutex<Option<UsageSession>>>,
    current_state: Arc<Mutex<UsageState>>,
    idle_threshold_seconds: u32,
}

impl UsageService {
    pub fn new(
        usage_repo: Arc<UsageRepository>,
        policy_repo: Arc<PolicyRepository>,
        device_repo: Arc<DeviceRepository>,
        event_repo: Arc<EventRepository>,
        foreground_provider: Arc<dyn ForegroundAppProvider>,
        idle_detector: Arc<dyn IdleDetector>,
        enforcement_service: Arc<EnforcementService>,
        idle_threshold_seconds: u32,
    ) -> Self {
        Self {
            usage_repo,
            policy_repo,
            device_repo,
            event_repo,
            foreground_provider,
            idle_detector,
            enforcement_service,
            current_session: Arc::new(Mutex::new(None)),
            current_state: Arc::new(Mutex::new(UsageState::Idle)),
            idle_threshold_seconds,
        }
    }

    /// Primary tracking tick executed once per second.
    pub fn tick(&self) -> Result<UsageState, String> {
        let identity = self.device_repo.get_device_identity()?;
        let dev_id = identity.device_id.unwrap_or_else(Uuid::new_v4);

        if identity.status == DeviceStatus::Revoked {
            let mut state_lock = self.current_state.lock().unwrap();
            *state_lock = UsageState::Restricted;
            return Ok(UsageState::Restricted);
        }

        // 1. Inspect idle & workstation lock state
        if self.idle_detector.is_idle(self.idle_threshold_seconds) {
            self.pause_current_session()?;
            let mut state_lock = self.current_state.lock().unwrap();
            *state_lock = UsageState::Idle;
            return Ok(UsageState::Idle);
        }

        // 2. Inspect active foreground application
        let foreground_app = self.foreground_provider.get_foreground_app()?;
        let fg = match foreground_app {
            Some(app) => app,
            None => {
                self.pause_current_session()?;
                let mut state_lock = self.current_state.lock().unwrap();
                *state_lock = UsageState::Idle;
                return Ok(UsageState::Idle);
            }
        };

        let target_exe = normalize_process_name(&fg.executable_name);

        // Register discovered app into tracked_apps list
        let _ = self.usage_repo.register_discovered_app(&target_exe, &target_exe);

        // 3. Match against configured policies
        let active_policy = self.policy_repo.get_policy_for_target(&target_exe)?;

        let today_str = Utc::now().format("%Y-%m-%d").to_string();
        let mut daily_total = self.usage_repo.get_daily_usage(&today_str, &target_exe)?;

        let mut session_lock = self.current_session.lock().unwrap();

        // Check if session switched
        let need_new_session = match &*session_lock {
            Some(s) => s.target_executable != target_exe,
            None => true,
        };

        if need_new_session {
            // Close previous session if exists
            if let Some(mut prev) = session_lock.take() {
                prev.ended_at = Some(Utc::now());
                let _ = self.usage_repo.close_session(&prev.id, prev.ended_at.unwrap(), prev.duration_seconds);
                let evt = FocusGuardEvent::new(
                    dev_id,
                    EventType::UsageSessionEnded,
                    Some(&prev.target_executable),
                    "Target window lost foreground",
                );
                let _ = self.event_repo.enqueue_event(&evt);
            }

            let new_session = UsageSession {
                id: Uuid::new_v4(),
                target_executable: target_exe.clone(),
                started_at: Utc::now(),
                last_checkpoint_at: Utc::now(),
                ended_at: None,
                duration_seconds: 0,
            };
            self.usage_repo.save_session_checkpoint(&new_session)?;
            let evt = FocusGuardEvent::new(
                dev_id,
                EventType::UsageSessionStarted,
                Some(&target_exe),
                "Application focused in foreground",
            );
            let _ = self.event_repo.enqueue_event(&evt);

            *session_lock = Some(new_session);
        }

        // Increment active session
        if let Some(session) = session_lock.as_mut() {
            session.duration_seconds += 1;
            session.last_checkpoint_at = Utc::now();
            self.usage_repo.save_session_checkpoint(session)?;
            daily_total = self.usage_repo.add_daily_usage(&today_str, &target_exe, 1)?;
        }

        drop(session_lock);

        // 4. Evaluate Policy Decision
        let (limit_sec, warn_sec) = if let Some(p) = &active_policy {
            (p.limit_seconds, p.warning_threshold_seconds)
        } else {
            (0, 0)
        };

        let decision = evaluate(daily_total, limit_sec, warn_sec, &identity.status);

        let new_state = match decision {
            PolicyDecision::Allow => UsageState::Active,
            PolicyDecision::Warn => {
                let evt = FocusGuardEvent::new(
                    dev_id,
                    EventType::UsageLimitWarning,
                    Some(&target_exe),
                    &format!("Warning threshold of {}s reached for {}", warn_sec, target_exe),
                );
                let _ = self.event_repo.enqueue_event(&evt);
                UsageState::Warning
            }
            PolicyDecision::LimitReached => {
                let evt = FocusGuardEvent::new(
                    dev_id,
                    EventType::LimitReached,
                    Some(&target_exe),
                    &format!("Daily limit of {}s reached for {}", limit_sec, target_exe),
                );
                let _ = self.event_repo.enqueue_event(&evt);
                UsageState::LimitReached
            }
            PolicyDecision::Enforce => {
                if let Some(p) = &active_policy {
                    let _ = self.enforcement_service.execute_enforcement(p, &target_exe, fg.pid);
                }
                UsageState::Restricted
            }
            PolicyDecision::Revoked => UsageState::Restricted,
        };

        let mut state_lock = self.current_state.lock().unwrap();
        *state_lock = new_state;
        Ok(new_state)
    }

    pub fn pause_current_session(&self) -> Result<(), String> {
        let mut session_lock = self.current_session.lock().unwrap();
        if let Some(mut s) = session_lock.take() {
            s.ended_at = Some(Utc::now());
            self.usage_repo.close_session(&s.id, s.ended_at.unwrap(), s.duration_seconds)?;

            let identity = self.device_repo.get_device_identity()?;
            let dev_id = identity.device_id.unwrap_or_else(Uuid::new_v4);
            let evt = FocusGuardEvent::new(
                dev_id,
                EventType::UsageSessionEnded,
                Some(&s.target_executable),
                "Session paused",
            );
            let _ = self.event_repo.enqueue_event(&evt);
        }
        Ok(())
    }

    pub fn get_current_state(&self) -> UsageState {
        *self.current_state.lock().unwrap()
    }
}
