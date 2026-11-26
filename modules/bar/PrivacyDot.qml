import QtQuick
import qs.config
import qs.services

// While an app uses the microphone or the camera (Privacy): an orange dot with a microphone
// and a camera for which is in use; hovered, the apps' names.
Item {
    id: root

    readonly property string names: Privacy.unique([...Privacy.camera, ...Privacy.mic]).join(", ")

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: Privacy.active

    Row {
        id: row

        spacing: 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: Config.colours.orange
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Privacy.camera.length > 0
            text: "\u{F05A0}"
            color: Config.colours.orange
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Privacy.mic.length > 0
            text: "\u{F036C}"
            color: Config.colours.orange
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: area.containsMouse
            text: root.names
            color: Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
    }
}
