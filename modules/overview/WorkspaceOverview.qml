import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.modules.controlcentre as CC
import qs.services

// Workspace overview that grows out of the middle of the bar: this monitor's workspaces
// with live pictures of their windows. Click a window to go to it, the empty part of a
// workspace to go there, or drag a window onto another workspace to move it there.
// Escape or a click outside closes it.
Item {
    id: root

    required property ShellScreen screen
    property bool open
    signal closed

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int base: (monitor?.id ?? 0) * Config.workspaces.perMonitor
    readonly property int activeId: monitor?.activeWorkspace?.id ?? -1

    // The monitor in layout coordinates, which window positions are given in.
    readonly property real monX: monitor?.x ?? 0
    readonly property real monY: monitor?.y ?? 0
    readonly property real monW: (monitor?.width ?? 1920) / (monitor?.scale || 1)
    readonly property real monH: (monitor?.height ?? 1080) / (monitor?.scale || 1)

    readonly property real cellW: Config.overview.cell
    readonly property real scale: cellW / monW
    readonly property real cellH: monH * scale

    readonly property var occupied: {
        const ids = {};
        for (const ws of Hyprland.workspaces.values)
            if (ws.toplevels.values.length > 0)
                ids[ws.id] = true;
        return ids;
    }

    // Local numbers (1-based) of the workspaces shown, as in the bar.
    readonly property var shown: {
        const nums = [];
        for (let i = 1; i <= Config.workspaces.perMonitor; i++) {
            const id = base + i;
            if (i <= Config.workspaces.shown || occupied[id] || id === activeId)
                nums.push(i);
        }
        return nums;
    }

    readonly property int columns: Math.max(1, Math.min(shown.length, Config.overview.columns))
    readonly property int rows: Math.ceil(shown.length / columns)
    readonly property real fullWidth: columns * cellW + (columns - 1) * Config.overview.spacing + Config.overview.padding * 2
    readonly property real fullHeight: rows * cellH + (rows - 1) * Config.overview.spacing + Config.overview.padding * 2

    // Windows on a workspace, floating ones last so they're drawn on top.
    function windowsOn(id: int): var {
        return Hyprland.toplevels.values.filter(t => t.workspace?.id === id && t.lastIpcObject?.at).sort((a, b) => (a.lastIpcObject.floating ? 1 : 0) - (b.lastIpcObject.floating ? 1 : 0));
    }

    width: open ? fullWidth : Config.launcher.seed
    height: open ? fullHeight : 0
    visible: height > 0
    focus: open

    onOpenChanged: if (open)
        forceActiveFocus()
    Keys.onEscapePressed: closed()

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    CC.Background {
        anchors.fill: parent
    }

    // Content keeps its full size while the pane grows, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        Grid {
            id: grid

            x: (parent.width - root.fullWidth) / 2 + Config.overview.padding
            y: Config.overview.padding
            columns: root.columns
            spacing: Config.overview.spacing
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            Repeater {
                model: root.shown

                delegate: Rectangle {
                    id: cell

                    required property int modelData
                    readonly property int wsId: root.base + modelData

                    width: root.cellW
                    height: root.cellH
                    radius: 10
                    color: drop.containsDrag ? Config.colours.buttonHover : Config.colours.card
                    border.width: wsId === root.activeId ? 2 : 0
                    border.color: Config.colours.active

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Overview.focusWorkspace(cell.wsId);
                            root.closed();
                        }
                    }

                    DropArea {
                        id: drop

                        anchors.fill: parent
                        keys: ["moqs-window"]
                        onDropped: drag => {
                            const w = drag.source;
                            if (w && w.wsId !== cell.wsId)
                                Overview.moveWindow(w.address, cell.wsId, root.activeId);
                        }
                    }

                    Repeater {
                        model: root.open ? root.windowsOn(cell.wsId) : []

                        delegate: Item {
                            id: win

                            required property HyprlandToplevel modelData
                            readonly property var ipc: modelData.lastIpcObject
                            readonly property string address: modelData.address
                            readonly property int wsId: cell.wsId
                            readonly property real homeX: (ipc.at[0] - root.monX) * root.scale
                            readonly property real homeY: (ipc.at[1] - root.monY) * root.scale
                            readonly property var entry: DesktopEntries.heuristicLookup(ipc.class ?? "")

                            x: homeX
                            y: homeY
                            width: Math.max(8, ipc.size[0] * root.scale)
                            height: Math.max(8, ipc.size[1] * root.scale)
                            z: area.drag.active ? 10 : ipc.floating ? 2 : 1

                            Drag.active: area.drag.active
                            Drag.keys: ["moqs-window"]
                            Drag.source: win
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 6
                                color: Config.colours.button

                                ScreencopyView {
                                    id: preview

                                    anchors.fill: parent
                                    captureSource: root.open ? win.modelData.wayland : null
                                    live: root.open
                                }

                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !preview.hasContent
                                    implicitSize: Math.min(32, parent.width * 0.6, parent.height * 0.6)
                                    source: Quickshell.iconPath(win.entry?.icon ?? (win.ipc.class ?? ""), "application-x-executable")
                                    asynchronous: true
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: "transparent"
                                border.width: area.containsMouse || win.modelData.activated ? 2 : 0
                                border.color: Config.colours.active
                            }

                            MouseArea {
                                id: area

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                drag.target: win
                                drag.threshold: 6
                                // Lifted above the other workspaces while dragged.
                                onPressed: cell.z = 1
                                onReleased: {
                                    if (drag.active)
                                        win.Drag.drop();
                                    cell.z = 0;
                                    win.x = Qt.binding(() => win.homeX);
                                    win.y = Qt.binding(() => win.homeY);
                                }
                                onClicked: {
                                    Overview.focusWindow(win.address);
                                    root.closed();
                                }
                            }
                        }
                    }

                    // The workspace's number, over its windows.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        z: 5
                        width: number.implicitWidth + 12
                        height: number.implicitHeight + 4
                        radius: height / 2
                        color: Qt.alpha(Config.colours.card, 0.85)

                        Text {
                            id: number

                            anchors.centerIn: parent
                            text: cell.modelData
                            color: cell.wsId === root.activeId ? Config.colours.text : Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
