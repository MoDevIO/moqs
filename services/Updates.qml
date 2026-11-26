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
    // From the update's log, for the details: the steps reached in order, the inputs nix
    // flake update moved ([{ name, from, to }], dates as yyyy-MM-dd, `added` for new ones),
    // the packages whose version changes ([{ name, from, to, size }], from nix store
    // diff-closures; "" for one that comes or goes), how many changed only in size, when it
    // ended (ms), and its last lines of output.
    property var reached: []
    property var inputs: []
    property var changes: []
    property int resized
    property real endedAt
    property var tail: []
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
            // The branch's commit feed on GitHub, rather than nix fetching all of nixpkgs
            // whenever it has moved. Not the API, whose 60 requests an hour without a token
            // nix needs for its github: inputs. Inputs as github:owner/repo or
            // git+https://github.com/owner/repo.
            const repo = o.type === "github" ? `${o.owner}/${o.repo}` : (o.url ?? "").match(/^(?:git\+)?https:\/\/github\.com\/([^\/?#]+\/[^\/?#]+?)(?:\.git)?\/?(?:[?#].*)?$/)?.[1];
            if (repo) {
                latestCheck.command = ["curl", "-sf", "--max-time", "20", `https://github.com/${repo}/${o.ref ? `commits/${o.ref}.atom` : "commits.atom"}`];
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
        endedAt = 0;
        reached = ["inputs"];
        inputs = [];
        changes = [];
        resized = 0;
        tail = [];
        Quickshell.execDetached(["systemd-run", "--user", "--unit=moqs-update", "--collect", "--quiet", "sh", "-c", `
log="$XDG_RUNTIME_DIR/moqs-update.log"
exec >"$log" 2>&1
echo "::began $(date +%s)"
fail() { echo "::ended $(date +%s)"; echo "::failed $1"; notify-send -a Updates -u critical -i dialog-error "Update failed" "$1"; exit 1; }
cd "$1" || fail "Couldn't open $1"
echo "::inputs"
nix flake update || fail "nix flake update failed"
echo "::build"
out=$(nix build --no-link --print-out-paths ".#nixosConfigurations.$2.config.system.build.toplevel") || fail "The build failed (see $log)"
if [ "$out" = "$(readlink -f /run/current-system)" ]; then
    echo "::ended $(date +%s)"
    echo "::done Already up to date"
    notify-send -a Updates -i emblem-default "System up to date" "Nothing changed."
    exit 0
fi
echo "::changes"
nix store diff-closures /run/current-system "$out" 2>/dev/null
echo "::switch"
pkexec /run/current-system/sw/bin/systemd-run --collect --pipe --quiet --service-type=exec --unit=moqs-switch sh -c '
/run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set "$1" && exec "$1/bin/switch-to-configuration" switch' sh "$out" || fail "Switching was cancelled or failed (see $log)"
echo "::ended $(date +%s)"
echo "::done Updated"
notify-send -a Updates -i emblem-default "System updated" "NixOS $(basename "$out" | sed 's/.*-//')"
`, "sh", flake, host]);
        logFile.reload();
    }

    // The log: its last "::step message" line, and the details (see inputs).
    function readLog(text: string): void {
        const all = text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\n");
        const lines = all.filter(l => l.startsWith("::"));
        const began = lines.find(l => l.startsWith("::began "));
        if (began)
            startedAt = Number(began.slice(8)) * 1000;
        const ended = lines.find(l => l.startsWith("::ended "));
        endedAt = ended ? Number(ended.slice(8)) * 1000 : 0;
        const steps = lines.filter(l => l !== began && l !== ended && l !== "::changes");
        reached = steps.map(l => l.match(/^::(\w+)/)?.[1] ?? "");
        // nix flake update: "• Updated input 'nixpkgs':", then the old and the new lock,
        // each ending in its date: "'github:…' (2026-11-21)".
        const date = l => (l ?? "").match(/\((\d{4}-\d{2}-\d{2})\)\s*$/)?.[1] ?? "";
        const ins = [];
        all.forEach((l, i) => {
            const m = l.match(/(Updated|Added) input '([^']+)'/);
            if (m && !m[2].includes("/"))
                ins.push(m[1] === "Added" ? { name: m[2], added: true, from: "", to: date(all[i + 1]) } : { name: m[2], from: date(all[i + 1]), to: date(all[i + 2]) });
        });
        inputs = ins;
        // nix store diff-closures: "firefox: 145.0 → 146.0, +2048.3 KiB".
        const at = all.indexOf("::changes");
        const diff = at < 0 ? [] : all.slice(at + 1, all.findIndex((l, i) => i > at && l.startsWith("::")) >>> 0);
        const versions = [];
        let sized = 0;
        for (const l of diff) {
            const m = l.match(/^(.+?): (.+?) → (.+?)(?:, (.+))?$/);
            if (m)
                versions.push({ name: m[1], from: m[2] === "∅" ? "" : m[2], to: m[3] === "∅" ? "" : m[3], size: m[4] ?? "" });
            else if (/^.+?: [+-]/.test(l))
                sized++;
        }
        changes = versions;
        resized = sized;
        tail = all.filter(l => l.trim() && !l.startsWith("::")).slice(-8);
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
                    // The newest commit is the feed's first entry.
                    const date = Date.parse(text.match(/<entry>[\s\S]*?<updated>([^<]+)<\/updated>/)[1]);
                    if (isNaN(date))
                        throw new Error();
                    root.latest = date;
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
