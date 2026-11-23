import QtQuick
import qs.config

// A rounded button for the display popup; primary is white.
Rectangle {
    id: button

    property string text
    property bool primary

    signal clicked

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 34
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: primary ? (buttonArea.containsMouse ? Qt.darker(Config.colours.active, 1.1) : Config.colours.active) : buttonArea.containsMouse ? Config.colours.buttonHover : Config.colours.button

    Text {
        id: label

        anchors.centerIn: parent
        text: button.text
        color: button.primary ? Config.colours.activeText : Config.colours.text
        font.family: Config.font.family
        font.pointSize: Config.font.size
        font.bold: button.primary
    }

    MouseArea {
        id: buttonArea

        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
