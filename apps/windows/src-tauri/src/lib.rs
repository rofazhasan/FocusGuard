pub mod adapters;
pub mod app;
pub mod application;
pub mod domain;
pub mod infrastructure;

use std::sync::Arc;
use infrastructure::api::ApiClient;
use infrastructure::database::Database;
use infrastructure::secure_storage::SecureCredentialStore;
use infrastructure::windows::{ForegroundAppProvider, IdleDetector, ProcessController};
use adapters::repositories::{DeviceRepository, EventRepository, PolicyRepository, UsageRepository};
use application::{DeviceService, EnforcementService, SyncService, TimerService, UsageService};
use app::AppState;

pub fn build_app_state(
    db: Database,
    api_base_url: &str,
    cred_store: Arc<dyn SecureCredentialStore>,
    foreground_provider: Arc<dyn ForegroundAppProvider>,
    idle_detector: Arc<dyn IdleDetector>,
    process_controller: Arc<dyn ProcessController>,
) -> AppState {
    let api_client = Arc::new(ApiClient::new(api_base_url));
    let device_repo = Arc::new(DeviceRepository::new(db.clone()));
    let usage_repo = Arc::new(UsageRepository::new(db.clone()));
    let policy_repo = Arc::new(PolicyRepository::new(db.clone()));
    let event_repo = Arc::new(EventRepository::new(db.clone()));

    let device_service = Arc::new(DeviceService::new(
        device_repo.clone(),
        cred_store,
        api_client.clone(),
    ));

    let dev_id_clone = device_repo.clone();
    let enforcement_service = Arc::new(EnforcementService::new(
        process_controller,
        event_repo.clone(),
        Arc::new(move || dev_id_clone.get_device_identity().ok().and_then(|i| i.device_id)),
    ));

    let usage_service = Arc::new(UsageService::new(
        usage_repo.clone(),
        policy_repo.clone(),
        device_repo.clone(),
        event_repo.clone(),
        foreground_provider,
        idle_detector,
        enforcement_service.clone(),
        60, // 60s idle threshold
    ));

    let timer_service = Arc::new(TimerService::new(usage_repo.clone()));

    let sync_service = Arc::new(SyncService::new(
        device_service.clone(),
        device_repo.clone(),
        policy_repo.clone(),
        usage_repo.clone(),
        event_repo.clone(),
        api_client.clone(),
    ));

    AppState {
        db,
        api_client,
        device_service,
        usage_service,
        timer_service,
        sync_service,
        enforcement_service,
        device_repo,
        usage_repo,
        policy_repo,
        event_repo,
    }
}
