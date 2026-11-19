import QtQuick
import qs.config

// A small clickable icon, brightening on hover.
Text {
    id: root

    property string icon

    signal clicked

    text: icon
    color: area.containsMouse ? Config.colours.text : Config.colours.subtext
    font.family: Config.font.family
    font.pointSize: Config.font.size

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
