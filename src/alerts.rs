use crate::{
    Result, Settings,
    net::{AUDIO_LIMIT, Network},
    storage,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    io::Read,
    path::Path,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

#[derive(Debug, Deserialize)]
pub struct Event {
    pub name: String,
    pub epoch: f64,
    #[serde(default)]
    pub arabic: String,
    #[serde(default)]
    pub city: String,
}

pub fn claim_event(event: &Event, state: &Path, now: f64) -> Result<bool> {
    if !["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].contains(&event.name.as_str())
        || !event.epoch.is_finite()
        || !(0.0..=90.0).contains(&(now - event.epoch))
    {
        return Ok(false);
    }
    let _lock = storage::lock(state, "alerts.lock", 3)?;
    let path = state.join("delivered.json");
    let raw: Value = storage::read_bounded(&path, 16384)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default();
    let mut ledger: BTreeMap<String, f64> = raw
        .as_object()
        .into_iter()
        .flatten()
        .filter_map(|(key, value)| value.as_f64().map(|value| (key.clone(), value)))
        .collect();
    ledger.retain(|_, value| value.is_finite() && (0.0..3.0 * 86400.0).contains(&(now - *value)));
    let key = format!("{}:{}", event.name, event.epoch as i64);
    if ledger.contains_key(&key) {
        return Ok(false);
    }
    ledger.insert(key, now);
    while ledger.len() > 32 {
        let oldest = ledger
            .iter()
            .min_by(|a, b| a.1.total_cmp(b.1))
            .map(|(k, _)| k.clone())
            .unwrap();
        ledger.remove(&oldest);
    }
    storage::atomic_write(&path, &serde_json::to_vec(&ledger)?)?;
    Ok(true)
}

pub fn tone(kind: &str) -> Vec<u8> {
    let rate: u32 = 16000;
    let seconds: f64 = if kind == "bell" { 2.2 } else { 1.8 };
    let count = (seconds * rate as f64) as u32;
    let mut output = Vec::with_capacity(44 + count as usize * 2);
    output.extend_from_slice(b"RIFF");
    output.extend_from_slice(&(36 + count * 2).to_le_bytes());
    output.extend_from_slice(b"WAVEfmt \x10\0\0\0\x01\0\x01\0");
    output.extend_from_slice(&rate.to_le_bytes());
    output.extend_from_slice(&(rate * 2).to_le_bytes());
    output.extend_from_slice(b"\x02\0\x10\0data");
    output.extend_from_slice(&(count * 2).to_le_bytes());
    let notes: &[(f64, f64)] = if kind == "bell" {
        &[(0.0, 523.25)]
    } else {
        &[(0.0, 660.0), (0.5, 880.0)]
    };
    for i in 0..count {
        let t = i as f64 / rate as f64;
        let mut value = 0.0;
        for (start, hz) in notes {
            let elapsed = t - start;
            if elapsed < 0.0 {
                continue;
            }
            let envelope = (elapsed / 0.015).min(1.0) * (-elapsed * 3.1).exp();
            let phase = std::f64::consts::TAU * hz * elapsed;
            value += envelope * (phase.sin() + 0.22 * (phase * 2.01).sin());
        }
        let sample = (value * 0.32 * ((seconds - t) / 0.1).min(1.0)).clamp(-1.0, 1.0);
        output.extend_from_slice(&((sample * 32767.0) as i16).to_le_bytes());
    }
    output
}
fn valid_audio_header(bytes: &[u8], mp3: bool) -> bool {
    if mp3 {
        bytes.starts_with(b"ID3")
            || (bytes.len() >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0)
    } else {
        bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WAVE")
    }
}
pub fn prepare_sound(settings: &Settings, cache: &Path, network: &impl Network) -> Result<String> {
    let sound = settings.sound.as_str();
    if sound == "none" {
        return Ok(String::new());
    }
    if sound == "custom" {
        let expanded = if let Some(rest) = settings.audio_file.strip_prefix("~/") {
            std::path::PathBuf::from(std::env::var_os("HOME").ok_or("HOME is not set")?).join(rest)
        } else {
            settings.audio_file.clone().into()
        };
        let extension = expanded
            .extension()
            .and_then(|x| x.to_str())
            .unwrap_or("")
            .to_lowercase();
        if !expanded.is_file()
            || !["mp3", "wav", "ogg", "flac", "m4a", "opus"].contains(&extension.as_str())
        {
            return Err("Choose an existing MP3, WAV, OGG, FLAC, M4A, or Opus audio file".into());
        }
        return Ok(expanded.canonicalize()?.to_string_lossy().into_owned());
    }
    let url = match sound {
        "adhan-nafees" => Some("https://cdn.aladhan.com/audio/adhans/a1.mp3"),
        "adhan-alafasy" => Some("https://cdn.aladhan.com/audio/adhans/a9.mp3"),
        "chime" | "bell" => None,
        _ => return Err("Unknown alert sound".into()),
    };
    storage::private_dir(cache)?;
    let path = cache.join(format!(
        "{sound}.{}",
        if url.is_some() { "mp3" } else { "wav" }
    ));
    if let Ok(mut file) = fs::File::open(&path) {
        let meta = file.metadata()?;
        let mut header = [0; 12];
        if meta.is_file()
            && (1001..=AUDIO_LIMIT as u64).contains(&meta.len())
            && file.read_exact(&mut header).is_ok()
            && valid_audio_header(&header, url.is_some())
        {
            return Ok(path.to_string_lossy().into_owned());
        }
    }
    let bytes = if let Some(url) = url {
        network.get(url, AUDIO_LIMIT, 25)?
    } else {
        tone(sound)
    };
    if !(1000..=AUDIO_LIMIT).contains(&bytes.len()) || !valid_audio_header(&bytes, url.is_some()) {
        return Err("Could not download a valid adhan. Please retry.".into());
    }
    storage::atomic_write(&path, &bytes)?;
    Ok(path.to_string_lossy().into_owned())
}

pub fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#x27;")
}
fn notify(title: &str, body: &str) -> Result<()> {
    let mut child = Command::new("notify-send")
        .args([
            "--app-name=Awqat",
            "--icon=appointment-soon",
            "--urgency=normal",
            "--expire-time=15000",
            "--",
            title,
            &escape(body),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                return if status.success() {
                    Ok(())
                } else {
                    Err("The desktop notification could not be delivered".into())
                };
            }
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            result => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(match result {
                    Err(e) => e.into(),
                    _ => "Desktop notification timed out".into(),
                });
            }
        }
    }
}
pub fn test_notification() -> Result<()> {
    notify(
        "Awqat · Test notification",
        "Prayer-time notifications are ready.",
    )
}
pub fn deliver(
    settings: &Settings,
    event: &Event,
    cache: &Path,
    state: &Path,
    network: &impl Network,
) -> Result<Value> {
    if !settings.notifications && settings.sound == "none"
        || !claim_event(event, state, crate::now())?
    {
        return Ok(json!({"ok":true,"skipped":true}));
    }
    let mut warning = String::new();
    if settings.notifications {
        let title = format!("{} · {}", event.name, event.arabic);
        let body = format!(
            "It’s time for {}.{}",
            event.name,
            if event.city.is_empty() {
                String::new()
            } else {
                format!("\n{}", event.city)
            }
        );
        if notify(&title, &body).is_err() {
            warning = "The desktop notification could not be delivered.".into();
        }
    }
    let file = prepare_sound(settings, cache, network)?;
    Ok(
        json!({"ok":true,"file":if crate::now()-event.epoch>90.0 {String::new()} else {file},"warning":warning}),
    )
}
