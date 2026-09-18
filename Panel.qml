import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
    id: root
    moduleName: "yasserdo.awqat"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property bool editing: false
    property string settingsPage: "location"
    readonly property var report: hostWidget ? hostWidget.report : null
    readonly property var next: hostWidget ? hostWidget.next : null
    readonly property double now: hostWidget ? hostWidget.now : Date.now() / 1000
    readonly property bool loading: hostWidget ? hostWidget.loading : false
    readonly property bool clock24: hostWidget ? hostWidget.clock24 : false
    readonly property color ink: Color.popups.text
    readonly property color accent: Color.accent
    readonly property color muted: Qt.alpha(ink, 0.55)
    readonly property string sans: "Adwaita Sans"
    readonly property double previewMinute: Math.floor(now / 60) * 60
    readonly property var previewPrayer: root.next || ({name: "Dhuhr", arabic: "الظهر", time24: "11:47", time12: "11:47", period: "AM", epoch: root.previewMinute + 3600})
    readonly property string customFormatError: barPreset.value === "custom" ? Model.formatError(customFormat.text) : ""
    onSettingsPageChanged: scroll.contentY = 0
    onOpenedChanged: if (!opened) editing = false

    function open() {
        if (hostWidget) { if (!report) hostWidget.refresh(false) }
        root.controller.show()
    }
    function audioPreferences() {
        return {sound: soundChoice.value, volume: Math.round(volume.value), audioFile: audioFile.text.trim()}
    }
    function saveSettings() {
        hostWidget.save({locationMode: mode.value, city: city.text.trim(), method: method.value, school: school.value,
            barPreset: barPreset.value, barFormat: customFormat.text, showIcon: iconToggle.checked,
            clock24: timeFormat.value === "24", notifications: notificationToggle.checked,
            sound: soundChoice.value, volume: Math.round(volume.value), audioFile: audioFile.text.trim()})
        editing = false
    }
    onEditingChanged: {
        scroll.contentY = 0
        if (editing && hostWidget) {
            mode.value = hostWidget.setting("locationMode", "auto")
            city.text = hostWidget.setting("city", "Riyadh")
            method.value = String(hostWidget.setting("method", "auto"))
            school.value = String(hostWidget.setting("school", "0"))
            barPreset.value = hostWidget.setting("barPreset", "name-time")
            customFormat.text = hostWidget.setting("barFormat", "{name} {h}::{mm}:{ampm}")
            iconToggle.checked = hostWidget.setting("showIcon", true) !== false
            timeFormat.value = hostWidget.clock24 ? "24" : "12"
            notificationToggle.checked = hostWidget.setting("notifications", false) === true
            soundChoice.value = hostWidget.setting("sound", "none")
            volume.value = hostWidget.setting("volume", 35)
            audioFile.text = hostWidget.setting("audioFile", "")
        }
    }

    Ui.KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        centerOnBar: false
        focusTarget: root.editing && root.settingsPage === "bar" ? barPreset.focusItem : focusScope
        contentWidth: fittedContentWidth(Style.space(root.editing ? 340 : 300))
        contentHeight: fittedContentHeight(content.implicitHeight)
        padding: Style.space(12)
        borderSpec: Border.flat(Qt.alpha(root.ink, 0.16), 1)

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: { if (root.editing) root.editing = false; else root.close() }
            Flickable {
                id: scroll
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: content.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                Column {
                    id: content
                    width: parent.width
                    spacing: Style.space(10)

                    Item {
                        width: parent.width
                        height: Style.space(28)
                        Row {
                            spacing: Style.space(8)
                            anchors.verticalCenter: parent.verticalCenter
                            AwqatIcon { ink: root.ink; opacity: 0.7; width: Style.space(23); height: width; anchors.verticalCenter: parent.verticalCenter }
                            Text { textFormat: Text.PlainText; text: "Awqat"; color: root.ink; font.family: root.sans; font.pixelSize: Style.space(16); font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                            Text { textFormat: Text.PlainText; text: "أوقات"; color: root.muted; font.family: "Noto Naskh Arabic"; font.pixelSize: Style.space(16); anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(4)
                            Ui.PanelActionButton {
                                iconText: "\uf021"; tooltipText: "Refresh times and detect location again"; size: Style.space(24)
                                foreground: root.muted; hoverColor: root.accent; focusable: true
                                enabled: !root.loading
                                onClicked: if (root.hostWidget) root.hostWidget.refresh(true)
                            }
                            Ui.PanelActionButton {
                                iconText: root.editing ? "×" : "\uf013"; tooltipText: root.editing ? "Back to prayer times" : "Location & calculation settings"
                                size: Style.space(24); foreground: root.muted; hoverColor: root.accent; focusable: true
                                onClicked: root.editing = !root.editing
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: locationInfo.implicitHeight
                        Column {
                            id: locationInfo
                            width: parent.width - autoBadge.width - Style.space(12)
                            spacing: Style.space(5)
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width; elide: Text.ElideRight
                                text: root.report ? root.report.location.name : (root.loading ? "Finding your location…" : "Your daily prayer companion")
                                color: root.ink; font.family: root.sans; font.pixelSize: Style.space(12); font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width; elide: Text.ElideRight
                                text: root.report ? root.report.dateLabel : "Prayer times for wherever you are"
                                color: root.muted; font.family: root.sans; font.pixelSize: Style.space(11)
                            }
                        }
                        Rectangle {
                            id: autoBadge
                            anchors.right: parent.right; anchors.top: parent.top
                            width: badgeText.implicitWidth + Style.space(16); height: Style.space(18); radius: height / 2
                            color: "transparent"
                            Text {
                                textFormat: Text.PlainText
                                id: badgeText; anchors.centerIn: parent
                                text: root.loading ? "Updating…" : (root.report && !root.report.location.automatic ? "Manual" : "Auto · IP")
                                color: root.muted; font.family: root.sans; font.pixelSize: Style.space(10)
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Style.space(78)
                        visible: !root.editing
                        radius: Style.space(8)
                        color: Qt.alpha(root.ink, 0.035)
                        Column {
                            anchors.left: parent.left; anchors.top: parent.top
                            anchors.margins: Style.space(11)
                            spacing: Style.space(4)
                            Text {
                                textFormat: Text.PlainText
                                text: root.next ? root.next.name + " in" : "Next prayer"
                                color: root.muted; font.family: root.sans; font.pixelSize: Style.space(11)
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.next ? Model.countdown(root.next.epoch - root.now, false) : "— : — : —"
                                color: root.ink; font.family: "Adwaita Mono"; font.pixelSize: Style.space(24)
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            anchors.right: parent.right; anchors.rightMargin: Style.space(11)
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.next ? Model.timeLabel(root.next, root.clock24) + (root.report && root.next.epoch >= root.report.dayEnds ? "\ntomorrow" : "") : (root.loading ? "Loading…" : "Refresh to load")
                            horizontalAlignment: Text.AlignRight
                            color: root.muted; font.family: root.sans; font.pixelSize: Style.space(11)
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.leftMargin: Style.space(11); anchors.rightMargin: Style.space(11); anchors.bottomMargin: Style.space(7)
                            height: 1; color: Qt.alpha(root.ink, 0.06)
                            Rectangle {
                                height: parent.height
                                width: parent.width * Model.progress(root.report, root.now)
                                color: Qt.alpha(root.accent, 0.45)
                                Behavior on width { NumberAnimation { duration: 600 } }
                            }
                        }
                    }

                    Column {
                        width: parent.width; spacing: Style.space(4)
                        visible: !root.editing
                        Item {
                            width: parent.width; height: Style.space(20)
                            Text { textFormat: Text.PlainText; text: root.report && root.now >= root.report.dayEnds ? "Saved schedule" : "Today"; color: root.muted; font.family: root.sans; font.pixelSize: Style.space(10); font.letterSpacing: 0; anchors.verticalCenter: parent.verticalCenter }
                            Ui.Button {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: root.clock24 ? "24H" : "12H"; fontSize: Style.space(10); foreground: root.muted; focusable: true
                                tooltipText: "Switch time format"
                                onClicked: if (root.hostWidget) root.hostWidget.save({clock24: !root.clock24})
                            }
                        }
                        Column {
                            width: parent.width; spacing: Style.space(2)
                            Repeater {
                                model: root.report ? root.report.rows : []
                                delegate: Rectangle {
                                    id: prayerRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool upcoming: root.next !== null && root.next.epoch === modelData.epoch && root.next.name === modelData.name
                                    readonly property bool passed: modelData.epoch <= root.now
                                    width: parent.width; height: Style.space(30); radius: Style.space(6)
                                    color: upcoming ? Qt.alpha(root.accent, 0.07) : "transparent"
                                    border.width: 0
                                    Rectangle {
                                        anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
                                        width: Style.space(4); height: width; radius: width / 2
                                        color: prayerRow.upcoming ? root.accent : Qt.alpha(root.ink, prayerRow.passed ? 0.15 : 0.35)
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.left: parent.left; anchors.leftMargin: Style.space(24); anchors.verticalCenter: parent.verticalCenter
                                        text: prayerRow.modelData.name
                                        color: prayerRow.upcoming ? root.accent : Qt.alpha(root.ink, prayerRow.passed ? 0.5 : 0.9)
                                        font.family: root.sans; font.pixelSize: Style.space(12); font.weight: prayerRow.upcoming ? Font.DemiBold : Font.Normal
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.right: timeLabel.left; anchors.rightMargin: Style.space(16); anchors.verticalCenter: parent.verticalCenter
                                        text: prayerRow.modelData.arabic
                                        font.family: "Noto Naskh Arabic"; font.pixelSize: Style.space(15)
                                        color: prayerRow.upcoming ? Qt.alpha(root.accent, 0.85) : Qt.alpha(root.ink, 0.35)
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        id: timeLabel
                                        anchors.right: parent.right; anchors.rightMargin: Style.space(14); anchors.verticalCenter: parent.verticalCenter
                                        text: Model.timeLabel(prayerRow.modelData, root.clock24)
                                        color: prayerRow.upcoming ? root.accent : Qt.alpha(root.ink, prayerRow.passed ? 0.5 : 0.9)
                                        font.family: "Adwaita Mono"; font.pixelSize: Style.space(12); font.weight: prayerRow.upcoming ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                        Text {
                            textFormat: Text.PlainText
                            visible: !root.report; width: parent.width; horizontalAlignment: Text.AlignHCenter
                            topPadding: Style.space(20); bottomPadding: Style.space(20)
                            text: root.loading ? "Fetching your local prayer times…" : "Your schedule will appear here."
                            color: root.muted; font.family: root.sans; font.pixelSize: Style.space(13)
                        }
                    }

                    Column {
                        width: parent.width; spacing: Style.space(10)
                        visible: root.editing
                        Row {
                            width: parent.width; spacing: Style.space(4)
                            Repeater {
                                model: [{key: "location", label: "Location"}, {key: "bar", label: "Bar"}, {key: "alerts", label: "Alerts"}]
                                delegate: Ui.Button {
                                    required property var modelData
                                    width: (parent.width - Style.space(8)) / 3
                                    text: modelData.label; fontFamily: root.sans; fontSize: Style.space(12)
                                    selected: root.settingsPage === modelData.key; focusable: true
                                    onClicked: root.settingsPage = modelData.key
                                }
                            }
                        }
                        Column {
                            width: parent.width; spacing: Style.space(12)
                            visible: root.settingsPage === "location"
                        Ui.Dropdown {
                            id: mode; width: parent.width; label: "LOCATION"; value: "auto"
                            options: [{value: "auto", label: "Automatic · detect from IP"}, {value: "manual", label: "Choose a city"}]
                            onChanged: function(value) { mode.value = value }
                        }
                        Ui.TextField {
                            id: city; width: parent.width; visible: mode.value === "manual"
                            placeholderText: "City name, e.g. Riyadh"; text: "Riyadh"
                            onAccepted: root.saveSettings()
                        }
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width; wrapMode: Text.WordWrap
                            text: "Automatic location follows your public IP and checks every 30 minutes. A VPN may change the detected city."
                            font.family: root.sans; font.pixelSize: Style.space(12); color: root.muted
                        }
                        Ui.Dropdown {
                            id: method; width: parent.width; label: "CALCULATION METHOD"; value: "auto"
                            options: [
                                {value: "auto", label: "Automatic · local authority"},
                                {value: "4", label: "Umm al-Qura · Makkah"},
                                {value: "3", label: "Muslim World League"},
                                {value: "2", label: "ISNA · North America"},
                                {value: "5", label: "Egyptian General Authority"},
                                {value: "1", label: "University of Islamic Sciences · Karachi"},
                                {value: "8", label: "Gulf Region"},
                                {value: "9", label: "Kuwait"},
                                {value: "10", label: "Qatar"},
                                {value: "11", label: "Singapore"},
                                {value: "13", label: "Diyanet · Turkey"}]
                            onChanged: function(value) { method.value = value }
                        }
                        Ui.Dropdown {
                            id: school; width: parent.width; label: "ASR CALCULATION"; value: "0"
                            options: [{value: "0", label: "Standard · Shafi‘i, Maliki, Hanbali"}, {value: "1", label: "Hanafi"}]
                            onChanged: function(value) { school.value = value }
                        }
                        }
                        Column {
                            width: parent.width; spacing: Style.space(12)
                            visible: root.settingsPage === "bar"
                            FormatPicker {
                                id: barPreset; width: parent.width
                                options: Model.barOptions(root.previewPrayer, root.report, root.previewMinute, {barFormat: customFormat.text, clock24: timeFormat.value === "24"}); value: "name-time"
                                onChanged: function(value) { barPreset.value = value }
                            }
                            Ui.TextField {
                                id: customFormat; width: parent.width; visible: barPreset.value === "custom"
                                placeholderText: "{name} {h}::{mm}:{ampm}"; maximumLength: 200
                                Accessible.name: "Custom bar format"
                            }
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width; visible: root.customFormatError !== ""; wrapMode: Text.WordWrap
                                text: root.customFormatError; color: root.accent; font.family: root.sans; font.pixelSize: Style.space(11)
                            }
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width; visible: barPreset.value === "custom"; wrapMode: Text.WordWrap
                                text: "{name}  {arabic}  {short}  {time}  {time24}  {time12}  {h}  {hh}  {H}  {HH}  {mm}  {ampm}  {AMPM}  {remaining}  {remainingClock}  {city}  {icon}"
                                color: root.muted; font.family: "Adwaita Mono"; font.pixelSize: Style.space(10)
                            }
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width; visible: barPreset.value === "custom"; wrapMode: Text.WordWrap
                                text: "Use any order or separators. h/hh = 12-hour; H/HH = 24-hour. Doubled letters add a leading zero. RemainingClock shows seconds."
                                color: root.muted; font.family: root.sans; font.pixelSize: Style.space(11)
                            }
                            Ui.Dropdown {
                                id: timeFormat; width: parent.width; label: "TIME FORMAT"; value: "12"
                                options: [{value: "12", label: "12-hour · 11:47 AM"}, {value: "24", label: "24-hour · 15:15"}]
                                onChanged: function(value) { timeFormat.value = value }
                            }
                            Ui.Toggle {
                                id: iconToggle; width: parent.width; label: "Show Awqat icon"; checked: true
                                fontFamily: root.sans; titleSize: Style.space(12)
                                onClicked: checked = !checked
                            }
                            Text { textFormat: Text.PlainText; text: "LIVE PREVIEW"; color: root.muted; font.family: root.sans; font.pixelSize: Style.space(10) }
                            Rectangle {
                                width: parent.width; height: previewText.implicitHeight + Style.space(22)
                                radius: Style.space(6); color: Qt.alpha(root.ink, 0.04)
                                Row {
                                    anchors.centerIn: parent; spacing: Style.space(7)
                                    AwqatIcon {
                                        visible: iconToggle.checked || barPreset.value === "icon"
                                        ink: root.ink; width: Style.space(17); height: width; anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        id: previewText
                                        width: Math.min(implicitWidth, barPreset.width - Style.space(58)); elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        text: Model.formatBar(root.previewPrayer, root.report, root.now, {barPreset: barPreset.value, barFormat: customFormat.text, clock24: timeFormat.value === "24"})
                                        color: root.ink; font.family: "Adwaita Mono"; font.pixelSize: Style.space(12)
                                    }
                                }
                            }
                        }
                        Column {
                            width: parent.width; spacing: Style.space(12)
                            visible: root.settingsPage === "alerts"
                            Ui.Toggle {
                                id: notificationToggle; width: parent.width; label: "Prayer-time notification"; checked: false
                                fontFamily: root.sans; titleSize: Style.space(12)
                                onClicked: checked = !checked
                            }
                            Ui.Button {
                                text: "Send test notification"; fontFamily: root.sans; fontSize: Style.space(12); focusable: true
                                enabled: root.hostWidget && !root.hostWidget.audioBusy
                                onClicked: root.hostWidget.testNotification()
                            }
                            Ui.Dropdown {
                                id: soundChoice; width: parent.width; label: "PRAYER-TIME SOUND"; value: "none"
                                options: [{value: "none", label: "Silent"}, {value: "chime", label: "Gentle chime"},
                                    {value: "bell", label: "Soft bell"}, {value: "adhan-nafees", label: "Adhan · Ahmad al-Nafees"},
                                    {value: "adhan-alafasy", label: "Adhan · Mishary Alafasy"}, {value: "custom", label: "My own audio file…"}]
                                onChanged: function(value) { soundChoice.value = value }
                            }
                            Ui.TextField {
                                id: audioFile; width: parent.width; visible: soundChoice.value === "custom"
                                placeholderText: "~/Music/adhan.mp3"
                            }
                            Column {
                                width: parent.width; spacing: Style.space(6); visible: soundChoice.value !== "none"
                                Text { textFormat: Text.PlainText; text: "Volume · " + Math.round(volume.value) + "%"; color: root.muted; font.family: root.sans; font.pixelSize: Style.space(11) }
                                Ui.PanelSlider {
                                    id: volume; width: parent.width; bar: root.bar
                                    minimum: 0; maximum: 100; step: 5; integer: true; value: 35
                                    fillColor: root.accent
                                    onMoved: function(value) { volume.value = value }
                                    activeFocusOnTab: true
                                    Accessible.name: "Prayer sound volume, " + Math.round(value) + " percent"
                                    Keys.onLeftPressed: value = Math.max(minimum, value - step)
                                    Keys.onRightPressed: value = Math.min(maximum, value + step)
                                    Keys.onDownPressed: value = Math.max(minimum, value - step)
                                    Keys.onUpPressed: value = Math.min(maximum, value + step)
                                    Rectangle { anchors.fill: parent; anchors.margins: -2; visible: volume.activeFocus; color: "transparent"; border.width: 1; border.color: root.accent; radius: 4 }
                                }
                                Row {
                                    spacing: Style.space(6)
                                    Ui.Button {
                                        text: root.hostWidget && root.hostWidget.audioBusy ? "Preparing…" : "Preview sound"
                                        focusable: true; fontFamily: root.sans; fontSize: Style.space(12)
                                        enabled: root.hostWidget && !root.hostWidget.audioBusy
                                        onClicked: root.hostWidget.previewAudio(root.audioPreferences())
                                    }
                                    Ui.Button {
                                        text: "Stop"; focusable: true; fontFamily: root.sans; fontSize: Style.space(12)
                                        enabled: root.hostWidget && (root.hostWidget.playing || root.hostWidget.audioBusy)
                                        onClicked: root.hostWidget.stopAudio()
                                    }
                                }
                            }
                            Text {
                                textFormat: Text.PlainText
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "Alerts run while Omarchy is running and your device is awake. Sunrise is excluded. Missed prayers older than 90 seconds stay silent. Adhan recordings download once, then work offline."
                                color: root.muted; font.family: root.sans; font.pixelSize: Style.space(11)
                            }
                            Text {
                                textFormat: Text.PlainText
                                visible: root.hostWidget && root.hostWidget.audioError !== ""
                                width: parent.width; wrapMode: Text.WordWrap
                                text: root.hostWidget ? root.hostWidget.audioError : ""
                                color: root.accent; font.family: root.sans; font.pixelSize: Style.space(11)
                            }
                        }
                        Ui.Button {
                            width: parent.width; text: "Save settings"; foreground: root.accent; selected: true
                            fontFamily: root.sans; verticalPadding: Style.space(12); focusable: true
                            enabled: (mode.value === "auto" || city.text.trim().length > 0) && root.customFormatError === "" && (soundChoice.value !== "custom" || audioFile.text.trim().length > 0)
                            onClicked: root.saveSettings()
                        }
                    }

                    Text {

                        textFormat: Text.PlainText
                        width: parent.width
                        visible: text !== ""
                        text: root.hostWidget && root.hostWidget.error ? root.hostWidget.error : (root.hostWidget && root.hostWidget.audioError ? "Audio: " + root.hostWidget.audioError : (root.report && root.now >= root.report.dayEnds ? "Updating for the new day…" : (root.report && root.report.offline ? "Offline · showing saved times" + (root.report.locationStale ? " and last detected location" : "") : (root.report && root.report.missingTomorrow ? "Tomorrow’s times are unavailable. Retrying shortly." : ""))))
                        color: root.accent; font.family: root.sans; font.pixelSize: Style.space(11); wrapMode: Text.WordWrap
                    }
                    Ui.Button {
                        visible: root.hostWidget && root.hostWidget.error !== "" && !root.loading
                        text: "Retry"; fontFamily: root.sans; focusable: true
                        onClicked: root.hostWidget.refresh(true)
                    }
                    Ui.Button {
                        visible: root.hostWidget && root.hostWidget.playing
                        width: parent.width; text: "Stop prayer audio"; fontFamily: root.sans; focusable: true
                        onClicked: root.hostWidget.stopAudio()
                    }
                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(root.ink, 0.08) }
                    Column {
                        width: parent.width; spacing: Style.space(5)
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: root.report ? root.report.hijri : "Every prayer, a new beginning."
                            color: Qt.alpha(root.ink, 0.65); font.family: root.sans; font.pixelSize: Style.space(10)
                        }
                        Text {
                            textFormat: Text.PlainText
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: root.report ? root.report.method.replace(" University, Makkah", " · Makkah") + " · " + root.report.location.timezone : "Location by IP · Times by AlAdhan"
                            color: Qt.alpha(root.ink, 0.35); font.family: root.sans; font.pixelSize: Style.space(9)
                        }
                    }
                }
            }
        }
    }
}
