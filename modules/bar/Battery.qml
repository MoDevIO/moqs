import QtQuick
import Quickshell.Services.UPower
import qs.config

// Battery level icon; hidden on machines without a laptop battery.
Text {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property real level: device?.percentage ?? 0
    readonly property bool charging: !UPower.onBattery
    readonly property bool low: !charging && level <= 0.15

    // battery-outline, battery-10 .. battery-90, battery
    readonly property list<int> discharging: [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
    // battery-charging-outline, battery-charging-10 .. battery-charging-100
    readonly property list<int> charge: [0xF089F, 0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]

    visible: device?.isLaptopBattery ?? false
    text: String.fromCodePoint((charging ? charge : discharging)[Math.round(level * 10)])
    color: low ? "#ff6b6b" : Config.colours.text
    font.family: Config.font.family
    font.pointSize: Config.font.icon
}
