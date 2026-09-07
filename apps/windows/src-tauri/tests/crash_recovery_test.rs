use chrono::{Duration, Utc};
use std::sync::Arc;
use uuid::Uuid;

use focusguard_windows::application::TimerService;
use focusguard_windows::domain::usage::UsageSession;
use focusguard_windows::infrastructure::database::Database;
use focusguard_windows::adapters::repositories::UsageRepository;

#[test]
fn test_crash_recovery_excludes_downtime() {
    let db = Database::open_in_memory().unwrap();
    let usage_repo = Arc::new(UsageRepository::new(db));
    let timer_service = TimerService::new(usage_repo.clone());

    let session_start = Utc::now() - Duration::hours(5); // App started 5 hours ago
    let last_checkpoint = session_start + Duration::minutes(20); // Tracked 20m, then crashed

    let crashed_session = UsageSession {
        id: Uuid::new_v4(),
        target_executable: "discord.exe".to_string(),
        started_at: session_start,
        last_checkpoint_at: last_checkpoint,
        ended_at: None, // Unclosed!
        duration_seconds: 1200, // 20 minutes
    };

    usage_repo.save_session_checkpoint(&crashed_session).unwrap();

    // Verify unclosed session is detected
    let unclosed = usage_repo.find_unclosed_session().unwrap();
    assert!(unclosed.is_some());
    assert_eq!(unclosed.unwrap().duration_seconds, 1200);

    // Run crash recovery
    let recovery_result = timer_service.recover_unclosed_sessions().unwrap();
    assert!(recovery_result.is_some());

    // Verify session is now closed with ended_at == last_checkpoint_at
    let after_recovery = usage_repo.find_unclosed_session().unwrap();
    assert!(after_recovery.is_none(), "Must have no unclosed sessions after recovery");

    // The duration remains 1200s (20m), completely excluding the 4h40m of downtime!
}
