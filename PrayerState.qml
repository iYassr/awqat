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
    property int consumers: 0
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
    property int audioGeneration: 0
    property bool warmupPending: false
    readonly property bool audioBusy: alertProc.running
    readonly property bool playing: player.running
    readonly property bool loading: fetcher.running
    readonly property var next: Model.nextPrayer(report, now)

    function attach() { consumers++ }
    function detach() {
        consumers = Math.max(0, consumers - 1)
        if (consumers > 0) return
        // QML singletons survive their widgets. Last-view teardown must stop work.
        config = ""
        refreshDebounce.stop()
        queuedForce = false
        stopAudio()
        alertProc.running = false
        fetcher.running = false
        report = null
        error = ""
        audioError = ""
        failures = 0
        retryAt = 0
        openPanels = 0
        secondsInBar = false
    }
    function configure(value) {
        if (config === value) return
        config = value
        report = null
        error = ""
        failures = 0
        queuedEvent = null
        stopAudio()
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
            if (nextSettings.sound !== "none") {
                if (alertProc.running) warmupPending = true
                else prepareAudio(nextSettings, false, null)
            }
        }
    }
    function stopAudio() {
        audioGeneration++
        warmupPending = false
        queuedEvent = null
        playPrepared = false
        pendingAudioFile = ""
        intentionalStop = player.running
        player.running = false
    }
    function launchPendingAudio() {
        if (!pendingAudioFile) return
        intentionalStop = false
        player.command = ["mpv", "--no-config", "--no-video", "--really-quiet", "--no-terminal",
            "--load-scripts=no", "--autoload-files=no", "--access-references=no", "--ytdl=no",
            "--demuxer-lavf-o=protocol_whitelist=file",
            "--volume=" + playbackVolume, "--", pendingAudioFile]
        pendingAudioFile = ""
        player.running = true
    }
    function testNotification() {
        if (alertProc.running) return
        audioError = ""
        playPrepared = false
        alertProc.command = [decodeURIComponent(Qt.resolvedUrl("awqat-helper").toString().replace(/^file:\/\//, "")), "alerts", "--test-notification"]
        alertProc.generation = audioGeneration
        alertProc.timedOut = false
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
        playbackVolume = Model.audioVolume(settings.volume)
        playPrepared = preview || event !== null
        var args = [decodeURIComponent(Qt.resolvedUrl("awqat-helper").toString().replace(/^file:\/\//, "")), "alerts", "--settings", JSON.stringify(settings)]
        if (event) args.push("--event", JSON.stringify(Object.assign({}, event, {city: report ? report.location.name : ""})))
        alertProc.command = args
        alertProc.generation = audioGeneration
        alertProc.timedOut = false
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
        var args = [decodeURIComponent(Qt.resolvedUrl("awqat-helper").toString().replace(/^file:\/\//, "")), "times", "--settings", config]
        if (force === true) args.push("--force")
        fetcher.command = args
        fetcher.timedOut = false
        fetcher.running = true
    }
    function failed(message) {
        error = message
        failures = Math.min(failures + 1, 5)
        retryAt = Date.now() / 1000 + Model.retryDelay(failures)
    }
    Timer { id: refreshDebounce; interval: 200; onTriggered: root.refresh(false) }
    Timer {
        interval: 110000
        running: fetcher.running
        onTriggered: {
            fetcher.timedOut = true
            fetcher.running = false
            root.failed("Location update timed out. Retrying automatically.")
        }
    }
    Timer {
        interval: 40000
        running: alertProc.running
        onTriggered: {
            alertProc.timedOut = true
            root.playPrepared = false
            alertProc.running = false
            root.audioError = "Alert preparation timed out. Please retry."
        }
    }
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
        property bool timedOut: false
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code, status) {
            if (!root.config) return
            if (root.activeConfig !== root.config || root.queuedForce) {
                var force = root.queuedForce
                root.queuedForce = false
                Qt.callLater(function() { root.refresh(force) })
                return
            }
            // Finish each request once; a timeout keeps its specific error.
            if (timedOut) return
            if (code !== 0) {
                root.failed("Prayer times helper stopped unexpectedly. Retrying automatically.")
                return
            }
            try {
                var result = JSON.parse(stdout.text)
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
    Process {
        id: alertProc
        property bool timedOut: false
        property int generation: 0
        stdout: StdioCollector { waitForEnd: true }
        onExited: function(code, status) {
            // Stop or a settings change invalidates a still-finishing request.
            if (!timedOut && generation === root.audioGeneration) {
                if (code !== 0) root.audioError = "Could not start the alert helper."
                else {
                    try {
                        var result = JSON.parse(stdout.text)
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
            if (root.queuedEvent) {
                var event = root.queuedEvent
                var generationAtExit = root.audioGeneration
                root.queuedEvent = null
                Qt.callLater(function() {
                    if (generationAtExit === root.audioGeneration)
                        root.prepareAudio(root.alertSettings, false, event)
                })
            } else if (root.warmupPending) {
                root.warmupPending = false
                var warmupGeneration = root.audioGeneration
                Qt.callLater(function() {
                    if (warmupGeneration === root.audioGeneration)
                        root.prepareAudio(root.alertSettings, false, null)
                })
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
