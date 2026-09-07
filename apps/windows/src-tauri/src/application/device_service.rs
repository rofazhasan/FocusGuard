use chrono::Utc;
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;
use std::sync::Arc;

use crate::domain::device::{DeviceCredentials, DeviceIdentity, DeviceStatus};
use crate::infrastructure::api::ApiClient;
use crate::infrastructure::secure_storage::SecureCredentialStore;
use crate::adapters::repositories::DeviceRepository;

pub struct DeviceService {
    device_repo: Arc<DeviceRepository>,
    secure_store: Arc<dyn SecureCredentialStore>,
    api_client: Arc<ApiClient>,
}

impl DeviceService {
    pub fn new(
        device_repo: Arc<DeviceRepository>,
        secure_store: Arc<dyn SecureCredentialStore>,
        api_client: Arc<ApiClient>,
    ) -> Self {
        Self {
            device_repo,
            secure_store,
            api_client,
        }
    }

    /// Initializes device identity on startup:
    /// Checks secure storage for persistent credentials.
    /// If present, ensures status is ACTIVE; otherwise UNREGISTERED.
    pub fn initialize(&self) -> Result<DeviceIdentity, String> {
        let mut identity = self.device_repo.get_device_identity()?;
        let creds = self.secure_store.load_credentials()?;

        if let Some(c) = creds {
            if identity.status != DeviceStatus::Revoked {
                identity.device_id = Some(c.device_id);
                identity.user_id = c.user_id;
                identity.status = DeviceStatus::Active;
                self.device_repo.save_device_identity(&identity)?;
            }
        }

        // Generate Ed25519 keypair if missing
        if identity.public_key_pem.is_empty() {
            let mut csprng = OsRng;
            let signing_key = SigningKey::generate(&mut csprng);
            let verifying_key = signing_key.verifying_key();
            let pubkey_bytes = verifying_key.as_bytes();
            identity.public_key_pem = format!(
                "-----BEGIN PUBLIC KEY-----\n{}\n-----END PUBLIC KEY-----",
                base64_encode(pubkey_bytes)
            );
            self.device_repo.save_device_identity(&identity)?;
        }

        Ok(identity)
    }

    pub fn start_pairing(&self, session_id_or_code: &str) -> Result<String, String> {
        let mut identity = self.initialize()?;
        let session_id = self.api_client.submit_pairing_request(
            session_id_or_code,
            &identity.device_name,
            &identity.public_key_pem,
        )?;

        identity.status = DeviceStatus::PendingApproval;
        self.device_repo.save_device_identity(&identity)?;
        Ok(session_id)
    }

    pub fn check_pairing_status(&self, session_id: &str) -> Result<bool, String> {
        if let Some((device_id, token)) = self.api_client.poll_pairing_status(session_id)? {
            let creds = DeviceCredentials {
                device_id,
                user_id: None,
                device_token: token,
                credential_version: 1,
                created_at: Utc::now(),
                expires_at: Some(Utc::now() + chrono::Duration::days(30)),
            };

            self.secure_store.save_credentials(&creds)?;

            let mut identity = self.device_repo.get_device_identity()?;
            identity.device_id = Some(device_id);
            identity.status = DeviceStatus::Active;
            self.device_repo.save_device_identity(&identity)?;
            return Ok(true);
        }

        Ok(false)
    }

    pub fn handle_revocation(&self) -> Result<(), String> {
        let _ = self.secure_store.clear_credentials();

        let mut identity = self.device_repo.get_device_identity()?;
        identity.status = DeviceStatus::Revoked;
        self.device_repo.save_device_identity(&identity)?;
        Ok(())
    }

    pub fn get_credentials(&self) -> Result<Option<DeviceCredentials>, String> {
        self.secure_store.load_credentials()
    }
}

fn base64_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = if chunk.len() > 1 { chunk[1] } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] } else { 0 };

        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | (b2 as u32);
        out.push(ALPHABET[((n >> 18) & 63) as usize] as char);
        out.push(ALPHABET[((n >> 12) & 63) as usize] as char);

        if chunk.len() > 1 {
            out.push(ALPHABET[((n >> 6) & 63) as usize] as char);
        } else {
            out.push('=');
        }

        if chunk.len() > 2 {
            out.push(ALPHABET[(n & 63) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}
