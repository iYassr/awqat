import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave

spec = importlib.util.spec_from_file_location("alerts", Path(__file__).resolve().parents[1] / "alerts.py")
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


class AlertTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state = patch.object(a, "STATE", Path(self.temp.name) / "state")
        self.cache = patch.object(a, "CACHE", Path(self.temp.name) / "audio")
        self.state.start()
        self.cache.start()

    def tearDown(self):
        self.state.stop()
        self.cache.stop()
        self.temp.cleanup()

    def test_duplicate_claim_is_persisted(self):
        event = {"name": "Fajr", "epoch": 1000}
        self.assertTrue(a.claim_event(event, now=1001))
        self.assertFalse(a.claim_event(event, now=1002))
        self.assertTrue(a.claim_event({"name": "Dhuhr", "epoch": 1100}, now=1101))

    def test_sleep_catchup_future_and_sunrise_are_silent(self):
        for event in [{"name": "Fajr", "epoch": 1}, {"name": "Fajr", "epoch": 2000}, {"name": "Sunrise", "epoch": 1000}]:
            self.assertFalse(a.claim_event(event, now=1001))

    def test_alerts_off_do_not_claim_or_send(self):
        with patch.object(a, "claim_event") as claim, patch.object(a.subprocess, "run") as run:
            self.assertTrue(a.deliver({}, {"name": "Fajr", "epoch": 1000})["skipped"])
        claim.assert_not_called()
        run.assert_not_called()

    def test_notification_and_audio_are_independent(self):
        with patch.object(a, "claim_event", return_value=True), patch.object(a.subprocess, "run") as run:
            result = a.deliver({"notifications": True, "sound": "none"}, {"name": "Fajr", "epoch": a.time.time(), "city": "Riyadh"})
        self.assertTrue(result["ok"])
        self.assertEqual(result["file"], "")
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], "notify-send")

    def test_tones_are_small_valid_cached_wave_files(self):
        for kind in ("chime", "bell"):
            path = Path(a.prepare_sound({"sound": kind}))
            self.assertLess(path.stat().st_size, 80000)
            with wave.open(str(path)) as f:
                self.assertEqual(f.getframerate(), 16000)
                self.assertEqual(f.getnchannels(), 1)
            with patch.object(a, "make_tone", side_effect=AssertionError("regenerated")):
                self.assertEqual(a.prepare_sound({"sound": kind}), str(path))

    def test_custom_audio_requires_a_local_supported_file(self):
        with self.assertRaises(ValueError):
            a.prepare_sound({"sound": "custom", "audioFile": "https://example.com/a.mp3"})
        with self.assertRaises(ValueError):
            a.prepare_sound({"sound": "custom", "audioFile": "/etc/passwd"})

    def test_notifications_survive_audio_download_failure(self):
        with patch.object(a, "claim_event", return_value=True), patch.object(a.subprocess, "run") as run, patch.object(a, "prepare_sound", side_effect=ValueError("offline")):
            result = a.deliver({"notifications": True, "sound": "adhan-nafees"}, {"name": "Fajr", "epoch": a.time.time()})
        self.assertFalse(result["ok"])
        self.assertEqual(run.call_count, 1)

    def test_busy_ledger_lock_has_a_deadline(self):
        with patch.object(a.fcntl, "flock", side_effect=BlockingIOError), patch.object(a.time, "monotonic", side_effect=[0, 4]):
            with self.assertRaises(TimeoutError):
                a.claim_event({"name": "Fajr", "epoch": 1000}, now=1001)

    def test_failed_ledger_write_cleans_temporary_file(self):
        with patch.object(a.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                a.claim_event({"name": "Fajr", "epoch": 1000}, now=1001)
        self.assertEqual([path.name for path in a.STATE.iterdir()], ["alerts.lock"])


if __name__ == "__main__":
    unittest.main()
