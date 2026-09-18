use super::*;
use crate::{net::Network, storage::Cache};
use jiff::{Timestamp, civil::Date};
use serde_json::json;
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    sync::{
        Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

fn instant(text: &str) -> f64 {
    text.parse::<Timestamp>().unwrap().as_second() as f64
}
fn fixture(date: &str) -> Value {
    let day: Date = date.parse().unwrap();
    let mut timings = serde_json::Map::new();
    for (name, hour) in times::PRAYERS
        .iter()
        .zip(["04:22", "05:40", "11:47", "15:15", "17:54", "19:24"])
    {
        timings.insert((*name).into(), json!(format!("{date}T{hour}:00+03:00")));
    }
    json!({"timings":timings,"date":{"gregorian":{"date":day.strftime("%d-%m-%Y").to_string()},"hijri":{"day":"7","month":{"en":"Rabi II"},"year":"1448"}},"meta":{"method":{"name":"Umm al-Qura"}}})
}
#[derive(Default)]
struct Fake {
    requests: Mutex<Vec<String>>,
    calls: AtomicUsize,
    offline: bool,
    missing: Option<String>,
    corrupt: Option<Value>,
}
impl Network for Fake {
    fn get(&self, url: &str, _: usize, _: u64) -> Result<Vec<u8>> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.requests.lock().unwrap().push(url.into());
        if self.offline || self.missing.as_ref().is_some_and(|s| url.contains(s)) {
            return Err("offline".into());
        }
        let value = if let Some(ref corrupt) = self.corrupt {
            corrupt.clone()
        } else if url == "https://ipwho.is/" {
            json!({"success":true,"city":"Riyadh","country":"Saudi Arabia","country_code":"SA","latitude":24.7,"longitude":46.7,"timezone":{"id":"Asia/Riyadh"},"ip":"192.0.2.1","connection":{"isp":"test"}})
        } else if url.contains("geocoding-api") {
            json!({"results":[{"name":"Riyadh","country":"Saudi Arabia","country_code":"SA","latitude":24.7,"longitude":46.7,"timezone":"Asia/Riyadh"}]})
        } else {
            let part = url
                .split("/timings/")
                .nth(1)
                .unwrap()
                .split('?')
                .next()
                .unwrap();
            let date = Date::strptime("%d-%m-%Y", part)?;
            json!({"code":200,"data":fixture(&date.to_string())})
        };
        Ok(serde_json::to_vec(&value)?)
    }
}
fn setup() -> (tempfile::TempDir, Cache) {
    let temp = tempfile::tempdir().unwrap();
    let cache = Cache::new(temp.path().join("cache"));
    (temp, cache)
}
fn report(cache: &Cache, net: &Fake) -> Value {
    times::report(
        &Settings::default(),
        cache,
        net,
        false,
        instant("2026-09-18T10:00:00Z"),
    )
    .unwrap()
}
fn event(name: &str, epoch: f64) -> alerts::Event {
    alerts::Event {
        name: name.into(),
        epoch,
        arabic: String::new(),
        city: String::new(),
    }
}

