pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config

// Audio bars from cava along the bottom border while something plays. On or off, and how
// high the bars reach, from the control centre; both are kept in
// $XDG_STATE_HOME/moqs/visualizer as { "enabled": true, "height": 24 }.
Singleton {
    id: root

    property bool enabled
    // How high (px) the bars reach at full level, from the screen's bottom edge.
    property int height: Config.visualizer.height
    readonly property int minHeight: 4
    readonly property int maxHeight: Config.visualizer.maxHeight
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
        save.restart();
    }

    function setHeight(px: int): void {
        height = Math.max(minHeight, Math.min(maxHeight, px));
        save.restart();
    }

    // Dragging the slider saves once it pauses.
    Timer {
        id: save

        interval: 300
        onTriggered: stateFile.setText(JSON.stringify({ enabled: root.enabled, height: root.height }) + "\n")
    }

    onRunningChanged: if (!running)
        levels = []

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", statePath.replace(/\/[^\/]*$/, "")])

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: {
            const t = text().trim();
            let s = {};
            try {
                s = JSON.parse(t);
            } catch (e) {
                // The first versions kept only "on" or "off".
                s = { enabled: t === "on" };
            }
            root.enabled = !!s.enabled;
            if (s.height > 0)
                root.height = Math.max(root.minHeight, Math.min(root.maxHeight, s.height));
        }
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
