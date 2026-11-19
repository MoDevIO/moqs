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
    // Which list's popover is up: "", "wifi", "bluetooth", "airdrop", "power", "audio" or
    // "clipboard".
    property string expanded: ""
    // A popover is up; it's its own window, so the pointer leaving for it mustn't close this.
    readonly property bool popupOpen: popover.visible

    // Opens the list named from its chevron, where it was clicked; again closes it.
    // Without a click on the chevron itself, it opens from the chevron's middle.
    function toggle(name: string, button: Item, centred: bool): void {
        if (expanded === name && popover.visible) {
            popover.close();
            return;
        }
        // The list first, so the popover opens at its size.
        expanded = name;
        const at = centred ? Qt.point(button.width / 2, button.height / 2) : button.clickPos;
        popover.openAt(button, at.x, at.y);
    }

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
        if (!open) {
            expanded = "";
            popover.close();
        }
        if (open) {
            Brightness.refresh();
            PowerProfiles.refresh();
        }
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

    // Keeps the clipboard list current while the panel is open.
    Binding {
        target: Clipboard
        property: "active"
        value: true
        when: root.open
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
                    onExpandClicked: root.toggle("wifi", expandButton)
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
                    onExpandClicked: root.toggle("bluetooth", expandButton)
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
                    onExpandClicked: root.toggle("airdrop", expandButton)
                }

                // White unless on the default, balanced; click cycles through the profiles.
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    enabled: PowerProfiles.available
                    checked: PowerProfiles.available && PowerProfiles.profile !== "balanced"
                    icon: PowerProfiles.icon(PowerProfiles.profile)
                    title: "Power"
                    subtitle: PowerProfiles.available ? PowerProfiles.name(PowerProfiles.profile) : "Unavailable"
                    expanded: root.expanded === "power"
                    onClicked: PowerProfiles.cycle()
                    onExpandClicked: root.toggle("power", expandButton)
                }

                // Clipboard history; the whole tile opens it.
                Tile {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    icon: "\u{F014C}"
                    title: "Clipboard"
                    subtitle: !Clipboard.available ? "cliphist isn't installed" : Clipboard.describe(Clipboard.entries[0]) || "Nothing copied yet"
                    expanded: root.expanded === "clipboard"
                    onClicked: root.toggle("clipboard", expandButton, true)
                    onExpandClicked: root.toggle("clipboard", expandButton)
                }
            }

            // Volume, with the output list behind the chevron.
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

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

                ExpandButton {
                    id: audioButton

                    expanded: root.expanded === "audio" && popover.visible
                    onClicked: root.toggle("audio", audioButton)
                }
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

    // The lists behind the chevrons, one at a time.
    Popover {
        id: popover

        onVisibleChanged: if (!visible && !reopening) root.expanded = ""

        Loader {
            width: parent.width
            sourceComponent: ({ wifi: wifiList, bluetooth: bluetoothList, airdrop: airdropList, power: powerList, audio: audioList, clipboard: clipboardList })[root.expanded] ?? null
        }
    }

    Component {
        id: wifiList

        WifiList {
            color: "transparent"
            active: true
            devices: root.wifi
        }
    }

    Component {
        id: bluetoothList

        BluetoothList {
            color: "transparent"
            active: true
            adapter: root.adapter
        }
    }

    Component {
        id: airdropList

        AirDropList {
            color: "transparent"
            active: true
            onPicked: device => {
                Owly.pick(device);
                root.open = false;
            }
        }
    }

    Component {
        id: powerList

        PowerProfileList {
            color: "transparent"
            onPicked: popover.close()
        }
    }

    Component {
        id: audioList

        AudioOutputList {
            onPicked: popover.close()
        }
    }

    Component {
        id: clipboardList

        ClipboardList {
            onPicked: root.open = false
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
