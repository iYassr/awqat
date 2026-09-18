"""Adversarial inputs at the network, storage, and notification boundaries."""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import unittest
from test_prayer_times import p, LOCATION, fixture
from test_alerts import a
from datetime import date
import tempfile


class SecurityTests(unittest.TestCase):
    def test_json_transport_is_bounded_and_does_not_follow_redirects(self):
        with patch.object(p.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='{}')) as run:
            self.assertEqual(p.get_json('https://ipwho.is/'), {})
        argv = run.call_args.args[0]
        self.assertEqual(argv[:2], ['curl', '-q'])
        for key, value in [('--proto', '=https'), ('--proto-redir', '=https'),
                           ('--max-redirs', '0'), ('--max-filesize', '262144')]:
            self.assertEqual(argv[argv.index(key) + 1], value)
        self.assertNotIn('shell', run.call_args.kwargs)

    def test_oversized_and_non_object_json_rejected(self):
        for body in ['[]', '"string"', '{"x":"' + 'x' * 262144 + '"}']:
            with self.subTest(body_length=len(body)), patch.object(p.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=body)):
                with self.assertRaises(ValueError):
                    p.get_json('https://ipwho.is/')

    def test_location_rejects_control_characters_and_excessive_text(self):
        for name in ['bad\ncity', 'x' * 201]:
            with self.assertRaises(ValueError):
                p.validate_location(dict(LOCATION, name=name))

    def test_prayer_timestamp_must_match_date_and_order(self):
        for timestamp in ['2027-09-18T04:22:00+03:00', '2026-09-18T23:00:00+03:00']:
            data = fixture(date(2026, 9, 18), LOCATION, '4', '0')
            data['timings']['Fajr'] = timestamp
            with self.assertRaises(ValueError):
                p.validate_day(data, date(2026, 9, 18))

    def test_cache_directory_and_files_are_private(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(p, 'CACHE', Path(folder) / 'cache'):
            p.write_cache('key', {'location': LOCATION})
            self.assertEqual(p.CACHE.stat().st_mode & 0o777, 0o700)
            self.assertEqual(next(p.CACHE.glob('*.json')).stat().st_mode & 0o777, 0o600)

    def test_notification_markup_is_escaped_and_shell_text_is_literal(self):
        city = '<img src="https://example.invalid/tracker"> $(touch /tmp/awqat-injection)'
        with patch.object(a, 'claim_event', return_value=True), patch.object(a.subprocess, 'run') as run:
            a.deliver({'notifications': True}, {'name': 'Fajr', 'epoch': a.time.time(), 'city': city})
        args = run.call_args.args[0]
        self.assertIn('--', args)
        self.assertNotIn('<img', args[-1])
        self.assertIn('$(touch /tmp/awqat-injection)', args[-1])
        self.assertNotIn('shell', run.call_args.kwargs)

    def test_oversized_ledger_is_discarded_and_state_is_private(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(a, 'STATE', Path(folder)):
            (a.STATE / 'delivered.json').write_text('x' * 16385)
            self.assertTrue(a.claim_event({'name': 'Fajr', 'epoch': 1000}, now=1001))
            self.assertEqual(a.STATE.stat().st_mode & 0o777, 0o700)
            self.assertEqual((a.STATE / 'delivered.json').stat().st_mode & 0o777, 0o600)

    def test_failed_audio_download_cleans_partial_file(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(a, 'CACHE', Path(folder)), patch.object(a.subprocess, 'run', return_value=SimpleNamespace(returncode=63)) as run:
            with self.assertRaises(ValueError):
                a.prepare_sound({'sound': 'adhan-nafees'})
            self.assertEqual(list(a.CACHE.iterdir()), [])
            args = run.call_args.args[0]
            self.assertEqual(args[:2], ['curl', '-q'])
            self.assertEqual(args[args.index('--max-redirs') + 1], '0')


if __name__ == '__main__':
    unittest.main()
