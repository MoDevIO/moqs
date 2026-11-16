import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.bar
import qs.modules.controlcentre
import qs.modules.matrix
import qs.modules.music
import qs.modules.notifications
import qs.services

// One frame per screen: the visible border plus invisible windows reserving space for it.
Scope {
    id: root

    required property ShellScreen modelData

    readonly property int top: Config.bar.height
    readonly property int side: Config.border.thickness

    Exclusion { anchors.top: true; exclusiveZone: root.top }
    Exclusion { anchors.bottom: true; exclusiveZone: root.side }
    Exclusion { anchors.left: true; exclusiveZone: root.side }
    Exclusion { anchors.right: true; exclusiveZone: root.side }

    PanelWindow {
        id: win

        screen: root.modelData
        color: "transparent"
        WlrLayershell.namespace: "shell-frame"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        // Lets text fields (Wi-Fi password, music search, messages) take typing while their panel is open.
        WlrLayershell.keyboardFocus: cc.open || music.open || matrix.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only the border and panels take input; the interior passes clicks through.
        mask: Region {
            x: root.side
            y: root.top
            width: win.width - root.side * 2
            height: win.height - root.top - root.side
            intersection: Intersection.Xor

            Region {
                item: notifs
                intersection: Intersection.Subtract
            }

            Region {
                item: cc
                intersection: Intersection.Subtract
            }

            Region {
                item: send
                intersection: Intersection.Subtract
            }

            Region {
                item: music
                intersection: Intersection.Subtract
            }

            Region {
                item: matrix
                intersection: Intersection.Subtract
            }
        }

        // Pushing the pointer into the top-right corner opens the notification centre,
        // the bottom-left corner the music player and the bottom-right corner Matrix.
        // Open panels close once the pointer leaves them (plus a rounding-sized margin).
        HoverHandler {
            id: hover

            // Uses the panel's final size, so a still-growing panel doesn't close itself.
            function near(p: point, left: real, right: real, bottom: real): bool {
                const r = Config.border.rounding;
                return p.x >= left - r && p.x <= right + r && p.y <= bottom + r;
            }

            onPointChanged: {
                const p = point.position;
                const hc = Config.notifs.hotCorner;

                if (p.x >= win.width - hc && p.y <= hc)
                    notifs.centreOpen = true;
                else if (notifs.centreOpen && !near(p, win.width - root.side - notifs.targetWidth, win.width, root.top + notifs.targetHeight))
                    notifs.centreOpen = false;

                if (cc.open && !near(p, (win.width - cc.targetWidth) / 2, (win.width + cc.targetWidth) / 2, root.top + cc.targetHeight))
                    cc.open = false;

                const r = Config.border.rounding;
                if (p.x <= hc && p.y >= win.height - hc)
                    music.open = true;
                else if (music.open && (p.x > root.side + music.targetWidth + r || p.y < win.height - root.side - music.targetHeight - r))
                    music.open = false;

                if (p.x >= win.width - hc && p.y >= win.height - hc)
                    matrix.open = true;
                else if (matrix.open && (p.x < win.width - root.side - matrix.targetWidth - r || p.y < win.height - root.side - matrix.targetHeight - r))
                    matrix.open = false;
            }
            onHoveredChanged: {
                if (!hovered) {
                    notifs.centreOpen = false;
                    cc.open = false;
                    music.open = false;
                    matrix.open = false;
                }
            }
        }

        // An oversized rectangle whose thick border reaches past the screen edges;
        // its inner edge forms the rounded cutout.
        Rectangle {
            readonly property int overflow: 2000

            x: root.side - overflow
            y: root.top - overflow
            width: win.width - root.side * 2 + overflow * 2
            height: win.height - root.top - root.side + overflow * 2
            color: "transparent"
            radius: Config.border.rounding + overflow
            border.width: overflow
            border.color: Config.border.colour
            antialiasing: true
        }

        Bar {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.side
            anchors.rightMargin: root.side
            height: root.top
            screen: root.modelData
            onClockClicked: {
                Owly.closeSend();
                cc.open = !cc.open;
            }
        }

        Panel {
            id: notifs

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: root.top
            anchors.rightMargin: root.side
            screen: root.modelData
        }

        ControlCentre {
            id: cc

            anchors.top: parent.top
            anchors.topMargin: root.top
            anchors.horizontalCenter: parent.horizontalCenter
        }

        SendPanel {
            id: send

            anchors.top: parent.top
            anchors.topMargin: root.top
            anchors.horizontalCenter: parent.horizontalCenter
        }

        MusicPanel {
            id: music

            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.side
            anchors.bottomMargin: root.side
        }

        MatrixPanel {
            id: matrix

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: root.side
            anchors.bottomMargin: root.side
        }
    }

    component Exclusion: PanelWindow {
        screen: root.modelData
        color: "transparent"
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
        WlrLayershell.namespace: "shell-exclusion"
    }
}
