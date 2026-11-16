pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen backlight through brightnessctl.
Singleton {
    id: root

    // 0..1
    property real value: 0
    property real pending: -1

    function refresh(): void {
        get.running = true;
    }

    function set(v: real): void {
        // Never go fully dark.
        value = Math.max(0.01, Math.min(1, v));
        pending = value;
        if (!apply.running)
            debounce.restart();
    }

    Component.onCompleted: refresh()

    Timer {
        id: debounce

        interval: 30
        onTriggered: {
            apply.command = ["brightnessctl", "-q", "set", `${Math.round(root.pending * 100)}%`];
            root.pending = -1;
            apply.running = true;
        }
    }

    Process {
        id: apply

        onExited: if (root.pending >= 0) debounce.restart()
    }

    Process {
        id: get

        // device,class,current,percent,max
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",");
                if (parts.length >= 5)
                    root.value = parseInt(parts[2]) / parseInt(parts[4]);
            }
        }
    }
}
