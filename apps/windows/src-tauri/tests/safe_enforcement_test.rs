use std::sync::Arc;
use uuid::Uuid;

use focusguard_windows::application::EnforcementService;
use focusguard_windows::domain::enforcement::{is_protected_process, EnforcementAction};
use focusguard_windows::domain::policy::{Policy, PolicyTarget, TargetType};
use focusguard_windows::infrastructure::database::Database;
use focusguard_windows::infrastructure::windows::MockProcessController;
use focusguard_windows::adapters::repositories::EventRepository;

#[test]
fn test_protected_process_denylist() {
    // Critical system processes must be refused
    assert!(is_protected_process("System"));
    assert!(is_protected_process("system"));
    assert!(is_protected_process("csrss.exe"));
    assert!(is_protected_process("CSRSS.EXE"));
    assert!(is_protected_process("C:\\Windows\\System32\\csrss.exe"));
    assert!(is_protected_process("winlogon.exe"));
    assert!(is_protected_process("services.exe"));
    assert!(is_protected_process("lsass.exe"));
    assert!(is_protected_process("smss.exe"));
    assert!(is_protected_process("explorer.exe"));
    assert!(is_protected_process("focusguard.exe"));
    assert!(is_protected_process("focusguard-windows.exe"));

    // Normal user productivity/entertainment targets must not be in denylist
    assert!(!is_protected_process("discord.exe"));
    assert!(!is_protected_process("chrome.exe"));
    assert!(!is_protected_process("steam.exe"));
    assert!(!is_protected_process("spotify.exe"));
    assert!(!is_protected_process("code.exe"));
}

#[test]
fn test_enforcement_refusal_on_protected_target() {
    let db = Database::open_in_memory().unwrap();
    let event_repo = Arc::new(EventRepository::new(db));
    let proc_ctrl = Arc::new(MockProcessController::new());

    let service = EnforcementService::new(
        proc_ctrl.clone(),
        event_repo.clone(),
        Arc::new(|| Some(Uuid::new_v4())),
    );

    let policy = Policy {
        id: Uuid::new_v4(),
        user_id: None,
        name: "Dangerous Policy".to_string(),
        limit_seconds: 60,
        warning_threshold_seconds: 30,
        enforcement_action: EnforcementAction::CloseApplication,
        is_enabled: true,
        version: 1,
        targets: vec![PolicyTarget {
            id: Uuid::new_v4(),
            policy_id: Uuid::new_v4(),
            target_type: TargetType::App,
            target_value: "csrss.exe".to_string(),
        }],
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
    };

    // Attempt enforcement against csrss.exe
    let result = service
        .execute_enforcement(&policy, "csrss.exe", 9999)
        .expect("Enforcement call should succeed with safe refusal");

    assert!(!result.executed, "Must NOT execute termination on protected target");
    assert!(result.reason.contains("Security refusal"));

    // Ensure mock controller recorded zero terminations
    assert_eq!(proc_ctrl.terminated_pids.lock().unwrap().len(), 0);
    assert_eq!(proc_ctrl.gracefully_closed_pids.lock().unwrap().len(), 0);

    // Ensure ENFORCEMENT_FAILED event was queued
    let events = event_repo.list_pending_events(10).unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_type, focusguard_windows::domain::events::EventType::EnforcementFailed);
}

#[test]
fn test_enforcement_on_normal_app() {
    let db = Database::open_in_memory().unwrap();
    let event_repo = Arc::new(EventRepository::new(db));
    let proc_ctrl = Arc::new(MockProcessController::new());

    let service = EnforcementService::new(
        proc_ctrl.clone(),
        event_repo.clone(),
        Arc::new(|| Some(Uuid::new_v4())),
    );

    let policy = Policy {
        id: Uuid::new_v4(),
        user_id: None,
        name: "Gaming Policy".to_string(),
        limit_seconds: 1800,
        warning_threshold_seconds: 1500,
        enforcement_action: EnforcementAction::CloseApplication,
        is_enabled: true,
        version: 1,
        targets: vec![PolicyTarget {
            id: Uuid::new_v4(),
            policy_id: Uuid::new_v4(),
            target_type: TargetType::App,
            target_value: "game.exe".to_string(),
        }],
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
    };

    let result = service
        .execute_enforcement(&policy, "game.exe", 1234)
        .expect("Enforcement execution should succeed");

    assert!(result.executed);
    assert_eq!(proc_ctrl.gracefully_closed_pids.lock().unwrap().len(), 1);
    assert_eq!(proc_ctrl.gracefully_closed_pids.lock().unwrap()[0], 1234);

    let events = event_repo.list_pending_events(10).unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_type, focusguard_windows::domain::events::EventType::EnforcementTriggered);
}
