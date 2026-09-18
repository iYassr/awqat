import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui

Column {
    id: root
    property string value: "name-time"
    property var options: []
    property alias focusItem: trigger
    signal changed(string value)
    spacing: Style.space(6)
    function selected() {
        for (var i = 0; i < options.length; i++) if (options[i].value === value) return options[i]
        return {title: "Prayer + time", example: ""}
    }
    function choose(index) {
        if (index < 0 || index >= options.length) return
        value = options[index].value
        changed(value)
        popup.close()
        trigger.forceActiveFocus()
    }
    Text { text: "BAR DISPLAY"; color: Qt.alpha(Color.popups.text, 0.55); font.family: "Adwaita Sans"; font.pixelSize: Style.space(10) }
    Rectangle {
        id: trigger
        width: parent.width; height: Style.space(47); radius: Style.space(5)
        color: Qt.alpha(Color.popups.text, 0.035)
        border.width: 1; border.color: Qt.alpha(activeFocus ? Color.accent : Color.popups.text, activeFocus ? 0.7 : 0.18)
        activeFocusOnTab: true
        Accessible.role: Accessible.ComboBox
        Accessible.name: "Bar display: " + root.selected().title + ", " + root.selected().example
        Accessible.onPressAction: popup.open()
        Keys.onReturnPressed: popup.open()
        Keys.onSpacePressed: popup.open()
        Keys.onDownPressed: popup.open()
        Keys.onUpPressed: popup.open()
        Column {
            anchors.left: parent.left; anchors.right: arrow.left; anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(8); spacing: Style.space(3)
            Text { text: root.selected().title; color: Color.popups.text; font.family: "Adwaita Sans"; font.pixelSize: Style.space(12) }
            Text { width: parent.width; text: root.selected().example; textFormat: Text.PlainText; elide: Text.ElideRight; color: Qt.alpha(Color.popups.text, 0.6); font.family: "Adwaita Mono"; font.pixelSize: Style.space(11) }
        }
        Text { id: arrow; anchors.right: parent.right; anchors.rightMargin: Style.space(11); anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: Color.popups.text }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { trigger.forceActiveFocus(); popup.open() } }
        Controls.Popup {
            id: popup
            y: trigger.height + Style.space(4)
            width: trigger.width
            height: Math.min(Style.space(320), optionsList.contentHeight + padding * 2)
            padding: Style.space(4)
            focus: true
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
            background: Rectangle { color: Color.popups.background; radius: Style.space(6); border.width: 1; border.color: Qt.alpha(Color.popups.text, 0.2) }
            onOpened: {
                for (var i = 0; i < root.options.length; i++) if (root.options[i].value === root.value) optionsList.currentIndex = i
                optionsList.positionViewAtIndex(optionsList.currentIndex, ListView.Contain)
                optionsList.forceActiveFocus()
            }
            contentItem: ListView {
                id: optionsList
                clip: true
                model: root.options
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
                Keys.onDownPressed: currentIndex = Math.min(count - 1, currentIndex + 1)
                Keys.onUpPressed: currentIndex = Math.max(0, currentIndex - 1)
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Home) { currentIndex = 0; event.accepted = true }
                    else if (event.key === Qt.Key_End) { currentIndex = count - 1; event.accepted = true }
                }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                Keys.onReturnPressed: root.choose(currentIndex)
                Keys.onEnterPressed: root.choose(currentIndex)
                Keys.onSpacePressed: root.choose(currentIndex)
                Keys.onEscapePressed: { popup.close(); trigger.forceActiveFocus() }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: optionsList.width; height: Style.space(48); radius: Style.space(4)
                    color: index === optionsList.currentIndex ? Qt.alpha(Color.accent, 0.09) : "transparent"
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.title + ", " + modelData.example
                    Column {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(9); spacing: Style.space(3)
                        Text { text: modelData.title + (modelData.value === root.value ? "  ✓" : ""); color: Color.popups.text; font.family: "Adwaita Sans"; font.pixelSize: Style.space(12) }
                        Row {
                            spacing: Style.space(5)
                            AwqatIcon { visible: modelData.value === "icon"; ink: Color.popups.text; width: Style.space(15); height: width }
                            Text { visible: modelData.value !== "icon"; text: modelData.example; textFormat: Text.PlainText; width: optionsList.width - Style.space(24); elide: Text.ElideRight; color: Qt.alpha(Color.popups.text, 0.64); font.family: "Adwaita Mono"; font.pixelSize: Style.space(11) }
                        }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onPositionChanged: optionsList.currentIndex = parent.index; onClicked: root.choose(parent.index) }
                }
            }
        }
    }
}
