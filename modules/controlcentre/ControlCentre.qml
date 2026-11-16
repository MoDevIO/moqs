import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.config
import qs.services

// Hangs from the clock in the middle of the bar.
Item {
    id: root

    property bool open: false
    // Which device list is shown: "", "wifi", "bluetooth" or "airdrop".
    property string expanded: ""

    readonly property real targetWidth: open ? Config.controlCentre.width : 0
    readonly property real targetHeight: open ? content.implicitHeight : 0

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var wifi: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    readonly property string ssid: {
        for (const dev of wifi)
            for (const net of dev.networks.values)
                if (net.connected)
                    return net.name;
        return "";
    }
    readonly property var btConnected: adapter?.devices.values.filter(d => d.connected) ?? []

    onOpenChanged: {
        if (!open)
            expanded = "";
        if (open)
            Brightness.refresh();
    }

    width: targetWidth
    height: targetHeight
    visible: width > 0 && height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    PwObjectTracker {
        objects: [root.sink]
    }

    Background {
        anchors.fill: parent
    }

    // Content keeps its full width while the panel animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.controlCentre.width - Config.controlCentre.padding * 2
            spacing: Config.controlCentre.spacing
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            Item {
                implicitHeight: Config.controlCentre.padding - Config.controlCentre.spacing
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                uniformCellWidths: true
                rowSpacing: Config.controlCentre.spacing
                columnSpacing: Config.controlCentre.spacing

                Tile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    checked: Networking.wifiEnabled
                    enabled: Networking.wifiHardwareEnabled
                    icon: checked ? "\u{F05A9}" : "\u{F05AA}"
                    title: "Wi-Fi"
                    subtitle: !checked ? "Off" : root.ssid || "Not connected"
                    expanded: root.expanded === "wifi"
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                    onExpandClicked: root.expanded = expanded ? "" : "wifi"
                }

                Tile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    checked: root.adapter?.enabled ?? false
                    enabled: root.adapter !== null
                    icon: checked ? "\u{F00AF}" : "\u{F00B2}"
                    title: "Bluetooth"
                    subtitle: !root.adapter ? "No adapter" : !checked ? "Off" : root.btConnected.length === 0 ? "Not connected" : root.btConnected.map(d => d.name).join(", ")
                    expanded: root.expanded === "bluetooth"
                    onClicked: root.adapter.enabled = !root.adapter.enabled
                    onExpandClicked: root.expanded = expanded ? "" : "bluetooth"
                }

                Tile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    checked: Owly.receiving
                    icon: "\u{F0003}"
                    title: "AirDrop"
                    subtitle: Owly.error || (!Owly.radioUp ? "Radio unavailable" : checked ? "Receiving" : "Off")
                    expanded: root.expanded === "airdrop"
                    onClicked: Owly.setReceiving(!Owly.receiving)
                    onExpandClicked: root.expanded = expanded ? "" : "airdrop"
                }
            }

            WifiList {
                Layout.fillWidth: true
                visible: active
                active: root.expanded === "wifi"
                devices: root.wifi
            }

            BluetoothList {
                Layout.fillWidth: true
                visible: active
                active: root.expanded === "bluetooth"
                adapter: root.adapter
            }

            AirDropList {
                Layout.fillWidth: true
                visible: active
                active: root.expanded === "airdrop"
                onPicked: device => {
                    Owly.pick(device);
                    root.open = false;
                }
            }

            Slider {
                Layout.fillWidth: true
                value: root.sink?.audio?.volume ?? 0
                dimmed: root.sink?.audio?.muted ?? false
                icon: dimmed || value === 0 ? "\u{F0581}" : "\u{F057E}"
                onMoved: v => {
                    if (root.sink?.audio) {
                        root.sink.audio.muted = false;
                        root.sink.audio.volume = v;
                    }
                }
                onIconClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
            }

            Slider {
                Layout.fillWidth: true
                value: Brightness.value
                icon: "\u{F00DF}"
                onMoved: v => Brightness.set(v)
            }

            NowPlaying {
                Layout.fillWidth: true
            }

            Item {
                implicitHeight: Config.controlCentre.padding - Config.controlCentre.spacing
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