#[test]
fn timezone_and_year_rollover() {
    let (_temp, cache) = setup();
    let net = Fake::default();
    let out = times::report(
        &Settings::default(),
        &cache,
        &net,
        false,
        instant("2026-12-31T22:00:00Z"),
    )
    .unwrap();
    assert_eq!(out["date"], "2027-01-01");
    assert_eq!(out["events"].as_array().unwrap().len(), 18);
    assert_eq!(out["dayEnds"], instant("2027-01-01T21:00:00Z") as i64);
    assert_eq!(out["rows"][1]["prayer"], false);
}
#[test]
fn cached_schedule_survives_network_failure() {
    let (_temp, cache) = setup();
    report(&cache, &Fake::default());
    let out = times::report(
        &Settings::default(),
        &cache,
        &Fake {
            offline: true,
            ..Fake::default()
        },
        true,
        instant("2026-09-18T10:00:00Z"),
    )
    .unwrap();
    assert_eq!(out["offline"], true);
    assert_eq!(out["locationStale"], true);
    assert_eq!(out["rows"].as_array().unwrap().len(), 6);
}
#[test]
fn new_city_does_not_reuse_old_location() {
    let (_temp, cache) = setup();
    report(&cache, &Fake::default());
    let settings = Settings {
        location_mode: "manual".into(),
        city: "London".into(),
        ..Settings::default()
    };
    assert!(
        times::report(
            &settings,
            &cache,
            &Fake {
                offline: true,
                ..Fake::default()
            },
            false,
            instant("2026-09-18T10:00:00Z")
        )
        .is_err()
    );
}
#[test]
fn missing_tomorrow_keeps_today() {
    let (_temp, cache) = setup();
    let out = report(
        &cache,
        &Fake {
            missing: Some("19-09-2026".into()),
            ..Fake::default()
        },
    );
    assert_eq!(out["missingTomorrow"], true);
    assert_eq!(out["rows"].as_array().unwrap().len(), 6);
}
#[test]
fn warm_report_has_no_network_calls() {
    let (_temp, cache) = setup();
    report(&cache, &Fake::default());
    let net = Fake {
        offline: true,
        ..Fake::default()
    };
    assert_eq!(report(&cache, &net)["offline"], false);
    assert_eq!(net.calls.load(Ordering::SeqCst), 0);
}
#[test]
fn calculation_method_and_school_have_separate_cache_keys() {
    let (_temp, cache) = setup();
    let net = Fake::default();
    report(&cache, &net);
    let settings = Settings {
        method: "3".into(),
        school: "1".into(),
        ..Settings::default()
    };
    times::report(
        &settings,
        &cache,
        &net,
        false,
        instant("2026-09-18T10:00:00Z"),
    )
    .unwrap();
    assert_eq!(net.calls.load(Ordering::SeqCst), 7);
    assert_eq!(
        net.requests
            .lock()
            .unwrap()
            .iter()
            .filter(|url| url.contains("school=1&method=3"))
            .count(),
        3
    );
}
#[test]
fn ip_and_isp_not_persisted() {
    let (_temp, cache) = setup();
    let out = report(&cache, &Fake::default());
    assert!(out["location"].get("ip").is_none());
    let data = fs::read_to_string(cache.path("location:auto")).unwrap();
    assert!(!data.contains("192.0.2.1"));
    assert!(!data.contains("isp"));
}
#[test]
fn invalid_methods_rejected_before_network() {
    let (_temp, cache) = setup();
    let net = Fake::default();
    for method in ["24", "-1", ";touch x", ""] {
        let settings = Settings {
            method: method.into(),
            ..Settings::default()
        };
        assert!(times::report(&settings, &cache, &net, false, 0.0).is_err());
    }
    assert_eq!(net.calls.load(Ordering::SeqCst), 0);
}
#[test]
fn manual_city_country_hint() {
    let (_temp, cache) = setup();
    let net = Fake::default();
    let settings = Settings {
        location_mode: "manual".into(),
        city: "Riyadh, SA".into(),
        ..Settings::default()
    };
    assert!(
        times::report(
            &settings,
            &cache,
            &net,
            false,
            instant("2026-09-18T10:00:00Z")
        )
        .is_ok()
    );
    assert!(
        !net.requests
            .lock()
            .unwrap()
            .iter()
            .any(|url| url.contains("ipwho"))
    );
}
#[test]
fn wrong_day_and_unzoned_timestamps_rejected() {
    let (_temp, cache) = setup();
    report(&cache, &Fake::default());
    for bad in [
        "2026-09-18T04:22:00",
        "2027-09-18T04:22:00+03:00",
        "2026-09-18T23:00:00+03:00",
    ] {
        let mut data = fixture("2026-09-18");
        data["timings"]["Fajr"] = json!(bad);
        let net = Fake {
            corrupt: Some(json!({"code":200,"data":data})),
            ..Fake::default()
        };
        // The existing valid cache must survive malformed forced responses.
        assert_eq!(
            times::report(
                &Settings::default(),
                &cache,
                &net,
                true,
                instant("2026-09-18T10:00:00Z")
            )
            .unwrap()["offline"],
            true
        );
    }
}
#[test]
fn after_midnight_isha_is_supported() {
    let (_temp, cache) = setup();
    report(&cache, &Fake::default());
    let mut data = fixture("2026-09-18");
    data["timings"]["Isha"] = json!("2026-09-19T00:15:00+03:00");
    let net = Fake {
        corrupt: Some(json!({"code":200,"data":data})),
        ..Fake::default()
    };
    let out = times::report(
        &Settings::default(),
        &cache,
        &net,
        true,
        instant("2026-09-18T10:00:00Z"),
    )
    .unwrap();
    assert_eq!(out["rows"][5]["time24"], "00:15");
}
#[test]
fn invalid_cache_timezone_is_refetched() {
    let (_temp, cache) = setup();
    let out = report(&cache, &Fake::default());
    let mut loc = out["location"].clone();
    loc["timezone"] = json!("Invalid/Zone");
    cache
        .write("location:auto", &loc, instant("2026-09-18T10:00:00Z"))
        .unwrap();
    let net = Fake::default();
    assert_eq!(report(&cache, &net)["offline"], false);
    assert_eq!(net.calls.load(Ordering::SeqCst), 1);
}
#[test]
fn invalid_text_and_coordinates_rejected() {
    let (_temp, cache) = setup();
    let loc = report(&cache, &Fake::default())["location"].clone();
    for bad in ["bad\ncity".into(), "x".repeat(201)] {
        let mut v = loc.clone();
        v["name"] = json!(bad);
        assert!(times::Location::parse(&v).is_err());
    }
    let mut v = loc;
    v["latitude"] = json!(91);
    assert!(times::Location::parse(&v).is_err());
}
#[test]
fn cache_future_time_and_deep_nesting_rejected() {
    let (_temp, cache) = setup();
    cache.write("future", &json!({}), 9999999999.0).unwrap();
    assert!(cache.read("future", now()).is_none());
    fs::write(
        cache.path("nested"),
        format!("{}0{}", "[".repeat(2000), "]".repeat(2000)),
    )
    .unwrap();
    assert!(cache.read("nested", now()).is_none());
}
#[test]
fn cache_failure_does_not_lose_live_data() {
    let (temp, _) = setup();
    let path = temp.path().join("file");
    fs::write(&path, b"x").unwrap();
    let cache = Cache::new(path);
    let (out, stale) = cache
        .cached(
            "x",
            60.0,
            false,
            now(),
            || Ok(json!({"live":true})),
            |_| Ok(()),
        )
        .unwrap();
    assert_eq!(out["live"], true);
    assert!(!stale);
}
#[test]
fn cache_pruning_preserves_unrelated_files() {
    let (_temp, cache) = setup();
    for i in 0..110 {
        cache.write(&i.to_string(), &json!({"i":i}), now()).unwrap();
    }
    fs::write(cache.root.join("keep-me.json"), "{}").unwrap();
    cache.prune(now());
    assert_eq!(fs::read_dir(&cache.root).unwrap().count(), 97);
    assert!(cache.root.join("keep-me.json").exists());
}
#[test]
fn private_cache_permissions() {
    let (_temp, cache) = setup();
    cache.write("test", &json!({}), now()).unwrap();
    assert_eq!(
        fs::metadata(&cache.root).unwrap().permissions().mode() & 0o777,
        0o700
    );
    assert_eq!(
        fs::metadata(cache.path("test"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
}
#[test]
fn non_https_network_rejected() {
    assert!(net::Http.get("http://example.invalid/", 1024, 1).is_err());
}
#[test]
fn non_object_and_oversized_json_rejected() {
    for corrupt in [
        json!([]),
        json!("text"),
        json!({"x":"x".repeat(net::JSON_LIMIT)}),
    ] {
        assert!(
            Fake {
                corrupt: Some(corrupt),
                ..Fake::default()
            }
            .json("https://ipwho.is/")
            .is_err()
        );
    }
}
#[test]
fn query_encoding_is_literal() {
    assert_eq!(
        net::encode("a&x=$(id) /ال"),
        "a%26x%3D%24%28id%29%20%2F%D8%A7%D9%84"
    );
}
#[test]
fn persisted_duplicate_alert_claims() {
    let temp = tempfile::tempdir().unwrap();
    assert!(alerts::claim_event(&event("Fajr", 1000.0), temp.path(), 1001.0).unwrap());
    assert!(!alerts::claim_event(&event("Fajr", 1000.0), temp.path(), 1002.0).unwrap());
}
#[test]
fn concurrent_alert_claims_deliver_once() {
    let temp = tempfile::tempdir().unwrap();
    let e = event("Fajr", 1000.0);
    let results = std::thread::scope(|s| {
        let a = s.spawn(|| alerts::claim_event(&e, temp.path(), 1001.0).unwrap());
        let b = s.spawn(|| alerts::claim_event(&e, temp.path(), 1001.0).unwrap());
        (a.join().unwrap(), b.join().unwrap())
    });
    assert_ne!(results.0, results.1);
}
#[test]
fn late_future_and_sunrise_alerts_are_silent() {
    let temp = tempfile::tempdir().unwrap();
    for e in [
        event("Fajr", 1.0),
        event("Fajr", 2000.0),
        event("Sunrise", 1000.0),
        event("Fajr", f64::NAN),
    ] {
        assert!(!alerts::claim_event(&e, temp.path(), 1001.0).unwrap());
    }
}
#[test]
fn disabled_alerts_do_not_touch_state() {
    let temp = tempfile::tempdir().unwrap();
    let state = temp.path().join("state");
    assert_eq!(
        alerts::deliver(
            &Settings::default(),
            &event("Fajr", now()),
            &temp.path().join("audio"),
            &state,
            &Fake::default()
        )
        .unwrap()["skipped"],
        true
    );
    assert!(!state.exists());
}
#[test]
fn bounded_ledger_recovers_from_corruption() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("delivered.json"), "x".repeat(16385)).unwrap();
    assert!(alerts::claim_event(&event("Fajr", 1000.0), temp.path(), 1001.0).unwrap());
    assert_eq!(
        fs::metadata(temp.path().join("delivered.json"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
}
#[test]
fn held_lock_has_deadline() {
    let temp = tempfile::tempdir().unwrap();
    let _lock = storage::lock(temp.path(), "lock", 0).unwrap();
    assert!(storage::lock(temp.path(), "lock", 0).is_err());
}
#[test]
fn tone_is_valid_small_and_cached() {
    let temp = tempfile::tempdir().unwrap();
    let net = Fake {
        offline: true,
        ..Fake::default()
    };
    for sound in ["chime", "bell"] {
        let settings = Settings {
            sound: sound.into(),
            ..Settings::default()
        };
        let path = alerts::prepare_sound(&settings, temp.path(), &net).unwrap();
        let bytes = fs::read(&path).unwrap();
        assert!(bytes.len() < 80000);
        assert_eq!(&bytes[..4], b"RIFF");
        assert_eq!(u32::from_le_bytes(bytes[24..28].try_into().unwrap()), 16000);
        assert_eq!(
            alerts::prepare_sound(&settings, temp.path(), &net).unwrap(),
            path
        );
    }
    assert_eq!(net.calls.load(Ordering::SeqCst), 0);
}
#[test]
fn corrupt_tone_is_regenerated() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("chime.wav"), vec![0; 4000]).unwrap();
    let path = alerts::prepare_sound(
        &Settings {
            sound: "chime".into(),
            ..Settings::default()
        },
        temp.path(),
        &Fake::default(),
    )
    .unwrap();
    assert_eq!(&fs::read(path).unwrap()[..4], b"RIFF");
}
#[test]
fn custom_sound_requires_regular_local_supported_file() {
    let temp = tempfile::tempdir().unwrap();
    for path in ["https://example.invalid/a.mp3", "/etc/passwd"] {
        assert!(
            alerts::prepare_sound(
                &Settings {
                    sound: "custom".into(),
                    audio_file: path.into(),
                    ..Settings::default()
                },
                temp.path(),
                &Fake::default()
            )
            .is_err()
        );
    }
    let path = temp.path().join("audio.wav");
    fs::write(&path, alerts::tone("bell")).unwrap();
    assert!(
        alerts::prepare_sound(
            &Settings {
                sound: "custom".into(),
                audio_file: path.to_string_lossy().into_owned(),
                ..Settings::default()
            },
            temp.path(),
            &Fake::default()
        )
        .is_ok()
    );
}
#[test]
fn failed_download_leaves_no_partial_file() {
    let temp = tempfile::tempdir().unwrap();
    assert!(
        alerts::prepare_sound(
            &Settings {
                sound: "adhan-nafees".into(),
                ..Settings::default()
            },
            temp.path(),
            &Fake {
                offline: true,
                ..Fake::default()
            }
        )
        .is_err()
    );
    assert_eq!(fs::read_dir(temp.path()).unwrap().count(), 0);
}
#[test]
fn markup_is_escaped() {
    assert_eq!(
        alerts::escape("<img src=\"x\">&$(id)"),
        "&lt;img src=&quot;x&quot;&gt;&amp;$(id)"
    );
}
#[test]
fn invalid_settings_rejected() {
    assert!(parse_settings("[]").is_err());
    assert!(parse_settings("{\"notifications\":\"yes\"}").is_err());
}

#[test]
fn malformed_ledger_entry_preserves_other_claims() {
    let temp = tempfile::tempdir().unwrap();
    fs::write(
        temp.path().join("delivered.json"),
        r#"{"Fajr:1000":1001,"broken":"invalid"}"#,
    )
    .unwrap();
    assert!(!alerts::claim_event(&event("Fajr", 1000.0), temp.path(), 1002.0).unwrap());
}

#[test]
fn failed_atomic_write_leaves_no_temporary_file() {
    let temp = tempfile::tempdir().unwrap();
    let destination = temp.path().join("directory");
    fs::create_dir(&destination).unwrap();
    assert!(storage::atomic_write(&destination, b"data").is_err());
    assert_eq!(fs::read_dir(temp.path()).unwrap().count(), 1);
}

#[test]
fn symlinked_private_directory_is_not_chmodded() {
    let temp = tempfile::tempdir().unwrap();
    let target = temp.path().join("outside");
    fs::create_dir(&target).unwrap();
    fs::set_permissions(&target, fs::Permissions::from_mode(0o755)).unwrap();
    let link = temp.path().join("cache");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    assert!(storage::private_dir(&link).is_err());
    assert_eq!(
        fs::metadata(&target).unwrap().permissions().mode() & 0o777,
        0o755
    );
}

#[test]
fn symlinked_cache_and_lock_files_are_rejected() {
    let temp = tempfile::tempdir().unwrap();
    let target = temp.path().join("outside.json");
    fs::write(&target, b"{}").unwrap();
    let link = temp.path().join("data.json");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    assert!(storage::read_bounded(&link, 100).is_err());
    std::os::unix::fs::symlink(&target, temp.path().join("lock")).unwrap();
    assert!(storage::lock(temp.path(), "lock", 0).is_err());
    assert_eq!(fs::read(&target).unwrap(), b"{}");
}

#[test]
fn fifo_cache_and_audio_do_not_block() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("chime.wav");
    assert!(
        std::process::Command::new("mkfifo")
            .arg(&path)
            .status()
            .unwrap()
            .success()
    );
    assert!(storage::read_bounded(&path, 100).is_err());
    assert!(storage::lock(temp.path(), "chime.wav", 0).is_err());
    let settings = Settings {
        sound: "chime".into(),
        ..Settings::default()
    };
    alerts::prepare_sound(&settings, temp.path(), &Fake::default()).unwrap();
    assert!(fs::metadata(&path).unwrap().is_file());
}
