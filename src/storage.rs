use crate::Result;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions, TryLockError},
    io::{Read, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant, SystemTime},
};

pub fn private_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path)?;
    // Open the directory itself: never chmod a symlink target.
    let directory = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW)
        .open(path)?;
    directory.set_permissions(fs::Permissions::from_mode(0o700))?;
    Ok(())
}

pub fn open_regular(path: &Path) -> Result<File> {
    // O_NONBLOCK prevents FIFOs from hanging before metadata can be checked.
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)?;
    if !file.metadata()?.is_file() {
        return Err("Expected a regular data file".into());
    }
    Ok(file)
}

pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path.parent().ok_or("Missing parent directory")?;
    private_dir(parent)?;
    let mut temp = tempfile::Builder::new()
        .prefix(".pending-")
        .tempfile_in(parent)?;
    temp.write_all(bytes)?;
    temp.flush()?;
    temp.persist(path)?;
    Ok(())
}

pub fn read_bounded(path: &Path, limit: usize) -> Result<Vec<u8>> {
    let file = open_regular(path)?;
    if !file.metadata()?.is_file() || file.metadata()?.len() > limit as u64 {
        return Err("Invalid or oversized data file".into());
    }
    let mut data = Vec::new();
    file.take(limit as u64 + 1).read_to_end(&mut data)?;
    if data.len() > limit {
        return Err("Data file is too large".into());
    }
    Ok(data)
}

pub fn lock(path: &Path, name: &str, seconds: u64) -> Result<Option<File>> {
    private_dir(path)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path.join(name))?;
    if !file.metadata()?.is_file() {
        return Err("Expected a regular lock file".into());
    }
    let deadline = Instant::now() + Duration::from_secs(seconds);
    loop {
        match file.try_lock() {
            Ok(()) => return Ok(Some(file)),
            Err(TryLockError::WouldBlock) if Instant::now() < deadline => {
                thread::sleep(Duration::from_millis(50))
            }
            Err(TryLockError::WouldBlock) => {
                return Err("Another update is still running. Please retry.".into());
            }
            Err(TryLockError::Error(e)) => return Err(e.into()),
        }
    }
}

pub struct Cache {
    pub root: PathBuf,
}
impl Cache {
    pub fn new(root: PathBuf) -> Self {
        Self { root }
    }
    pub fn path(&self, key: &str) -> PathBuf {
        self.root
            .join(format!("{:x}.json", Sha256::digest(key.as_bytes())))
    }
    pub fn read(&self, key: &str, now: f64) -> Option<(Value, f64)> {
        let bytes = read_bounded(&self.path(key), 262144).ok()?;
        let value: Value = serde_json::from_slice(&bytes).ok()?;
        let saved = value.get("saved")?.as_f64()?;
        let data = value.get("data")?;
        if !saved.is_finite() || saved > now + 300.0 || !data.is_object() {
            return None;
        }
        Some((data.clone(), saved))
    }
    pub fn write(&self, key: &str, data: &Value, now: f64) -> Result<()> {
        atomic_write(
            &self.path(key),
            &serde_json::to_vec(&json!({"saved":now,"data":data}))?,
        )
    }
    pub fn cached<F, V>(
        &self,
        key: &str,
        ttl: f64,
        force: bool,
        now: f64,
        fetch: F,
        validate: V,
    ) -> Result<(Value, bool)>
    where
        F: FnOnce() -> Result<Value>,
        V: Fn(&Value) -> Result<()>,
    {
        let old = self
            .read(key, now)
            .filter(|(data, _)| validate(data).is_ok());
        if let Some((ref data, saved)) = old
            && !force
            && (0.0..ttl).contains(&(now - saved))
        {
            return Ok((data.clone(), false));
        }
        match fetch().and_then(|value| {
            validate(&value)?;
            Ok(value)
        }) {
            Ok(data) => {
                let _ = self.write(key, &data, now);
                Ok((data, false))
            }
            Err(_) if old.is_some() => Ok((old.unwrap().0, true)),
            Err(e) => Err(e),
        }
    }
    pub fn prune(&self, now: f64) {
        let Ok(entries) = fs::read_dir(&self.root) else {
            return;
        };
        let mut files = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = fs::symlink_metadata(&path) else {
                continue;
            };
            if !meta.is_file() {
                continue;
            }
            let modified = meta
                .modified()
                .unwrap_or(SystemTime::UNIX_EPOCH)
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs_f64();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with(".pending-") && now - modified > 3600.0 {
                let _ = fs::remove_file(&path);
            }
            if let Some(stem) = name.strip_suffix(".json")
                && stem.len() == 64
                && stem.bytes().all(|c| c.is_ascii_hexdigit())
            {
                files.push((modified, meta.len(), path));
            }
        }
        files.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut size = 0;
        for (i, (modified, length, path)) in files.into_iter().enumerate() {
            size += length;
            if i >= 96 || size > 2 * 1024 * 1024 || now - modified > 35.0 * 86400.0 {
                let _ = fs::remove_file(path);
            }
        }
    }
}
