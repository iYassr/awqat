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
        receive(configured(url, limit, seconds)?, limit)
    }
}

fn configured(url: &str, limit: usize, seconds: u64) -> Result<Easy> {
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
    Ok(easy)
}

fn receive(mut easy: Easy, limit: usize) -> Result<Vec<u8>> {
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

#[cfg(test)]
mod transport_tests {
    use super::*;
    #[test]
    #[ignore = "run with tests/security_transport.py for an isolated TLS fixture"]
    fn https_transport_boundaries() {
        let base = std::env::var("AWQAT_TLS_URL").expect("TLS fixture URL");
        let ca = std::env::var("AWQAT_TLS_CA").expect("TLS fixture CA");
        let fetch = |path: &str, seconds: u64| {
            let mut easy = configured(&format!("{base}{path}"), JSON_LIMIT, seconds).unwrap();
            easy.cainfo(&ca).unwrap();
            receive(easy, JSON_LIMIT)
        };
        assert_eq!(fetch("/ok", 2).unwrap(), b"{}");
        assert_eq!(fetch("/exact", 2).unwrap().len(), JSON_LIMIT);
        assert!(fetch("/oversized", 2).is_err());
        assert!(fetch("/chunked", 2).is_err());
        assert!(fetch("/redirect", 2).is_err());
        assert!(fetch("/error", 2).is_err());
        assert!(fetch("/slow", 1).is_err());
        assert!(Http.get(&format!("{base}/ok"), JSON_LIMIT, 2).is_err());
        let mut mismatch = configured(
            &format!("{}/ok", base.replace("localhost", "127.0.0.1")),
            JSON_LIMIT,
            2,
        )
        .unwrap();
        mismatch.cainfo(&ca).unwrap();
        assert!(receive(mismatch, JSON_LIMIT).is_err());
    }
}
