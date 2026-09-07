use std::sync::Arc;
use tempfile::tempdir;
use uuid::Uuid;

use focusguard_windows::build_app_state;
use focusguard_windows::domain::device::{DeviceCredentials, DeviceStatus};
use focusguard_windows::domain::events::EventType;
use focusguard_windows::domain::usage::UsageState;
use focusguard_windows::infrastructure::database::Database;
use focusguard_windows::infrastructure::secure_storage::{PlatformCredentialStore, SecureCredentialStore};
use focusguard_windows::infrastructure::windows::{
    MockForegroundAppProvider, MockIdleDetector, MockProcessController,
};

#[test]
fn test_windows_first_vertical_slice_complete() {
    println!("\n=== RUNNING FOCUSGUARD PHASE 3: FIRST MINIMAL WINDOWS VERTICAL SLICE ===");

    let tmp = tempdir().unwrap();
    let db_path = tmp.path().join("test_focusguard.db");
    let cred_path = tmp.path().join("test_cred.dat");

    let fg_provider = Arc::new(MockForegroundAppProvider::new());
    let idle_detector = Arc::new(MockIdleDetector::new());
    let proc_controller = Arc::new(MockProcessController::new());
    let cred_store = Arc::new(PlatformCredentialStore::new(&cred_path));

    // 1. Windows App Launches
    println!("[Step 1] Initializing FocusGuard Windows application state...");
    let db = Database::open_file(&db_path).unwrap();
    let state = build_app_state(
        db,
        "http://localhost:8080",
        cred_store.clone(),
        fg_provider.clone(),
        idle_detector.clone(),
        proc_controller.clone(),
    );

    let identity = state.device_service.initialize().unwrap();
    assert_eq!(identity.status, DeviceStatus::Unregistered);
    assert!(!identity.public_key_pem.is_empty(), "Ed25519 identity key must be generated");
    println!("✓ Unregistered device with Ed25519 identity initialized.");

    // 2. Pair Device & Store Credential
    println!("[Step 2] Simulating device pairing & persistent credential receipt...");
    let test_device_id = Uuid::new_v4();
    let test_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.simulated_windows_device_token";
    let creds = DeviceCredentials {
        device_id: test_device_id,
        user_id: Some(Uuid::new_v4()),
        device_token: test_token.to_string(),
        credential_version: 1,
        created_at: chrono::Utc::now(),
        expires_at: Some(chrono::Utc::now() + chrono::Duration::days(30)),
    };
    cred_store.save_credentials(&creds).unwrap();

    let mut paired_identity = identity.clone();
    paired_identity.device_id = Some(test_device_id);
    paired_identity.status = DeviceStatus::Active;
    state.device_repo.save_device_identity(&paired_identity).unwrap();

    let active_identity = state.device_repo.get_device_identity().unwrap();
    assert_eq!(active_identity.status, DeviceStatus::Active);
    println!("✓ Device paired: {} (Status: ACTIVE).", test_device_id);

    // 3. Detect Foreground Application
    println!("[Step 3] Foreground Window Provider detects discord.exe...");
    fg_provider.set_foreground(4400, "discord.exe", Some("C:\\Discord\\discord.exe"), Some("Discord - Friends"));

    // 4. Track 60 Seconds
    println!("[Step 4] Tracking 60 active seconds with 1s monotonic checkpoints...");
    for sec in 1..=60 {
        let usage_state = state.usage_service.tick().unwrap();
        assert_eq!(usage_state, UsageState::Active);
    }
    println!("✓ 60 seconds of focused usage tracked.");

    // 5. Persist Usage
    println!("[Step 5] Verifying persistent SQLite usage checkpoint...");
    let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let tracked_seconds = state.usage_repo.get_daily_usage(&today, "discord.exe").unwrap();
    assert_eq!(tracked_seconds, 60, "Must have exactly 60 seconds accumulated in SQLite");
    println!("✓ SQLite daily usage verified: 60s for discord.exe.");

    // 6. Restart Windows Client (Drop state completely!)
    println!("[Step 6] Simulating Windows Client Restart (dropping memory state)...");
    drop(state);

    // 7. Reopen database and verify state restored without re-pairing!
    println!("[Step 7] Reopening application from disk...");
    let db2 = Database::open_file(&db_path).unwrap();
    let cred_store2 = Arc::new(PlatformCredentialStore::new(&cred_path));
    let state2 = build_app_state(
        db2,
        "http://localhost:8080",
        cred_store2.clone(),
        fg_provider.clone(),
        idle_detector.clone(),
        proc_controller.clone(),
    );

    let restored_identity = state2.device_service.initialize().unwrap();
    assert_eq!(restored_identity.status, DeviceStatus::Active, "Must remain ACTIVE after restart");
    assert_eq!(restored_identity.device_id, Some(test_device_id), "Device ID must persist");
    println!("✓ Device restored credentials from DPAPI/SecureStore: No re-pairing required!");

    // 8. Restore Usage
    println!("[Step 8] Verifying usage state restored correctly...");
    let restored_seconds = state2.usage_repo.get_daily_usage(&today, "discord.exe").unwrap();
    assert_eq!(restored_seconds, 60, "Usage must be 60s following restart");
    println!("✓ Usage restored from SQLite: 60s.");

    // 9. Sync Event
    println!("[Step 9] Verifying offline event queueing and sync readiness...");
    let pending_events = state2.event_repo.list_pending_events(10).unwrap();
    assert!(!pending_events.is_empty(), "Must have queued lifecycle events");
    assert_eq!(pending_events[0].event_type, EventType::UsageSessionStarted);
    println!("✓ Queued event ready for sync: {:?}.", pending_events[0].event_type);

    // Mark event synced
    let event_ids: Vec<Uuid> = pending_events.iter().map(|e| e.id).collect();
    state2.event_repo.mark_events_synced(&event_ids).unwrap();
    let count_after = state2.event_repo.get_pending_count().unwrap();
    assert_eq!(count_after, 0);
    println!("✓ Event sync confirmed: 0 pending events remaining.");

    println!("\n🎉 FOCUSGUARD PHASE 3 MINIMAL WINDOWS VERTICAL SLICE PASSED 100%!\n");
}
