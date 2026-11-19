import QtQuick
import qs.config

// Round chevron button that opens a list below; it turns over while the list is open.
Rectangle {
    id: root

    property bool expanded
    // On a white (active) background.
    property bool inverted
    property bool enabled: true

    signal clicked

    implicitWidth: 28
    implicitHeight: 28
    radius: width / 2
    color: area.containsMouse ? (inverted ? Qt.alpha(Config.colours.activeText, 0.1) : Config.colours.button) : "transparent"

    Text {
        anchors.centerIn: parent
        text: "\u{F0140}"
        rotation: root.expanded ? 180 : 0
        color: root.inverted ? Config.colours.activeText : Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.size

        Behavior on rotation {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
