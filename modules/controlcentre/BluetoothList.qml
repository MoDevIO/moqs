import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.config

// Paired and nearby Bluetooth devices. Click to connect or disconnect;
// unpaired devices are paired, trusted and then connected.
Rectangle {
    id: root

    required property BluetoothAdapter adapter
    property bool active

    readonly property var devices: (adapter?.devices.values ?? [])
        .filter(d => d.name && d.name.replace(/[-:]/g, "") !== d.address.replace(/:/g, ""))
        .sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name))

    function glyph(icon: string): string {
        if (icon.includes("audio") || icon.includes("headset") || icon.includes("headphone"))
            return "\u{F02CB}";
        if (icon.includes("phone"))
            return "\u{F011C}";
        if (icon.includes("computer"))
            return "\u{F0322}";
        if (icon.includes("mouse"))
            return "\u{F037D}";
        if (icon.includes("keyboard"))
            return "\u{F030C}";
        return "\u{F00AF}";
    }

    function select(dev: BluetoothDevice): void {
        if (dev.connected)
            dev.disconnect();
        else if (dev.paired)
            dev.connect();
        else {
            dev.trusted = true;
            dev.pair();
        }
    }

    // Look for new devices only while the list is shown.
    onActiveChanged: if (adapter?.enabled) adapter.discovering = active

    implicitHeight: layout.implicitHeight + 12
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Text {
            Layout.margins: 8
            visible: root.devices.length === 0
            text: root.adapter?.enabled ? "Searching…" : "Bluetooth is off"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 240)
            visible: root.devices.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices

            delegate: ListRow {
                id: row

                required property BluetoothDevice modelData

                width: list.width
                active: modelData.connected
                icon: root.glyph(modelData.icon)
                title: modelData.name
                subtitle: {
                    const d = modelData;
                    if (d.pairing)
                        return "Pairing…";
                    if (d.state === BluetoothDeviceState.Connecting)
                        return "Connecting…";
                    if (d.state === BluetoothDeviceState.Disconnecting)
                        return "Disconnecting…";
                    if (d.connected)
                        return d.batteryAvailable ? `${Math.round(d.battery * 100)}%` : "Connected";
                    return d.paired ? "Paired" : "";
                }
                onClicked: root.select(modelData)

                // Finish what pairing started.
                Connections {
                    target: row.modelData

                    function onPairedChanged(): void {
                        if (row.modelData.paired)
                            row.modelData.connect();
                    }
                }
            }
        }
    }
}
