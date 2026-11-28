import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.services

// Workspaces of this bar's monitor, numbered 1..perMonitor, as dots, as the icon of each
// one's largest window, or as numbers (WorkspaceStyle, set over IPC). Occupied ones are
// brighter than empty ones; a white dot slides to the active workspace, unless it shows an
// icon, which is then bigger and brighter than the rest. A right click opens the workspace overview.
Item {
    id: root

    required property ShellScreen screen

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property int base: (monitor?.id ?? 0) * Config.workspaces.perMonitor
    readonly property int activeId: monitor?.activeWorkspace?.id ?? -1
    readonly property string style: WorkspaceStyle.style
    readonly property bool dots: style === "dots"

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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: Overview.toggle(root.screen.name)
    }

    // Positioned by the active workspace's delegate.
    Rectangle {
        id: indicator

        width: root.style === "numbers" ? Config.workspaces.activeBadge : Config.workspaces.activeDot
        height: width
        y: (root.height - height) / 2
        radius: width / 2
        color: Config.colours.active
        opacity: root.style === "icons" && WorkspaceStyle.largest[root.activeId] ? 0 : 1

        Behavior on opacity {
            Anim {}
        }

        Behavior on x {
            Anim {}
        }

        Behavior on width {
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
            readonly property bool occupied: !!root.occupied[wsId]
            readonly property string appClass: WorkspaceStyle.largest[wsId] ?? ""
            readonly property var entry: appClass ? DesktopEntries.heuristicLookup(appClass) : null
            readonly property bool showIcon: root.style === "icons" && appClass !== ""

            width: root.dots ? Config.workspaces.slot : Config.workspaces.wideSlot
            height: Config.workspaces.size

            Behavior on width {
                Anim {}
            }

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
                color: ws.occupied ? Config.colours.subtext : Config.colours.muted
                // The indicator covers the active one.
                opacity: root.style === "numbers" || ws.showIcon || (ws.active && root.style !== "numbers") ? 0 : 1

                Behavior on opacity {
                    Anim {}
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: Config.workspaces.icon
                source: ws.showIcon ? Quickshell.iconPath(ws.entry?.icon ?? ws.appClass, "application-x-executable") : ""
                opacity: ws.showIcon ? (ws.active ? 1 : 0.7) : 0
                scale: ws.showIcon ? (ws.active ? 1.15 : 0.9) : 0.5

                Behavior on opacity {
                    Anim {}
                }

                Behavior on scale {
                    Anim {}
                }
            }

            Text {
                anchors.centerIn: parent
                text: ws.modelData
                font.family: Config.font.family
                font.pointSize: Config.font.small
                font.bold: ws.active
                color: ws.active ? Config.colours.activeText : ws.occupied ? Config.colours.text : Config.colours.subtext
                opacity: root.style === "numbers" ? 1 : 0

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
