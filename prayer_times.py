#!/usr/bin/env python3
"""Awqat's network/cache boundary. Only Python's standard library is required."""
import argparse
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib
import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.parse import urlencode
from zoneinfo import ZoneInfo

CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "omarchy-awqat"
PRAYERS = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
ARABIC = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
ICONS = ["☾", "☀", "☀", "◒", "◓", "☾"]
MAX_CACHE_FILES = 96
MAX_CACHE_AGE = 35 * 86400
MAX_CACHE_BYTES = 2 * 1024 * 1024


def get_json(url):
    # curl bounds DNS lookup as well as transfer time; urllib's timeout does
    # not bound the platform resolver. No command is passed through a shell.
    result = subprocess.run(["curl", "-q", "-fsSL", "--proto", "=https", "--proto-redir", "=https",
                             "--max-redirs", "0", "--max-filesize", "262144",
                             "--connect-timeout", "5", "--max-time", "15",
                             "--user-agent", "OmarchyAwqat/1.0", url],
                            capture_output=True, text=True, timeout=18)
    if result.returncode:
        raise ValueError("Could not reach the location or prayer times service. Check your connection and retry.")
    if len(result.stdout.encode("utf-8")) > 262144:
        raise ValueError("Service response is too large.")
    data = json.loads(result.stdout)
    if not isinstance(data, dict):
        raise ValueError("Service returned an invalid response.")
    return data


def read_cache(key):
    try:
        path = CACHE / (hashlib.sha256(key.encode()).hexdigest() + ".json")
        if path.stat().st_size > 262144:
            return None
        value = json.loads(path.read_text())
        if not isinstance(value, dict) or not isinstance(value.get("data"), dict):
            return None
        if not isinstance(value.get("saved"), (float, int)) or not math.isfinite(value["saved"]) or value["saved"] > time.time() + 300:
            return None
        return value
    except (OSError, ValueError, TypeError, OverflowError, RecursionError):
        return None


def write_cache(key, data):
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    CACHE.chmod(0o700)
    path = CACHE / (hashlib.sha256(key.encode()).hexdigest() + ".json")
    temp = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=CACHE, prefix=".pending-", delete=False) as f:
            temp = f.name
            json.dump({"saved": time.time(), "data": data}, f)
        os.replace(temp, path)
    finally:
        if temp and os.path.exists(temp):
            os.unlink(temp)


def cached(key, ttl, fetch, force=False, validate=None):
    old = read_cache(key)
    if old and validate:
        try:
            validate(old["data"])
        except (KeyError, ValueError, TypeError, IndexError, AttributeError, OverflowError):
            old = None
    if old and not force and 0 <= time.time() - old["saved"] < ttl:
        return old["data"], False
    try:
        data = fetch()
    except Exception:
        if old:
            return old["data"], True
        raise
    # A read-only/full cache must not discard a successful network response.
    try:
        write_cache(key, data)
    except OSError:
        pass
    return data, False


def prune_cache():
    """Bound disk use without touching files outside this plugin's cache."""
    try:
        entries = sorted(((p.stat().st_mtime, p.stat().st_size, p) for p in CACHE.glob("*.json")
                          if len(p.stem) == 64 and all(c in "0123456789abcdef" for c in p.stem)), reverse=True)
        size = 0
        for index, (modified, length, path) in enumerate(entries):
            size += length
            if index >= MAX_CACHE_FILES or size > MAX_CACHE_BYTES or time.time() - modified > MAX_CACHE_AGE:
                path.unlink(missing_ok=True)
        for path in CACHE.glob(".pending-*"):
            if time.time() - path.stat().st_mtime > 3600:
                path.unlink(missing_ok=True)
    except OSError:
        pass


