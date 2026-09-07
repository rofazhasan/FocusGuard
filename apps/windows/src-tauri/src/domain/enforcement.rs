use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EnforcementAction {
    Notify,
    CloseApplication,
    PauseTracking,
}

impl std::fmt::Display for EnforcementAction {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EnforcementAction::Notify => write!(f, "NOTIFY"),
            EnforcementAction::CloseApplication => write!(f, "CLOSE_APPLICATION"),
            EnforcementAction::PauseTracking => write!(f, "PAUSE_TRACKING"),
        }
    }
}

pub const PROTECTED_PROCESS_DENYLIST: &[&str] = &[
    "system",
    "registry",
    "smss.exe",
    "csrss.exe",
    "wininit.exe",
    "winlogon.exe",
    "services.exe",
    "lsass.exe",
    "fontdrvhost.exe",
    "dwm.exe",
    "spoolsv.exe",
    "explorer.exe",
    "taskmgr.exe",
    "svchost.exe",
    "sihost.exe",
    "ctfmon.exe",
    "focusguard.exe",
    "focusguard-windows.exe",
];

/// Verifies whether an executable name is protected by the Windows operating system
/// or FocusGuard stability invariants.
pub fn is_protected_process(executable_name: &str) -> bool {
    let normalized = executable_name.trim().to_lowercase();
    for protected in PROTECTED_PROCESS_DENYLIST {
        if normalized == *protected || normalized.ends_with(&format!("\\{}", protected)) || normalized.ends_with(&format!("/{}", protected)) {
            return true;
        }
    }
    false
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnforcementResult {
    pub target: String,
    pub action: EnforcementAction,
    pub executed: bool,
    pub reason: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}
