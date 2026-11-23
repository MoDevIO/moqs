pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The workspace overview, which grows out of the bar on the focused monitor. Opened by
// right-clicking the workspace dots, or over IPC:
//   qs ipc call overview toggle   (also open, close)
Singleton {
    id: root

    property bool open
    // Monitor it opened on.
    property string screen

    function show(name: string): void {
        screen = name || (Hyprland.focusedMonitor?.name ?? "");
        Hyprland.refreshToplevels();
        open = true;
    }

    function toggle(name: string): void {
        if (open)
            open = false;
        else
            show(name);
    }

    function on(s: ShellScreen): bool {
        return open && (screen === "" || s.name === screen);
    }

    // Focuses a window and goes to its workspace.
    function focusWindow(address: string): void {
        Hyprland.dispatch(`hl.dsp.focus({window = "address:0x${address}"})`);
    }

    function focusWorkspace(id: int): void {
        Hyprland.dispatch(`hl.dsp.focus({workspace = ${id}})`);
    }

    // Moves a window to a workspace and stays on the one shown now. Hyprland moves the
    // focused window, so it's focused first.
    function moveWindow(address: string, workspace: int, stay: int): void {
        Hyprland.dispatch(`hl.dsp.focus({window = "address:0x${address}"})`);
        Hyprland.dispatch(`hl.dsp.window.move({workspace = ${workspace}})`);
        if (stay > 0)
            Hyprland.dispatch(`hl.dsp.focus({workspace = ${stay}})`);
        settle.restart();
    }

    // Window positions come from the last IPC snapshot; take a new one once moves land.
    Timer {
        id: settle

        interval: 150
        onTriggered: Hyprland.refreshToplevels()
    }

    IpcHandler {
        target: "overview"

        function toggle(): void {
            root.toggle("");
        }

        function open(): void {
            root.show("");
        }

        function close(): void {
            root.open = false;
        }
    }
}
