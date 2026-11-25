pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// How far the system flake's nixpkgs is behind its branch, and the control centre's update:
// nix flake update, a build of nixosConfigurations.<host> as the user, then (asking for the
// password through polkit, see Auth) setting it as the system and switching to it, as
// nixos-rebuild does. The flake and host come from settings.json ("updates", the Nix options
// services.moqs.updates.flake and .host); without a flake none of this shows.
//
// The update runs as its own systemd user unit (moqs-update), so the shell restarting as the
// new system comes in doesn't stop it; it writes its progress to $XDG_RUNTIME_DIR/moqs-update.log
// as "::step" lines, which the shell (old or new) follows. Over IPC:
//   qs ipc call updates check
//   qs ipc call updates update
//   qs ipc call updates status
Singleton {
    id: root

    readonly property string flake: Settings.updatesFlake.replace(/^~/, Quickshell.env("HOME"))
    readonly property bool configured: flake !== ""
    property string hostname
    readonly property string host: Settings.updatesHost || hostname

    // When the locked nixpkgs and its branch's newest commit were made (ms), and the days
    // between them; -1 until known.
    property real locked
    property real latest
    readonly property int behind: locked && latest ? Math.max(0, Math.floor((latest - locked) / 86400000)) : -1
    // The branch, e.g. "nixos-unstable".
    property string branch
    property string checkError

    // The update: running, its step (inputs, build, switch, done or failed), what it said
    // last, and when it began.
    property bool running
    property string step
    property string message
    property real startedAt
    readonly property string stepName: ({ inputs: "Updating inputs", build: "Building", switch: "Switching", done: "Done", failed: "Failed" })[step] ?? ""
    readonly property string logPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/moqs-update.log`

    function check(): void {
        if (configured && !latestCheck.running)
            lockFile.reload();
    }

    // Reads the lock's root nixpkgs: when it was made, and where it comes from.
    function readLock(text: string): void {
        try {
            const lock = JSON.parse(text);
            const name = lock.nodes[lock.root].inputs.nixpkgs;
            const node = lock.nodes[Array.isArray(name) ? name[0] : name];
            locked = (node.locked.lastModified ?? 0) * 1000;
            const o = node.original;
            branch = o.ref ?? "";
            // One small request to GitHub for the branch's newest commit, rather than nix
            // fetching all of nixpkgs whenever it has moved.
            if (o.type === "github") {
                latestCheck.command = ["curl", "-sf", "--max-time", "20", `https://api.github.com/repos/${o.owner}/${o.repo}/commits/${o.ref || "HEAD"}`];
                latestCheck.running = true;
            }
        } catch (e) {
            checkError = "Couldn't read flake.lock";
        }
    }

    function update(): void {
        if (!configured || running)
            return;
        running = true;
        step = "inputs";
        message = "";
        startedAt = Date.now();
        Quickshell.execDetached(["systemd-run", "--user", "--unit=moqs-update", "--collect", "--quiet", "sh", "-c", `
log="$XDG_RUNTIME_DIR/moqs-update.log"
exec >"$log" 2>&1
echo "::began $(date +%s)"
fail() { echo "::failed $1"; notify-send -a Updates -u critical -i dialog-error "Update failed" "$1"; exit 1; }
cd "$1" || fail "Couldn't open $1"
echo "::inputs"
nix flake update || fail "nix flake update failed"
echo "::build"
out=$(nix build --no-link --print-out-paths ".#nixosConfigurations.$2.config.system.build.toplevel") || fail "The build failed (see $log)"
if [ "$out" = "$(readlink -f /run/current-system)" ]; then
    echo "::done Already up to date"
    notify-send -a Updates -i emblem-default "System up to date" "Nothing changed."
    exit 0
fi
echo "::switch"
pkexec /run/current-system/sw/bin/systemd-run --collect --pipe --quiet --service-type=exec --unit=moqs-switch sh -c '
/run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set "$1" && exec "$1/bin/switch-to-configuration" switch' sh "$out" || fail "Switching was cancelled or failed (see $log)"
echo "::done Updated"
notify-send -a Updates -i emblem-default "System updated" "NixOS $(basename "$out" | sed 's/.*-//')"
`, "sh", flake, host]);
        logFile.reload();
    }

    // The log's last "::step message" line.
    function readLog(text: string): void {
        const lines = text.split("\n").filter(l => l.startsWith("::"));
        const began = lines.find(l => l.startsWith("::began "));
        if (began)
            startedAt = Number(began.slice(8)) * 1000;
        const steps = lines.filter(l => l !== began);
        const last = steps[steps.length - 1];
        if (!last)
            return;
        const m = last.match(/^::(\w+)\s*(.*)$/);
        step = m[1];
        message = m[2];
        if (step === "done" || step === "failed") {
            running = false;
            check();
        } else {
            running = true;
        }
    }

    Timer {
        // A minute after starting, then every six hours.
        running: root.configured
        repeat: true
        triggeredOnStart: true
        interval: 6 * 3600000
        onTriggered: delay.restart()
    }

    Timer {
        id: delay

        interval: 60000
        onTriggered: root.check()
    }

    // Is an update running (e.g. started before the shell restarted)?
    Timer {
        running: root.running
        repeat: true
        interval: 5000
        onTriggered: unitState.running = true
    }

    Process {
        id: unitState

        command: ["systemctl", "--user", "is-active", "--quiet", "moqs-update"]
        onExited: code => {
            if (code !== 0) {
                logFile.reload();
                if (root.step !== "done" && root.step !== "failed" && root.running) {
                    root.running = false;
                    root.step = "failed";
                    root.message = "Stopped";
                }
            }
        }
    }

    Process {
        id: latestCheck

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.latest = Date.parse(JSON.parse(text).commit.committer.date);
                    root.checkError = "";
                } catch (e) {
                    root.checkError = "Couldn't reach the nixpkgs branch";
                }
            }
        }
    }

    FileView {
        id: lockFile

        path: root.configured ? `${root.flake}/flake.lock` : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readLock(text())
    }

    FileView {
        id: logFile

        path: root.logPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.readLog(text());
            // After a restart: still running?
            unitState.running = true;
        }
    }

    FileView {
        path: "/proc/sys/kernel/hostname"
        onLoaded: root.hostname = text().trim()
    }

    IpcHandler {
        target: "updates"

        function check(): void {
            root.check();
        }

        function update(): string {
            if (!root.configured)
                return "no flake set (services.moqs.updates.flake)";
            root.update();
            return "started";
        }

        function status(): string {
            return root.running ? `${root.stepName}…` : root.behind < 0 ? "unknown" : `nixpkgs ${root.behind} days behind ${root.branch}${root.step ? `; last update: ${root.stepName} ${root.message}` : ""}`;
        }
    }
}
