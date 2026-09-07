use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::device::DeviceCredentials;

pub trait SecureCredentialStore: Send + Sync {
    fn save_credentials(&self, creds: &DeviceCredentials) -> Result<(), String>;
    fn load_credentials(&self) -> Result<Option<DeviceCredentials>, String>;
    fn clear_credentials(&self) -> Result<(), String>;
}

/// File-backed secure credential store utilizing DPAPI on Windows and AES-GCM on Unix/CI.
pub struct PlatformCredentialStore {
    path: PathBuf,
}

impl PlatformCredentialStore {
    pub fn new<P: AsRef<Path>>(path: P) -> Self {
        Self {
            path: path.as_ref().to_path_buf(),
        }
    }
}

#[cfg(target_os = "windows")]
mod win_impl {
    use super::*;
    use windows::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTOAPI_BLOB,
    };
    use std::ptr::null_mut;

    pub fn encrypt_bytes(data: &[u8]) -> Result<Vec<u8>, String> {
        let mut input_blob = CRYPTOAPI_BLOB {
            cbData: data.len() as u32,
            pbData: data.as_ptr() as *mut u8,
        };
        let mut output_blob = CRYPTOAPI_BLOB {
            cbData: 0,
            pbData: null_mut(),
        };

        unsafe {
            let res = CryptProtectData(
                &mut input_blob,
                windows::core::PCWSTR::null(),
                None,
                None,
                None,
                0,
                &mut output_blob,
            );

            if res.is_err() {
                return Err("CryptProtectData failed to encrypt credential".to_string());
            }

            let slice = std::slice::from_raw_parts(output_blob.pbData, output_blob.cbData as usize);
            let vec = slice.to_vec();
            windows::Win32::Foundation::LocalFree(windows::Win32::Foundation::HLOCAL(output_blob.pbData as _));
            Ok(vec)
        }
    }

    pub fn decrypt_bytes(data: &[u8]) -> Result<Vec<u8>, String> {
        let mut input_blob = CRYPTOAPI_BLOB {
            cbData: data.len() as u32,
            pbData: data.as_ptr() as *mut u8,
        };
        let mut output_blob = CRYPTOAPI_BLOB {
            cbData: 0,
            pbData: null_mut(),
        };

        unsafe {
            let res = CryptUnprotectData(
                &mut input_blob,
                None,
                None,
                None,
                None,
                0,
                &mut output_blob,
            );

            if res.is_err() {
                return Err("CryptUnprotectData failed to decrypt credential".to_string());
            }

            let slice = std::slice::from_raw_parts(output_blob.pbData, output_blob.cbData as usize);
            let vec = slice.to_vec();
            windows::Win32::Foundation::LocalFree(windows::Win32::Foundation::HLOCAL(output_blob.pbData as _));
            Ok(vec)
        }
    }
}

#[cfg(not(target_os = "windows"))]
mod unix_impl {
    use aes_gcm::{
        aead::{Aead, KeyInit},
        Aes256Gcm, Nonce,
    };
    use sha2::{Digest, Sha256};

    fn get_key() -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(b"focusguard_local_secure_credential_entropy_v1");
        hasher.finalize().into()
    }

    pub fn encrypt_bytes(data: &[u8]) -> Result<Vec<u8>, String> {
        let key = get_key();
        let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
        let nonce = Nonce::from_slice(b"focusguard99"); // 12 bytes
        let ciphertext = cipher
            .encrypt(nonce, data)
            .map_err(|e| format!("AES encryption failed: {:?}", e))?;
        Ok(ciphertext)
    }

    pub fn decrypt_bytes(data: &[u8]) -> Result<Vec<u8>, String> {
        let key = get_key();
        let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
        let nonce = Nonce::from_slice(b"focusguard99");
        let plaintext = cipher
            .decrypt(nonce, data)
            .map_err(|e| format!("AES decryption failed: {:?}", e))?;
        Ok(plaintext)
    }
}

impl SecureCredentialStore for PlatformCredentialStore {
    fn save_credentials(&self, creds: &DeviceCredentials) -> Result<(), String> {
        let json = serde_json::to_string(creds).map_err(|e| e.to_string())?;
        
        #[cfg(target_os = "windows")]
        let encrypted = win_impl::encrypt_bytes(json.as_bytes())?;
        #[cfg(not(target_os = "windows"))]
        let encrypted = unix_impl::encrypt_bytes(json.as_bytes())?;

        if let Some(parent) = self.path.parent() {
            let _ = fs::create_dir_all(parent);
        }

        fs::write(&self.path, encrypted).map_err(|e| e.to_string())?;
        Ok(())
    }

    fn load_credentials(&self) -> Result<Option<DeviceCredentials>, String> {
        if !self.path.exists() {
            return Ok(None);
        }

        let raw = fs::read(&self.path).map_err(|e| e.to_string())?;
        if raw.is_empty() {
            return Ok(None);
        }

        #[cfg(target_os = "windows")]
        let decrypted = win_impl::decrypt_bytes(&raw)?;
        #[cfg(not(target_os = "windows"))]
        let decrypted = unix_impl::decrypt_bytes(&raw)?;

        let creds: DeviceCredentials =
            serde_json::from_slice(&decrypted).map_err(|e| e.to_string())?;
        Ok(Some(creds))
    }

    fn clear_credentials(&self) -> Result<(), String> {
        if self.path.exists() {
            // Overwrite with zeros before deletion
            let len = fs::metadata(&self.path).map(|m| m.len()).unwrap_or(128);
            let zeros = vec![0u8; len as usize];
            let _ = fs::write(&self.path, zeros);
            let _ = fs::remove_file(&self.path);
        }
        Ok(())
    }
}
