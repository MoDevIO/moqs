pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Music playback through an mpv instance controlled over its JSON IPC socket.
Singleton {
    id: root

    // Songs as returned by Navidrome; mpv's playlist mirrors this.
    property var queue: []
    property int index: -1
    readonly property var current: index >= 0 && index < queue.length ? queue[index] : null

    property bool paused: true
    property real position: 0
    property real duration: 0
    readonly property bool playing: current !== null && !paused

    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/quickshell-mpv-${Quickshell.processId}.sock`
    property var pending: []

    function send(command: var): void {
        const line = JSON.stringify({ command }) + "\n";
        if (socket.connected) {
            socket.write(line);
            socket.flush();
        } else {
            pending.push(line);
            mpv.running = true;
        }
    }

    function play(songs: var, start: int): void {
        queue = songs;
        send(["playlist-clear"]);
        send(["stop"]);
        for (const s of songs)
            send(["loadfile", Navidrome.streamUrl(s.id), "append"]);
        send(["set_property", "playlist-pos", start]);
        send(["set_property", "pause", false]);
    }

    function toggle(): void {
        if (current)
            send(["cycle", "pause"]);
    }

    function next(): void {
        send(["playlist-next"]);
    }

    // Restarts the song unless it has only just begun.
    function previous(): void {
        if (position > 3)
            seek(0);
        else
            send(["playlist-prev"]);
    }

    function seek(seconds: real): void {
        send(["set_property", "time-pos", seconds]);
    }

    Process {
        id: mpv

        command: ["mpv", "--idle=yes", "--no-video", "--no-terminal", "--force-window=no", `--input-ipc-server=${root.socketPath}`]
        onStarted: connectRetry.start()
        onExited: {
            socket.connected = false;
            root.index = -1;
            root.paused = true;
        }
    }

    // mpv creates the socket shortly after starting.
    Timer {
        id: connectRetry

        interval: 100
        repeat: true
        onTriggered: {
            if (socket.connected || !mpv.running)
                stop();
            else
                socket.connected = true;
        }
    }

    Socket {
        id: socket

        path: root.socketPath

        onConnectedChanged: {
            if (!connected)
                return;
            connectRetry.stop();
            for (const [id, prop] of [[1, "pause"], [2, "time-pos"], [3, "duration"], [4, "playlist-pos"]])
                write(JSON.stringify({ command: ["observe_property", id, prop] }) + "\n");
            for (const line of root.pending)
                write(line);
            root.pending = [];
            flush();
        }

        parser: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.event !== "property-change")
                    return;
                switch (msg.name) {
                case "pause":
                    root.paused = msg.data ?? true;
                    break;
                case "time-pos":
                    root.position = msg.data ?? 0;
                    break;
                case "duration":
                    root.duration = msg.data ?? 0;
                    break;
                case "playlist-pos":
                    root.index = msg.data ?? -1;
                    break;
                }
            }
        }
    }

    // Now playing, then a play once the song is half over.
    property bool scrobbled
    onCurrentChanged: {
        scrobbled = false;
        if (current)
            Navidrome.scrobble(current.id, false);
    }
    onPositionChanged: {
        if (current && !scrobbled && duration > 0 && position > duration / 2) {
            scrobbled = true;
            Navidrome.scrobble(current.id, true);
        }
    }
}
