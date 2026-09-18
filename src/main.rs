mod alerts;
mod net;
mod storage;
mod times;

use serde::Deserialize;
use serde_json::{Value, json};
use std::{env, path::PathBuf};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Clone, Debug, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct Settings {
    location_mode: String,
    city: String,
    method: String,
    school: String,
    notifications: bool,
    sound: String,
    audio_file: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            location_mode: "auto".into(),
            city: "Riyadh".into(),
            method: "auto".into(),
            school: "0".into(),
            notifications: false,
            sound: "none".into(),
            audio_file: String::new(),
        }
    }
}

fn now() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

fn user_dir(variable: &str, fallback: &str) -> Result<PathBuf> {
    if let Some(path) = env::var_os(variable)
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
    {
        return Ok(path.join("omarchy-awqat"));
    }
    Ok(PathBuf::from(env::var_os("HOME").ok_or("HOME is not set")?)
        .join(fallback)
        .join("omarchy-awqat"))
}

fn parse_settings(input: &str) -> Result<Settings> {
    let value: Value = serde_json::from_str(input)?;
    if !value.is_object() {
        return Err("Settings must be a JSON object".into());
    }
    Ok(serde_json::from_value(value)?)
}

fn run() -> Result<Value> {
    let mut args = env::args().skip(1);
    let mode = args.next().ok_or("Expected times or alerts subcommand")?;
    if mode == "--version" {
        return Ok(json!({"ok":true,"version":env!("CARGO_PKG_VERSION")}));
    }
    let mut settings = Settings::default();
    let mut force = false;
    let mut test_notification = false;
    let mut event = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--settings" => settings = parse_settings(&args.next().ok_or("Missing settings")?)?,
            "--event" => {
                event = Some(serde_json::from_str::<alerts::Event>(
                    &args.next().ok_or("Missing event")?,
                )?)
            }
            "--force" => force = true,
            "--test-notification" => test_notification = true,
            _ => return Err(format!("Unknown argument: {arg}").into()),
        }
    }
    let network = net::Http;
    let cache = storage::Cache::new(user_dir("XDG_CACHE_HOME", ".cache")?);
    match mode.as_str() {
        "times" => {
            let _lock = storage::lock(&cache.root, ".lock", 50).or_else(|error| {
                // A full/read-only cache must not prevent a live schedule.
                if error.downcast_ref::<std::io::Error>().is_some_and(|e| {
                    matches!(
                        e.raw_os_error(),
                        Some(libc::EACCES | libc::EROFS | libc::ENOSPC | libc::EDQUOT)
                    )
                }) {
                    Ok(None)
                } else {
                    Err(error)
                }
            })?;
            let report = times::report(&settings, &cache, &network, force, now())?;
            cache.prune(now());
            Ok(report)
        }
        "alerts" => {
            if test_notification {
                alerts::test_notification()?;
                return Ok(json!({"ok":true,"file":""}));
            }
            if let Some(event) = event {
                alerts::deliver(
                    &settings,
                    &event,
                    &cache.root,
                    &user_dir("XDG_STATE_HOME", ".local/state")?,
                    &network,
                )
            } else {
                Ok(json!({"ok":true,"file":alerts::prepare(&settings, &cache.root, &network)?}))
            }
        }
        _ => Err("Expected times or alerts subcommand".into()),
    }
}

fn main() {
    let result = run().unwrap_or_else(|e| json!({"ok": false, "error": e.to_string()}));
    println!("{result}");
}

#[cfg(test)]
mod tests;
