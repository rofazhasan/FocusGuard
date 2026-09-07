use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

pub trait IdleDetector: Send + Sync {
    fn get_idle_seconds(&self) -> u32;
    fn is_locked(&self) -> bool;
    fn is_idle(&self, threshold_seconds: u32) -> bool {
        self.is_locked() || self.get_idle_seconds() >= threshold_seconds
    }
}

#[cfg(target_os = "windows")]
pub struct WindowsIdleDetector;

#[cfg(target_os = "windows")]
impl IdleDetector for WindowsIdleDetector {
    fn get_idle_seconds(&self) -> u32 {
        use windows::Win32::System::SystemInformation::GetTickCount;
        use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};

        unsafe {
            let mut lii = LASTINPUTINFO {
                cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
                dwTime: 0,
            };

            if GetLastInputInfo(&mut lii).as_bool() {
                let now_ticks = GetTickCount();
                let diff = now_ticks.saturating_sub(lii.dwTime);
                diff / 1000
            } else {
                0
            }
        }
    }

    fn is_locked(&self) -> bool {
        // Query Desktop/Session lock state via OpenInputDesktop
        use windows::Win32::UI::WindowsAndMessaging::{
            CloseDesktop, OpenInputDesktop, DESKTOP_SWITCHDESKTOP, DF_ALLOWOTHERACCOUNTHOOK,
        };
        unsafe {
            let desk = OpenInputDesktop(0, false, DESKTOP_SWITCHDESKTOP.0);
            if desk.0 == 0 as _ {
                true // Cannot open input desktop, workstation locked or UAC secure desktop
            } else {
                let _ = CloseDesktop(desk);
                false
            }
        }
    }
}

pub struct MockIdleDetector {
    idle_seconds: Arc<AtomicU32>,
    locked: Arc<AtomicBool>,
}

impl MockIdleDetector {
    pub fn new() -> Self {
        Self {
            idle_seconds: Arc::new(AtomicU32::new(0)),
            locked: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn set_idle_seconds(&self, seconds: u32) {
        self.idle_seconds.store(seconds, Ordering::SeqCst);
    }

    pub fn set_locked(&self, locked: bool) {
        self.locked.store(locked, Ordering::SeqCst);
    }
}

impl IdleDetector for MockIdleDetector {
    fn get_idle_seconds(&self) -> u32 {
        self.idle_seconds.load(Ordering::SeqCst)
    }

    fn is_locked(&self) -> bool {
        self.locked.load(Ordering::SeqCst)
    }
}
