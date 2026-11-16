import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

// Workspaces of this bar's monitor as dots, numbered 1..perMonitor. Occupied dots are
// brighter than empty ones; a white dot slides to the active workspace.
Item {
    id: root

    required property ShellScreen screen

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int base: (monitor?.id ?? 0) * Config.workspaces.perMonitor
    readonly property int activeId: monitor?.activeWorkspace?.id ?? -1

    readonly property var occupied: {
        const ids = {};
        for (const ws of Hyprland.workspaces.values)
            if (ws.toplevels.values.length > 0)
                ids[ws.id] = true;
        return ids;
    }

    // Local numbers (1-based) of the workspaces to show.
    readonly property var shown: {
        const nums = [];
        for (let i = 1; i <= Config.workspaces.perMonitor; i++) {
            const id = base + i;
            if (i <= Config.workspaces.shown || occupied[id] || id === activeId)
                nums.push(i);
        }
        return nums;
    }

    implicitWidth: list.contentWidth
    implicitHeight: Config.workspaces.size

    // Positioned by the active workspace's delegate.
    Rectangle {
        id: indicator

        width: Config.workspaces.activeDot
        height: width
        y: (root.height - height) / 2
        radius: width / 2
        color: Config.colours.active

        Behavior on x {
            Anim {}
        }
    }

    ListView {
        id: list

        anchors.fill: parent
        orientation: ListView.Horizontal
        interactive: false

        model: ScriptModel {
            values: root.shown
        }

        add: Transition {
            Anim {
                properties: "opacity,scale"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                properties: "opacity,scale"
                to: 0
            }
        }

        displaced: Transition {
            Anim {
                property: "x"
            }
        }

        delegate: Item {
            id: ws

            required property int modelData
            readonly property int wsId: root.base + modelData
            readonly property bool active: wsId === root.activeId

            width: Config.workspaces.slot
            height: Config.workspaces.size

            Binding {
                when: ws.active
                target: indicator
                property: "x"
                value: ws.x + (ws.width - indicator.width) / 2
                restoreMode: Binding.RestoreNone
            }

            Rectangle {
                anchors.centerIn: parent
                width: Config.workspaces.dot
                height: width
                radius: width / 2
                color: root.occupied[ws.wsId] ? Config.colours.subtext : Config.colours.muted
                // The indicator covers the active one.
                opacity: ws.active ? 0 : 1

                Behavior on opacity {
                    Anim {}
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${ws.wsId}})`)
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 220
        easing.type: Easing.OutCubic
    }
}
