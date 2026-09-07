use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use uuid::Uuid;

use crate::domain::events::FocusGuardEvent;

#[derive(Debug, Clone)]
pub struct ApiClient {
    base_url: String,
    client: Client,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PairingRequestBody<'a> {
    device_name: &'a str,
    platform: &'a str,
    client_type: &'a str,
    app_version: &'a str,
    public_key: &'a str,
    key_algorithm: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pairing_code: Option<&'a str>,
}

#[derive(Deserialize)]
struct PairingSubmitResponse {
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    status: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairingStatusPollResponse {
    status: String,
    #[serde(default)]
    device_id: Option<String>,
    #[serde(default)]
    device_token: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HeartbeatRequest<'a> {
    app_version: &'a str,
    protection_state: &'a str,
    policy_version: u32,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct HeartbeatResponse {
    pub acknowledged: bool,
    pub device_status: String,
    pub latest_policy_version: u32,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct RawPolicyTargetDto {
    pub id: String,
    pub policy_id: String,
    pub target_type: String,
    pub target_value: String,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct RawPolicyDto {
    pub id: String,
    pub name: String,
    pub limit_seconds: u32,
    pub warning_threshold_seconds: Option<u32>,
    pub enforcement_mode: Option<String>,
    pub is_enabled: bool,
    pub version: u32,
    pub targets: Option<Vec<RawPolicyTargetDto>>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PolicySyncResponse {
    pub policy_version: u32,
    pub policies: Vec<RawPolicyDto>,
    pub sync_cursor: String,
    pub status: String,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UsageDelta {
    pub target_value: String,
    pub duration_seconds: u32,
    pub date: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UsageSyncRequest<'a> {
    device_id: String,
    sync_sequence: u32,
    usage_deltas: &'a [UsageDelta],
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct UsageSyncResponse {
    pub server_timestamp: i64,
    pub sync_sequence: u32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EventDto<'a> {
    id: String,
    device_id: String,
    event_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    domain: Option<&'a str>,
    reason: &'a str,
    timestamp: String,
}

#[derive(Serialize)]
struct BatchEventRequest<'a> {
    events: Vec<EventDto<'a>>,
}

#[derive(Deserialize, Debug)]
pub struct BatchEventResponse {
    pub success: bool,
    pub processed: u32,
    pub duplicates: u32,
}

impl ApiClient {
    pub fn new(base_url: &str) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .unwrap_or_else(|_| Client::new());

        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            client,
        }
    }

    pub fn submit_pairing_request(
        &self,
        session_id_or_code: &str,
        device_name: &str,
        public_key_pem: &str,
    ) -> Result<String, String> {
        let is_uuid = Uuid::parse_str(session_id_or_code).is_ok();
        let url = if is_uuid {
            format!("{}/api/v1/pairing/sessions/{}/request", self.base_url, session_id_or_code)
        } else {
            format!("{}/api/v1/pairing/request", self.base_url)
        };

        let body = PairingRequestBody {
            device_name,
            platform: "WINDOWS",
            client_type: "WINDOWS_AGENT",
            app_version: "0.3.0",
            public_key: public_key_pem,
            key_algorithm: "Ed25519",
            pairing_code: if is_uuid { None } else { Some(session_id_or_code) },
        };

        let res = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .map_err(|e| format!("Network error submitting pairing: {:?}", e))?;

        if !res.status().is_success() {
            let status = res.status();
            let txt = res.text().unwrap_or_default();
            return Err(format!("Pairing submit rejected ({}) {}", status, txt));
        }

        let resp: PairingSubmitResponse = res
            .json()
            .map_err(|e| format!("Failed to parse pairing submit response: {:?}", e))?;

        if let Some(sid) = resp.session_id {
            Ok(sid)
        } else if is_uuid {
            Ok(session_id_or_code.to_string())
        } else {
            Err("Server did not return session ID".to_string())
        }
    }

    pub fn poll_pairing_status(&self, session_id: &str) -> Result<Option<(Uuid, String)>, String> {
        let url = format!("{}/api/v1/pairing/sessions/{}/status", self.base_url, session_id);
        let res = self
            .client
            .get(&url)
            .send()
            .map_err(|e| format!("Network error polling pairing: {:?}", e))?;

        if !res.status().is_success() {
            return Err(format!("Poll failed with HTTP {}", res.status()));
        }

        let resp: PairingStatusPollResponse = res
            .json()
            .map_err(|e| format!("Failed to decode poll status: {:?}", e))?;

        if resp.status == "APPROVED" || resp.status == "CONSUMED" {
            if let (Some(did_str), Some(tok)) = (resp.device_id, resp.device_token) {
                let did = Uuid::parse_str(&did_str).map_err(|e| e.to_string())?;
                return Ok(Some((did, tok)));
            }
        }

        Ok(None)
    }

    pub fn heartbeat(
        &self,
        device_id: &Uuid,
        token: &str,
        app_version: &str,
        policy_version: u32,
    ) -> Result<HeartbeatResponse, String> {
        let url = format!("{}/api/v1/devices/{}/heartbeat", self.base_url, device_id);
        let body = HeartbeatRequest {
            app_version,
            protection_state: "PROTECTED",
            policy_version,
        };

        let res = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .json(&body)
            .send()
            .map_err(|e| format!("Heartbeat error: {:?}", e))?;

        if res.status() == reqwest::StatusCode::FORBIDDEN {
            return Err("DEVICE_REVOKED".to_string());
        }

        if !res.status().is_success() {
            return Err(format!("Heartbeat returned HTTP {}", res.status()));
        }

        res.json().map_err(|e| e.to_string())
    }

    pub fn sync_policies(&self, token: &str) -> Result<PolicySyncResponse, String> {
        let url = format!("{}/api/v1/device/policies/sync", self.base_url);
        let res = self
            .client
            .get(&url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .map_err(|e| format!("Policy sync network error: {:?}", e))?;

        if res.status() == reqwest::StatusCode::FORBIDDEN {
            return Err("DEVICE_REVOKED".to_string());
        }

        if !res.status().is_success() {
            return Err(format!("Policy sync returned HTTP {}", res.status()));
        }

        res.json().map_err(|e| e.to_string())
    }

    pub fn sync_usage(
        &self,
        device_id: &Uuid,
        token: &str,
        sync_sequence: u32,
        deltas: &[UsageDelta],
    ) -> Result<UsageSyncResponse, String> {
        let url = format!("{}/api/v1/usage/sync", self.base_url);
        let body = UsageSyncRequest {
            device_id: device_id.to_string(),
            sync_sequence,
            usage_deltas: deltas,
        };

        let res = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .json(&body)
            .send()
            .map_err(|e| format!("Usage sync network error: {:?}", e))?;

        if res.status() == reqwest::StatusCode::FORBIDDEN {
            return Err("DEVICE_REVOKED".to_string());
        }

        if !res.status().is_success() {
            return Err(format!("Usage sync returned HTTP {}", res.status()));
        }

        res.json().map_err(|e| e.to_string())
    }

    pub fn send_batch_events(
        &self,
        device_id: &Uuid,
        token: &str,
        events: &[FocusGuardEvent],
    ) -> Result<BatchEventResponse, String> {
        let url = format!("{}/api/v1/events/batch", self.base_url);
        let dtos: Vec<EventDto> = events
            .iter()
            .map(|e| EventDto {
                id: e.id.to_string(),
                device_id: device_id.to_string(),
                event_type: e.event_type.to_string(),
                domain: e.target.as_deref(),
                reason: &e.reason,
                timestamp: e.timestamp.to_rfc3339(),
            })
            .collect();

        let body = BatchEventRequest { events: dtos };

        let res = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .json(&body)
            .send()
            .map_err(|e| format!("Event batch network error: {:?}", e))?;

        if res.status() == reqwest::StatusCode::FORBIDDEN {
            return Err("DEVICE_REVOKED".to_string());
        }

        if !res.status().is_success() {
            return Err(format!("Batch events returned HTTP {}", res.status()));
        }

        res.json().map_err(|e| e.to_string())
    }
}
