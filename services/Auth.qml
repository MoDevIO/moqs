pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit

// The polkit agent: when an app asks for an administrator's password (pkexec, the update,
// mounting a disk, …), a pane with a password field grows out of the middle of the bar on the
// focused monitor, where the control centre does (AuthPane). Only one agent runs per session;
// with another (e.g. polkit-gnome or hyprpolkitagent) already running, this one doesn't.
Singleton {
    id: root

    readonly property AuthFlow flow: agent.flow
    readonly property bool active: agent.isActive
    readonly property bool registered: agent.isRegistered
    // The monitor the request came up on.
    property string screen

    function on(s: ShellScreen): bool {
        return active && (screen === "" || s.name === screen);
    }

    PolkitAgent {
        id: agent

        onAuthenticationRequestStarted: root.screen = Hyprland.focusedMonitor?.name ?? ""
    }
}
