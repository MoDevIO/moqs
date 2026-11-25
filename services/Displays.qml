pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Display arrangement. Plugging in a display opens a panel out of the bar, on the focused
// screen, to arrange the displays side by side or mirror one onto the others, and to set
// each one's resolution and scale; changes go through `hyprctl eval 'hl.monitor{…}'`
// and revert by themselves unless kept within 15 seconds. A kept setup is
// remembered for that set of displays (by their descriptions, as names like DP-1 change
// between ports) in $XDG_STATE_HOME/moqs/displays.json and restored when it's plugged in
// again. Also opened over IPC:
//   qs ipc call displays open   (also close)
Singleton {
    id: root

    property bool open
    // Monitor it opened on.
    property string screen
    // Why it opened, e.g. "DELL U2720Q connected", or "".
    property string reason

    // From `hyprctl monitors all -j`: [{ name, description, width, height, refresh, x, y,
    // scale, transform, mirrorOf, disabled, modes }], sizes in pixels, positions in layout
    // pixels, modes as "WxH@R", largest first.
    property var monitors: []
    // The arrangement being edited: name -> { x, y } in layout pixels.
    property var layout: ({})
    // "extend" or "mirror".
    property string mode: "extend"
    // The display the others show in mirror mode.
    property string mirrorSource
    // Resolution and scale picked per display: name -> { mode: "WxH@R", scale }.
    property var settings: ({})
    // The display whose resolution and scale are shown.
    property string selected
    // Scales offered, besides the one a display has.
    readonly property var scales: [1, 1.25, 1.5, 1.6, 1.75, 2]

    // After Apply: the setup to go back to, and seconds left to keep the new one.
    property var previous: null
    property int countdown: 0
    readonly property int keepSeconds: 15

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs/displays.json`
    property var saved: ({})

    // Built in: laptop panels, preferred as the mirror source.
    function builtIn(name: string): bool {
        return /^(eDP|LVDS|DSI)/.test(name);
    }

    // The resolution ("WxH@R") and scale a display has now, or that were picked for it.
    function modeOf(m: var): string {
        return settings[m.name]?.mode ?? `${m.width}x${m.height}@${m.refresh.toFixed(2)}`;
    }

    function scaleOf(m: var): real {
        return settings[m.name]?.scale ?? m.scale;
    }

    // "WxH@R" as { w, h, r }.
    function parseMode(mode: string): var {
        const p = mode.match(/^(\d+)x(\d+)(?:@([\d.]+))?/);
        return p ? { w: Number(p[1]), h: Number(p[2]), r: Number(p[3] ?? 60) } : { w: 1920, h: 1080, r: 60 };
    }

    // "2560×1440 · 144 Hz"
    function modeName(mode: string): string {
        const p = parseMode(mode);
        // 59.94 and 60 both exist, so rates that aren't whole keep their decimals.
        const r = Math.abs(p.r - Math.round(p.r)) < 0.005 ? String(Math.round(p.r)) : p.r.toFixed(2);
        return `${p.w}×${p.h} · ${r} Hz`;
    }

    function scaleName(s: real): string {
        return `${Number(s.toFixed(3))}×`;
    }

    // Size in layout pixels (scaled, and turned for portrait transforms).
    function size(m: var): var {
        const p = parseMode(modeOf(m));
        const s = scaleOf(m);
        const w = Math.round(p.w / s);
        const h = Math.round(p.h / s);
        return m.transform % 2 === 1 ? { w: h, h: w } : { w, h };
    }

    function setMode(name: string, mode: string): void {
        pick(name, { mode });
    }

    function setScale(name: string, scale: real): void {
        pick(name, { scale });
    }

    // A new size: the displays are put back edge to edge, from the leftmost one on.
    function pick(name: string, change: var): void {
        const m = byName(name);
        if (!m)
            return;
        const s = Object.assign({}, settings);
        s[name] = Object.assign({ mode: modeOf(m), scale: scaleOf(m) }, s[name], change);
        settings = s;
        const order = monitors.filter(x => layout[x.name]).sort((a, b) => layout[a.name].x - layout[b.name].x || layout[a.name].y - layout[b.name].y);
        for (const x of order.slice(1)) {
            const l = Object.assign({}, layout);
            const p = l[x.name];
            delete l[x.name];
            layout = l;
            const placed = snap(x.name, p.x, p.y);
            const back = Object.assign({}, layout);
            back[x.name] = placed;
            layout = back;
        }
    }

    function byName(name: string): var {
        return monitors.find(m => m.name === name) ?? null;
    }

    // The key a set of displays is remembered under.
    function setupKey(list: var): string {
        return list.map(m => m.description || m.name).sort().join(" + ");
    }

    // Reads the displays, then runs done().
    function refresh(done: var): void {
        reader.done = done ?? null;
        reader.running = true;
    }

    function show(why: string): void {
        reason = why;
        refresh(() => {
            edit();
            const added = monitors.find(m => why.startsWith(m.description || m.name));
            if (added)
                selected = added.name;
            screen = Hyprland.focusedMonitor?.name ?? "";
            open = true;
        });
    }

    // Shown on this screen's frame.
    function on(s: ShellScreen): bool {
        return open && (screen === "" || s.name === screen || !Quickshell.screens.some(x => x.name === screen));
    }

    function close(): void {
        if (countdown > 0)
            revert();
        open = false;
    }

    // Starts editing from the current setup.
    function edit(): void {
        const l = {};
        for (const m of monitors)
            l[m.name] = { x: m.x, y: m.y };
        layout = l;
        const mirrored = monitors.find(m => m.mirrorOf && m.mirrorOf !== "none");
        mode = mirrored ? "mirror" : "extend";
        mirrorSource = mirrored ? sourceName(mirrored.mirrorOf) : (monitors.find(m => builtIn(m.name)) ?? monitors[0])?.name ?? "";
        settings = {};
        selected = (monitors.find(m => !builtIn(m.name)) ?? monitors[0])?.name ?? "";
    }

    // hyprctl gives the mirrored display as a name or an ID.
    function sourceName(of: string): string {
        const byId = monitors.find(m => String(m.id) === String(of));
        return byId ? byId.name : of;
    }

    // Where a display dropped at (x, y) ends up: touching the nearest edge of another one,
    // lined up with its top, middle or bottom (or left, centre, right) when close.
    function snap(name: string, x: real, y: real): var {
        const me = byName(name);
        if (!me)
            return { x, y };
        const s = size(me);
        const others = monitors.filter(m => m.name !== name && layout[m.name] && !m.disabled);
        if (!others.length)
            return { x: 0, y: 0 };
        const tolerance = 120;
        const align = (v, lo, len, olen) => {
            for (const t of [lo, lo + (olen - len) / 2, lo + olen - len])
                if (Math.abs(v - t) < tolerance)
                    return Math.round(t);
            return Math.round(Math.max(lo - len + 1, Math.min(lo + olen - 1, v)));
        };
        const overlaps = (cx, cy) => others.some(o => {
            const p = layout[o.name];
            const os = size(o);
            return cx < p.x + os.w && cx + s.w > p.x && cy < p.y + os.h && cy + s.h > p.y;
        });
        let best = null;
        let bestD = Infinity;
        for (const o of others) {
            const p = layout[o.name];
            const os = size(o);
            const candidates = [
                { x: p.x + os.w, y: align(y, p.y, s.h, os.h) },
                { x: p.x - s.w, y: align(y, p.y, s.h, os.h) },
                { x: align(x, p.x, s.w, os.w), y: p.y + os.h },
                { x: align(x, p.x, s.w, os.w), y: p.y - s.h }
            ];
            for (const c of candidates) {
                const d = Math.hypot(c.x - x, c.y - y);
                if (d < bestD && !overlaps(c.x, c.y)) {
                    best = c;
                    bestD = d;
                }
            }
        }
        return best ?? { x, y };
    }

    function move(name: string, x: real, y: real): void {
        const l = Object.assign({}, layout);
        l[name] = snap(name, x, y);
        layout = l;
    }

    // One hl.monitor call for a display, with the resolution and scale from `picked`
    // (name -> { mode, scale }) or else its own.
    function spec(m: var, x: int, y: int, mirror: string, picked: var): string {
        const p = picked[m.name] ?? {};
        const parts = [`output = "${m.name}"`, `mode = "${p.mode ?? `${m.width}x${m.height}@${m.refresh.toFixed(2)}`}"`, `position = "${x}x${y}"`, `scale = ${p.scale ?? m.scale}`];
        if (m.transform)
            parts.push(`transform = ${m.transform}`);
        // Always given: a display that mirrors keeps doing so unless told mirror = "".
        parts.push(`mirror = "${mirror}"`);
        return `hl.monitor({${parts.join(", ")}})`;
    }

    // The Lua for an arrangement: positions shifted so the top-left display is at 0x0.
    function arrangement(mode: string, layout: var, source: string, picked: var): string {
        const list = monitors.filter(m => !m.disabled);
        if (mode === "mirror")
            return list.map(m => m.name === source ? spec(m, 0, 0, "", picked) : spec(m, 0, 0, source, picked)).join("\n");
        const xs = list.map(m => layout[m.name]?.x ?? m.x);
        const ys = list.map(m => layout[m.name]?.y ?? m.y);
        const dx = Math.min(...xs);
        const dy = Math.min(...ys);
        return list.map((m, i) => spec(m, xs[i] - dx, ys[i] - dy, "", picked)).join("\n");
    }

    function run(lua: string): void {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }

    // Applies the edited setup and starts the countdown to going back.
    function apply(): void {
        const before = {};
        const had = {};
        for (const m of monitors) {
            before[m.name] = { x: m.x, y: m.y };
            had[m.name] = { mode: `${m.width}x${m.height}@${m.refresh.toFixed(2)}`, scale: m.scale };
        }
        const mirrored = monitors.find(m => m.mirrorOf && m.mirrorOf !== "none");
        previous = { mode: mirrored ? "mirror" : "extend", layout: before, source: mirrored ? sourceName(mirrored.mirrorOf) : "", settings: had };
        run(arrangement(mode, layout, mirrorSource, settings));
        countdown = keepSeconds;
        ticker.restart();
    }

    function keep(): void {
        ticker.stop();
        countdown = 0;
        previous = null;
        const s = Object.assign({}, saved);
        const positions = {};
        for (const m of monitors)
            positions[m.description || m.name] = Object.assign({}, layout[m.name] ?? { x: m.x, y: m.y }, { mode: modeOf(m), scale: scaleOf(m) });
        const source = byName(mirrorSource);
        s[setupKey(monitors)] = { mode, source: source ? (source.description || source.name) : "", positions };
        saved = s;
        stateFile.setText(JSON.stringify(s, null, 1) + "\n");
        open = false;
    }

    function revert(): void {
        ticker.stop();
        countdown = 0;
        if (previous) {
            run(arrangement(previous.mode, previous.layout, previous.source, previous.settings));
            layout = previous.layout;
            mode = previous.mode;
            settings = {};
            if (previous.source)
                mirrorSource = previous.source;
        }
        previous = null;
        refresh(null);
    }

    // A display came or went: restore the setup remembered for the displays now connected,
    // or ask how to arrange them.
    function plugged(name: string): void {
        refresh(() => {
            if (monitors.length < 2) {
                if (open && countdown === 0)
                    open = false;
                return;
            }
            const remembered = saved[setupKey(monitors)];
            const added = byName(name);
            if (!remembered) {
                show(added ? `${added.description || added.name} connected` : "");
                return;
            }
            const l = {};
            const picked = {};
            for (const m of monitors) {
                const p = remembered.positions[m.description || m.name];
                l[m.name] = p ? { x: p.x, y: p.y } : { x: m.x, y: m.y };
                // Only resolutions the display still offers.
                if (p?.mode && m.modes.includes(p.mode))
                    picked[m.name] = { mode: p.mode, scale: p.scale ?? m.scale };
                else if (p?.scale)
                    picked[m.name] = { scale: p.scale };
            }
            const source = monitors.find(m => (m.description || m.name) === remembered.source);
            run(arrangement(remembered.mode, l, source?.name ?? "", picked));
            restored.createObject(root, { command: ["notify-send", "-a", "Displays", "-i", "video-display", "-A", "arrange=Arrange", "Display setup restored", remembered.mode === "mirror" ? "Mirroring" : "Side by side, as you arranged them"] });
        });
    }

    // "2560x1440@143.97Hz" as "2560x1440@143.97", without repeats, largest and fastest first.
    function sortModes(list: var): var {
        const out = [...new Set(list.map(x => String(x).replace(/Hz$/i, "")))];
        return out.sort((a, b) => {
            const p = parseMode(a);
            const q = parseMode(b);
            return q.w * q.h - p.w * p.h || q.r - p.r;
        });
    }

    Component {
        id: restored

        Process {
            running: true
            stdout: StdioCollector {
                onStreamFinished: if (text.trim() === "arrange")
                    root.show("")
            }
            onExited: destroy()
        }
    }

    Timer {
        id: ticker

        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.countdown <= 0)
                root.revert();
        }
    }

    // A moment for a new display to come up before it's read.
    Timer {
        id: settle

        property string name

        interval: 800
        onTriggered: root.plugged(name)
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "monitoraddedv2") {
                settle.name = event.data.split(",")[1] ?? "";
                settle.restart();
            } else if (event.name === "monitorremovedv2" || event.name === "monitorremoved") {
                settle.name = "";
                settle.restart();
            }
        }
    }

    Process {
        id: reader

        property var done: null

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).map(m => ({
                        id: m.id,
                        name: m.name,
                        description: m.description ?? "",
                        width: m.width,
                        height: m.height,
                        refresh: m.refreshRate ?? 60,
                        x: m.x,
                        y: m.y,
                        scale: m.scale || 1,
                        transform: m.transform ?? 0,
                        mirrorOf: String(m.mirrorOf ?? "none"),
                        disabled: !!m.disabled,
                        modes: root.sortModes(m.availableModes ?? [])
                    }));
                } catch (e) {}
                const d = reader.done;
                reader.done = null;
                d?.();
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
                root.saved = JSON.parse(text()) ?? {};
            } catch (e) {}
        }
    }

    IpcHandler {
        target: "displays"

        function open(): void {
            root.show("");
        }

        function close(): void {
            root.close();
        }
    }
}
