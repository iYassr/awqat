import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model
import "." as Core

Ui.BarWidget {
    id: root
    moduleName: "yasserdo.awqat"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property var report: Core.PrayerState.report
    readonly property string error: Core.PrayerState.error
    readonly property double now: Core.PrayerState.now
    readonly property bool loading: Core.PrayerState.loading
    readonly property bool clock24: setting("clock24", false) === true
    readonly property var next: Core.PrayerState.next
    readonly property string barLabel: Model.formatBar(next, report, now, settings)
    readonly property bool showIcon: setting("showIcon", true) !== false || barLabel === ""
    readonly property bool playing: Core.PrayerState.playing
    readonly property bool audioBusy: Core.PrayerState.audioBusy
    readonly property string audioError: Core.PrayerState.audioError
    property bool pendingOpen: false
    property bool pendingSettings: false
    property string pendingPage: "location"
    property bool countedOpen: false
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing : false

    function open(editSettings, page) {
        pendingSettings = editSettings === true
        pendingPage = ["location", "bar", "alerts"].indexOf(page) >= 0 ? page : "location"
        Core.PrayerState.touch()
        unloadTimer.stop()
        if (panelLoader.item) {
            panelLoader.item.settingsPage = pendingPage
            panelLoader.item.editing = pendingSettings
            panelLoader.item.open()
        } else {
            pendingOpen = true
            panelLoader.active = true
        }
    }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() { opened ? close() : open() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
    function configuration() {
        return JSON.stringify({locationMode: setting("locationMode", "auto"), city: setting("city", "Riyadh"),
                               method: setting("method", "auto"), school: setting("school", "0")})
    }
    function refresh(force) { Core.PrayerState.refresh(force) }
    function previewAudio(values) { Core.PrayerState.prepareAudio(values, true, null) }
    function stopAudio() { Core.PrayerState.stopAudio() }
    function testNotification() { Core.PrayerState.testNotification() }
    function save(values) {
        if (!bar || !bar.shell) return
        var entry = Object.assign({}, settings, values)
        bar.shell.updateEntryInline(moduleName, entry)
    }
    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }
    onBarChanged: injectPanel()
    onSettingsChanged: { Core.PrayerState.configure(configuration()); Core.PrayerState.preferences(settings) }
    Component.onCompleted: { Core.PrayerState.configure(configuration()); Core.PrayerState.preferences(settings) }
    Component.onDestruction: if (countedOpen) Core.PrayerState.openPanels = Math.max(0, Core.PrayerState.openPanels - 1)
    onOpenedChanged: {
        if (opened !== countedOpen) {
            Core.PrayerState.openPanels = Math.max(0, Core.PrayerState.openPanels + (opened ? 1 : -1))
            countedOpen = opened
        }
        if (!opened) unloadTimer.restart()
    }
    Timer {
        id: unloadTimer
        interval: 300
        onTriggered: if (!root.opened) panelLoader.active = false
    }
    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            if (root.pendingOpen) {
                root.pendingOpen = false
                item.settingsPage = root.pendingPage
                item.editing = root.pendingSettings
                item.open()
            }
        }
    }
    IpcHandler {
        target: "yasserdo.awqat"
        function open() { root.open() }
        function close() { root.close() }
        function toggle() { root.toggle() }
        function refresh() { root.refresh(true) }
        function settings() { root.open(true) }
        function settingsTab(page: string) { root.open(true, page) }
        function preview(sound: string, volume: string) {
            var level = Number(volume)
            root.previewAudio(Object.assign({}, root.settings, {sound: sound, volume: isFinite(level) ? level : 35}))
        }
        function stopAudio() { root.stopAudio() }
        function testNotification() { root.testNotification() }
        function status(): string {
            return JSON.stringify({loading: root.loading, error: root.error, report: root.report, next: root.next, panelLoaded: panelLoader.active, openPanels: Core.PrayerState.openPanels, requests: Core.PrayerState.requests, retryAt: Core.PrayerState.retryAt, barLabel: root.barLabel, playing: root.playing, audioError: root.audioError})
        }
    }
    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: ""
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? -1 : label.implicitWidth + scaledHorizontalMargin * 2
        tooltipText: root.report ? root.report.location.name + " · " + (root.next ? root.next.name + " at " + Model.timeLabel(root.next, root.clock24) : "Prayer times") : "Awqat · Prayer times"
        Accessible.role: Accessible.Button
        Accessible.name: "Awqat prayer times. " + tooltipText
        Accessible.onPressAction: root.toggle()
        onPressed: function(b) {
            if (b === Qt.MiddleButton) root.refresh(true)
            else root.toggle()
        }
        Row {
            id: label
            anchors.centerIn: parent
            spacing: Style.space(6)
            AwqatIcon {
                visible: root.showIcon || root.vertical
                ink: button.foreground
                opacity: 0.8
                width: Style.space(17)
                height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !root.vertical && root.barLabel !== ""
                text: root.barLabel
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, Style.space(300))
                elide: Text.ElideRight
                color: button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
