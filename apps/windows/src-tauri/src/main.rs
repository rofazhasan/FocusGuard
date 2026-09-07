#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::path::PathBuf;
use std::sync::Arc;

use focusguard_windows::build_app_state;
use focusguard_windows::infrastructure::database::Database;
use focusguard_windows::infrastructure::secure_storage::PlatformCredentialStore;

#[cfg(target_os = "windows")]
use focusguard_windows::infrastructure::windows::{
    WindowsForegroundAppProvider, WindowsIdleDetector, WindowsProcessController,
};
#[cfg(not(target_os = "windows"))]
use focusguard_windows::infrastructure::windows::{
    MockForegroundAppProvider, MockIdleDetector, MockProcessController,
};

fn main() {
    env_logger::init();
    println!("Starting FocusGuard Windows Native Client v0.3.0...");

    let app_data_dir = std::env::var("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            std::env::current_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .join(".focusguard-data")
        });

    let _ = std::fs::create_dir_all(&app_data_dir);
    let db_path = app_data_dir.join("focusguard_client.db");
    let cred_path = app_data_dir.join("focusguard_cred.dat");

    let db = Database::open_file(&db_path).expect("Failed to open SQLite database");
    let cred_store = Arc::new(PlatformCredentialStore::new(&cred_path));

    let backend_url = std::env::var("FOCUSGUARD_API_URL")
        .unwrap_or_else(|_| "http://localhost:8080".to_string());

    #[cfg(target_os = "windows")]
    let (fg_provider, idle_detector, proc_controller) = (
        Arc::new(WindowsForegroundAppProvider),
        Arc::new(WindowsIdleDetector),
        Arc::new(WindowsProcessController),
    );

    #[cfg(not(target_os = "windows"))]
    let (fg_provider, idle_detector, proc_controller) = (
        Arc::new(MockForegroundAppProvider::new()),
        Arc::new(MockIdleDetector::new()),
        Arc::new(MockProcessController::new()),
    );

    let state = build_app_state(
        db,
        &backend_url,
        cred_store,
        fg_provider,
        idle_detector,
        proc_controller,
    );

    // 1. Crash recovery on startup
    if let Ok(Some(note)) = state.timer_service.recover_unclosed_sessions() {
        println!("[Crash Recovery] {}", note);
    }

    // 2. Initialize device identity
    let _ = state.device_service.initialize();

    println!("FocusGuard Windows core initialized. Running background services...");
}
