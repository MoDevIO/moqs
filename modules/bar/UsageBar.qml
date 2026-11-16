import QtQuick
import qs.config

// Icon plus a small bar; a full bar means 100% usage.
Row {
    id: root

    property string icon
    property real value

    spacing: 6

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: Config.colours.text
        font.family: Config.font.family
        font.pointSize: Config.font.size
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 6
        radius: height / 2
        color: Config.colours.muted

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: height / 2
            color: root.value >= 0.9 ? "#ff6b6b" : Config.colours.text

            Behavior on width {
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
