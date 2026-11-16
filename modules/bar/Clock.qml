import QtQuick
import Quickshell
import qs.config

// Centre of the bar; clicking it opens the control centre.
Item {
    id: root

    signal clicked

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Row {
        id: row

        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.size
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.size
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
