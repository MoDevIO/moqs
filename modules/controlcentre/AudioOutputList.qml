import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.config

// Audio outputs to pick from; the default one is white.
Item {
    id: root

    signal picked

    // Hardware and network outputs, not the streams playing into them.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)

    function icon(node: PwNode): string {
        const name = node.name.toLowerCase();
        if (name.startsWith("bluez"))
            return "\u{F0970}";
        if (name.startsWith("raop") || name.includes("airplay"))
            return "\u{F101E}";
        if (name.includes("hdmi") || name.includes("displayport"))
            return "\u{F0502}";
        if (name.includes("usb"))
            return "\u{F0553}";
        if (name.includes("headphone") || name.includes("headset"))
            return "\u{F02CB}";
        return "\u{F04C3}";
    }

    implicitHeight: layout.implicitHeight + 12

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 2

        Repeater {
            model: root.sinks

            ListRow {
                required property PwNode modelData

                Layout.fillWidth: true
                active: Pipewire.defaultAudioSink?.id === modelData.id
                icon: root.icon(modelData)
                title: modelData.description || modelData.nickname || modelData.name
                onClicked: {
                    Pipewire.preferredDefaultAudioSink = modelData;
                    root.picked();
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.margins: 8
            visible: root.sinks.length === 0
            text: "No audio outputs"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }
}
