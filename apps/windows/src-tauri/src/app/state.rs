use std::sync::Arc;

use crate::application::{DeviceService, EnforcementService, SyncService, TimerService, UsageService};
use crate::infrastructure::api::ApiClient;
use crate::infrastructure::database::Database;
use crate::adapters::repositories::{DeviceRepository, EventRepository, PolicyRepository, UsageRepository};

pub struct AppState {
    pub db: Database,
    pub api_client: Arc<ApiClient>,
    pub device_service: Arc<DeviceService>,
    pub usage_service: Arc<UsageService>,
    pub timer_service: Arc<TimerService>,
    pub sync_service: Arc<SyncService>,
    pub enforcement_service: Arc<EnforcementService>,
    pub device_repo: Arc<DeviceRepository>,
    pub usage_repo: Arc<UsageRepository>,
    pub policy_repo: Arc<PolicyRepository>,
    pub event_repo: Arc<EventRepository>,
}
