import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.modules.auth
import qs.modules.bar
import qs.modules.controlcentre
import qs.modules.controlcentre as CC
import qs.modules.dashboard
import qs.modules.displays
import qs.modules.launcher
import qs.modules.matrix
import qs.modules.music
import qs.modules.notifications
import qs.modules.overview
import qs.modules.session
import qs.services

// One frame per screen: the visible border plus invisible windows reserving space for it.
Scope {
    id: root

    required property ShellScreen modelData

    readonly property int top: Config.bar.height
    readonly property int side: Config.border.thickness

    // 0 open, 1 covered: locking, a pane grows out of the bar over the whole screen, like the
    // launcher, and the lock screen takes over from it; unlocking, it shrinks back.
    property real closed: Lock.closing || Lock.locked ? 1 : 0

    Behavior on closed {
        NumberAnimation {
            duration: Lock.closeDuration
            easing.type: Easing.OutCubic
        }
    }

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
        // A Matrix reply, the launcher and the session menu take the keyboard outright, so their fields get it without a click.
        WlrLayershell.keyboardFocus: auth.open || matrix.replying || launcher.open || sessionMenu.open || overview.open || displays.open ? WlrKeyboardFocus.Exclusive : cc.open || music.open || matrix.open || dash.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only the border and panels take input; the interior passes clicks through. While a
        // panel is pulled out the whole screen does, so a quick pull can't leave the pointer
        // outside the frame, where the drag would stop getting its moves. The launcher and the
        // session menu take the whole screen too, so a click anywhere else closes them.
        mask: dragging || launcher.open || sessionMenu.open || overview.open || displays.open ? dragMask : frameMask

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
                item: sessionMenu
                intersection: Intersection.Subtract
            }

            Region {
                item: auth
                intersection: Intersection.Subtract
            }

            Region {
                item: overview
                intersection: Intersection.Subtract
            }

            Region {
                item: displays
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

                if (cc.open && !cc.popupOpen && !cc.holdOpen && !near(p, (win.width - cc.targetWidth) / 2, (win.width + cc.targetWidth) / 2, root.top + cc.targetHeight))
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
                    if (!cc.popupOpen && !cc.holdOpen)
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

        // While the launcher, session menu, overview or display panel is open, a click
        // anywhere outside it closes it.
        MouseArea {
            anchors.fill: parent
            visible: launcher.open || sessionMenu.open || overview.open || displays.open
            onPressed: {
                Launcher.open = false;
                Lock.menuOpen = false;
                Overview.open = false;
                if (Displays.open)
                    Displays.close();
            }
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

        // The lock pane, below the bar so the bar fades out over it rather than being covered.
        CC.Background {
            anchors.top: parent.top
            anchors.topMargin: root.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: (win.width - root.side * 2) * root.closed
            height: (win.height - root.top - root.side) * root.closed
            visible: root.closed > 0
        }

        // The bar and panels fade out as the lock pane comes down.
        Item {
            anchors.fill: parent
            opacity: 1 - root.closed
            visible: opacity > 0

            // Below the panels; rises out of the bottom border, as high as set in the control
            // centre (by default into the gap above it).
            VisualizerStrip {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - (root.side + Config.border.rounding) * 2
                height: Visualizer.height
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
                    Lock.menuOpen = false;
                    Overview.open = false;
                    if (Displays.open)
                        Displays.close();
                    cc.open = !cc.open;
                }
                onUpdatesClicked: {
                    Owly.closeSend();
                    Launcher.open = false;
                    Lock.menuOpen = false;
                    Overview.open = false;
                    if (Displays.open)
                        Displays.close();
                    cc.showUpdates();
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

            // A popover closing: it's its own window, so the pointer may have left the panel
            // while over it; then the panel closes too. Where the pointer is comes from
            // Hyprland: this window learns it only once the pointer moves again (a click
            // outside the popover only closes the popover).
            Connections {
                target: cc

                function onPopupOpenChanged(): void {
                    if (!cc.popupOpen)
                        ccRecheck.restart();
                }
            }

            Timer {
                id: ccRecheck

                interval: 150
                onTriggered: if (cc.open && !cc.popupOpen && !cc.holdOpen)
                    cursorPos.running = true
            }

            Process {
                id: cursorPos

                command: ["hyprctl", "cursorpos", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (!cc.open || cc.popupOpen || cc.holdOpen)
                            return;
                        let c = null;
                        try {
                            c = JSON.parse(text);
                        } catch (e) {
                            return;
                        }
                        // Hyprland's layout to this screen's coordinates.
                        const p = Qt.point(c.x - root.modelData.x, c.y - root.modelData.y);
                        if (!hover.near(p, (win.width - cc.targetWidth) / 2, (win.width + cc.targetWidth) / 2, root.top + cc.targetHeight))
                            cc.open = false;
                    }
                }
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
                // The control centre, send panel and overview share its spot.
                onOpenChanged: if (open) {
                    cc.open = false;
                    Owly.closeSend();
                    Overview.open = false;
                    if (Displays.open)
                        Displays.close();
                }
            }

            SessionMenu {
                id: sessionMenu

                open: Lock.menuOn(root.modelData)
                anchors.top: parent.top
                anchors.topMargin: root.top
                anchors.horizontalCenter: parent.horizontalCenter
                onClosed: Lock.menuOpen = false
                // It shares the launcher's spot.
                onOpenChanged: if (open) {
                    cc.open = false;
                    Owly.closeSend();
                    Overview.open = false;
                    if (Displays.open)
                        Displays.close();
                }
            }

            WorkspaceOverview {
                id: overview

                screen: root.modelData
                open: Overview.on(root.modelData)
                anchors.top: parent.top
                anchors.topMargin: root.top
                anchors.horizontalCenter: parent.horizontalCenter
                onClosed: Overview.open = false
                // It shares the launcher's spot.
                onOpenChanged: if (open) {
                    cc.open = false;
                    Owly.closeSend();
                    Launcher.open = false;
                    Lock.menuOpen = false;
                    if (Displays.open)
                        Displays.close();
                }
            }

            DisplayPanel {
                id: displays

                open: Displays.on(root.modelData)
                anchors.top: parent.top
                anchors.topMargin: root.top
                anchors.horizontalCenter: parent.horizontalCenter
                onClosed: Displays.close()
                // It shares the launcher's spot; a display plugged in takes it over.
                onOpenChanged: if (open) {
                    cc.open = false;
                    Owly.closeSend();
                    Launcher.open = false;
                    Lock.menuOpen = false;
                    Overview.open = false;
                }
            }

            // A polkit request takes the control centre's spot over anything there.
            AuthPane {
                id: auth

                open: Auth.on(root.modelData)
                anchors.top: parent.top
                anchors.topMargin: root.top
                anchors.horizontalCenter: parent.horizontalCenter
                onOpenChanged: if (open) {
                    cc.open = false;
                    Owly.closeSend();
                    Launcher.open = false;
                    Lock.menuOpen = false;
                    Overview.open = false;
                    if (Displays.open)
                        Displays.close();
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
