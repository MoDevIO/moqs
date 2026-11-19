import QtQuick
import Quickshell
import qs.config
import qs.services

// Centre of the bar; clicking it opens the control centre. While volume or brightness
// changes, it turns into a slider showing the level.
Item {
    id: root

    signal clicked

    readonly property bool osd: Osd.kind !== ""

    implicitWidth: osd ? level.implicitWidth : row.implicitWidth
    implicitHeight: row.implicitHeight

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 8
        opacity: root.osd ? 0 : 1
        scale: root.osd ? 0.9 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 150
            }
        }

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

    // Read only: the level, not something to drag.
    Row {
        id: level

        anchors.centerIn: parent
        spacing: 10
        opacity: root.osd ? 1 : 0
        scale: root.osd ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 150
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            horizontalAlignment: Text.AlignHCenter
            text: Osd.icon
            color: Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.size
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Config.osd.width
            height: 6
            radius: height / 2
            color: Config.colours.button

            Rectangle {
                width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, Osd.value)))
                height: parent.height
                radius: height / 2
                visible: Osd.value > 0
                color: Osd.kind === "volume" && Osd.muted ? Config.colours.subtext : Config.colours.text

                Behavior on width {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: `${Math.round(Osd.value * 100)}%`
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
