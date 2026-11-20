import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.modules.controlcentre as CC
import qs.modules.matrix as MX
import qs.modules
import qs.services

// App launcher that grows out of the middle of the bar. Typing filters the apps, the ones
// used most first, with matching Matrix rooms and recent files among them; Enter or a click
// starts or opens one, arrows (or Tab) move, Escape closes. A first character switches mode:
//   = calculate (Enter copies)      > run a command (Shift+Enter in a terminal)
//   ? search the web or open a URL  : find an emoji (Enter copies)
//   ; snippets (Enter copies; "name: text" saves one, Ctrl+Delete removes)
//   / recent files
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
    readonly property var prefixes: ({ "=": "calc", ">": "run", "?": "web", ":": "emoji", ";": "snippet", "/": "file" })
    readonly property string mode: prefixes[query.charAt(0)] ?? "apps"
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
    // | "emoji" | "snippet" | "save", … }]
    readonly property var shown: {
        const q = rest.toLowerCase();
        switch (mode) {
        case "calc": {
            const v = Launcher.calculate(rest);
            return [{ kind: "calc", expr: rest, result: isNaN(v) ? "" : Launcher.formatNumber(v) }];
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
        case "snippet": {
            const out = Launcher.snippets.filter(x => !q || x.name.toLowerCase().includes(q) || x.text.toLowerCase().includes(q)).map(x => ({ kind: "snippet", snippet: x }));
            // "name: text" saves a snippet.
            const m = rest.match(/^([^:]+?)\s*:\s*(.+)$/);
            if (m)
                out.unshift({ kind: "save", name: m[1], text: m[2] });
            return out;
        }
        case "file":
            return files(q, 60, 0);
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
        case "snippet":
            copy(item.snippet.text);
            break;
        case "save":
            Launcher.addSnippet(item.name, item.text);
            search.text = ";";
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
            return item.result ? `= ${item.result}` : item.expr ? "…" : "Type a calculation";
        case "run":
            return item.command || "Type a command";
        case "web":
            return item.text ? `Search for "${item.text}"` : "Type to search the web";
        case "url":
            return item.url.replace(/^https?:\/\//i, "");
        case "emoji":
            return item.emoji[1].charAt(0).toUpperCase() + item.emoji[1].slice(1);
        case "snippet":
            return item.snippet.name;
        case "save":
            return `Save snippet "${item.name}"`;
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
        case "run":
            return item.command ? "Enter runs · Shift+Enter in a terminal" : "";
        case "web":
            return item.text ? Settings.search.replace(/^https?:\/\/(www\.)?/, "").replace(/\/.*$/, "") : "";
        case "url":
            return "Open";
        case "emoji":
            return item.emoji[2].split(" ").map(a => `:${a}:`).join(" ");
        case "snippet":
            return item.snippet.text.replace(/\n/g, " ⏎ ");
        case "save":
            return item.text;
        }
        return "";
    }

    // Glyph for rows without an app icon, avatar or emoji.
    readonly property var glyphs: ({ calc: "\u{F00EC}", run: "\u{F018D}", web: "\u{F0349}", url: "\u{F059F}", snippet: "\u{F09ED}", save: "\u{F0415}" })

    readonly property int rowHeight: Config.launcher.row
    readonly property real targetWidth: open ? Config.launcher.width : Config.launcher.seed
    readonly property real targetHeight: open ? content.implicitHeight : 0

    onOpenChanged: {
        if (open) {
            search.text = "";
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
                    Keys.onReturnPressed: event => root.activate(root.shown[list.currentIndex], event.modifiers & Qt.ShiftModifier)
                    // Ctrl+Delete removes the selected snippet.
                    Keys.onDeletePressed: event => {
                        const item = root.shown[list.currentIndex];
                        if (event.modifiers & Qt.ControlModifier && item?.kind === "snippet")
                            Launcher.removeSnippet(item.snippet.name);
                        else
                            event.accepted = false;
                    }
                    Keys.onEnterPressed: event => root.activate(root.shown[list.currentIndex], event.modifiers & Qt.ShiftModifier)
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: root.closed()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search apps, rooms and files"
                        color: Config.colours.muted
                        font: search.font
                    }
                }
            }

            ListView {
                id: list

                SmoothScroll {
                    flickable: list
                }

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(count, Config.launcher.shown) * root.rowHeight + Math.max(0, Math.min(count, Config.launcher.shown) - 1) * spacing
                visible: count > 0
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
                                visible: row.kind === "room"
                                name: row.kind === "room" ? Matrix.roomName(row.modelData.room) : ""
                                source: row.kind === "room" ? Matrix.mediaUrl(row.modelData.room.meta.avatar ?? "", false) : ""
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
                                text: root.glyphs[row.kind] ?? ""
                                color: Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.icon
                            }
                        }

                        Text {
                            readonly property bool placeholder: (row.kind === "calc" && !row.modelData.result) || (row.kind === "run" && !row.modelData.command) || (row.kind === "web" && !row.modelData.text)

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
                            horizontalAlignment: ["calc", "run", "url"].includes(row.kind) ? Text.AlignRight : Text.AlignLeft
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
                visible: list.count === 0
                text: root.mode === "snippet" ? "No snippets yet: type ;name: text to save one" : root.mode === "file" ? "No recent files match" : "Nothing matches"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            // What the first characters do, while nothing is typed.
            Text {
                Layout.fillWidth: true
                visible: root.query === ""
                horizontalAlignment: Text.AlignHCenter
                text: "= calc   > run   ? web   : emoji   ; snippets   / files"
                color: Config.colours.muted
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Item {
                implicitHeight: 0
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
