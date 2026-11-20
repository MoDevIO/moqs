import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.config
import qs.modules

// Networks seen by the Wi-Fi devices. Click to connect or disconnect;
// secured networks without saved settings ask for a password first.
Rectangle {
    id: root

    required property var devices
    property bool active

    // The network waiting for a password, if any.
    property var asking: null
    property var failed: null

    readonly property var networks: {
        const seen = {};
        for (const dev of devices)
            for (const net of dev.networks.values)
                if (net.name && (!seen[net.name] || net.connected || net.signalStrength > seen[net.name].signalStrength && !seen[net.name].connected))
                    seen[net.name] = net;
        return Object.values(seen).sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength);
    }

    function strength(net: var): string {
        const s = net.signalStrength > 1 ? net.signalStrength / 100 : net.signalStrength;
        return s > 0.75 ? "\u{F0928}" : s > 0.5 ? "\u{F0925}" : s > 0.25 ? "\u{F0922}" : "\u{F091F}";
    }

    function secured(net: var): bool {
        return net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Owe;
    }

    function select(net: var): void {
        failed = null;
        if (net.connected)
            net.disconnect();
        else if (net.known || !secured(net))
            net.connect();
        else
            asking = asking === net ? null : net;
    }

    // Scan only while the list is shown.
    onActiveChanged: {
        for (const dev of devices)
            dev.scannerEnabled = active;
        if (!active)
            asking = null;
    }

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
            visible: root.networks.length === 0
            text: "Searching…"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        ListView {
            id: list

            SmoothScroll {
                flickable: list
            }

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 240)
            visible: root.networks.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.networks

            delegate: ColumnLayout {
                id: entry

                required property var modelData
                readonly property var net: modelData

                width: list.width
                spacing: 2

                Connections {
                    target: entry.net

                    function onConnectionFailed(): void {
                        root.failed = entry.net;
                    }
                }

                ListRow {
                    Layout.fillWidth: true
                    active: entry.net.connected
                    icon: root.strength(entry.net)
                    title: entry.net.name
                    subtitle: entry.net.stateChanging ? "Connecting…" : root.failed === entry.net ? "Failed" : entry.net.connected ? "Connected" : ""
                    trailing: root.secured(entry.net) ? "\u{F033E}" : ""
                    onClicked: root.select(entry.net)
                }

                // Password prompt
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    visible: root.asking === entry.net
                    implicitHeight: 32
                    radius: height / 2
                    color: Config.colours.button

                    onVisibleChanged: {
                        psk.text = "";
                        if (visible)
                            psk.forceActiveFocus();
                    }

                    TextInput {
                        id: psk

                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Config.colours.text
                        selectionColor: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                        clip: true

                        onAccepted: {
                            entry.net.connectWithPsk(text);
                            root.asking = null;
                        }
                        Keys.onEscapePressed: root.asking = null

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !psk.text
                            text: "Password, then Enter"
                            color: Config.colours.muted
                            font: psk.font
                        }
                    }
                }
            }
        }
    }
}
