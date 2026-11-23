pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config

// Audio bars from cava along the bottom border while something plays. On or off from the
// control centre; the choice is kept in $XDG_STATE_HOME/moqs/visualizer, "on" or "off".
Singleton {
    id: root

    property bool enabled
    // cava is installed.
    property bool available: true
    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    readonly property bool running: enabled && available && playing
    // One level per bar, 0..1; empty while not running.
    property var levels: []

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs/visualizer`
    readonly property string configPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/moqs-cava-${Quickshell.processId}.conf`

    function toggle(): void {
        enabled = !enabled;
        stateFile.setText(enabled ? "on\n" : "off\n");
    }

    onRunningChanged: if (!running)
        levels = []

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", statePath.replace(/\/[^\/]*$/, "")])

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: root.enabled = text().trim() === "on"
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v cava"]
        onExited: code => root.available = code === 0
    }

    // Raw output: one line per frame, the bars' levels 0..1000 separated by ";".
    Process {
        running: root.running
        command: ["sh", "-c", `cat > "$1" <<'EOF'
[general]
bars = ${Config.visualizer.bars}
framerate = ${Config.visualizer.framerate}
[output]
method = raw
channels = mono
mono_option = average
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
frame_delimiter = 10
EOF
exec cava -p "$1"`, "sh", root.configPath]

        stdout: SplitParser {
            onRead: line => root.levels = line.split(";").filter(x => x !== "").map(x => Number(x) / 1000)
        }
    }
}
