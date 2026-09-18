use crate::{
    Result, Settings,
    net::{Network, encode},
    storage::Cache,
};
use jiff::{Timestamp, ToSpan, civil::Date, tz::TimeZone};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const PRAYERS: [&str; 6] = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"];
const ARABIC: [&str; 6] = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"];
const ICONS: [&str; 6] = ["☾", "☀", "☀", "◒", "◓", "☾"];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Location {
    pub name: String,
    pub country: String,
    pub country_code: String,
    pub latitude: f64,
    pub longitude: f64,
    pub timezone: String,
    pub automatic: bool,
}
impl Location {
    pub fn parse(value: &Value) -> Result<Self> {
        let loc: Self = serde_json::from_value(value.clone())?;
        for text in [&loc.name, &loc.country, &loc.country_code, &loc.timezone] {
            validate_text(text, 200)?;
        }
        if !loc.latitude.is_finite()
            || !loc.longitude.is_finite()
            || !(-90.0..=90.0).contains(&loc.latitude)
            || !(-180.0..=180.0).contains(&loc.longitude)
        {
            return Err("Location service returned invalid coordinates".into());
        }
        TimeZone::get(&loc.timezone)?;
        Ok(loc)
    }
}

pub fn validate_text(text: &str, max: usize) -> Result<()> {
    if text.is_empty() || text.chars().count() > max || text.chars().any(char::is_control) {
        return Err("Service returned invalid text".into());
    }
    Ok(())
}
fn text<'a>(value: &'a Value, pointer: &str) -> Result<&'a str> {
    value
        .pointer(pointer)
        .and_then(Value::as_str)
        .ok_or_else(|| "Service returned incomplete data".into())
}
fn detect(network: &impl Network) -> Result<Value> {
    let raw = network.json("https://ipwho.is/")?;
    if raw["success"] != true {
        return Err("Could not detect your location. Try again or enter a city.".into());
    }
    let name = [&raw["city"], &raw["region"], &raw["country"]]
        .into_iter()
        .filter_map(|v| v.as_str())
        .find(|v| !v.is_empty())
        .unwrap_or("");
    Ok(
        json!({"name":name,"country":raw["country"],"countryCode":raw["country_code"],
        "latitude":raw["latitude"],"longitude":raw["longitude"],"timezone":raw["timezone"]["id"],"automatic":true}),
    )
}
fn find_city(query: &str, network: &impl Network) -> Result<Value> {
    if query.trim().is_empty() {
        return Err("Enter a city, or choose automatic location".into());
    }
    let (name, hint) = query.split_once(',').unwrap_or((query, ""));
    let raw = network.json(&format!(
        "https://geocoding-api.open-meteo.com/v1/search?name={}&count=5&language=en",
        encode(name.trim())
    ))?;
    let hint = hint.trim().to_lowercase();
    let city = raw["results"]
        .as_array()
        .and_then(|cities| {
            cities.iter().find(|city| {
                hint.is_empty()
                    || ["country", "country_code"]
                        .iter()
                        .any(|key| city[key].as_str().unwrap_or("").to_lowercase() == hint)
            })
        })
        .ok_or("City not found. Try its English name or automatic location.")?;
    Ok(
        json!({"name":city["name"],"country":city["country"],"countryCode":city["country_code"],"latitude":city["latitude"],"longitude":city["longitude"],"timezone":city["timezone"],"automatic":false}),
    )
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Row {
    pub name: String,
    pub arabic: String,
    pub icon: String,
    pub epoch: i64,
    pub time24: String,
    pub time12: String,
    pub period: String,
    pub prayer: bool,
}
struct Day {
    rows: Vec<Row>,
    method: String,
    hijri: String,
}
fn parse_day(data: &Value, day: Date, zone: &TimeZone) -> Result<Day> {
    if text(data, "/date/gregorian/date")? != day.strftime("%d-%m-%Y").to_string() {
        return Err("Prayer times service returned the wrong date".into());
    }
    let mut rows = Vec::with_capacity(6);
    let mut previous = None;
    for (i, name) in PRAYERS.iter().enumerate() {
        let value = text(data, &format!("/timings/{name}"))?;
        let instant: Timestamp = value
            .parse()
            .map_err(|_| "Prayer times are invalid or missing their timezone")?;
        let local = instant.to_zoned(zone.clone());
        let epoch = instant.as_second();
        if (local.date() != day
            && !(*name == "Isha" && local.date() == day.checked_add(1.days())?))
            || previous.is_some_and(|p| epoch <= p)
        {
            return Err("Prayer times have invalid dates or ordering".into());
        }
        previous = Some(epoch);
        let hour = local.hour();
        rows.push(Row {
            name: (*name).into(),
            arabic: ARABIC[i].into(),
            icon: ICONS[i].into(),
            epoch,
            time24: format!("{:02}:{:02}", hour, local.minute()),
            time12: format!(
                "{}:{:02}",
                if hour % 12 == 0 { 12 } else { hour % 12 },
                local.minute()
            ),
            period: if hour < 12 { "AM" } else { "PM" }.into(),
            prayer: *name != "Sunrise",
        });
    }
    let method = text(data, "/meta/method/name")?.to_string();
    validate_text(&method, 200)?;
    let mut parts = Vec::new();
    for pointer in [
        "/date/hijri/day",
        "/date/hijri/month/en",
        "/date/hijri/year",
    ] {
        let value = data.pointer(pointer).ok_or("Missing Hijri date")?;
        let part = match value {
            Value::String(v) => v.clone(),
            Value::Number(n) if n.is_i64() || n.is_u64() => n.to_string(),
            _ => return Err("Invalid Hijri date".into()),
        };
        validate_text(&part, 100)?;
        parts.push(part);
    }
    Ok(Day {
        rows,
        method,
        hijri: format!("{} AH", parts.join(" ")),
    })
}

fn day_key(day: Date, loc: &Location, method: &str, school: &str) -> String {
    // Match the original Python JSON key spacing so installed caches migrate.
    format!(
        "[\"day-v1\", \"{day}\", {}, {}, {}, {}, {}]",
        json!(loc.latitude),
        json!(loc.longitude),
        json!(loc.timezone),
        json!(method),
        json!(school)
    )
}

pub fn report(
    settings: &Settings,
    cache: &Cache,
    network: &impl Network,
    force: bool,
    now: f64,
) -> Result<Value> {
    if settings.method != "auto"
        && (!settings.method.bytes().all(|c| c.is_ascii_digit())
            || settings.method.parse::<u8>().map_or(true, |m| m > 23))
    {
        return Err("Invalid calculation method".into());
    }
    if !["0", "1"].contains(&settings.school.as_str()) {
        return Err("Invalid Asr calculation setting".into());
    }
    if !["auto", "manual"].contains(&settings.location_mode.as_str()) {
        return Err("Invalid location mode".into());
    }
    let automatic = settings.location_mode == "auto";
    let query: String = settings.city.trim().chars().take(150).collect();
    let key = if automatic {
        "location:auto".into()
    } else {
        format!("location:city:{}", query.to_lowercase())
    };
    let (data, location_stale) = cache.cached(
        &key,
        if automatic { 1800.0 } else { 2592000.0 },
        force,
        now,
        || {
            if automatic {
                detect(network)
            } else {
                find_city(&query, network)
            }
        },
        |v| {
            Location::parse(v)?;
            Ok(())
        },
    )?;
    let loc = Location::parse(&data)?;
    let method = if settings.method == "auto" && loc.country_code == "SA" {
        "4"
    } else {
        &settings.method
    };
    let zone = TimeZone::get(&loc.timezone)?;
    let local = Timestamp::from_second(now as i64)?.to_zoned(zone.clone());
    let today = local.date();
    let load_day = |day: Date| -> Result<(Day, bool)> {
        let key = day_key(day, &loc, method, &settings.school);
        let (data, stale) = cache.cached(
            &key,
            7.0 * 86400.0,
            force,
            now,
            || {
                let mut url = format!(
                    "https://api.aladhan.com/v1/timings/{}?latitude={}&longitude={}&timezonestring={}&iso8601=true&school={}",
                    day.strftime("%d-%m-%Y"), loc.latitude, loc.longitude,
                    encode(&loc.timezone), settings.school
                );
                if method != "auto" {
                    url.push_str(&format!("&method={method}"));
                }
                let raw = network.json(&url)?;
                if raw["code"] != 200 || !raw["data"].is_object() {
                    return Err("Prayer times service is unavailable. Please retry.".into());
                }
                Ok(raw["data"].clone())
            },
            |data| parse_day(data, day, &zone).map(|_| ()),
        )?;
        Ok((parse_day(&data, day, &zone)?, stale))
    };
    let (current, mut stale) = load_day(today)?;
    let mut events = current.rows.clone();
    let yesterday = today.checked_sub(1.days())?;
    let tomorrow = today.checked_add(1.days())?;
    let mut missing_future = false;
    std::thread::scope(|scope| {
        let previous = scope.spawn(|| load_day(yesterday));
        let next = scope.spawn(|| load_day(tomorrow));
        for (date, handle) in [(yesterday, previous), (tomorrow, next)] {
            match handle
                .join()
                .unwrap_or_else(|_| Err("Schedule worker stopped unexpectedly".into()))
            {
                Ok((day, was_stale)) => {
                    events.extend(day.rows);
                    stale |= was_stale;
                }
                Err(_) => {
                    if date > today {
                        missing_future = true;
                    }
                }
            }
        }
    });
    events.sort_by_key(|r| r.epoch);
    let midnight = zone
        .to_zoned(tomorrow.at(0, 0, 0, 0))?
        .timestamp()
        .as_second();
    let due = cache
        .read(&key, now)
        .map_or(now + 1800.0, |(_, saved)| saved + 1800.0);
    let refresh_at = if automatic {
        (midnight as f64).min((now + 60.0).max(due))
    } else {
        midnight as f64
    };
    Ok(
        json!({"ok":true,"location":loc,"date":today.to_string(),"dateLabel":local.strftime("%A, %-d %B").to_string(),
        "dayEnds":midnight,"hijri":current.hijri,"method":current.method,"school":settings.school,
        "rows":current.rows,"events":events,"offline":stale || location_stale,"locationStale":location_stale,
        "missingTomorrow":missing_future,"updated":now,"refreshAt":refresh_at}),
    )
}
