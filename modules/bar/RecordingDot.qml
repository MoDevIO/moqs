import QtQuick
import qs.config
import qs.services

// A red dot and the time while the screen is recorded; a click stops it.
Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: Capture.recording

    Row {
        id: row

        spacing: 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: Config.colours.red

            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite

                NumberAnimation {
                    to: 0.35
                    duration: 700
                }
                NumberAnimation {
                    to: 1
                    duration: 700
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Capture.elapsed
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
        onClicked: Capture.stop()
    }
}
