#!/usr/bin/env python3
"""Run the real PrayerState QML in an isolated, headless test shell.

Uses fake helper responses: no desktop windows, real alerts, or network calls.
Python and Quickshell are test tools; this creates no user configuration.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import QtQuick
import Quickshell
import "core" as Core
ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    property int checks: 0
    property double started: Date.now()
    function check(value, message) {
        if (!value) { console.error("AWQAT_TEST_FAIL: " + message); Qt.quit(); throw new Error(message) }
        checks++
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (Date.now() - test.started > 12000) { console.error("AWQAT_TEST_FAIL: phase timeout " + test.phase); Qt.quit(); return }
            var state = Core.PrayerState
            test.ticks++
            switch (test.phase) {
            case 0:
                state.attach(); state.attach()
                state.configure('{"locationMode":"auto"}')
                test.phase = 1
                break
            case 1:
                if (!state.report) return
                test.check(state.consumers === 2, "two widgets share one state")
                state.detach()
                test.check(state.consumers === 1 && !!state.report, "one remaining widget retains the schedule")
                state.prepareAudio({sound:"chime",volume:0}, true, null)
                test.phase = 2
                break
            case 2:
                if (!state.audioBusy) return
                test.check(state.audioBusy, "audio preparation started")
                state.stopAudio()
                state.audioError = "keep this message"
                test.phase = 3
                break
            case 3:
                if (state.audioBusy) return
                test.check(!state.playing && state.audioError === "keep this message", "late result after Stop is ignored")
                state.preferences({sound:"chime",volume:0})
                test.phase = 4
                break
            case 4:
                if (!state.audioBusy) return
                state.preferences({sound:"bell",volume:0})
                test.check(state.warmupPending, "changed sound is queued")
                test.phase = 5
                break
            case 5:
                if (state.audioBusy || state.warmupPending) return
                test.check(state.audioError === "", "latest sound warmup succeeds")
                state.prepareAudio({sound:"chime",volume:0}, true, null)
                test.phase = 6
                break
            case 6:
                if (!state.audioBusy) return
                test.check(state.audioBusy, "preparation in flight before teardown")
                state.detach()
                test.check(state.consumers === 0 && state.config === "", "last widget deactivates the singleton")
                test.check(state.report === null, "teardown clears stale schedule")
                test.ticks = 0
                test.phase = 7
                break
            case 7:
                if (test.ticks < 8) return
                test.check(!state.loading && !state.audioBusy && !state.playing, "teardown stops all processes")
                test.check(state.audioError === "" && state.error === "", "terminated processes cannot replace cleared errors")
                var before = state.requests
                state.refresh(true)
                test.check(state.requests === before, "disabled state cannot refresh")
                state.attach()
                state.configure('{"locationMode":"auto"}')
                test.phase = 8
                break
            case 8:
                if (!state.report) return
                test.check(state.consumers === 1, "reattaching reactivates the state")
                state.refresh(true)
                test.phase = 9
                break
            case 9:
                if (!state.loading) return
                test.check(state.loading, "schedule fetch in flight before teardown")
                state.detach()
                test.ticks = 0
                test.phase = 10
                break
            case 10:
                if (test.ticks < 8) return
                test.check(!state.loading && state.report === null && state.error === "", "cancelled fetch cannot repopulate disabled state")
                console.log("AWQAT_TEST_PASS: " + test.checks + " lifecycle checks")
                Qt.quit()
            }
        }
    }
}
'''
HELPER = '''#!/usr/bin/python3
import json, sys, time
if sys.argv[1] == "times":
    time.sleep(0.35)
    print(json.dumps({"ok":True,"events":[],"rows":[],"refreshAt":time.time()+3600,"dayEnds":time.time()+3600}))
else:
    settings=json.loads(sys.argv[sys.argv.index("--settings")+1])
    time.sleep(0.35)
    print(json.dumps({"ok":True,"file":""} if settings["sound"]=="bell" else {"ok":False,"error":"stale alert result"}))
'''
with tempfile.TemporaryDirectory(prefix="awqat-qml-test-") as folder:
    root = Path(folder)
    core = root / 'core'
    core.mkdir()
    for name in ['PrayerState.qml', 'Model.js', 'qmldir']:
        shutil.copy2(ROOT / name, core / name)
    (root / 'shell.qml').write_text(HARNESS)
    helper = core / 'awqat-helper'
    helper.write_text(HELPER)
    helper.chmod(0o700)
    runtime = root / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=str(runtime),
               XDG_CONFIG_HOME=str(root / 'config'), XDG_CACHE_HOME=str(root / 'cache'),
               XDG_STATE_HOME=str(root / 'state'), QML_DISABLE_DISK_CACHE='1')
    result = subprocess.run(['qs', '-p', str(root / 'shell.qml'), '--no-color'],
                            env=env, text=True, capture_output=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or 'AWQAT_TEST_FAIL' in output or 'AWQAT_TEST_PASS' not in output:
        raise SystemExit(output)
    print(next(line for line in output.splitlines() if 'AWQAT_TEST_PASS' in line))
