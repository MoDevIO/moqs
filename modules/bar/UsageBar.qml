import QtQuick
import Quickshell.Widgets
import qs.config

// Pill that fills from the left with usage (full = 100%), with its label in the centre.
// The label is drawn twice, light over the track and dark over the fill, so it reads at any level.
ClippingRectangle {
    id: root

    property string label
    property real value
    readonly property real level: Math.max(0, Math.min(1, value))

    implicitWidth: 44
    implicitHeight: 16
    radius: height / 2
    color: Config.colours.muted

    Text {
        id: light

        anchors.centerIn: parent
        text: root.label
        color: Config.colours.text
        font.family: Config.font.sans
        font.pointSize: 7
        font.weight: Font.DemiBold
        font.letterSpacing: 0.5
    }

    Item {
        width: root.width * root.level
        height: root.height
        clip: true

        Behavior on width {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            color: root.level >= 0.9 ? "#ff6b6b" : Config.colours.active
        }

        Text {
            x: light.x
            y: light.y
            text: light.text
            color: Config.colours.activeText
            font: light.font
        }
    }
}
