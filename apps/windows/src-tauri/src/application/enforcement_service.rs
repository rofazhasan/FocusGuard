use chrono::Utc;
use std::sync::Arc;
use uuid::Uuid;

use crate::domain::enforcement::{is_protected_process, EnforcementAction, EnforcementResult};
use crate::domain::events::{EventType, FocusGuardEvent};
use crate::domain::policy::Policy;
use crate::infrastructure::windows::ProcessController;
use crate::adapters::repositories::EventRepository;

pub struct EnforcementService {
    process_controller: Arc<dyn ProcessController>,
    event_repo: Arc<EventRepository>,
    device_id_getter: Arc<dyn Fn() -> Option<Uuid> + Send + Sync>,
}

impl EnforcementService {
    pub fn new(
        process_controller: Arc<dyn ProcessController>,
        event_repo: Arc<EventRepository>,
        device_id_getter: Arc<dyn Fn() -> Option<Uuid> + Send + Sync>,
    ) -> Self {
        Self {
            process_controller,
            event_repo,
            device_id_getter,
        }
    }

    pub fn execute_enforcement(
        &self,
        policy: &Policy,
        target_executable: &str,
        pid: u32,
    ) -> Result<EnforcementResult, String> {
        let dev_id = (self.device_id_getter)().unwrap_or_else(Uuid::new_v4);

        // Security Invariant: Refuse enforcement on system-critical processes
        if is_protected_process(target_executable) {
            let reason = format!(
                "Security refusal: {} is a critical Windows system process.",
                target_executable
            );
            let event = FocusGuardEvent::new(
                dev_id,
                EventType::EnforcementFailed,
                Some(target_executable),
                &reason,
            );
            let _ = self.event_repo.enqueue_event(&event);

            return Ok(EnforcementResult {
                target: target_executable.to_string(),
                action: policy.enforcement_action,
                executed: false,
                reason,
                timestamp: Utc::now(),
            });
        }

        match policy.enforcement_action {
            EnforcementAction::Notify => {
                let reason = format!(
                    "FocusGuard notification: Daily limit reached for {}.",
                    target_executable
                );
                let event = FocusGuardEvent::new(
                    dev_id,
                    EventType::EnforcementTriggered,
                    Some(target_executable),
                    &reason,
                );
                let _ = self.event_repo.enqueue_event(&event);

                Ok(EnforcementResult {
                    target: target_executable.to_string(),
                    action: EnforcementAction::Notify,
                    executed: true,
                    reason,
                    timestamp: Utc::now(),
                })
            }
            EnforcementAction::CloseApplication => {
                let res = self
                    .process_controller
                    .close_gracefully(pid)
                    .or_else(|_| self.process_controller.terminate_process(pid));

                match res {
                    Ok(_) => {
                        let reason = format!(
                            "Terminated process {} (PID {}) per policy.",
                            target_executable, pid
                        );
                        let event = FocusGuardEvent::new(
                            dev_id,
                            EventType::EnforcementTriggered,
                            Some(target_executable),
                            &reason,
                        );
                        let _ = self.event_repo.enqueue_event(&event);

                        Ok(EnforcementResult {
                            target: target_executable.to_string(),
                            action: EnforcementAction::CloseApplication,
                            executed: true,
                            reason,
                            timestamp: Utc::now(),
                        })
                    }
                    Err(err) => {
                        let reason = format!(
                            "Failed to terminate process {} (PID {}): {}",
                            target_executable, pid, err
                        );
                        let event = FocusGuardEvent::new(
                            dev_id,
                            EventType::EnforcementFailed,
                            Some(target_executable),
                            &reason,
                        );
                        let _ = self.event_repo.enqueue_event(&event);

                        Ok(EnforcementResult {
                            target: target_executable.to_string(),
                            action: EnforcementAction::CloseApplication,
                            executed: false,
                            reason,
                            timestamp: Utc::now(),
                        })
                    }
                }
            }
            EnforcementAction::PauseTracking => {
                let reason = format!("Tracking paused for {}.", target_executable);
                Ok(EnforcementResult {
                    target: target_executable.to_string(),
                    action: EnforcementAction::PauseTracking,
                    executed: true,
                    reason,
                    timestamp: Utc::now(),
                })
            }
        }
    }
}
