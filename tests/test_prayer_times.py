import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("prayer_times", Path(__file__).resolve().parents[1] / "prayer_times.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

LOCATION = {"name": "Riyadh", "country": "Saudi Arabia", "countryCode": "SA",
            "latitude": 24.6877, "longitude": 46.7219, "timezone": "Asia/Riyadh", "automatic": True}


def fixture(day, loc, method, school):
    return {"timings": {name: f"{day.isoformat()}T{hour}:00+03:00" for name, hour in
                        zip(p.PRAYERS, ["04:22", "05:40", "11:47", "15:15", "17:54", "19:24"])},
            "date": {"gregorian": {"date": day.strftime("%d-%m-%Y")},
                     "hijri": {"day": "7", "month": {"en": "Rabi II"}, "year": "1448"}},
            "meta": {"method": {"name": "Umm al-Qura"}}}


class PrayerTimesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.cache = patch.object(p, "CACHE", Path(self.temp.name))
        self.cache.start()

    def tearDown(self):
        self.cache.stop()
        self.temp.cleanup()

    def test_timezone_date_and_year_rollover(self):
        # UTC is still Dec 31, but it is already Jan 1 in Riyadh.
        now = datetime(2026, 12, 31, 22, tzinfo=timezone.utc)
        with patch.object(p, "detect_location", return_value=LOCATION), patch.object(p, "fetch_day", side_effect=fixture) as fetch:
            result = p.report({}, now=now)
        self.assertEqual(result["date"], "2027-01-01")
        self.assertEqual(len(result["events"]), 18)
        self.assertEqual({str(c.args[0]) for c in fetch.call_args_list}, {"2026-12-31", "2027-01-01", "2027-01-02"})
        self.assertTrue(all(c.args[2] == "4" for c in fetch.call_args_list))
        self.assertEqual(result["dayEnds"], datetime(2027, 1, 1, 21, tzinfo=timezone.utc).timestamp())
        self.assertFalse(result["rows"][1]["prayer"])

    def test_cached_schedule_survives_network_failure(self):
        now = datetime(2026, 9, 18, 10, tzinfo=timezone.utc)
        with patch.object(p, "detect_location", return_value=LOCATION), patch.object(p, "fetch_day", side_effect=fixture):
            p.report({}, now=now)
        with patch.object(p, "detect_location", side_effect=OSError("offline")), patch.object(p, "fetch_day", side_effect=OSError("offline")):
            result = p.report({}, force=True, now=now)
        self.assertTrue(result["offline"])
        self.assertTrue(result["locationStale"])
        self.assertEqual(len(result["rows"]), 6)

    def test_new_city_does_not_reuse_old_city_times(self):
        now = datetime(2026, 9, 18, 10, tzinfo=timezone.utc)
        with patch.object(p, "detect_location", return_value=LOCATION), patch.object(p, "fetch_day", side_effect=fixture):
            p.report({}, now=now)
        with patch.object(p, "find_city", side_effect=OSError("offline")):
            with self.assertRaises(OSError):
                p.report({"locationMode": "manual", "city": "London"}, now=now)

    def test_missing_tomorrow_keeps_today(self):
        today = datetime(2026, 9, 18, 10, tzinfo=timezone.utc)
        def fetch(day, *args):
            if day > today.date():
                raise OSError("offline")
            return fixture(day, *args)
        with patch.object(p, "detect_location", return_value=LOCATION), patch.object(p, "fetch_day", side_effect=fetch):
            result = p.report({}, now=today)
        self.assertTrue(result["missingTomorrow"])
        self.assertEqual(len(result["rows"]), 6)

    def test_method_and_school_cache_are_independent(self):
        now = datetime(2026, 9, 18, 10, tzinfo=timezone.utc)
        with patch.object(p, "detect_location", return_value=LOCATION), patch.object(p, "fetch_day", side_effect=fixture) as fetch:
            p.report({}, now=now)
            p.report({"method": "3", "school": "1"}, now=now)
        self.assertEqual(fetch.call_count, 6)
        self.assertEqual(sum(c.args[2:] == ("3", "1") for c in fetch.call_args_list), 3)

    def test_ip_address_is_not_stored(self):
        raw = {"success": True, "city": "Riyadh", "country": "Saudi Arabia", "country_code": "SA",
               "latitude": 24.7, "longitude": 46.7, "timezone": {"id": "Asia/Riyadh"}, "ip": "192.0.2.1"}
        with patch.object(p, "get_json", return_value=raw):
            self.assertNotIn("ip", p.detect_location())

    def test_rejects_wrong_date_and_timezone_free_times(self):
        day = datetime(2026, 9, 18).date()
        wrong = fixture(day + timedelta(days=1), LOCATION, "4", "0")
        with patch.object(p, "get_json", return_value={"code": 200, "data": wrong}):
            with self.assertRaisesRegex(ValueError, "wrong date"):
                p.fetch_day(day, LOCATION, "4", "0")

        wrong = fixture(day, LOCATION, "4", "0")
        wrong["timings"]["Fajr"] = "2026-09-18T04:22:00"
        with patch.object(p, "get_json", return_value={"code": 200, "data": wrong}):
            with self.assertRaisesRegex(ValueError, "timezone"):
                p.fetch_day(day, LOCATION, "4", "0")

    def test_cache_write_failure_does_not_lose_live_data(self):
        with patch.object(p, "write_cache", side_effect=OSError("disk full")):
            result, stale = p.cached("example", 60, lambda: {"live": True})
        self.assertEqual(result, {"live": True})
        self.assertFalse(stale)

    def test_structurally_corrupt_cache_is_refetched(self):
        p.write_cache("broken", {"missing": "fields"})
        with patch.object(p, "detect_location", return_value=LOCATION):
            value, stale = p.cached("broken", 60, p.detect_location, validate=p.validate_location)
        self.assertEqual(value["name"], "Riyadh")
        self.assertFalse(stale)

    def test_cache_size_is_bounded(self):
        for i in range(110):
            p.write_cache(str(i), {"value": i})
        unrelated = p.CACHE / "keep-me.json"
        unrelated.write_text("{}")
        p.prune_cache()
        self.assertEqual(len(list(p.CACHE.glob("*.json"))), p.MAX_CACHE_FILES + 1)
        self.assertTrue(unrelated.exists())

    def test_warm_report_makes_no_network_requests(self):
        now = datetime(2026, 9, 18, 10, tzinfo=timezone.utc)
        with patch.object(p, "detect_location", return_value=LOCATION), patch.object(p, "fetch_day", side_effect=fixture):
            p.report({}, now=now)
        with patch.object(p, "detect_location", side_effect=AssertionError("network")), patch.object(p, "fetch_day", side_effect=AssertionError("network")):
            result = p.report({}, now=now)
        self.assertFalse(result["offline"])
        self.assertFalse(result["missingTomorrow"])

    def test_malformed_cached_timezone_is_refetched(self):
        p.write_cache("location:auto", dict(LOCATION, timezone="Invalid/Timezone"))
        with patch.object(p, "detect_location", return_value=LOCATION) as fetch:
            loc, stale = p.cached("location:auto", 1800, p.detect_location, validate=p.validate_location)
        self.assertEqual(loc, LOCATION)
        self.assertFalse(stale)
        fetch.assert_called_once()

    def test_future_cache_timestamp_is_not_trusted(self):
        with patch.object(p.time, "time", return_value=9999999999):
            p.write_cache("future", {"old": True})
        self.assertIsNone(p.read_cache("future"))

    def test_after_midnight_isha_is_supported(self):
        day = datetime(2026, 9, 18).date()
        data = fixture(day, LOCATION, "4", "0")
        data["timings"]["Isha"] = "2026-09-19T00:15:00+03:00"
        self.assertEqual(p.validate_day(data, day), data)

    def test_deeply_nested_cache_is_discarded(self):
        import hashlib
        path = p.CACHE / (hashlib.sha256(b"nested").hexdigest() + ".json")
        path.write_text('[' * 2000 + '0' + ']' * 2000)
        self.assertIsNone(p.read_cache("nested"))



if __name__ == "__main__":
    unittest.main()
