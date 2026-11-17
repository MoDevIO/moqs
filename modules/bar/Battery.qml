import QtQuick
import Quickshell.Services.UPower
import qs.config

// Battery level icon; click to show or hide the percentage beside it. Hidden on machines
// without a laptop battery.
Item {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property real level: device?.percentage ?? 0
    readonly property bool charging: !UPower.onBattery
    readonly property bool low: !charging && level <= 0.15
    readonly property color colour: low ? "#ff6b6b" : Config.colours.text

    property bool showPercentage: Config.bar.showBatteryPercentage

    // battery-outline, battery-10 .. battery-90, battery
    readonly property list<int> discharging: [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
    // battery-charging-outline, battery-charging-10 .. battery-charging-100
    readonly property list<int> charge: [0xF089F, 0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]

    visible: device?.isLaptopBattery ?? false
    implicitWidth: icon.implicitWidth + label.width
    implicitHeight: icon.implicitHeight

    Text {
        id: icon

        anchors.verticalCenter: parent.verticalCenter
        text: String.fromCodePoint((root.charging ? root.charge : root.discharging)[Math.round(root.level * 10)])
        color: root.colour
        font.family: Config.font.family
        font.pointSize: Config.font.icon
    }

    // Grows out from the icon: the width opens while the text fades in.
    Item {
        id: label

        anchors.left: icon.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.showPercentage ? percent.implicitWidth + 4 : 0
        height: percent.implicitHeight
        clip: true

        Behavior on width {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        Text {
            id: percent

            x: 4
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.round(root.level * 100)}%`
            color: root.colour
            opacity: root.showPercentage ? 1 : 0
            font.family: Config.font.sans
            font.pointSize: Config.font.small
            font.weight: Font.Medium
            // Tabular digits keep the width steady as the value changes.
            font.features: { "tnum": 1 }

            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.showPercentage = !root.showPercentage
    }
}
