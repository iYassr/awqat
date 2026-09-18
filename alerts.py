#!/usr/bin/env python3
"""Short-lived alert preparation; playback stays owned by Quickshell."""
import argparse
import fcntl
import html
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import wave

CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "omarchy-awqat" / "audio"
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "omarchy-awqat"
ADHANS = {"adhan-nafees": "https://cdn.aladhan.com/audio/adhans/a1.mp3",
          "adhan-alafasy": "https://cdn.aladhan.com/audio/adhans/a9.mp3"}
PRAYERS = {"Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"}


def claim_event(event, now=None):
    """Persist before delivery, so reloads and multiple monitors cannot repeat it."""
    now = time.time() if now is None else now
    epoch = float(event.get("epoch", 0))
    if event.get("name") not in PRAYERS or not math.isfinite(epoch) or not 0 <= now - epoch <= 90:
        return False
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    STATE.chmod(0o700)
    with (STATE / "alerts.lock").open("a") as lock:
        deadline = time.monotonic() + 3
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Another alert is still being prepared. Please retry.")
                time.sleep(0.05)
        ledger_path = STATE / "delivered.json"
        try:
            if ledger_path.stat().st_size > 16384:
                raise ValueError("Oversized delivery ledger")
            ledger = json.loads(ledger_path.read_text())
            if not isinstance(ledger, dict):
                ledger = {}
        except (OSError, ValueError, RecursionError):
            ledger = {}
        ledger = {k: v for k, v in ledger.items() if isinstance(v, (float, int)) and math.isfinite(v) and 0 <= now - v < 3 * 86400}
        key = event["name"] + ":" + str(int(epoch))
        if key in ledger:
            return False
        ledger[key] = now
        ledger = dict(sorted(ledger.items(), key=lambda pair: pair[1])[-32:])
        temp = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=STATE, delete=False) as f:
                temp = f.name
                json.dump(ledger, f)
            os.replace(temp, ledger_path)
        finally:
            if temp:
                Path(temp).unlink(missing_ok=True)
        return True


def make_tone(path, kind):
    rate = 16000
    seconds = 2.2 if kind == "bell" else 1.8
    frames = bytearray()
    for i in range(int(rate * seconds)):
        t = i / rate
        value = 0
        notes = [(0, 660), (0.5, 880)] if kind == "chime" else [(0, 523.25)]
        for start, hz in notes:
            elapsed = t - start
            if elapsed < 0:
                continue
            envelope = min(1, elapsed / 0.015) * math.exp(-elapsed * 3.1)
            value += envelope * (math.sin(2 * math.pi * hz * elapsed) + 0.22 * math.sin(2 * math.pi * hz * 2.01 * elapsed))
        fade = min(1, (seconds - t) / 0.1)
        frames.extend(struct.pack("<h", int(max(-1, min(1, value * 0.32 * fade)) * 32767)))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(frames)


def prepare_sound(settings):
    sound = settings.get("sound", "none")
    if sound == "none":
        return ""
    if sound == "custom":
        path = Path(str(settings.get("audioFile", ""))).expanduser()
        if not path.is_file() or path.suffix.lower() not in {".mp3", ".wav", ".ogg", ".flac", ".m4a", ".opus"}:
            raise ValueError("Choose an existing MP3, WAV, OGG, FLAC, M4A, or Opus audio file.")
        return str(path.resolve())
    if sound not in ADHANS and sound not in {"chime", "bell"}:
        raise ValueError("Unknown alert sound.")
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    CACHE.chmod(0o700)
    path = CACHE / (sound + (".mp3" if sound in ADHANS else ".wav"))
    if path.is_file() and 1000 < path.stat().st_size <= 8388608:
        return str(path)
    with tempfile.NamedTemporaryFile(dir=CACHE, prefix=".audio-", delete=False) as f:
        temp = Path(f.name)
    try:
        if sound in ADHANS:
            result = subprocess.run(["curl", "-q", "-fsSL", "--max-redirs", "0", "--connect-timeout", "5", "--max-time", "25",
                "--max-filesize", "8388608", "--proto", "=https", "--proto-redir", "=https",
                "--output", str(temp), ADHANS[sound]], capture_output=True, timeout=28)
            with temp.open("rb") as f:
                header = f.read(3)
            if result.returncode or not 1000 <= temp.stat().st_size <= 8388608 or not (header == b"ID3" or header[:1] == b"\xff"):
                raise ValueError("Could not download the adhan. Check your connection and try Preview again.")
        else:
            make_tone(temp, sound)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)
    return str(path)


def deliver(settings, event):
    notifications = settings.get("notifications", False) is True
    sound_on = settings.get("sound", "none") != "none"
    if not notifications and not sound_on:
        return {"ok": True, "skipped": True}
    if not claim_event(event):
        return {"ok": True, "skipped": True}
    warning = ""
    if notifications:
        try:
            title = event["name"] + " · " + event.get("arabic", "")
            body = "It’s time for " + event["name"] + "." + ("\n" + str(event.get("city", "")) if event.get("city") else "")
            subprocess.run(["notify-send", "--app-name=Awqat", "--icon=appointment-soon",
                "--urgency=normal", "--expire-time=15000", "--", title, html.escape(body)], check=True, timeout=5)
        except (OSError, subprocess.SubprocessError):
            warning = "The desktop notification could not be delivered."
    try:
        audio = prepare_sound(settings) if sound_on else ""
    except Exception as error:
        return {"ok": False, "error": str(error)}
    # Never start audio late because an on-demand download took too long.
    if time.time() - float(event["epoch"]) > 90:
        audio = ""
    return {"ok": True, "file": audio, "warning": warning}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", default="{}")
    parser.add_argument("--event")
    parser.add_argument("--test-notification", action="store_true")
    args = parser.parse_args()
    try:
        settings = json.loads(args.settings)
        if not isinstance(settings, dict):
            raise ValueError("Settings must be a JSON object.")
        if args.test_notification:
            subprocess.run(["notify-send", "--app-name=Awqat", "--icon=appointment-soon", "--expire-time=6000",
                            "--", "Awqat · Test notification", "Prayer-time notifications are ready."], check=True, timeout=5)
            result = {"ok": True, "file": ""}
        else:
            result = deliver(settings, json.loads(args.event)) if args.event else {"ok": True, "file": prepare_sound(settings)}
    except Exception as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
