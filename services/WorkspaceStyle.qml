pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// How the bar shows workspaces: "dots", "icons" (the icon of each workspace's largest
// window) or "numbers". Kept in $XDG_STATE_HOME/moqs/workspaces as { "style": "icons" }.
// Picked in the control centre, or over IPC:
//   qs ipc call workspaces toggleIcons     (icons <-> dots; also toggleNumbers)
//   qs ipc call workspaces set numbers     (dots, icons or numbers)
//   qs ipc call workspaces get
Singleton {
    id: root

    readonly property var styles: ["dots", "icons", "numbers"]
    property string style: "dots"

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs/workspaces`

    function set(s: string): bool {
        if (!styles.includes(s))
            return false;
        style = s;
        stateFile.setText(JSON.stringify({ style: s }) + "\n");
        if (s === "icons")
            Hyprland.refreshToplevels();
        return true;
    }

    function toggle(s: string): void {
        set(style === s ? "dots" : s);
    }

    function cycle(): void {
        set(styles[(styles.indexOf(style) + 1) % styles.length]);
    }

    function name(s: string): string {
        return ({ dots: "Dots", icons: "App icons", numbers: "Numbers" })[s] ?? s;
    }

    function icon(s: string): string {
        return ({ dots: "\u{F01D8}", icons: "\u{F003B}", numbers: "\u{F03A0}" })[s] ?? "";
    }

    // The class of the largest window on each workspace, by id. Window sizes come from the
    // last IPC snapshot, which is renewed below while icons show.
    readonly property var largest: {
        const best = {};
        for (const t of Hyprland.toplevels.values) {
            const id = t.workspace?.id;
            const ipc = t.lastIpcObject;
            if (id === undefined || !ipc?.class)
                continue;
            const area = (ipc.size?.[0] ?? 0) * (ipc.size?.[1] ?? 0);
            if (!best[id] || area > best[id].area)
                best[id] = { area, cls: ipc.class };
        }
        const out = {};
        for (const id in best)
            out[id] = best[id].cls;
        return out;
    }

    // Window sizes change when windows open, close, move or float; there is no event for a
    // floating window being resized, so a slow timer catches those.
    Connections {
        target: root.style === "icons" ? Hyprland : null

        function onRawEvent(event: HyprlandEvent): void {
            if (/^(openwindow|closewindow|movewindow|changefloatingmode|fullscreen|activewindowv2|workspacev2|moveworkspace)/.test(event.name))
                refresh.restart();
        }
    }

    Timer {
        id: refresh

        interval: 120
        onTriggered: Hyprland.refreshToplevels()
    }

    Timer {
        running: root.style === "icons"
        repeat: true
        interval: 5000
        onTriggered: Hyprland.refreshToplevels()
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", statePath.replace(/\/[^\/]*$/, "")])

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text()).style;
                if (root.styles.includes(s))
                    root.style = s;
            } catch (e) {}
            if (root.style === "icons")
                Hyprland.refreshToplevels();
        }
    }

    IpcHandler {
        target: "workspaces"

        function toggleIcons(): string {
            root.toggle("icons");
            return root.style;
        }

        function toggleNumbers(): string {
            root.toggle("numbers");
            return root.style;
        }

        function set(style: string): string {
            return root.set(style) ? root.style : `unknown style "${style}"; use dots, icons or numbers`;
        }

        function get(): string {
            return root.style;
        }
    }
}
