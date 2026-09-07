use std::sync::Arc;

use crate::adapters::repositories::UsageRepository;

pub struct TimerService {
    usage_repo: Arc<UsageRepository>,
}

impl TimerService {
    pub fn new(usage_repo: Arc<UsageRepository>) -> Self {
        Self { usage_repo }
    }

    /// Performs safe crash recovery on startup.
    /// Inspects the database for any session left unclosed due to application termination,
    /// power loss, or operating system restart. Sets `ended_at = last_checkpoint_at`.
    /// Invariant: Downtime during crash is never counted toward application usage.
    pub fn recover_unclosed_sessions(&self) -> Result<Option<String>, String> {
        if let Some(session) = self.usage_repo.find_unclosed_session()? {
            let recovery_note = format!(
                "Recovered unclosed session {} for {} (ended at checkpoint {})",
                session.id, session.target_executable, session.last_checkpoint_at
            );
            self.usage_repo.close_session(
                &session.id,
                session.last_checkpoint_at,
                session.duration_seconds,
            )?;
            Ok(Some(recovery_note))
        } else {
            Ok(None)
        }
    }
}
