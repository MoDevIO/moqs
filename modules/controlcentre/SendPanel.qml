import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Drop target for sending files to the device picked in the control centre.
// Stays open while files are fetched from elsewhere; closed with its × button.
Item {
    id: root

    readonly property bool open: Owly.target !== null
    // Kept after closing, so the title doesn't blank while the panel shrinks away.
    property string name

    Connections {
        target: Owly

        function onTargetChanged(): void {
            if (Owly.target)
                root.name = Owly.target.name;
        }
    }

    readonly property real targetWidth: open ? Config.controlCentre.width : 0
    readonly property real targetHeight: open ? content.implicitHeight : 0

    width: targetWidth
    height: targetHeight
    visible: width > 0 && height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    Background {
        anchors.fill: parent
    }

    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.controlCentre.width - Config.controlCentre.padding * 2
            spacing: Config.controlCentre.spacing

            Item {
                implicitHeight: Config.controlCentre.padding - Config.controlCentre.spacing
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                Text {
                    Layout.fillWidth: true
                    text: `Send to ${root.name}`
                    elide: Text.ElideRight
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    font.bold: true
                }

                Text {
                    text: "󰅖"
                    color: closeArea.containsMouse ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size

                    MouseArea {
                        id: closeArea

                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Owly.closeSend()
                    }
                }
            }

            Rectangle {
                id: zone

                readonly property bool hovered: drop.containsDrag
                readonly property bool busy: Owly.sendState === "sending"
                readonly property bool progressing: busy && Owly.sendTotal > 0
                readonly property real progress: Owly.sendTotal > 0 ? Math.min(Owly.sendSent / Owly.sendTotal, 1) : 0

                function size(bytes: real): string {
                    const units = ["B", "KB", "MB", "GB"];
                    let i = 0;
                    while (bytes >= 1000 && i < units.length - 1) {
                        bytes /= 1000;
                        i++;
                    }
                    return `${bytes.toFixed(i && bytes < 10 ? 1 : 0)} ${units[i]}`;
                }

                Layout.fillWidth: true
                implicitHeight: 96
                radius: Config.border.rounding - Config.controlCentre.padding / 2
                color: hovered ? Config.colours.buttonHover : Config.colours.card
                border.width: 1
                border.color: hovered ? Config.colours.text : Config.colours.muted

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                DropArea {
                    id: drop

                    anchors.fill: parent
                    enabled: !zone.busy
                    keys: ["text/uri-list"]
                    onDropped: event => {
                        const files = [];
                        const urls = [];
                        for (const u of event.urls) {
                            const s = u.toString();
                            if (s.startsWith("file://"))
                                files.push(decodeURIComponent(s.slice(7)));
                            else if (/^https?:/.test(s))
                                urls.push(s);
                        }
                        event.acceptProposedAction();
                        Owly.send(files, urls);
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 6

                    Text {
                        id: icon

                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            switch (Owly.sendState) {
                            case "sending":
                                return "\u{F0552}";
                            case "delivered":
                                return "\u{F012C}";
                            case "declined":
                            case "failed":
                                return "\u{F0156}";
                            default:
                                return "\u{F0552}";
                            }
                        }
                        color: Owly.sendState === "failed" ? "#ff6b6b" : Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: 20

                        // Gentle pulse while a transfer is under way.
                        SequentialAnimation on opacity {
                            running: zone.busy
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) icon.opacity = 1

                            NumberAnimation {
                                to: 0.3
                                duration: 600
                            }
                            NumberAnimation {
                                to: 1
                                duration: 600
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Owly.sendState === "idle" ? (zone.hovered ? "Release to send" : "Drag files to send here") : zone.progressing ? `${Math.floor(zone.progress * 100)} % · ${zone.size(Owly.sendSent)} of ${zone.size(Owly.sendTotal)}` : Owly.sendDetail
                        elide: Text.ElideRight
                        color: Owly.sendState === "failed" ? "#ff6b6b" : Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    // Transfer progress, once the receiver has accepted.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        implicitHeight: 4
                        radius: 2
                        color: Config.colours.muted
                        visible: zone.progressing

                        Rectangle {
                            width: parent.width * zone.progress
                            height: parent.height
                            radius: parent.radius
                            color: Config.colours.text

                            Behavior on width {
                                NumberAnimation {
                                    duration: 150
                                }
                            }
                        }
                    }
                }
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
