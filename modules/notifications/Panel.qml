import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.services
import qs.modules

// Top-right panel that grows out of the frame: popups, or the full notification centre.
Item {
    id: root

    required property ShellScreen screen
    property bool centreOpen: false
    // Keeps the centre open after a pull until the pointer has been on it.
    property bool holdOpen
    // Height while being pulled out of the border, or -1 when not.
    property real dragHeight: -1
    readonly property bool dragging: dragHeight >= 0

    readonly property bool focusedScreen: Hyprland.focusedMonitor?.name === screen.name
    readonly property bool showPopups: !centreOpen && focusedScreen && Notifs.popups.length > 0
    readonly property real maxHeight: screen.height * Config.notifs.maxHeight

    readonly property real centreHeight: Math.min(centre.wantedHeight, maxHeight)

    onCentreOpenChanged: {
        if (centreOpen)
            Notifs.hidePopups();
        else
            holdOpen = false;
    }

    function dragTo(h: real): void {
        dragHeight = Math.max(0, Math.min(centreHeight, h));
    }

    // Opens if pulled far enough, and stays open until the pointer has been on it: a pull
    // past its full size leaves the pointer outside the frame.
    function release(): void {
        centreOpen = dragHeight >= centreHeight * Config.dashboard.openAt;
        holdOpen = centreOpen;
        dragHeight = -1;
    }

    readonly property real targetWidth: centreOpen || showPopups ? Config.notifs.width : 0
    readonly property real targetHeight: centreOpen ? centreHeight : showPopups ? popups.implicitHeight : 0

    width: dragging ? Config.notifs.width : targetWidth
    height: dragging ? dragHeight : targetHeight
    visible: width > 0 && height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        enabled: !root.dragging

        Anim {}
    }

    HoverHandler {
        onHoveredChanged: {
            Notifs.paused = hovered;
            if (hovered)
                root.holdOpen = false;
        }
    }

    Background {
        anchors.fill: parent
    }

    // Content keeps its full width while the panel animates, so text doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        Column {
            id: popups

            anchors.top: parent.top
            anchors.right: parent.right
            width: Config.notifs.width
            padding: Config.notifs.padding
            spacing: Config.notifs.spacing
            opacity: root.centreOpen || root.dragging ? 0 : 1
            // A faded-out layer still catches clicks, so hide it once the fade is done.
            visible: opacity > 0

            Behavior on opacity {
                Anim {}
            }

            Repeater {
                model: ScriptModel {
                    values: [...Notifs.popups]
                }

                NotifCard {
                    width: popups.width - popups.padding * 2
                }
            }
        }

        ColumnLayout {
            id: centre

            anchors.top: parent.top
            anchors.right: parent.right
            width: Config.notifs.width
            height: root.maxHeight
            spacing: Config.notifs.spacing
            opacity: root.centreOpen || root.dragging ? 1 : 0
            // Otherwise the invisible centre sits on top of the popups and swallows their clicks.
            visible: opacity > 0

            readonly property real wantedHeight: header.implicitHeight + Config.notifs.padding * 2 + Config.notifs.spacing + (Notifs.list.length > 0 ? list.contentHeight : empty.implicitHeight)

            Behavior on opacity {
                Anim {}
            }

            RowLayout {
                id: header

                Layout.fillWidth: true
                Layout.topMargin: Config.notifs.padding
                Layout.leftMargin: Config.notifs.padding + 4
                Layout.rightMargin: Config.notifs.padding + 4

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    font.bold: true
                }

                Text {
                    visible: Notifs.list.length > 0
                    text: "Clear all"
                    color: clear.containsMouse ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small

                    MouseArea {
                        id: clear

                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.clear()
                    }
                }
            }

            Text {
                id: empty

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: Config.notifs.padding
                visible: Notifs.list.length === 0
                topPadding: 16
                bottomPadding: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                text: "No notifications"
                color: Config.colours.muted
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            ListView {
                id: list

                SmoothScroll {
                    flickable: list
                }

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Config.notifs.padding
                Layout.rightMargin: Config.notifs.padding
                Layout.bottomMargin: Config.notifs.padding
                visible: Notifs.list.length > 0
                clip: true
                spacing: Config.notifs.spacing
                boundsBehavior: Flickable.StopAtBounds

                model: ScriptModel {
                    values: [...Notifs.list]
                }

                delegate: NotifCard {
                    width: list.width
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
