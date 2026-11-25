pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Countdown timers, started from the launcher ("=10m", "=1h30 tea", "=90s pasta") or over IPC.
// The soonest counts down beside the clock; when one ends, a sound plays and a notification
// stays until dismissed. Kept in $XDG_STATE_HOME/moqs/timers.json, so they outlast a restart
// (one that ended meanwhile goes off at once).
//   qs ipc call timers start "25m focus"
//   qs ipc call timers list
//   qs ipc call timers cancel        (the soonest)
Singleton {
    id: root

    // [{ id, end (ms), total (ms), label }], soonest first.
    property var timers: []
    property real now: Date.now()
    readonly property var next: timers[0] ?? null

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs/timers.json`

    // "10m", "1h30", "1h 30m", "90s", "2 min tea" -> { ms, label }, or null without a unit.
    function parse(text: string): var {
        // Hours (with minutes after them, unit or not: "1h30"), or minutes; then seconds; then
        // the label. A bare number is a calculation, not a timer.
        const m = text.trim().match(/^(?:(\d+(?:[.,]\d+)?)\s*h(?:ours?)?\s*(?:(\d+)\s*(?:m(?:in(?:utes?|s)?)?)?)?|(\d+(?:[.,]\d+)?)\s*m(?:in(?:utes?|s)?)?)?\s*(?:(\d+)\s*s(?:ec(?:onds?|s)?)?)?(?:\s+(.*))?$/i);
        if (!m)
            return null;
        const num = x => Number((x ?? "0").replace(",", "."));
        const ms = ((num(m[1]) * 60 + num(m[2]) + num(m[3])) * 60 + num(m[4])) * 1000;
        if (!ms || ms > 7 * 86400000)
            return null;
        return { ms, label: (m[5] ?? "").trim() };
    }

    // "9:41", "1:02:03".
    function format(ms: real): string {
        const s = Math.max(0, Math.ceil(ms / 1000));
        const h = Math.floor(s / 3600), mm = Math.floor(s / 60) % 60, ss = s % 60;
        const two = n => String(n).padStart(2, "0");
        return h ? `${h}:${two(mm)}:${two(ss)}` : `${mm}:${two(ss)}`;
    }

    function start(ms: real, label: string): void {
        now = Date.now();
        set([...timers, { id: Math.random().toString(36).slice(2, 8), end: now + ms, total: ms, label }]);
    }

    function cancel(id: string): void {
        set(timers.filter(t => t.id !== id));
    }

    function set(list: var): void {
        timers = list.slice().sort((a, b) => a.end - b.end);
        stateFile.setText(JSON.stringify(timers) + "\n");
    }

    function ring(t: var): void {
        Quickshell.execDetached(["sh", "-c", "pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || paplay /run/current-system/sw/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null"]);
        Quickshell.execDetached(["notify-send", "-a", "Timer", "-u", "critical", "-i", "alarm-symbolic", t.label ? `${t.label}: time's up` : "Time's up", `${format(t.total)} timer`]);
    }

    Timer {
        running: root.timers.length > 0
        repeat: true
        interval: 250
        onTriggered: {
            root.now = Date.now();
            const done = root.timers.filter(t => t.end <= root.now);
            if (done.length) {
                done.forEach(root.ring);
                root.set(root.timers.filter(t => t.end > root.now));
            }
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", statePath.replace(/\/[^\/]*$/, "")])

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const t = JSON.parse(text());
                if (Array.isArray(t))
                    root.timers = t.filter(x => x && x.end && x.id).sort((a, b) => a.end - b.end);
            } catch (e) {}
        }
    }

    IpcHandler {
        target: "timers"

        function start(text: string): string {
            const p = root.parse(text);
            if (!p)
                return "give a time like 10m, 1h30 or 90s, and a label after it";
            root.start(p.ms, p.label);
            return `started ${root.format(p.ms)}${p.label ? " " + p.label : ""}`;
        }

        function list(): string {
            return root.timers.map(t => `${root.format(t.end - Date.now())}${t.label ? " " + t.label : ""}`).join("\n") || "no timers";
        }

        function cancel(): string {
            if (!root.next)
                return "no timers";
            root.cancel(root.next.id);
            return "cancelled";
        }
    }
}
