use crate::Result;
use curl::easy::Easy;
use serde_json::Value;
use std::time::Duration;

pub const JSON_LIMIT: usize = 262144;
pub const AUDIO_LIMIT: usize = 8388608;

pub trait Network: Sync {
    fn get(&self, url: &str, limit: usize, seconds: u64) -> Result<Vec<u8>>;
    fn json(&self, url: &str) -> Result<Value> {
        let bytes = self.get(url, JSON_LIMIT, 15)?;
        if bytes.len() > JSON_LIMIT {
            return Err("Service response is too large".into());
        }
        let value: Value = serde_json::from_slice(&bytes)?;
        if !value.is_object() {
            return Err("Service returned an invalid response".into());
        }
        Ok(value)
    }
}

pub struct Http;
impl Network for Http {
    fn get(&self, url: &str, limit: usize, seconds: u64) -> Result<Vec<u8>> {
        if !url.starts_with("https://") {
            return Err("Only HTTPS requests are allowed".into());
        }
        let mut easy = Easy::new();
        easy.url(url)?;
        easy.follow_location(false)?;
        easy.connect_timeout(Duration::from_secs(5))?;
        easy.timeout(Duration::from_secs(seconds))?;
        easy.useragent("OmarchyAwqat/1.2")?;
        easy.ssl_verify_peer(true)?;
        easy.ssl_verify_host(true)?;
        easy.max_filesize(limit as u64)?;
        let mut data = Vec::new();
        {
            let mut transfer = easy.transfer();
            transfer.write_function(|chunk| {
                if data.len().saturating_add(chunk.len()) > limit {
                    return Ok(0);
                }
                data.extend_from_slice(chunk);
                Ok(chunk.len())
            })?;
            transfer.perform().map_err(|_| "Could not reach the service or its response exceeded the download limit. Please retry.")?;
        }
        if easy.response_code()? != 200 {
            return Err("Service returned an error or redirect. Please retry.".into());
        }
        Ok(data)
    }
}

pub fn encode(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || b"-._~".contains(&byte) {
            encoded.push(byte as char);
        } else {
            use std::fmt::Write;
            let _ = write!(encoded, "%{byte:02X}");
        }
    }
    encoded
}
