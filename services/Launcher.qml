pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The app launcher, which grows out of the bar on the focused monitor. Opened over IPC:
//   qs ipc call launcher toggle   (open, close)
Singleton {
    id: root

    property bool open
    // Monitor it opened on; it stays there even if focus moves.
    property string screen

    function show(): void {
        screen = Hyprland.focusedMonitor?.name ?? "";
        open = true;
    }

    function toggle(): void {
        if (open)
            open = false;
        else
            show();
    }

    // Visible on this screen's frame.
    function on(s: ShellScreen): bool {
        return open && (screen === "" || s.name === screen);
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.open = false;
        }
    }
}
