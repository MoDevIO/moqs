pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Screenshots and screen recordings, from the control centre's Capture tile. What to take is
// picked on CaptureSelect, a dimmed layer over the focused screen: a click takes the window
// under the pointer, a drag a region, Space the whole screen. A screenshot (grim) is copied
// and saved to Config.capture.dir; a recording (wf-recorder) is saved there as an mp4 when
// stopped. Over IPC:
//   qs ipc call capture screenshot pick     (also screen, window: the active one)
//   qs ipc call capture record pick         (also screen; record again stops it)
//   qs ipc call capture stop
Singleton {
    id: root

    readonly property string dir: Config.capture.dir.replace(/^~/, Quickshell.env("HOME"))
    // wf-recorder is installed.
    property bool canRecord: true
    readonly property bool recording: recorder.running
    property real since
    property real now: Date.now()
    property string recordingPath
    readonly property string elapsed: {
        const s = Math.max(0, Math.floor((now - since) / 1000));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    // CaptureSelect is up on `selectScreen`, for a "screenshot" or a "record".
    property bool selecting
    property string selectFor
    property string selectScreen

    function stamp(): string {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
    }

    // "x,y wxh" in the layout's logical pixels, as grim and wf-recorder take it.
    function geometry(x: real, y: real, w: real, h: real): string {
        return `${Math.round(x)},${Math.round(y)} ${Math.round(w)}x${Math.round(h)}`;
    }

    function screenGeometry(): string {
        const m = Hyprland.focusedMonitor;
        if (!m)
            return "";
        return geometry(m.x, m.y, m.width / (m.scale || 1), m.height / (m.scale || 1));
    }

    function screenshot(mode: string): void {
        if (mode === "screen") {
            take(screenGeometry());
        } else if (mode === "window") {
            Hyprland.refreshToplevels();
            const w = Hyprland.activeToplevel?.lastIpcObject;
            take(w?.at && w?.size ? geometry(w.at[0], w.at[1], w.size[0], w.size[1]) : screenGeometry());
        } else {
            pick("screenshot");
        }
    }

    function record(mode: string): void {
        if (recording) {
            stop();
            return;
        }
        if (mode === "screen")
            startRecording(screenGeometry());
        else
            pick("record");
    }

    function pick(purpose: string): void {
        Hyprland.refreshToplevels();
        selectFor = purpose;
        selectScreen = Hyprland.focusedMonitor?.name ?? "";
        selecting = true;
    }

    // From CaptureSelect: the geometry picked, or "" for none.
    function picked(g: string): void {
        selecting = false;
        if (!g)
            return;
        pending = g;
        // Once the dimmed layer is off the screen.
        afterSelect.restart();
    }

    property string pending

    Timer {
        id: afterSelect

        interval: 250
        onTriggered: {
            if (root.selectFor === "record")
                root.startRecording(root.pending);
            else
                root.take(root.pending);
        }
    }

    function take(g: string): void {
        if (!g || shot.running)
            return;
        const file = `${dir}/Screenshot_${stamp()}.png`;
        shot.file = file;
        shot.command = ["sh", "-c", 'mkdir -p "$1" && grim -g "$3" "$2" && wl-copy --type image/png < "$2"', "sh", dir, file, g];
        shot.running = true;
    }

    function startRecording(g: string): void {
        if (!g || recording)
            return;
        recordingPath = `${dir}/Recording_${stamp()}.mp4`;
        recorder.command = ["sh", "-c", 'mkdir -p "$1" && exec wf-recorder -g "$3" -f "$2"', "sh", dir, recordingPath, g];
        since = Date.now();
        recorder.running = true;
    }

    function stop(): void {
        if (recording)
            recorder.signal(2);
    }

    // Says where it went; its buttons open the file or the folder. Separate, so waiting for
    // a click on them doesn't hold up the next capture.
    function announce(app: string, title: string, file: string, image: bool): void {
        Quickshell.execDetached(["sh", "-c", `action=$(notify-send -a "$1" -i "$3" ${image ? '-h "string:image-path:$2"' : ""} -A default=Open -A folder="Show in folder" "$4" "$(basename "$2")")
case "$action" in default) xdg-open "$2" ;; folder) xdg-open "$(dirname "$2")" ;; esac`, "sh", app, file, image ? file : "video-x-generic", title]);
    }

    Process {
        id: shot

        property string file

        onExited: code => {
            if (code === 0)
                root.announce("Screenshot", "Screenshot copied and saved", file, true);
            else
                Quickshell.execDetached(["notify-send", "-a", "Screenshot", "-i", "dialog-error", "Couldn't take the screenshot"]);
        }
    }

    Process {
        id: recorder

        onExited: code => {
            if (Date.now() - root.since < 1000)
                Quickshell.execDetached(["notify-send", "-a", "Recording", "-i", "dialog-error", "Couldn't record the screen"]);
            else
                root.announce("Recording", "Recording saved", root.recordingPath, false);
        }
    }

    Timer {
        running: root.recording
        repeat: true
        interval: 500
        onTriggered: root.now = Date.now()
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v wf-recorder"]
        onExited: code => root.canRecord = code === 0
    }

    IpcHandler {
        target: "capture"

        function screenshot(mode: string): void {
            root.screenshot(mode || "pick");
        }

        function record(mode: string): void {
            root.record(mode || "pick");
        }

        function stop(): void {
            root.stop();
        }
    }
}
