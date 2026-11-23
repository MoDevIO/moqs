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
// ~/.local/share/recently-used.xbel. "#" searches nixpkgs, from an index of `nix search
// nixpkgs ^` kept in $XDG_CACHE_HOME/moqs/nixpkgs.json and rebuilt when it's three days old.
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

    // Units for conversions, by lower case name: [dimension, factor to the dimension's base
    // unit, offset added after it (for temperatures)].
    readonly property var units: {
        const u = {};
        const def = (dim, factor, names, offset) => {
            for (const n of names.split(" "))
                u[n] = [dim, factor, offset ?? 0];
        };
        def("length", 1, "m meter meters metre metres");
        def("length", 1000, "km kilometer kilometers kilometre kilometres");
        def("length", 0.1, "dm");
        def("length", 0.01, "cm centimeter centimeters centimetre centimetres");
        def("length", 0.001, "mm millimeter millimeters millimetre millimetres");
        def("length", 1e-6, "µm um micrometer micrometers");
        def("length", 1e-9, "nm nanometer nanometers");
        def("length", 1609.344, "mi mile miles");
        def("length", 0.9144, "yd yard yards");
        def("length", 0.3048, "ft foot feet");
        def("length", 0.0254, "in inch inches");
        def("length", 1852, "nmi");
        def("mass", 1, "kg kilogram kilograms kilo kilos");
        def("mass", 0.001, "g gram grams");
        def("mass", 1e-6, "mg milligram milligrams");
        def("mass", 1000, "t ton tons tonne tonnes");
        def("mass", 0.45359237, "lb lbs pound pounds");
        def("mass", 0.028349523125, "oz ounce ounces");
        def("mass", 6.35029318, "st stone stones");
        def("volume", 1, "l liter liters litre litres");
        def("volume", 0.1, "dl");
        def("volume", 0.01, "cl");
        def("volume", 0.001, "ml milliliter milliliters millilitre millilitres cm3 cm³ ccm");
        def("volume", 1000, "m3 m³");
        def("volume", 3.785411784, "gal gallon gallons");
        def("volume", 0.946352946, "qt quart quarts");
        def("volume", 0.473176473, "pt pint pints");
        def("volume", 0.2365882365, "cup cups");
        def("volume", 0.0295735295625, "floz");
        def("volume", 0.01478676478125, "tbsp");
        def("volume", 0.00492892159375, "tsp");
        def("area", 1, "m2 m² sqm");
        def("area", 1e6, "km2 km²");
        def("area", 1e-4, "cm2 cm²");
        def("area", 1e4, "ha hectare hectares");
        def("area", 4046.8564224, "ac acre acres");
        def("area", 0.09290304, "ft2 ft² sqft");
        def("area", 2589988.110336, "mi2 mi²");
        def("speed", 1, "m/s mps");
        def("speed", 1 / 3.6, "km/h kmh kph");
        def("speed", 0.44704, "mph");
        def("speed", 1852 / 3600, "kn kt knot knots");
        def("time", 0.001, "ms");
        def("time", 1, "s sec secs second seconds");
        def("time", 60, "min mins minute minutes");
        def("time", 3600, "h hr hrs hour hours");
        def("time", 86400, "d day days");
        def("time", 604800, "wk week weeks");
        def("time", 31557600, "yr year years");
        def("data", 1, "b byte bytes");
        def("data", 0.125, "bit bits");
        ["k", "m", "g", "t", "p"].forEach((p, i) => {
            def("data", Math.pow(1000, i + 1), `${p}b ${p}byte ${p}bytes`);
            def("data", Math.pow(1024, i + 1), `${p}ib`);
            def("data", Math.pow(1000, i + 1) / 8, `${p}bit ${p}bits`);
        });
        def("energy", 1, "j joule joules");
        def("energy", 1000, "kj");
        def("energy", 4.184, "cal");
        def("energy", 4184, "kcal");
        def("energy", 3600, "wh");
        def("energy", 3.6e6, "kwh");
        def("energy", 3.6e9, "mwh");
        def("power", 1, "w watt watts");
        def("power", 1000, "kw");
        def("power", 1e6, "mw");
        def("power", 745.69987158227, "hp");
        def("power", 735.49875, "ps");
        def("pressure", 1, "pa");
        def("pressure", 100, "hpa mbar");
        def("pressure", 1000, "kpa");
        def("pressure", 1e5, "bar");
        def("pressure", 6894.757293168, "psi");
        def("pressure", 101325, "atm");
        def("temperature", 1, "k kelvin");
        def("temperature", 1, "c °c celsius degc", 273.15);
        def("temperature", 5 / 9, "f °f fahrenheit degf", 459.67 * 5 / 9);
        def("angle", 1, "rad");
        def("angle", Math.PI / 180, "deg ° degree degrees");
        return u;
    }

    // A conversion for "=…" like "5 km in mi", "100 °F to C" or "2^10 MiB in GB": { value,
    // unit } with the unit as typed, { error } for units that don't go together, or null if
    // the input isn't a conversion. The amount can be a calculation.
    function convert(input: string): var {
        const m = input.trim().match(/^(.*\S)\s+(?:to|in|as|->|→|=)\s+(\S+)$/i);
        if (!m)
            return null;
        const src = m[1].match(/^(.*?)\s*([a-zµ°²³\/]+[23²³]?)$/i);
        if (!src)
            return null;
        const from = units[src[2].toLowerCase()];
        const to = units[m[2].toLowerCase()];
        if (!from || !to)
            return null;
        const amount = src[1] === "" ? 1 : calculate(src[1]);
        if (isNaN(amount))
            return null;
        if (from[0] !== to[0])
            return { error: `Can't convert ${from[0]} to ${to[0]}` };
        return { value: (amount * from[1] + from[2] - to[2]) / to[1], unit: m[2] };
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

    // nixpkgs, for "#": [[attr, pname, version, description, the four lower case]], loaded on
    // first use.
    property var nixpkgs: []
    // "", "indexing", "ready" or "failed"
    property string nixpkgsState
    property string nixpkgsError
    readonly property string nixpkgsPath: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/moqs/nixpkgs.json`

    // Loads the index, building it first if it's missing or three days old. Fast when Nix's
    // evaluation cache is warm; after a nixpkgs update the first build takes a minute or so.
    function indexNixpkgs(): void {
        if (nixpkgsState === "indexing" || indexer.running)
            return;
        if (nixpkgsState === "")
            nixpkgsState = "indexing";
        nixpkgsError = "";
        indexer.running = true;
    }

    Process {
        id: indexer

        command: ["sh", "-c", `f=${JSON.stringify(root.nixpkgsPath)}
mkdir -p "$(dirname "$f")"
[ -n "$(find "$f" -mmin -4320 2>/dev/null)" ] && exit 0
nix search nixpkgs ^ --json > "$f.tmp" 2>"$f.err" && mv "$f.tmp" "$f" && rm -f "$f.err" && exit 0
grep -v '^evaluating' "$f.err" | tail -n 3 >&2
rm -f "$f.tmp" "$f.err"
exit 1`]

        stderr: StdioCollector {
            id: indexErrors
        }

        onExited: code => {
            if (code !== 0 && root.nixpkgs.length === 0) {
                root.nixpkgsState = "failed";
                root.nixpkgsError = indexErrors.text.trim().split("\n").pop() || "nix search failed";
                return;
            }
            nixpkgsFile.reload();
        }
    }

    FileView {
        id: nixpkgsFile

        path: root.nixpkgsState ? root.nixpkgsPath : ""
        printErrors: false
        onLoaded: {
            let data;
            try {
                data = JSON.parse(text());
            } catch (e) {
                return;
            }
            const out = [];
            for (const key in data) {
                const p = data[key];
                const attr = key.replace(/^legacyPackages\.[^.]+\./, "");
                const pname = p.pname ?? "";
                const description = p.description ?? "";
                out.push([attr, pname, p.version ?? "", description, attr.toLowerCase(), pname.toLowerCase(), description.toLowerCase(), attr.includes(".")]);
            }
            root.nixpkgs = out;
            root.nixpkgsState = "ready";
        }
    }

    // Packages matching q, best first: the name exactly, then starting with it, containing
    // it, and last the description. Top-level packages before nested ones (python3Packages.x).
    // The last search and what it matched. Its fields change in place, which doesn't notify,
    // so the launcher's results (a binding calling searchNixpkgs) don't depend on it.
    readonly property var lastNix: ({ q: "", matched: [] })
    onNixpkgsChanged: {
        lastNix.q = "";
        lastNix.matched = [];
    }

    function searchNixpkgs(q: string, limit: int): var {
        q = q.toLowerCase();
        if (q.length < 2)
            return [];
        // A longer query only matches what the shorter one did, so narrow those down
        // instead of going through all of nixpkgs again. Below three characters descriptions
        // don't count, so that's where it starts.
        const from = lastNix.q.length >= 3 && q.startsWith(lastNix.q) ? lastNix.matched : nixpkgs;
        const matched = [];
        const out = [];
        for (const p of from) {
            const attr = p[4];
            const pname = p[5];
            let sc = 0;
            if (attr === q || pname === q)
                sc = 100;
            else if (attr.startsWith(q) || pname.startsWith(q))
                sc = 80;
            else if (attr.includes(q) || pname.includes(q))
                sc = 60;
            else if (q.length >= 3 && p[6].includes(q))
                sc = 20;
            if (!sc)
                continue;
            matched.push(p);
            if (p[7])
                sc -= 30;
            out.push({ pkg: p, score: sc });
        }
        lastNix.q = q;
        lastNix.matched = matched;
        return out.sort((a, b) => b.score - a.score || a.pkg[0].length - b.pkg[0].length || a.pkg[0].localeCompare(b.pkg[0])).slice(0, limit);
    }

    // Packages started with "#" whose store path is still there (the garbage collector
    // hasn't removed them), so they start without downloading: attrs, last started first.
    // Each start is recorded in nix-runs.tsv as "attr<TAB>store path<TAB>time".
    property var nixCached: []
    readonly property string nixRunsPath: `${stateDir}/nix-runs.tsv`

    function checkNixCached(): void {
        if (!cachedCheck.running)
            cachedCheck.running = true;
    }

    Process {
        id: cachedCheck

        // Keeps the newest start of each package whose store path is still there (dropping
        // what the garbage collector removed), newest first, and prints that.
        command: ["sh", "-c", `[ -f "$1" ] || exit 0
while IFS="$(printf '\t')" read -r a p t; do
    [ -n "$p" ] && [ -e "$p" ] && printf '%s\t%s\t%s\n' "$a" "$p" "$t"
done < "$1" | sort -t "$(printf '\t')" -k3,3nr | awk -F '\t' '!seen[$1]++' > "$1.tmp" && mv "$1.tmp" "$1"
cat "$1"`, "sh", root.nixRunsPath]

        stdout: StdioCollector {
            onStreamFinished: root.nixCached = text.split("\n").map(l => l.split("\t")[0]).filter(a => a)
        }
    }

    // A package's entry in the index, or a bare one while the index isn't loaded.
    function nixPackage(attr: string): var {
        return nixpkgs.find(p => p[0] === attr) ?? [attr, "", "", "", attr.toLowerCase(), "", "", attr.includes(".")];
    }

    // Starts a package with nix run, in a terminal or not. A notification says it's starting
    // (the first start downloads it), and why if it fails within half a minute. Unfree
    // packages are allowed: picking one is asking for it. Its store path is recorded on the
    // side, for the list of cached packages.
    function runNix(attr: string, terminal: bool): void {
        const record = `( p=$(nix eval --raw "nixpkgs#$1.outPath" 2>/dev/null || NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --raw "nixpkgs#$1.outPath" 2>/dev/null) && printf '%s\t%s\t%s\n' "$1" "$p" "$(date +%s)" >> "$2" ) &`;
        if (terminal) {
            Quickshell.execDetached([Quickshell.env("TERMINAL") || "kitty", "-e", "sh", "-c", `${record}
nix run "nixpkgs#$1" || NIXPKGS_ALLOW_UNFREE=1 nix run --impure "nixpkgs#$1"
exec "\${SHELL:-sh}"`, "sh", attr, nixRunsPath]);
            return;
        }
        Quickshell.execDetached(["sh", "-c", `${record}
notify-send -a moqs -i nix-snowflake "Starting $1" "From nixpkgs. The first start downloads it."
start=$(date +%s)
err=$(nix run "nixpkgs#$1" 2>&1 >/dev/null) && exit 0
case "$err" in *unfree*) err=$(NIXPKGS_ALLOW_UNFREE=1 nix run --impure "nixpkgs#$1" 2>&1 >/dev/null) && exit 0 ;; esac
[ $(( $(date +%s) - start )) -lt 30 ] && notify-send -a moqs -i dialog-error "Couldn't start $1" "$(printf '%s' "$err" | grep -v '^warning' | tail -n 3)"`, "sh", attr, nixRunsPath]);
    }

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
