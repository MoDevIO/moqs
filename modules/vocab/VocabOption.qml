import QtQuick
import qs.config

// A setting at the bottom of the vocabulary pane: brighter when on, white under the pointer.
Text {
    id: root

    property bool on

    signal clicked

    color: area.containsMouse ? Config.colours.text : on ? Config.colours.subtext : Config.colours.muted
    font.family: Config.font.family
    font.pointSize: Config.font.small

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
