use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

use crate::domain::usage::normalize_process_name;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ForegroundAppInfo {
    pub pid: u32,
    pub executable_name: String,
    pub executable_path: Option<String>,
    pub window_title: Option<String>,
    pub timestamp: DateTime<Utc>,
}

pub trait ForegroundAppProvider: Send + Sync {
    fn get_foreground_app(&self) -> Result<Option<ForegroundAppInfo>, String>;
}

/// Native Windows Foreground Window Resolver
#[cfg(target_os = "windows")]
pub struct WindowsForegroundAppProvider;

#[cfg(target_os = "windows")]
impl ForegroundAppProvider for WindowsForegroundAppProvider {
    fn get_foreground_app(&self) -> Result<Option<ForegroundAppInfo>, String> {
        use windows::Win32::Foundation::{CloseHandle, HWND};
        use windows::Win32::System::ProcessStatus::K32GetProcessImageFileNameW;
        use windows::Win32::System::Threading::{
            OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
            PROCESS_QUERY_LIMITED_INFORMATION,
        };
        use windows::Win32::UI::WindowsAndMessaging::{
            GetForegroundWindow, GetWindowTextW, GetWindowThreadProcessId,
        };

        unsafe {
            let hwnd: HWND = GetForegroundWindow();
            if hwnd.0 == 0 as _ {
                return Ok(None);
            }

            let mut pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == 0 {
                return Ok(None);
            }

            // Window title
            let mut title_buf = [0u16; 512];
            let title_len = GetWindowTextW(hwnd, &mut title_buf);
            let window_title = if title_len > 0 {
                Some(String::from_utf16_lossy(&title_buf[..title_len as usize]))
            } else {
                None
            };

            // Process image path
            let h_process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if h_process.is_err() {
                return Ok(None);
            }
            let handle = h_process.unwrap();

            let mut path_buf = [0u16; 1024];
            let mut path_len = path_buf.len() as u32;

            let success = QueryFullProcessImageNameW(
                handle,
                PROCESS_NAME_WIN32,
                windows::core::PWSTR(path_buf.as_mut_ptr()),
                &mut path_len,
            );

            let _ = CloseHandle(handle);

            if success.is_err() || path_len == 0 {
                return Ok(None);
            }

            let full_path = String::from_utf16_lossy(&path_buf[..path_len as usize]);
            let exe_name = normalize_process_name(&full_path);

            Ok(Some(ForegroundAppInfo {
                pid,
                executable_name: exe_name,
                executable_path: Some(full_path),
                window_title,
                timestamp: Utc::now(),
            }))
        }
    }
}

/// Synthetic/Mock Foreground App Provider for headless tests and Unix development
pub struct MockForegroundAppProvider {
    current: Arc<Mutex<Option<ForegroundAppInfo>>>,
}

impl MockForegroundAppProvider {
    pub fn new() -> Self {
        Self {
            current: Arc::new(Mutex::new(None)),
        }
    }

    pub fn set_foreground(
        &self,
        pid: u32,
        executable_name: &str,
        executable_path: Option<&str>,
        window_title: Option<&str>,
    ) {
        let mut lock = self.current.lock().unwrap();
        *lock = Some(ForegroundAppInfo {
            pid,
            executable_name: normalize_process_name(executable_name),
            executable_path: executable_path.map(|s| s.to_string()),
            window_title: window_title.map(|s| s.to_string()),
            timestamp: Utc::now(),
        });
    }

    pub fn clear_foreground(&self) {
        let mut lock = self.current.lock().unwrap();
        *lock = None;
    }
}

impl ForegroundAppProvider for MockForegroundAppProvider {
    fn get_foreground_app(&self) -> Result<Option<ForegroundAppInfo>, String> {
        let lock = self.current.lock().unwrap();
        Ok(lock.clone())
    }
}
