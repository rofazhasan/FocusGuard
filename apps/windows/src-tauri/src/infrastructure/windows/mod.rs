pub mod foreground;
pub mod idle;
pub mod process;

pub use foreground::{ForegroundAppInfo, ForegroundAppProvider, MockForegroundAppProvider};
pub use idle::{IdleDetector, MockIdleDetector};
pub use process::{MockProcessController, ProcessController};

#[cfg(target_os = "windows")]
pub use foreground::WindowsForegroundAppProvider;
#[cfg(target_os = "windows")]
pub use idle::WindowsIdleDetector;
#[cfg(target_os = "windows")]
pub use process::WindowsProcessController;
