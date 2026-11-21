pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The app launcher, which grows out of the bar on the focused monitor. Opened over IPC:
//   qs ipc call launcher toggle   (open, close)
// How often and when each app was started is kept in $XDG_STATE_HOME/moqs/launcher.json, so
// the ones used most rank first. Snippets live next to it in snippets.txt, one per line as
// "name: text" ("\n" for a line break). Recent files come from the list GTK apps share,
// ~/.local/share/recently-used.xbel.
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs`

    // [[emoji, description, aliases, tags]], from gemoji.
    property var emoji: []
    // [{ name, text }]
    property var snippets: []
    // Newest first: [{ url, path, name, dir, mime, time }]
    property var recentFiles: []

    function parseSnippets(text: string): void {
        const out = [];
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*([^#:][^:]*?)\s*:\s?(.*)$/);
            if (m)
                out.push({ name: m[1], text: m[2].replace(/\\n/g, "\n") });
        }
        snippets = out;
    }

    function saveSnippets(list: var): void {
        snippets = list;
        const lines = ["# moqs snippets, one per line as \"name: text\"; \\n is a line break.", ...list.map(x => `${x.name.replace(/:/g, "")}: ${x.text.replace(/\n/g, "\\n")}`)];
        snippetsFile.setText(lines.join("\n") + "\n");
    }

    // Saves a snippet, replacing one of the same name.
    function addSnippet(name: string, text: string): void {
        saveSnippets([...snippets.filter(x => x.name.toLowerCase() !== name.toLowerCase()), { name, text }]);
    }

    function removeSnippet(name: string): void {
        saveSnippets(snippets.filter(x => x.name !== name));
    }

    function parseRecent(xml: string): void {
        const home = Quickshell.env("HOME");
        const out = [];
        const re = /<bookmark\s+href="(file:\/\/[^"]+)"[^>]*?modified="([^"]+)"[^>]*>([\s\S]*?)<\/bookmark>/g;
        let m;
        while ((m = re.exec(xml))) {
            let path;
            try {
                path = decodeURIComponent(m[1].slice(7));
            } catch (e) {
                continue;
            }
            const mime = (m[3].match(/<mime:mime-type\s+type="([^"]+)"/) ?? [])[1] ?? "";
            const slash = path.lastIndexOf("/");
            out.push({ url: m[1], path, name: path.slice(slash + 1), dir: path.slice(0, slash).replace(home, "~") || "/", mime, time: Date.parse(m[2]) || 0 });
        }
        recentFiles = out.sort((a, b) => b.time - a.time).slice(0, 300);
    }

    // An icon name for a MIME type, e.g. "application/pdf" -> "application-pdf".
    function mimeIcon(mime: string): string {
        return mime ? mime.replace("/", "-") : "text-x-generic";
    }

    // app id -> { count, last } (last in ms)
    property var usage: ({})
    readonly property string usagePath: `${stateDir}/launcher.json`

    // How much an app's use lifts it: grows with the count, halved for apps not started in
    // a month. 0..30.
    function boost(id: string): real {
        const u = usage[id];
        if (!u)
            return 0;
        const recent = Date.now() - u.last < 30 * 24 * 3600 * 1000;
        return Math.min(30, 9 * Math.log2(1 + u.count)) * (recent ? 1 : 0.5);
    }

    function used(id: string): void {
        const u = Object.assign({}, usage);
        u[id] = { count: (u[id]?.count ?? 0) + 1, last: Date.now() };
        usage = u;
        usageFile.setText(JSON.stringify(u) + "\n");
    }

    // A calculator for "=…": numbers (with . or , as the decimal point), + - * / % ^,
    // brackets, and sqrt abs sin cos tan asin acos atan ln log exp round floor ceil, pi, e.
    // Returns the result, or NaN for anything it can't read.
    function calculate(input: string): real {
        const src = input.replace(/\s+/g, "").replace(/×/g, "*").replace(/÷/g, "/").replace(/(\d),(\d)/g, "$1.$2").toLowerCase();
        let i = 0;
        const fns = { sqrt: Math.sqrt, abs: Math.abs, sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan, ln: Math.log, log: Math.log10, exp: Math.exp, round: Math.round, floor: Math.floor, ceil: Math.ceil };
        const consts = { pi: Math.PI, e: Math.E };
        function fail() {
            throw new Error("bad");
        }
        function peek() {
            return src[i];
        }
        // sum: term (("+"|"-") term)*
        function sum() {
            let v = term();
            while (peek() === "+" || peek() === "-")
                v = src[i++] === "+" ? v + term() : v - term();
            return v;
        }
        // term: power (("*"|"/"|"%") power)*
        function term() {
            let v = power();
            while ("*/%".includes(peek() ?? "x")) {
                const op = src[i++];
                const r = power();
                v = op === "*" ? v * r : op === "/" ? v / r : v % r;
            }
            return v;
        }
        // power: unary ("^" power)?, right to left
        function power() {
            const v = unary();
            if (peek() === "^") {
                i++;
                return Math.pow(v, power());
            }
            return v;
        }
        function unary() {
            if (peek() === "-") {
                i++;
                return -unary();
            }
            if (peek() === "+") {
                i++;
                return unary();
            }
            return atom();
        }
        function atom() {
            if (peek() === "(") {
                i++;
                const v = sum();
                if (src[i++] !== ")")
                    fail();
                return v;
            }
            const num = src.slice(i).match(/^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/);
            if (num) {
                i += num[0].length;
                return Number(num[0]);
            }
            const word = src.slice(i).match(/^[a-z]+/);
            if (word) {
                i += word[0].length;
                if (word[0] in consts)
                    return consts[word[0]];
                if (word[0] in fns && peek() === "(")
                    return fns[word[0]](atom());
            }
            return fail();
        }
        try {
            const v = sum();
            return i === src.length && src.length > 0 ? v : NaN;
        } catch (e) {
            return NaN;
        }
    }

    // A result as text: up to 12 significant digits, no trailing zeros.
    function formatNumber(v: real): string {
        if (!isFinite(v))
            return v > 0 ? "∞" : v < 0 ? "-∞" : "";
        return String(Number(v.toPrecision(12)));
    }

    property bool open
    // Monitor it opened on; it stays there even if focus moves.
    property string screen

    function show(): void {
        screen = Hyprland.focusedMonitor?.name ?? "";
        Lock.menuOpen = false;
        open = true;
    }

    function toggle(): void {
        if (open)
            open = false;
        else
            show();
    }

    // Visible on this screen's frame.
    function on(s: ShellScreen): bool {
        return open && (screen === "" || s.name === screen);
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", usagePath.replace(/\/[^\/]*$/, "")])

    FileView {
        path: Quickshell.shellPath("assets/emoji.json")
        printErrors: false
        onLoaded: {
            try {
                root.emoji = JSON.parse(text());
            } catch (e) {}
        }
    }

    FileView {
        id: snippetsFile

        path: `${root.stateDir}/snippets.txt`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseSnippets(text())
    }

    FileView {
        path: `${Quickshell.env("XDG_DATA_HOME") || `${Quickshell.env("HOME")}/.local/share`}/recently-used.xbel`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseRecent(text())
    }

    FileView {
        id: usageFile

        path: root.usagePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const u = JSON.parse(text());
                root.usage = u && typeof u === "object" ? u : {};
            } catch (e) {
                root.usage = {};
            }
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.open = false;
        }
    }
}
