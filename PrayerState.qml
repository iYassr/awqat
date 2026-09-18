pragma Singleton
import QtQuick
import Quickshell.Io
import "Model.js" as Model

// One clock and one fetch process, shared by every monitor.
Item {
    id: root
    property var report: null
    property string error: ""
    property double now: Date.now() / 1000
    property int openPanels: 0
    property string config: ""
    property string activeConfig: ""
    property double retryAt: 0
    property double lastAttempt: 0
    property int failures: 0
    property int requests: 0
    property bool queuedForce: false
    property bool secondsInBar: false
    property var alertSettings: ({notifications: false, sound: "none", volume: 35, audioFile: ""})
    property var alerted: []
    property string audioError: ""
    property bool playPrepared: false
    property int playbackVolume: 35
    property var queuedEvent: null
    property string pendingAudioFile: ""
    property bool intentionalStop: false
    readonly property bool audioBusy: alertProc.running
    readonly property bool playing: player.running
    readonly property bool loading: fetcher.running
    readonly property var next: Model.nextPrayer(report, now)

    function configure(value) {
        if (config === value) return
        config = value
        report = null
        error = ""
        failures = 0
        refreshDebounce.restart()
    }
    function touch() { now = Date.now() / 1000 }
    function preferences(settings) {
        secondsInBar = Model.barTemplate(settings).indexOf("{remainingClock}") >= 0
        var nextSettings = {notifications: settings.notifications === true, sound: settings.sound || "none",
            volume: settings.volume === undefined ? 35 : settings.volume, audioFile: settings.audioFile || ""}
        var changed = nextSettings.sound !== alertSettings.sound || nextSettings.audioFile !== alertSettings.audioFile
        alertSettings = nextSettings
        if (changed) {
            audioError = ""
            stopAudio()
            if (nextSettings.sound !== "none") prepareAudio(nextSettings, false, null)
        }
    }
    function stopAudio() {
        playPrepared = false
        pendingAudioFile = ""
        intentionalStop = player.running
        player.running = false
    }
    function launchPendingAudio() {
        if (!pendingAudioFile) return
        intentionalStop = false
        player.command = ["mpv", "--no-config", "--no-video", "--really-quiet", "--no-terminal",
            "--volume=" + playbackVolume, "--", pendingAudioFile]
        pendingAudioFile = ""
        player.running = true
    }
    function testNotification() {
        if (alertProc.running) return
        audioError = ""
        playPrepared = false
        alertProc.command = ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("alerts.py").toString().replace(/^file:\/\//, "")), "--test-notification"]
        alertProc.running = true
    }
    function prepareAudio(settings, preview, event) {
        if (alertProc.running) {
            if (event) queuedEvent = event
            else audioError = "Audio is being prepared. Please wait a moment."
            return
        }
        if (preview) stopAudio()
        audioError = ""
        playbackVolume = Math.max(0, Math.min(100, Number(settings.volume === undefined ? 35 : settings.volume)))
        playPrepared = preview || event !== null
        var args = ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("alerts.py").toString().replace(/^file:\/\//, "")), "--settings", JSON.stringify(settings)]
        if (event) args.push("--event", JSON.stringify(Object.assign({}, event, {city: report ? report.location.name : ""})))
        alertProc.command = args
        alertProc.running = true
    }
    function checkAlerts() {
        if (!alertSettings.notifications && alertSettings.sound === "none") return
        var event = Model.duePrayer(report, now, alerted)
        if (!event) return
        alerted = alerted.concat([event.name + ":" + event.epoch]).slice(-20)
        prepareAudio(alertSettings, false, event)
    }
    function refresh(force) {
        if (!config) return
        if (fetcher.running) { queuedForce = queuedForce || force === true; return }
        activeConfig = config
        lastAttempt = Date.now() / 1000
        requests++
        var args = ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("prayer_times.py").toString().replace(/^file:\/\//, "")), "--settings", config]
        if (force === true) args.push("--force")
        fetcher.command = args
        fetcher.running = true
    }
    function failed(message) {
        error = message
        failures = Math.min(failures + 1, 5)
        retryAt = Date.now() / 1000 + Model.retryDelay(failures)
    }
    Timer { id: refreshDebounce; interval: 200; onTriggered: root.refresh(false) }
    Timer {
        // The bar only changes at a prayer boundary. Cap sleep at one minute
        // to notice clock changes and resume from suspend; seconds are UI-only.
        interval: root.openPanels > 0 || root.secondsInBar ? 1000 : Math.max(1000, Math.min(60000, root.next ? (root.next.epoch - root.now) * 1000 : 60000))
        running: root.config !== ""
        repeat: true
        onTriggered: {
            root.touch()
            root.checkAlerts()
            if (!root.loading && (root.now >= root.retryAt || root.now < root.lastAttempt ||
                (root.report && root.now >= root.report.dayEnds && root.now - root.lastAttempt >= Model.retryDelay(root.failures))))
                root.refresh(false)
        }
    }
    Process {
        id: fetcher
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.activeConfig !== root.config) return
                try {
                    var result = JSON.parse(text)
                    if (result.ok) {
                        root.report = result
                        root.error = ""
                        if (result.offline || result.missingTomorrow) {
                            root.failures = Math.min(root.failures + 1, 5)
                            root.retryAt = Date.now() / 1000 + Model.retryDelay(root.failures)
                        } else {
                            root.failures = 0
                            root.retryAt = result.refreshAt || Math.min(result.dayEnds, Date.now() / 1000 + 1800)
                        }
                    } else root.failed(result.error || "Could not load prayer times.")
                } catch (e) { root.failed("Could not load prayer times. Please retry.") }
                root.touch()
                root.checkAlerts()
            }
        }
        onExited: function(code, status) {
            if (root.activeConfig !== root.config || root.queuedForce) {
                var force = root.queuedForce
                root.queuedForce = false
                Qt.callLater(function() { root.refresh(force) })
            } else if (code !== 0) root.failed("Prayer times helper stopped unexpectedly. Retrying automatically.")
        }
    }
    Process {
        id: alertProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    if (!result.ok) root.audioError = result.error || "Could not prepare audio."
                    else {
                        root.audioError = result.warning || ""
                        if (root.playPrepared && result.file) {
                            root.pendingAudioFile = result.file
                            if (player.running) { root.intentionalStop = true; player.running = false }
                            else root.launchPendingAudio()
                        }
                    }
                } catch (e) { root.audioError = "Could not prepare the prayer alert." }
            }
        }
        onExited: function(code, status) {
            if (code !== 0) root.audioError = "Could not start the alert helper."
            if (root.queuedEvent) {
                var event = root.queuedEvent
                root.queuedEvent = null
                Qt.callLater(function() { root.prepareAudio(root.alertSettings, false, event) })
            }
        }
    }
    Process {
        id: player
        onExited: function(code, status) {
            if (code !== 0 && !root.intentionalStop && root.playPrepared) root.audioError = "Audio playback failed. Check mpv and your sound output."
            root.intentionalStop = false
            root.launchPendingAudio()
        }
    }
}
