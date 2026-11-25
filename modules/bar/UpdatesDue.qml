import QtQuick
import qs.config
import qs.services

// Shown while nixpkgs is Config.updates.days or more behind, or an update runs: a snowflake
// and how many days, or the step running. A click opens the control centre, where the Updates
// tile is.
Item {
    id: root

    signal clicked

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: Updates.configured && (Updates.running || Updates.behind >= Config.updates.days)

    Row {
        id: row

        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F1105}"
            color: area.containsMouse ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.size

            SequentialAnimation on opacity {
                running: Updates.running
                loops: Animation.Infinite
                onRunningChanged: if (!running) parent.opacity = 1

                NumberAnimation {
                    to: 0.3
                    duration: 600
                }
                NumberAnimation {
                    to: 1
                    duration: 600
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Updates.running ? Updates.stepName : `${Updates.behind}d`
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
        onClicked: root.clicked()
    }
}
