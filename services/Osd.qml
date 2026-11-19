pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config

// Volume and brightness, shown in place of the clock while they change. Driven by changes
// from anywhere and over IPC, for touch strips and similar inputs:
//   qs ipc call volume press     shows the slider until release
//   qs ipc call volume up        one step up (down: one step down)
//   qs ipc call volume release
// and the same with brightness. release hides it right away; up and down without a press
// show it for a moment.
Singleton {
    id: root

    // "", "volume" or "brightness"
    property string kind
    property bool held

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    readonly property real value: kind === "brightness" ? Brightness.value : volume
    readonly property string icon: kind === "brightness" ? "\u{F00DF}" : muted || volume === 0 ? "\u{F0581}" : volume < 0.5 ? "\u{F0580}" : "\u{F057E}"

    function show(k: string): void {
        kind = k;
        if (!held)
            hide.restart();
    }

    function press(k: string): void {
        held = true;
        hide.stop();
        kind = k;
        if (k === "brightness")
            Brightness.refresh();
    }

    function release(k: string): void {
        if (kind !== k)
            return;
        held = false;
        hide.stop();
        kind = "";
        // The last step's change may only arrive now; it mustn't bring the level back.
        quiet.restart();
    }

    function step(k: string, dir: int): void {
        const d = dir * Config.osd.step;
        if (k === "brightness") {
            Brightness.set(Brightness.value + d);
        } else if (sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(1, volume + d));
        }
        show(k);
    }

    // Changes made elsewhere (keys, the control centre, other programs) show too.
    property bool ready
    onVolumeChanged: changed("volume")
    onMutedChanged: changed("volume")

    function changed(k: string): void {
        if (ready && !quiet.running)
            show(k);
    }

    Timer {
        id: quiet

        interval: 300
    }

    Connections {
        target: Brightness

        function onValueChanged(): void {
            if (root.kind !== "volume")
                root.changed("brightness");
        }
    }

    // The first values after start aren't changes.
    Timer {
        running: true
        interval: 2000
        onTriggered: root.ready = true
    }

    Timer {
        id: hide

        interval: Config.osd.timeout
        onTriggered: root.kind = ""
    }

    PwObjectTracker {
        objects: [root.sink]
    }

    IpcHandler {
        target: "volume"

        function press(): void {
            root.press("volume");
        }
        function up(): void {
            root.step("volume", 1);
        }
        function down(): void {
            root.step("volume", -1);
        }
        function release(): void {
            root.release("volume");
        }
    }

    IpcHandler {
        target: "brightness"

        function press(): void {
            root.press("brightness");
        }
        function up(): void {
            root.step("brightness", 1);
        }
        function down(): void {
            root.step("brightness", -1);
        }
        function release(): void {
            root.release("brightness");
        }
    }
}
