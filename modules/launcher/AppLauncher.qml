import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.modules.controlcentre as CC
import qs.modules.matrix as MX
import qs.modules
import qs.modules.vocab
import qs.services

// App launcher that grows out of the middle of the bar. Typing filters the apps, the ones
// used most first, with matching Matrix rooms and recent files among them; Enter or a click
// starts or opens one, arrows (or Tab) move, Escape closes. A first character switches mode:
//   = calculate or convert units ("5 km in mi"; Enter copies), or start a timer ("10m tea")
//   ! run a command (Shift+Enter in a terminal)
//   > Home Assistant ("desk lamp off", "desk lamp 40", "heater 21", "lights off")
//   ? search the web or open a URL  : find an emoji (Enter copies)
//   ; vocabulary practice ("+word = translation" adds one, Ctrl+Delete removes)
//   / recent files                  # nixpkgs, started with nix run (Shift+Enter in a terminal)
//   @ send a Matrix message: "@room message" (Enter sends; without a message, opens the room)
//   , open windows by title or app, the last used first (Enter goes to it)
Item {
    id: root

    property bool open
    signal closed

    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay).sort((a, b) => a.name.localeCompare(b.name))

    // How well an app matches the query: higher is better, 0 is no match.
    function score(app: DesktopEntry, q: string): int {
        const name = app.name.toLowerCase();
        if (name === q)
            return 100;
        if (name.startsWith(q))
            return 90;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 80;
        if (name.includes(q))
            return 70;
        const extra = [app.genericName, app.id, ...app.keywords].join(" ").toLowerCase();
        if (extra.includes(q))
            return 50;
        if (app.comment.toLowerCase().includes(q))
            return 30;
        // Letters in order, e.g. "ffx" for Firefox.
        let i = 0;
        for (const c of name)
            if (c === q[i])
                i++;
        return i === q.length ? 10 : 0;
    }

    readonly property string query: search.text.trim()
    // "apps", "calc" or "run", from the first character.
    readonly property var prefixes: ({ "=": "calc", "!": "run", ">": "hass", "?": "web", ":": "emoji", ";": "vocab", "/": "file", "#": "nix", "@": "reply", ",": "win" })
    readonly property string mode: prefixes[query.charAt(0)] ?? "apps"
    // "#" loads (and, if it's old, rebuilds) the nixpkgs index. Searching its 100 000-odd
    // packages waits for a pause in typing, so keys don't lag.
    onModeChanged: {
        // ";" asks a word; typing goes to its field.
        if (mode === "vocab") {
            vocabSession.start();
            // Once the card is shown; a hidden field can't take the focus.
            Qt.callLater(quiz.focusInput);
        } else {
            vocabSession.stop();
        }
        if (mode === "nix") {
            Launcher.indexNixpkgs();
            Launcher.checkNixCached();
        }
        // ">" lists every entity, with its state as of now.
        if (mode === "hass")
            HomeAssistant.loadAll();
        // "," lists the windows, with their classes and focus order from Hyprland.
        if (mode === "win")
            Hyprland.refreshToplevels();
    }
    onRestChanged: if (mode === "nix")
        nixTimer.restart()
    // The Home Assistant camera whose picture shows (Enter on it in ">"), or "". Typing,
    // Escape or Enter closes it.
    property string camera
    property int frame
    onQueryChanged: camera = ""
    property string nixQuery

    Timer {
        id: nixTimer

        interval: 120
        onTriggered: root.nixQuery = root.rest.toLowerCase()
    }
    // The query without its mode character.
    readonly property string rest: mode === "apps" ? query : query.slice(1).trim()

    // Recent files whose name contains q, newest first: [{ kind: "file", file, score }]
    function files(q: string, limit: int, base: real): var {
        const out = [];
        for (const f of Launcher.recentFiles) {
            const name = f.name.toLowerCase();
            const i = q ? name.indexOf(q) : 0;
            if (i < 0)
                continue;
            out.push({ kind: "file", file: f, score: base + (i === 0 ? 5 : 0) });
            if (out.length >= limit)
                break;
        }
        return out;
    }

    // What the list shows: [{ kind: "app" | "room" | "file" | "calc" | "run" | "web" | "url"
    // | "emoji", … }]; nothing for ";", which shows a card instead.
    readonly property var shown: {
        const q = rest.toLowerCase();
        switch (mode) {
        case "calc": {
            // A time ("10m", "1h30 tea") starts a timer.
            const t = Timers.parse(rest);
            if (t)
                return [{ kind: "timer", ms: t.ms, label: t.label }];
            const c = Launcher.convert(rest);
            if (c)
                return [{ kind: "calc", expr: rest, result: c.error ? "" : Launcher.formatNumber(Number(c.value.toPrecision(7))), unit: c.unit ?? "", error: c.error ?? "" }];
            const v = Launcher.calculate(rest);
            return [{ kind: "calc", expr: rest, result: isNaN(v) ? "" : Launcher.formatNumber(v), unit: "", error: "" }];
        }
        case "win": {
            // Not the windows a Steam game waits behind (GameGate).
            const wins = Hyprland.toplevels.values.filter(t => t.lastIpcObject?.class !== undefined && t.workspace?.name !== GameGate.hideaway);
            const out = [];
            for (const t of wins) {
                const ipc = t.lastIpcObject;
                const entry = DesktopEntries.heuristicLookup(ipc.class ?? "");
                const app = entry?.name ?? ipc.class ?? "";
                const title = (t.title || ipc.title || "").toLowerCase();
                const n = app.toLowerCase();
                const sc = !q ? 50 : title.startsWith(q) || n.startsWith(q) ? 90 : title.split(/[\s\-_.—|:]+/).some(w => w.startsWith(q)) || n.split(/[\s\-_.]+/).some(w => w.startsWith(q)) ? 80 : title.includes(q) || n.includes(q) || (ipc.class ?? "").toLowerCase().includes(q) ? 70 : 0;
                if (sc)
                    out.push({ kind: "win", win: t, app, icon: entry?.icon ?? ipc.class ?? "", recent: ipc.focusHistoryID ?? 999, score: sc });
            }
            if (!out.length)
                return [{ kind: "wininfo" }];
            // The last used first, but the one in focus now last: Enter alone goes back to
            // the one before, as Alt+Tab would.
            const order = w => w.recent === 0 ? 9999 : w.recent;
            return out.sort((a, b) => b.score - a.score || order(a) - order(b));
        }
        case "reply": {
            if (!Matrix.configured)
                return [{ kind: "replyinfo" }];
            Matrix.version;
            const found = Matrix.replyTargets(rest);
            return found.length ? found.map(x => ({ kind: "reply", room: x.room, message: x.message })) : [{ kind: "replyinfo" }];
        }
        case "hass": {
            if (!HomeAssistant.configured)
                return [{ kind: "hassinfo" }];
            const found = HomeAssistant.commands(rest);
            return found.length ? found.map(c => ({ kind: "hass", cmd: c })) : [{ kind: "hassinfo" }];
        }
        case "run":
            return [{ kind: "run", command: rest }];
        case "web": {
            const out = [];
            // Something like a web address: open it as well.
            if (/^(https?:\/\/)?[\w-]+(\.[\w-]+)+(:\d+)?(\/\S*)?$/i.test(rest))
                out.push({ kind: "url", url: /^https?:\/\//i.test(rest) ? rest : `https://${rest}` });
            out.push({ kind: "web", text: rest });
            return out;
        }
        case "emoji": {
            if (!q)
                return Launcher.emoji.slice(0, 60).map(e => ({ kind: "emoji", emoji: e }));
            const words = q.split(/\s+/);
            const out = [];
            for (const e of Launcher.emoji) {
                const aliases = e[2].split(" ");
                const name = e[1].toLowerCase();
                let sc = 0;
                if (aliases.includes(q.replace(/:/g, "")))
                    sc = 100;
                else if (words.every(w => aliases.some(a => a.startsWith(w)) || name.split(/[\s-]+/).some(n => n.startsWith(w))))
                    sc = 50;
                else if (words.every(w => name.includes(w) || e[3].includes(w)))
                    sc = 20;
                if (sc)
                    out.push({ kind: "emoji", emoji: e, score: sc });
            }
            return out.sort((a, b) => b.score - a.score).slice(0, 60);
        }
        case "vocab":
            return [];
        case "file":
            return files(q, 60, 0);
        case "nix": {
            // Nothing typed: the packages still in the store, which start right away.
            if (rest === "") {
                Launcher.nixpkgs;
                const cached = Launcher.nixCached.map(a => ({ kind: "nix", pkg: Launcher.nixPackage(a), cached: true }));
                return cached.length ? cached : [{ kind: "nixinfo" }];
            }
            if (Launcher.nixpkgsState !== "ready")
                return [{ kind: "nixinfo" }];
            if (nixQuery.length < 2)
                return [{ kind: "nixinfo" }];
            const found = Launcher.searchNixpkgs(nixQuery, 50);
            return found.length ? found.map(x => ({ kind: "nix", pkg: x.pkg })) : [{ kind: "nixinfo" }];
        }
        }

        Launcher.usage;
        if (!q)
            return apps.map(a => ({ kind: "app", app: a, score: Launcher.boost(a.id) })).sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name));
        const out = [];
        for (const a of apps) {
            const sc = score(a, q);
            if (sc > 0)
                out.push({ kind: "app", app: a, score: sc + Launcher.boost(a.id) });
        }
        // Rooms whose name starts with the query, or a word in it does.
        if (q.length >= 2 && Matrix.configured) {
            Matrix.version;
            let rooms = 0;
            for (const r of Matrix.findRooms(q)) {
                const name = Matrix.roomName(r).toLowerCase();
                const sc = name.startsWith(q) ? 85 : name.split(/[\s\-_.]+/).some(w => w.startsWith(q)) ? 75 : 0;
                if (sc && rooms++ < 4)
                    out.push({ kind: "room", room: r, score: sc });
            }
        }
        // A few recent files, below good app matches.
        if (q.length >= 3)
            out.push(...files(q, 3, 55));
        return out.sort((a, b) => b.score - a.score || root.title(a).localeCompare(root.title(b)));
    }

    function copy(text: string): void {
        // wl-copy rather than Quickshell.clipboardText: the clipboard needs a focused window,
        // and the launcher's goes away as it closes.
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    // Starts, opens, copies or runs a row. In a terminal: commands only, with Shift+Enter.
    function activate(item: var, terminal: bool): void {
        if (!item)
            return;
        switch (item.kind) {
        case "app":
            Launcher.used(item.app.id);
            item.app.execute();
            break;
        case "room":
            root.closed();
            // Opens the Matrix panel on the room, with the message field ready.
            Matrix.replyRequested(item.room.meta.room_id);
            return;
        case "file":
            Qt.openUrlExternally(item.file.url);
            break;
        case "calc":
            if (!item.result)
                return;
            copy(item.result);
            break;
        case "timer":
            Timers.start(item.ms, item.label);
            break;
        case "run":
            if (!item.command)
                return;
            if (terminal)
                Quickshell.execDetached([Quickshell.env("TERMINAL") || "kitty", "-e", "sh", "-c", `${item.command}; exec "\${SHELL:-sh}"`]);
            else
                Quickshell.execDetached(["sh", "-c", item.command]);
            break;
        case "web":
            if (!item.text)
                return;
            Qt.openUrlExternally(Settings.search.replace("%s", encodeURIComponent(item.text)));
            break;
        case "url":
            Qt.openUrlExternally(item.url);
            break;
        case "emoji":
            copy(item.emoji[0]);
            break;
        case "nix":
            Launcher.runNix(item.pkg[0], terminal);
            break;
        case "hass":
            if (item.cmd.action === "camera") {
                // Shown here, the launcher stays open.
                camera = item.cmd.entity;
                HomeAssistant.refreshOne(camera);
                return;
            }
            if (item.cmd.action === "copy")
                copy(HomeAssistant.value(item.cmd.entity));
            else
                HomeAssistant.run(item.cmd);
            break;
        case "win":
            Overview.focusWindow(item.win.address);
            break;
        case "wininfo":
            return;
        case "reply":
            if (!item.message) {
                root.closed();
                Matrix.replyRequested(item.room.meta.room_id);
                return;
            }
            Matrix.quickSend(item.room.meta.room_id, item.message);
            break;
        case "nixinfo":
        case "hassinfo":
        case "replyinfo":
            return;
        }
        root.closed();
    }

    // The row's main text, and the grey one beside it.
    function title(item: var): string {
        switch (item.kind) {
        case "app":
            return item.app.name;
        case "room":
            return Matrix.roomName(item.room);
        case "file":
            return item.file.name;
        case "calc":
            return item.result ? `= ${item.result}${item.unit ? " " + item.unit : ""}` : item.error || (item.expr ? "…" : "Type a calculation or 5 km in mi");
        case "timer":
            return `Start a ${Timers.format(item.ms)} timer${item.label ? ` · ${item.label}` : ""}`;
        case "run":
            return item.command || "Type a command";
        case "web":
            return item.text ? `Search for "${item.text}"` : "Type to search the web";
        case "url":
            return item.url.replace(/^https?:\/\//i, "");
        case "emoji":
            return item.emoji[1].charAt(0).toUpperCase() + item.emoji[1].slice(1);
        case "nix":
            return item.pkg[0];
        case "win":
            return item.win.title || item.app;
        case "wininfo":
            return "No window matches";
        case "reply":
            return Matrix.roomName(item.room);
        case "replyinfo":
            return Matrix.configured ? "No room matches" : "Matrix isn't set up";
        case "hass":
            return item.cmd.name;
        case "hassinfo":
            if (!HomeAssistant.configured)
                return "Home Assistant isn't set up";
            if (HomeAssistant.error)
                return HomeAssistant.error;
            return HomeAssistant.allEntities.length ? "Nothing matches" : "Loading…";
        case "nixinfo":
            if (Launcher.nixpkgsState === "failed")
                return "Couldn't index nixpkgs";
            if (Launcher.nixpkgsState !== "ready" && rest !== "")
                return "Indexing nixpkgs…";
            return rest === "" ? "Nothing started from nixpkgs is in the store" : rest.length < 2 ? "Type a package name" : "No package found";
        }
        return "";
    }

    function detail(item: var): string {
        switch (item.kind) {
        case "app":
            return item.app.genericName || item.app.comment;
        case "room": {
            const b = Matrix.bridge(item.room);
            return b ? `Matrix · ${({ discord: "Discord", signal: "Signal", telegram: "Telegram", whatsapp: "WhatsApp" })[b]}` : "Matrix";
        }
        case "file":
            return item.file.dir;
        case "calc":
            return item.result ? "Enter copies" : "";
        case "timer":
            return "Counts down beside the clock";
        case "run":
            return item.command ? "Enter runs · Shift+Enter in a terminal" : "";
        case "web":
            return item.text ? Settings.search.replace(/^https?:\/\/(www\.)?/, "").replace(/\/.*$/, "") : "";
        case "url":
            return "Open";
        case "emoji":
            return item.emoji[2].split(" ").map(a => `:${a}:`).join(" ");
        case "nix":
            return [item.cached ? "In the store" : "", item.pkg[2], item.pkg[3]].filter(x => x).join(" · ");
        case "win": {
            const ws = item.win.workspace;
            const where = !ws ? "" : ws.name.startsWith("special:") ? `special workspace ${ws.name.slice(8)}` : `workspace ${ws.name}`;
            return [item.app, where, item.recent === 0 ? "in focus" : ""].filter(x => x).join(" · ");
        }
        case "wininfo":
            return "Type part of a window's title or its app";
        case "reply":
            return item.message ? `Enter sends "${item.message}"` : "Type a message · Enter opens the room";
        case "replyinfo":
            return Matrix.configured ? "@room message" : "";
        case "hass":
            return item.cmd.detail;
        case "hassinfo":
            return HomeAssistant.configured ? "A name, then on, off or a number" : "Add url and token to hass.json";
        case "nixinfo":
            if (Launcher.nixpkgsState === "failed")
                return Launcher.nixpkgsError;
            if (rest === "")
                return "Type a package name to search nixpkgs";
            if (Launcher.nixpkgsState !== "ready")
                return "The first time after a nixpkgs update takes a minute";
            return rest.length < 2 ? "Enter starts it with nix run · Shift+Enter in a terminal" : "";
        }
        return "";
    }

    // Glyph for rows without an app icon, avatar or emoji.
    readonly property var glyphs: ({ calc: "\u{F00EC}", timer: "\u{F13AB}", run: "\u{F018D}", web: "\u{F0349}", url: "\u{F059F}", nix: "\u{F1105}", nixinfo: "\u{F1105}", hassinfo: "\u{F07D0}", replyinfo: "\u{F0368}", wininfo: "\u{F05AF}" })

    readonly property int rowHeight: Config.launcher.row
    readonly property real targetWidth: open ? Config.launcher.width : Config.launcher.seed
    readonly property real targetHeight: open ? content.implicitHeight : 0

    // VocabSession for the ";" pane.
    VocabSession {
        id: vocabSession
    }

    // Opened with text already in the search, e.g. ";" (Launcher.showWith).
    Connections {
        target: Launcher

        function onInitialChanged(): void {
            if (root.open && Launcher.initial) {
                search.text = Launcher.initial;
                Launcher.initial = "";
            }
        }
    }

    onOpenChanged: {
        if (open) {
            search.text = Launcher.initial;
            Launcher.initial = "";
            list.currentIndex = 0;
            list.positionViewAtBeginning();
            search.forceActiveFocus();
        }
    }

    width: targetWidth
    height: targetHeight
    visible: height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    CC.Background {
        anchors.fill: parent
    }

    // Content keeps its full width while the panel animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.launcher.width - Config.launcher.padding * 2
            spacing: Config.launcher.padding
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            Item {
                implicitHeight: 0
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: height / 2
                color: Config.colours.button

                Text {
                    id: searchIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0349}"
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.icon
                }

                TextInput {
                    id: search

                    anchors.left: searchIcon.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    color: Config.colours.text
                    selectionColor: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    clip: true

                    onTextChanged: list.currentIndex = 0
                    Keys.onReturnPressed: event => root.camera ? root.camera = "" : root.activate(root.shown[list.currentIndex], event.modifiers & Qt.ShiftModifier)
                    Keys.onEnterPressed: event => root.camera ? root.camera = "" : root.activate(root.shown[list.currentIndex], event.modifiers & Qt.ShiftModifier)
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: root.camera ? root.camera = "" : root.closed()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search apps, rooms and files"
                        color: Config.colours.muted
                        font: search.font
                    }
                }
            }

            VocabQuiz {
                id: quiz

                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                visible: root.mode === "vocab"
                session: vocabSession
                manage: true
                onEscaped: root.closed()
                onBackedOut: {
                    search.text = "";
                    search.forceActiveFocus();
                }
            }

            // A Home Assistant camera's picture, a new frame every second.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                visible: root.camera !== ""
                spacing: 6

                Timer {
                    running: root.camera !== "" && root.open
                    repeat: true
                    interval: 1000
                    onTriggered: {
                        root.frame++;
                        // A new token now and then; Home Assistant changes it every few minutes.
                        if (root.frame % 60 === 0)
                            HomeAssistant.refreshOne(root.camera);
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: width * 9 / 16
                    radius: 14
                    color: Config.colours.button
                    clip: true

                    // Two pictures taking turns, so the old frame stays until the new one is in:
                    // one loads the even frames, the other the odd ones.
                    Shot {
                        id: shotA

                        mine: root.frame - root.frame % 2
                        other: shotB
                    }

                    Shot {
                        id: shotB

                        mine: Math.max(0, root.frame - (root.frame + 1) % 2)
                        other: shotA
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !HomeAssistant.cameraUrl(root.camera, 0)
                        text: HomeAssistant.state(root.camera)?.state === "unavailable" ? "The camera is unavailable" : "Loading…"
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: `${HomeAssistant.name({ entity: root.camera, name: "" })} · Esc or Enter closes`
                    elide: Text.ElideRight
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }

            ListView {
                id: list

                SmoothScroll {
                    flickable: list
                }

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(count, Config.launcher.shown) * root.rowHeight + Math.max(0, Math.min(count, Config.launcher.shown) - 1) * spacing
                visible: count > 0 && !root.camera
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationWraps: true
                model: root.shown

                Behavior on Layout.preferredHeight {
                    Anim {}
                }

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    readonly property string kind: modelData.kind

                    width: list.width
                    height: root.rowHeight
                    radius: height / 2
                    color: current ? Config.colours.button : area.containsMouse ? Config.colours.buttonHover : "transparent"

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => root.activate(row.modelData, mouse.modifiers & Qt.ShiftModifier)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 14
                        spacing: 12

                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28

                            IconImage {
                                anchors.fill: parent
                                visible: row.kind === "app"
                                source: row.kind === "app" ? Quickshell.iconPath(row.modelData.app.icon, "application-x-executable") : ""
                                asynchronous: true
                            }

                            MX.Avatar {
                                anchors.fill: parent
                                readonly property bool shown: row.kind === "room" || row.kind === "reply"

                                visible: shown
                                name: shown ? Matrix.roomName(row.modelData.room) : ""
                                source: shown ? Matrix.mediaUrl(row.modelData.room.meta.avatar ?? "", false) : ""
                            }

                            IconImage {
                                anchors.fill: parent
                                visible: row.kind === "win"
                                source: row.kind === "win" ? Quickshell.iconPath(row.modelData.icon, "application-x-executable") : ""
                                asynchronous: true
                            }

                            IconImage {
                                anchors.fill: parent
                                visible: row.kind === "file"
                                source: row.kind === "file" ? Quickshell.iconPath(Launcher.mimeIcon(row.modelData.file.mime), "text-x-generic") : ""
                                asynchronous: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: row.kind === "emoji"
                                text: row.kind === "emoji" ? row.modelData.emoji[0] : ""
                                font.family: "Noto Color Emoji"
                                font.pointSize: Config.font.icon + 2
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: text !== ""
                                text: row.kind === "hass" ? row.modelData.cmd.glyph : root.glyphs[row.kind] ?? ""
                                color: Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.icon
                            }
                        }

                        Text {
                            readonly property bool placeholder: (row.kind === "calc" && !row.modelData.result) || (row.kind === "run" && !row.modelData.command) || (row.kind === "web" && !row.modelData.text) || row.kind === "nixinfo" || row.kind === "hassinfo" || row.kind === "replyinfo" || row.kind === "wininfo"

                            Layout.maximumWidth: list.width * 0.6
                            text: root.title(row.modelData)
                            elide: Text.ElideRight
                            color: placeholder ? Config.colours.subtext : Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.size
                            font.bold: row.kind === "calc" && row.modelData.result !== ""
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.detail(row.modelData)
                            horizontalAlignment: ["calc", "run", "url", "hass"].includes(row.kind) ? Text.AlignRight : Text.AlignLeft
                            elide: row.kind === "file" ? Text.ElideMiddle : Text.ElideRight
                            color: Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                visible: list.count === 0 && root.mode !== "vocab"
                text: root.mode === "file" ? "No recent files match" : "Nothing matches"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            // What the first characters do, while nothing is typed.
            Text {
                Layout.fillWidth: true
                visible: root.query === ""
                horizontalAlignment: Text.AlignHCenter
                text: "= calc/timer   ! run   > home   ? web   : emoji   ; words   / files   # nixpkgs   @ reply"
                color: Config.colours.muted
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Item {
                implicitHeight: 0
            }
        }
    }

    // One of the camera preview's two pictures.
    component Shot: Image {
        property int mine
        property Image other

        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        source: root.camera ? HomeAssistant.cameraUrl(root.camera, mine) : ""
        visible: status === Image.Ready && (mine === root.frame || other.status !== Image.Ready)
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
