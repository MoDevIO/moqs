pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Which apps use the microphone or the camera right now, for the bar's dot (PrivacyDot).
// The microphone: PipeWire's recording streams, not those recording what plays (a sink's
// monitor, as the visualizer's cava does). The camera: processes with a /dev/video device
// open, checked every few seconds, as apps such as browsers open it directly; PipeWire
// holding it stands for the apps behind its video streams.
Singleton {
    id: root

    // App names, each once.
    readonly property var mic: unique(micStreams.map(appName))
    property var camera: []
    readonly property bool active: mic.length > 0 || camera.length > 0

    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream)
    readonly property var micStreams: streams.filter(n => {
        const p = n.properties ?? {};
        return n.type === PwNodeType.AudioInStream && p["stream.capture.sink"] !== "true" && p["stream.monitor"] !== "true" && !String(p["target.object"] ?? "").endsWith(".monitor") && p["application.process.binary"] !== "cava";
    })
    readonly property var videoStreams: streams.filter(n => (n.properties ?? {})["media.class"] === "Stream/Input/Video")

    function appName(n: var): string {
        const p = n.properties ?? {};
        return p["application.name"] || p["application.process.binary"] || n.description || n.name || "An app";
    }

    function unique(list: var): var {
        return list.filter((x, i) => x && list.indexOf(x) === i);
    }

    // Properties are only there for nodes that are tracked.
    PwObjectTracker {
        objects: root.streams
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 3000
        onTriggered: cameraCheck.running = true
    }

    // The names of the processes with a camera open, one a line.
    Process {
        id: cameraCheck

        command: ["sh", "-c", "for p in /proc/[0-9]*; do ls -l \"$p/fd\" 2>/dev/null | grep -q ' -> /dev/video' && cat \"$p/comm\" 2>/dev/null; done; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const procs = text.split("\n").map(x => x.trim()).filter(x => x);
                const viaPipewire = procs.some(x => x === "pipewire" || x === "wireplumber");
                const direct = procs.filter(x => x !== "pipewire" && x !== "wireplumber");
                const names = root.unique([...direct, ...(viaPipewire ? root.videoStreams.map(root.appName) : [])]);
                if (JSON.stringify(names) !== JSON.stringify(root.camera))
                    root.camera = names;
            }
        }
    }
}
