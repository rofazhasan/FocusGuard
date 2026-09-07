use std::sync::Arc;
use uuid::Uuid;

use focusguard_windows::application::{EnforcementService, UsageService};
use focusguard_windows::domain::device::DeviceIdentity;
use focusguard_windows::domain::enforcement::EnforcementAction;
use focusguard_windows::domain::policy::{Policy, PolicyTarget, TargetType};
use focusguard_windows::domain::usage::UsageState;
use focusguard_windows::infrastructure::database::Database;
use focusguard_windows::infrastructure::windows::{
    MockForegroundAppProvider, MockIdleDetector, MockProcessController,
};
use focusguard_windows::adapters::repositories::{
    DeviceRepository, EventRepository, PolicyRepository, UsageRepository,
};

#[test]
fn test_usage_tracking_lifecycle() {
    let db = Database::open_in_memory().unwrap();
    let usage_repo = Arc::new(UsageRepository::new(db.clone()));
    let policy_repo = Arc::new(PolicyRepository::new(db.clone()));
    let device_repo = Arc::new(DeviceRepository::new(db.clone()));
    let event_repo = Arc::new(EventRepository::new(db.clone()));

    // Seed device identity
    let mut identity = DeviceIdentity::default();
    identity.device_id = Some(Uuid::new_v4());
    identity.status = focusguard_windows::domain::device::DeviceStatus::Active;
    device_repo.save_device_identity(&identity).unwrap();

    // Configure a 5-second test policy for discord.exe (warning at 3s)
    let policy = Policy {
        id: Uuid::new_v4(),
        user_id: None,
        name: "Test Discord Policy".to_string(),
        limit_seconds: 5,
        warning_threshold_seconds: 3,
        enforcement_action: EnforcementAction::CloseApplication,
        is_enabled: true,
        version: 1,
        targets: vec![PolicyTarget {
            id: Uuid::new_v4(),
            policy_id: Uuid::new_v4(),
            target_type: TargetType::App,
            target_value: "discord.exe".to_string(),
        }],
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
    };
    policy_repo.save_policies(&[policy]).unwrap();

    let fg_provider = Arc::new(MockForegroundAppProvider::new());
    let idle_detector = Arc::new(MockIdleDetector::new());
    let proc_controller = Arc::new(MockProcessController::new());

    let enforcement_service = Arc::new(EnforcementService::new(
        proc_controller.clone(),
        event_repo.clone(),
        Arc::new(|| Some(Uuid::new_v4())),
    ));

    let usage_service = UsageService::new(
        usage_repo.clone(),
        policy_repo.clone(),
        device_repo.clone(),
        event_repo.clone(),
        fg_provider.clone(),
        idle_detector.clone(),
        enforcement_service.clone(),
        60, // 60s idle threshold
    );

    // Initial tick with NO target in foreground -> IDLE
    let state = usage_service.tick().unwrap();
    assert_eq!(state, UsageState::Idle);

    // Bring discord.exe to foreground (PID: 5001)
    fg_provider.set_foreground(5001, "discord.exe", Some("C:\\Discord\\discord.exe"), Some("Discord"));

    // Tick 1: ACTIVE (1s)
    let s1 = usage_service.tick().unwrap();
    assert_eq!(s1, UsageState::Active);

    // Tick 2: ACTIVE (2s)
    let s2 = usage_service.tick().unwrap();
    assert_eq!(s2, UsageState::Active);

    // Tick 3: WARNING (3s >= warning_threshold 3s)
    let s3 = usage_service.tick().unwrap();
    assert_eq!(s3, UsageState::Warning);

    // Tick 4: WARNING (4s)
    let s4 = usage_service.tick().unwrap();
    assert_eq!(s4, UsageState::Warning);

    // Tick 5: LIMIT_REACHED (5s == limit 5s)
    let s5 = usage_service.tick().unwrap();
    assert_eq!(s5, UsageState::LimitReached);

    // Tick 6: RESTRICTED & ENFORCED (6s > limit 5s)
    let s6 = usage_service.tick().unwrap();
    assert_eq!(s6, UsageState::Restricted);

    // Verify enforcement closed process 5001
    assert_eq!(proc_controller.gracefully_closed_pids.lock().unwrap().len(), 1);
    assert_eq!(proc_controller.gracefully_closed_pids.lock().unwrap()[0], 5001);

    // Test idle awareness: user goes idle (> 60s)
    idle_detector.set_idle_seconds(65);
    let idle_state = usage_service.tick().unwrap();
    assert_eq!(idle_state, UsageState::Idle, "Must transition to IDLE when user is inactive");

    // Test workstation locked
    idle_detector.set_idle_seconds(0);
    idle_detector.set_locked(true);
    let locked_state = usage_service.tick().unwrap();
    assert_eq!(locked_state, UsageState::Idle, "Must not track when workstation is locked");
}
