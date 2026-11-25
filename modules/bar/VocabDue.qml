import QtQuick
import qs.config
import qs.services

// How many vocabulary words are due, while any are; a click opens the launcher's ";" pane.
Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    opacity: Vocab.dueCount > 0 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 250
        }
    }

    Row {
        id: row

        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F05CA}"
            color: area.containsMouse ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.size
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Vocab.dueCount
            color: area.containsMouse ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Launcher.showWith(";")
    }
}
