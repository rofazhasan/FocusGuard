use std::sync::{Arc, Mutex};

pub trait ProcessController: Send + Sync {
    fn close_gracefully(&self, pid: u32) -> Result<(), String>;
    fn terminate_process(&self, pid: u32) -> Result<(), String>;
}

#[cfg(target_os = "windows")]
pub struct WindowsProcessController;

#[cfg(target_os = "windows")]
impl ProcessController for WindowsProcessController {
    fn close_gracefully(&self, pid: u32) -> Result<(), String> {
        use windows::Win32::Foundation::{BOOL, LPARAM, HWND};
        use windows::Win32::UI::WindowsAndMessaging::{
            EnumWindows, GetWindowThreadProcessId, PostMessageW, WM_CLOSE,
        };

        struct EnumData {
            target_pid: u32,
            found: bool,
        }

        unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
            let data = &mut *(lparam.0 as *mut EnumData);
            let mut window_pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, Some(&mut window_pid));
            if window_pid == data.target_pid {
                let _ = PostMessageW(hwnd, WM_CLOSE, windows::Win32::Foundation::WPARAM(0), windows::Win32::Foundation::LPARAM(0));
                data.found = true;
            }
            BOOL(1)
        }

        let mut data = EnumData {
            target_pid: pid,
            found: false,
        };

        unsafe {
            let _ = EnumWindows(Some(enum_proc), LPARAM(&mut data as *mut _ as isize));
        }

        if data.found {
            Ok(())
        } else {
            Err("No top-level window found for target process".to_string())
        }
    }

    fn terminate_process(&self, pid: u32) -> Result<(), String> {
        use windows::Win32::Foundation::CloseHandle;
        use windows::Win32::System::Threading::{
            OpenProcess, TerminateProcess, PROCESS_TERMINATE,
        };

        unsafe {
            let h_proc = OpenProcess(PROCESS_TERMINATE, false, pid)
                .map_err(|e| format!("Failed to open process for termination: {:?}", e))?;
            
            let res = TerminateProcess(h_proc, 1);
            let _ = CloseHandle(h_proc);

            if res.is_err() {
                Err(format!("TerminateProcess failed: {:?}", res))
            } else {
                Ok(())
            }
        }
    }
}

pub struct MockProcessController {
    pub terminated_pids: Arc<Mutex<Vec<u32>>>,
    pub gracefully_closed_pids: Arc<Mutex<Vec<u32>>>,
}

impl MockProcessController {
    pub fn new() -> Self {
        Self {
            terminated_pids: Arc::new(Mutex::new(Vec::new())),
            gracefully_closed_pids: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

impl ProcessController for MockProcessController {
    fn close_gracefully(&self, pid: u32) -> Result<(), String> {
        let mut list = self.gracefully_closed_pids.lock().unwrap();
        list.push(pid);
        Ok(())
    }

    fn terminate_process(&self, pid: u32) -> Result<(), String> {
        let mut list = self.terminated_pids.lock().unwrap();
        list.push(pid);
        Ok(())
    }
}