@contextmanager
def cache_lock():
    """Deduplicate requests from independent shell instances, with a deadline."""
    try:
        CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
        CACHE.chmod(0o700)
        lock = (CACHE / ".lock").open("a")
    except OSError:
        yield  # Cache is optional; a read-only filesystem must still work.
        return
    with lock:
        deadline = time.monotonic() + 50
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Another location update is still running. Retrying shortly.")
                time.sleep(0.1)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def validate_location(loc):
    for key in ("name", "country", "countryCode", "timezone"):
        if not isinstance(loc[key], str) or not 0 < len(loc[key]) <= 200 or any(ord(c) < 32 for c in loc[key]):
            raise ValueError("Location service returned incomplete location details.")
    lat, lon = float(loc["latitude"]), float(loc["longitude"])
    if not (math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("Location service returned invalid coordinates.")
    ZoneInfo(loc["timezone"])
    return loc


def detect_location():
    raw = get_json("https://ipwho.is/")
    if raw.get("success") is not True:
        raise ValueError("Could not detect your location. Try again or enter a city in settings.")
    # Store only the location, never the IP address or ISP information.
    return validate_location({
        "name": raw.get("city") or raw.get("region") or raw["country"],
        "country": raw["country"], "countryCode": raw["country_code"],
        "latitude": raw["latitude"], "longitude": raw["longitude"],
        "timezone": raw["timezone"]["id"], "automatic": True,
    })


def find_city(query):
    if not query.strip():
        raise ValueError("Enter a city, or choose automatic location.")
    city_name, _, country_hint = query.partition(",")
    url = "https://geocoding-api.open-meteo.com/v1/search?" + urlencode({"name": city_name.strip(), "count": 5, "language": "en"})
    results = get_json(url).get("results", [])
    if country_hint.strip():
        hint = country_hint.strip().casefold()
        results = [city for city in results if hint in (str(city.get("country", "")).casefold(), str(city.get("country_code", "")).casefold())]
    if not results:
        raise ValueError("City not found. Try its name in English, or use automatic location.")
    city = results[0]
    return validate_location({
        "name": city["name"], "country": city.get("country", ""),
        "countryCode": city.get("country_code", ""), "latitude": city["latitude"],
        "longitude": city["longitude"], "timezone": city["timezone"], "automatic": False,
    })


def fetch_day(day, loc, method, school):
    params = {"latitude": loc["latitude"], "longitude": loc["longitude"],
              "timezonestring": loc["timezone"], "iso8601": "true", "school": school}
    if method != "auto":
        params["method"] = method
    url = "https://api.aladhan.com/v1/timings/" + day.strftime("%d-%m-%Y") + "?" + urlencode(params)
    raw = get_json(url)
    if raw.get("code") != 200 or not isinstance(raw.get("data"), dict):
        raise ValueError("Prayer times service is unavailable. Please retry.")
    data = raw["data"]
    return validate_day(data, day)


def validate_day(data, day):
    if data["date"]["gregorian"]["date"] != day.strftime("%d-%m-%Y"):
        raise ValueError("Prayer times service returned the wrong date.")
    # Reject malformed times before they reach the persistent cache.
    previous = None
    for name in PRAYERS:
        value = datetime.fromisoformat(data["timings"][name])
        if value.tzinfo is None:
            raise ValueError("Prayer times are missing their timezone.")
        # High-latitude schedules may place Isha just after midnight.
        if not day <= value.date() <= day + timedelta(days=1) or (previous is not None and value <= previous):
            raise ValueError("Prayer times have invalid dates or ordering.")
        previous = value
    if not isinstance(data["meta"]["method"]["name"], str) or not 0 < len(data["meta"]["method"]["name"]) <= 200:
        raise ValueError("Prayer times are missing the calculation method.")
    hijri = data["date"]["hijri"]
    for value in (hijri["day"], hijri["month"]["en"], hijri["year"]):
        if not isinstance(value, (str, int)) or not 0 < len(str(value)) <= 100:
            raise ValueError("Prayer times are missing the Hijri date.")
    return data


def day_rows(data):
    rows = []
    for name, arabic, icon in zip(PRAYERS, ARABIC, ICONS):
        value = datetime.fromisoformat(data["timings"][name])
        rows.append({"name": name, "arabic": arabic, "icon": icon,
                     "epoch": value.timestamp(), "time24": value.strftime("%H:%M"),
                     "time12": value.strftime("%I:%M").lstrip("0"), "period": value.strftime("%p"),
                     "prayer": name != "Sunrise"})
    return rows


def report(settings, force=False, now=None):
    if not isinstance(settings, dict):
        raise ValueError("Settings must be a JSON object.")
    automatic = settings.get("locationMode", "auto") != "manual"
    query = str(settings.get("city", "Riyadh")).strip()[:150]
    location_key = "location:auto" if automatic else "location:city:" + query.casefold()
    loc, location_stale = cached(location_key, 1800 if automatic else 2592000,
                                  detect_location if automatic else lambda: find_city(query), force, validate_location)
    method = str(settings.get("method", "auto"))
    if method != "auto" and (not method.isdigit() or not 0 <= int(method) <= 23):
        raise ValueError("Invalid calculation method.")
    if method == "auto" and loc["countryCode"] == "SA":
        method = "4"
    school = str(settings.get("school", "0"))
    if school not in ("0", "1"):
        raise ValueError("Invalid Asr calculation setting.")
    zone = ZoneInfo(loc["timezone"])
    local_now = (now or datetime.now(timezone.utc)).astimezone(zone)
    today = local_now.date()

    def load_day(day):
        key = json.dumps(["day-v1", str(day), loc["latitude"], loc["longitude"], loc["timezone"], method, school])
        return cached(key, 7 * 86400, lambda: fetch_day(day, loc, method, school), force, lambda data: validate_day(data, day))

    # Load today first so a failure for tomorrow never hides today's timetable.
    current, stale = load_day(today)
    events = day_rows(current)
    missing_future = False
    adjacent = [today - timedelta(days=1), today + timedelta(days=1)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [(day, pool.submit(load_day, day)) for day in adjacent]
        for day, future in futures:
            try:
                data, was_stale = future.result()
                events.extend(day_rows(data))
                stale = stale or was_stale
            except Exception:
                if day > today:
                    missing_future = True
    events.sort(key=lambda row: row["epoch"])
    hijri = current["date"]["hijri"]
    midnight = datetime.combine(today + timedelta(days=1), datetime.min.time(), zone)
    saved_location = read_cache(location_key)
    location_due = saved_location["saved"] + 1800 if saved_location else time.time() + 1800
    refresh_at = min(midnight.timestamp(), max(time.time() + 60, location_due)) if automatic else midnight.timestamp()
    return {"ok": True, "location": loc, "date": today.isoformat(),
            "dateLabel": local_now.strftime("%A, %-d %B"), "dayEnds": midnight.timestamp(),
            "hijri": f'{hijri["day"]} {hijri["month"]["en"]} {hijri["year"]} AH',
            "method": current["meta"]["method"]["name"], "school": school,
            "rows": day_rows(current), "events": events,
            "offline": stale or location_stale, "locationStale": location_stale,
            "missingTomorrow": missing_future, "updated": time.time(), "refreshAt": refresh_at}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", default="{}")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    try:
        with cache_lock():
            result = report(json.loads(args.settings), args.force)
            prune_cache()
    except Exception as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
