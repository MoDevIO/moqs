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
// used most first, with matching Matrix rooms among them; Enter or a click starts or opens
// one, arrows (or Tab) move, Escape closes. "=" calculates (Enter copies the result), ">"
// runs a command (Shift+Enter in a terminal).
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
    readonly property string mode: query.startsWith("=") ? "calc" : query.startsWith(">") ? "run" : "apps"

    // What the list shows: [{ kind: "app" | "room" | "calc" | "run", … }]
    readonly property var shown: {
        if (mode === "calc") {
            const expr = query.slice(1).trim();
            const v = Launcher.calculate(expr);
            return [{ kind: "calc", expr, result: isNaN(v) ? "" : Launcher.formatNumber(v) }];
        }
        if (mode === "run")
            return [{ kind: "run", command: query.slice(1).trim() }];

        const q = query.toLowerCase();
        Launcher.usage;
        if (!q)
            return apps.map(a => ({ kind: "app", app: a, score: Launcher.boost(a.id) })).sort((a, b) => b.score - a.score);
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
        return out.sort((a, b) => b.score - a.score);
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
        case "calc":
            if (!item.result)
                return;
            Quickshell.execDetached(["wl-copy", "--", item.result]);
            break;
        case "run":
            if (!item.command)
                return;
            if (terminal)
                Quickshell.execDetached([Quickshell.env("TERMINAL") || "kitty", "-e", "sh", "-c", `${item.command}; exec "\${SHELL:-sh}"`]);
            else
                Quickshell.execDetached(["sh", "-c", item.command]);
            break;
        }
        root.closed();
    }

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
                    Keys.onEnterPressed: event => root.activate(root.shown[list.currentIndex], event.modifiers & Qt.ShiftModifier)
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: root.closed()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Apps and rooms  ·  = calculate  ·  > run"
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

                            // Calculator and command
                            Text {
                                anchors.centerIn: parent
                                visible: row.kind === "calc" || row.kind === "run"
                                text: row.kind === "calc" ? "\u{F00EC}" : "\u{F018D}"
                                color: Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.icon
                            }
                        }

                        Text {
                            Layout.maximumWidth: list.width * 0.6
                            text: {
                                switch (row.kind) {
                                case "app":
                                    return row.modelData.app.name;
                                case "room":
                                    return Matrix.roomName(row.modelData.room);
                                case "calc":
                                    return row.modelData.result ? `= ${row.modelData.result}` : row.modelData.expr ? "…" : "Type a calculation";
                                default:
                                    return row.modelData.command || "Type a command";
                                }
                            }
                            elide: Text.ElideRight
                            color: (row.kind === "calc" && !row.modelData.result) || (row.kind === "run" && !row.modelData.command) ? Config.colours.subtext : Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.size
                            font.bold: row.kind === "calc" && row.modelData.result !== ""
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                switch (row.kind) {
                                case "app":
                                    return row.modelData.app.genericName || row.modelData.app.comment;
                                case "room": {
                                    const b = Matrix.bridge(row.modelData.room);
                                    return b ? `Matrix · ${({ discord: "Discord", signal: "Signal", telegram: "Telegram", whatsapp: "WhatsApp" })[b]}` : "Matrix";
                                }
                                case "calc":
                                    return row.modelData.result ? "Enter copies" : "";
                                default:
                                    return row.modelData.command ? "Enter runs · Shift+Enter in a terminal" : "";
                                }
                            }
                            horizontalAlignment: row.kind === "app" || row.kind === "room" ? Text.AlignLeft : Text.AlignRight
                            elide: Text.ElideRight
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
                text: "Nothing matches"
                color: Config.colours.subtext
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
