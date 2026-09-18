#!/usr/bin/env python3
"""Isolated CLI regressions; no real notification, playback, or network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

BINARY = Path(__file__).resolve().parents[1] / 'bin/awqat-core'


class AlertReliability(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.marker = self.root / 'notification'
        commands = self.root / 'bin'
        commands.mkdir()
        notify = commands / 'notify-send'
        notify.write_text('#!/bin/sh\nprintf notified > "$AWQAT_TEST_MARKER"\n')
        notify.chmod(0o700)
        self.env = dict(os.environ, PATH=str(commands),
                        XDG_CACHE_HOME=str(self.root / 'cache'),
                        XDG_STATE_HOME=str(self.root / 'state'),
                        AWQAT_TEST_MARKER=str(self.marker))

    def run_alert(self, *args):
        result = subprocess.run([str(BINARY), 'alerts', *args], env=self.env,
                                check=True, capture_output=True, text=True, timeout=5)
        return json.loads(result.stdout)

    def test_text_notification_survives_unusable_audio_cache(self):
        (self.root / 'cache').write_text('not a directory')
        args = ('--settings', json.dumps({'notifications': True, 'sound': 'chime'}),
                '--event', json.dumps({'name': 'Dhuhr', 'epoch': time.time()}))
        result = self.run_alert(*args)
        self.assertTrue(self.marker.exists())
        self.assertFalse(result['ok'])  # Audio failure stays visible.
        self.marker.unlink()
        self.assertTrue(self.run_alert(*args)['skipped'])
        self.assertFalse(self.marker.exists())

    def test_preview_uses_audio_subdirectory(self):
        result = self.run_alert('--settings', '{"sound":"chime"}')
        self.assertTrue(result['ok'])
        expected = self.root / 'cache/omarchy-awqat/audio/chime.wav'
        self.assertEqual(Path(result['file']), expected)
        self.assertTrue(expected.is_file())

    def test_notification_test_does_not_require_audio_cache(self):
        (self.root / 'cache').write_text('not a directory')
        result = self.run_alert('--settings', '{"sound":"chime"}', '--test-notification')
        self.assertTrue(result['ok'])
        self.assertTrue(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
