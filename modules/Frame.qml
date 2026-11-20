import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.bar
import qs.modules.controlcentre
import qs.modules.dashboard
import qs.modules.launcher
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
        // Lets text fields (Wi-Fi password, music search, messages, homework) take typing while their panel is open.
        // A Matrix reply and the launcher take the keyboard outright, so their fields get it without a click.
        WlrLayershell.keyboardFocus: matrix.replying || launcher.open ? WlrKeyboardFocus.Exclusive : cc.open || music.open || matrix.open || dash.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only the border and panels take input; the interior passes clicks through. While a
        // panel is pulled out the whole screen does, so a quick pull can't leave the pointer
        // outside the frame, where the drag would stop getting its moves. The launcher takes
        // the whole screen too, so a click anywhere else closes it.
        mask: dragging || launcher.open ? dragMask : frameMask

        readonly property bool dragging: dash.dragging || notifs.dragging || music.dragging || matrix.dragging

        readonly property Region dragMask: Region {
            width: win.width
            height: win.height
        }

        readonly property Region frameMask: Region {
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
                item: launcher
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

            Region {
                item: dash
                intersection: Intersection.Subtract
            }

            // The gap above the bottom border also grabs the dashboard.
            Region {
                x: root.side + Config.border.rounding
                y: win.height - root.side - Config.hyprland.gapsOut
                width: win.width - (root.side + Config.border.rounding) * 2
                height: Config.hyprland.gapsOut
                intersection: Intersection.Subtract
            }
        }

        // Pushing the pointer into the top-right corner opens the notification centre,
        // the bottom-left corner the music player and the bottom-right corner Matrix, unless
        // settings.json has that corner pulled out instead (dragToOpen).
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

                const drag = Settings.dragToOpen;
                if (!drag.notifications && p.x >= win.width - hc && p.y <= hc)
                    notifs.centreOpen = true;
                else if (notifs.centreOpen && !notifs.holdOpen && !near(p, win.width - root.side - notifs.targetWidth, win.width, root.top + notifs.targetHeight))
                    notifs.centreOpen = false;

                if (cc.open && !cc.popupOpen && !near(p, (win.width - cc.targetWidth) / 2, (win.width + cc.targetWidth) / 2, root.top + cc.targetHeight))
                    cc.open = false;

                const r = Config.border.rounding;
                if (!drag.music && p.x <= hc && p.y >= win.height - hc)
                    music.open = true;
                else if (music.open && !music.holdOpen && (p.x > root.side + music.targetWidth + r || p.y < win.height - root.side - music.targetHeight - r))
                    music.open = false;

                if (!drag.matrix && p.x >= win.width - hc && p.y >= win.height - hc)
                    matrix.open = true;
                else if (matrix.open && !matrix.holdOpen && (p.x < win.width - root.side - matrix.targetWidth - r || p.y < win.height - root.side - matrix.targetHeight - r))
                    matrix.open = false;

                const onDash = p.y >= win.height - root.side - dash.targetHeight && Math.abs(p.x - win.width / 2) <= dash.targetWidth / 2;
                if (dash.holdOpen && onDash)
                    dash.holdOpen = false;
                if (dash.open && !dash.holdOpen && (p.y < win.height - root.side - dash.targetHeight - r || Math.abs(p.x - win.width / 2) > dash.targetWidth / 2 + r))
                    dash.open = false;
            }
            onHoveredChanged: {
                if (!hovered) {
                    if (!notifs.holdOpen)
                        notifs.centreOpen = false;
                    if (!cc.popupOpen)
                        cc.open = false;
                    if (!music.holdOpen)
                        music.open = false;
                    if (!matrix.holdOpen)
                        matrix.open = false;
                    if (!dash.dragging && !dash.holdOpen)
                        dash.open = false;
                }
            }
        }

        // Clicking a corner whose panel is open takes that client back to its home view.
        TapHandler {
            onTapped: (eventPoint, button) => {
                const p = eventPoint.position;
                const bottom = p.y >= win.height - root.side;
                if (bottom && p.x <= root.side && music.open && !Settings.dragToOpen.music)
                    music.goHome();
                else if (bottom && p.x >= win.width - root.side && matrix.open && !Settings.dragToOpen.matrix)
                    matrix.goHome();
            }
        }

        // While the launcher is open, a click anywhere outside it closes it.
        MouseArea {
            anchors.fill: parent
            visible: launcher.open
            onPressed: Launcher.open = false
        }

        // Dragging the bottom border up pulls out the dashboard. The gap above it and the
        // peeking sliver count too, so the grab doesn't need a precise aim. The corners stay
        // free for the music player and Matrix.
        PanelDrag {
            panel: dash
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.side + Config.border.rounding
            anchors.rightMargin: root.side + Config.border.rounding
            height: root.side + Config.hyprland.gapsOut + (dash.peek && !dash.open ? Config.dashboard.peek : 0)
            onContainsMouseChanged: dash.peek = containsMouse
        }

        // Corners set to dragToOpen: their panels get pulled out of the border the same way.
        // Clicking one whose panel is open takes that client back to its home view.
        PanelDrag {
            panel: notifs
            downwards: true
            visible: Settings.dragToOpen.notifications
            anchors.top: parent.top
            anchors.right: parent.right
            // Stops short of the battery icon in the bar.
            width: root.side + Config.bar.padding
            height: root.top
        }

        PanelDrag {
            panel: music
            visible: Settings.dragToOpen.music
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: root.side + Config.border.rounding
            height: root.side + Config.border.rounding
            onClicked: if (startHeight > 0) music.goHome()
        }

        PanelDrag {
            panel: matrix
            visible: Settings.dragToOpen.matrix
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: root.side + Config.border.rounding
            height: root.side + Config.border.rounding
            onClicked: if (startHeight > 0) matrix.goHome()
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
                Launcher.open = false;
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

        AppLauncher {
            id: launcher

            open: Launcher.on(root.modelData)
            anchors.top: parent.top
            anchors.topMargin: root.top
            anchors.horizontalCenter: parent.horizontalCenter
            onClosed: Launcher.open = false
            // The control centre and send panel share its spot.
            onOpenChanged: if (open) {
                cc.open = false;
                Owly.closeSend();
            }
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

            screen: root.modelData
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: root.side
            anchors.bottomMargin: root.side
        }

        Dashboard {
            id: dash

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
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
