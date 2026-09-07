use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::protocol::Message;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsMessage {
    pub event: String,
    #[serde(default)]
    pub payload: serde_json::Value,
}

pub struct RealtimeWsClient {
    ws_url: String,
    token: String,
    is_running: Arc<AtomicBool>,
}

impl RealtimeWsClient {
    pub fn new(ws_url: &str, token: &str) -> Self {
        Self {
            ws_url: ws_url.to_string(),
            token: token.to_string(),
            is_running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn start<F>(&self, on_message: F)
    where
        F: Fn(WsMessage) + Send + Sync + 'static,
    {
        let url = format!("{}/ws?token={}", self.ws_url, self.token);
        let running = self.is_running.clone();
        running.store(true, Ordering::SeqCst);

        tokio::spawn(async move {
            while running.load(Ordering::SeqCst) {
                match connect_async(&url).await {
                    Ok((ws_stream, _)) => {
                        let (mut _write, mut read) = ws_stream.split();

                        while let Some(msg_result) = read.next().await {
                            if !running.load(Ordering::SeqCst) {
                                break;
                            }

                            if let Ok(Message::Text(text)) = msg_result {
                                if let Ok(parsed) = serde_json::from_str::<WsMessage>(&text) {
                                    on_message(parsed);
                                }
                            }
                        }
                    }
                    Err(_) => {
                        // Exponential or fixed backoff before reconnecting
                        tokio::time::sleep(Duration::from_secs(3)).await;
                    }
                }
            }
        });
    }

    pub fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
    }
}
