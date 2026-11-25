import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

// Picks what to capture (Capture.pick), over the focused screen dimmed: the window under the
// pointer lights up and a click takes it; a drag takes a region; Space or Enter the whole
// screen; Escape or a right click gives up.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        // The monitor's place in the layout, as window positions are given.
        readonly property real ox: monitor?.x ?? 0
        readonly property real oy: monitor?.y ?? 0

        // Windows shown on this screen, topmost first (floating above tiled): [{ x, y, w, h }]
        // here, in the window's coordinates.
        readonly property var windows: {
            const ws = monitor?.activeWorkspace?.id;
            const special = monitor?.lastIpcObject?.specialWorkspace?.id ?? 0;
            return Hyprland.toplevels.values.map(t => t.lastIpcObject).filter(o => o?.at && o?.size && (o.workspace?.id === ws || (special && o.workspace?.id === special))).sort((a, b) => (b.floating ? 1 : 0) - (a.floating ? 1 : 0)).map(o => ({ x: o.at[0] - ox, y: o.at[1] - oy, w: o.size[0], h: o.size[1] }));
        }

        // The dragged region, or the window under the pointer.
        property bool dragging
        property real sx
        property real sy
        property var region: null
        readonly property var hovered: {
            const p = { x: mouse.mouseX, y: mouse.mouseY };
            return windows.find(r => p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h) ?? null;
        }
        readonly property var selection: dragging ? region : hovered

        function finish(r: var): void {
            dragging = false;
            region = null;
            Capture.picked(r ? Capture.geometry(r.x + ox, r.y + oy, r.w, r.h) : "");
        }

        screen: modelData
        visible: Capture.selecting && (Capture.selectScreen === "" || modelData.name === Capture.selectScreen)
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "moqs-capture"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            dragging = false;
            region = null;
            if (visible)
                keys.forceActiveFocus();
        }

        Item {
            id: keys

            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: win.finish(null)
            Keys.onSpacePressed: win.finish({ x: 0, y: 0, w: win.width, h: win.height })
            Keys.onReturnPressed: win.finish({ x: 0, y: 0, w: win.width, h: win.height })
            Keys.onEnterPressed: win.finish({ x: 0, y: 0, w: win.width, h: win.height })
        }

        // Dim everything but the selection.
        readonly property var cut: selection ?? { x: 0, y: 0, w: 0, h: 0 }

        Rectangle {
            x: 0
            y: 0
            width: win.width
            height: win.cut.y
            color: dim
        }

        Rectangle {
            x: 0
            y: win.cut.y + win.cut.h
            width: win.width
            height: win.height - win.cut.y - win.cut.h
            color: dim
        }

        Rectangle {
            x: 0
            y: win.cut.y
            width: win.cut.x
            height: win.cut.h
            color: dim
        }

        Rectangle {
            x: win.cut.x + win.cut.w
            y: win.cut.y
            width: win.width - win.cut.x - win.cut.w
            height: win.cut.h
            color: dim
        }

        readonly property color dim: Qt.alpha("#000000", 0.45)

        Rectangle {
            visible: win.selection !== null
            x: win.cut.x - 2
            y: win.cut.y - 2
            width: win.cut.w + 4
            height: win.cut.h + 4
            color: "transparent"
            radius: win.dragging ? 2 : 10
            border.width: 2
            border.color: Config.colours.active
        }

        // The selection's size, under it (or inside, at the bottom of the screen).
        Rectangle {
            visible: win.selection !== null && win.cut.w > 0
            x: Math.max(4, Math.min(win.width - width - 4, win.cut.x))
            y: win.cut.y + win.cut.h + 8 + height < win.height ? win.cut.y + win.cut.h + 8 : win.cut.y + win.cut.h - height - 8
            width: size.implicitWidth + 16
            height: size.implicitHeight + 8
            radius: height / 2
            color: Config.colours.card

            Text {
                id: size

                anchors.centerIn: parent
                text: `${Math.round(win.cut.w)} × ${Math.round(win.cut.h)}`
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }

        // What to do, at the top.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Config.bar.height + 16
            width: hint.implicitWidth + 28
            height: hint.implicitHeight + 14
            radius: height / 2
            color: Config.colours.card

            Text {
                id: hint

                anchors.centerIn: parent
                text: `${Capture.selectFor === "record" ? "Record" : "Screenshot"}: click a window · drag a region · Space for the screen · Esc cancels`
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.CrossCursor

            onPressed: event => {
                if (event.button === Qt.RightButton) {
                    win.finish(null);
                    return;
                }
                win.sx = event.x;
                win.sy = event.y;
            }
            onPositionChanged: event => {
                if (!(event.buttons & Qt.LeftButton))
                    return;
                if (!win.dragging && Math.hypot(event.x - win.sx, event.y - win.sy) < 4)
                    return;
                win.dragging = true;
                win.region = { x: Math.min(win.sx, event.x), y: Math.min(win.sy, event.y), w: Math.abs(event.x - win.sx), h: Math.abs(event.y - win.sy) };
            }
            onReleased: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                if (win.dragging)
                    win.finish(win.region.w >= 2 && win.region.h >= 2 ? win.region : null);
                else
                    // A click: the window under it, or the whole screen.
                    win.finish(win.hovered ?? { x: 0, y: 0, w: win.width, h: win.height });
            }
        }
    }
}
