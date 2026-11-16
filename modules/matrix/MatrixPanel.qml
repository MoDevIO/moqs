import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

// Matrix client in the bottom-right corner: rooms, then a conversation with a message field.
Item {
    id: root

    property bool open: false
    property string roomId

    readonly property real targetWidth: open ? Config.matrix.width : 0
    readonly property real targetHeight: open ? Config.matrix.height : 0

    readonly property var room: {
        Matrix.version;
        return roomId ? Matrix.rooms[roomId] ?? null : null;
    }

    // Shown messages of the open room, newest last: [{ evt, text, own, first }]
    readonly property var messages: {
        Matrix.version;
        const out = [];
        let prev = "";
        for (const rowid of room?.timeline ?? []) {
            const evt = Matrix.events[rowid];
            const text = Matrix.text(evt);
            if (!text)
                continue;
            out.push({ evt, text, own: evt.sender === Matrix.userId, first: evt.sender !== prev });
            prev = evt.sender;
        }
        return out;
    }

    readonly property string statusText: {
        if (!Matrix.configured)
            return "";
        if (!Matrix.loggedIn)
            return `Log in at ${Matrix.url} first`;
        if (Matrix.status === "error")
            return Matrix.error || "Can't reach gomuks";
        if (Matrix.status !== "ready")
            return "Syncing…";
        return "";
    }

    function openRoom(id: string): void {
        roomId = id;
        const r = Matrix.rooms[id];
        if ((r?.timeline.length ?? 0) < 30)
            Matrix.paginate(id);
        Matrix.markRead(id);
        Matrix.loadMembers(id);
        input.forceActiveFocus();
    }

    function time(ts: real): string {
        const d = new Date(ts);
        return new Date().toDateString() === d.toDateString() ? Qt.formatTime(d, "HH:mm") : Qt.formatDate(d, "d MMM");
    }

    // Keep the open room marked as read while new messages arrive.
    onMessagesChanged: if (open && roomId) readDelay.restart()

    width: targetWidth
    height: targetHeight
    visible: width > 0 && height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    Timer {
        id: readDelay

        interval: 500
        onTriggered: Matrix.markRead(root.roomId)
    }

    Background {
        anchors.fill: parent
    }

    // Content keeps its full size while the panel animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Config.matrix.width
            height: Config.matrix.height
            spacing: Config.controlCentre.spacing
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Config.controlCentre.padding + 4
                Layout.leftMargin: Config.controlCentre.padding + 6
                Layout.rightMargin: Config.controlCentre.padding + 6
                spacing: 10

                Text {
                    visible: root.roomId !== ""
                    text: "\u{F0141}"
                    color: back.containsMouse ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size

                    MouseArea {
                        id: back

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.roomId = ""
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.room ? Matrix.roomName(root.room) : "Matrix"
                    elide: Text.ElideRight
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    font.bold: true
                }

                Text {
                    visible: text !== ""
                    text: root.room?.meta?.encryption_event ? "\u{F033E}" : ""
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }

            // Setup hint, connection problems
            Text {
                Layout.fillWidth: true
                Layout.fillHeight: !Matrix.configured
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                visible: text !== ""
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: !Matrix.configured ? `Run gomuks-web, log in at http://localhost:29325, then create ${Quickshell.shellPath("matrix.json")}:\n\n{\n  "url": "http://localhost:29325",\n  "username": "gomuks web user",\n  "password": "…"\n}\n\n("passwordCommand" works instead of "password".)` : root.statusText
                color: Matrix.status === "error" && Matrix.configured ? "#ff6b6b" : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            // Rooms
            ListView {
                id: rooms

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                Layout.bottomMargin: Config.controlCentre.padding
                visible: Matrix.configured && !root.roomId
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: Matrix.roomList

                delegate: Rectangle {
                    id: roomRow

                    required property var modelData
                    readonly property var meta: modelData.meta
                    readonly property int unread: meta.unread_messages ?? 0
                    readonly property bool highlight: (meta.unread_highlights ?? 0) > 0
                    readonly property var preview: {
                        Matrix.version;
                        return Matrix.events[meta.preview_event_rowid];
                    }

                    width: rooms.width
                    implicitHeight: 48
                    radius: 14
                    color: roomArea.containsMouse ? Config.colours.buttonHover : "transparent"

                    MouseArea {
                        id: roomArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openRoom(roomRow.meta.room_id)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 12
                        spacing: 10

                        Avatar {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            name: Matrix.roomName(roomRow.modelData)
                            source: Matrix.mediaUrl(roomRow.meta.avatar ?? "")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: Matrix.roomName(roomRow.modelData)
                                elide: Text.ElideRight
                                color: Config.colours.text
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                                font.bold: roomRow.unread > 0
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: {
                                    const p = roomRow.preview;
                                    const t = Matrix.text(p);
                                    return t ? `${Matrix.senderName(roomRow.meta.room_id, p.sender)}: ${t.split("\n")[0]}` : "";
                                }
                                elide: Text.ElideRight
                                color: Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                            }
                        }

                        // Unread badge; white when you're mentioned
                        Rectangle {
                            visible: roomRow.unread > 0
                            implicitWidth: Math.max(20, count.implicitWidth + 10)
                            implicitHeight: 20
                            radius: 10
                            color: roomRow.highlight ? Config.colours.active : Config.colours.button

                            Text {
                                id: count

                                anchors.centerIn: parent
                                text: roomRow.unread > 99 ? "99+" : roomRow.unread
                                color: roomRow.highlight ? Config.colours.activeText : Config.colours.text
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                            }
                        }
                    }
                }
            }

            // Conversation, newest at the bottom
            ListView {
                id: timeline

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                visible: !!root.room
                clip: true
                spacing: 2
                verticalLayoutDirection: ListView.BottomToTop
                boundsBehavior: Flickable.StopAtBounds
                model: [...root.messages].reverse()

                // Older messages when scrolled to the top.
                onAtYEndChanged: if (atYEnd && root.roomId) Matrix.paginate(root.roomId)

                delegate: Column {
                    id: msg

                    required property var modelData
                    // Room for the avatar beside others' messages.
                    readonly property int indent: modelData.own ? 0 : 32

                    width: timeline.width
                    topPadding: modelData.first ? 8 : 0
                    spacing: 2

                    Text {
                        visible: msg.modelData.first && !msg.modelData.own
                        leftPadding: msg.indent + 10
                        text: Matrix.senderName(root.roomId, msg.modelData.evt.sender)
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                        font.bold: true
                    }

                    Rectangle {
                        anchors.right: msg.modelData.own ? parent.right : undefined
                        x: msg.indent
                        width: Math.min(body.implicitWidth, timeline.width * 0.8 - msg.indent) + 24
                        height: body.implicitHeight + 14
                        radius: 14
                        color: msg.modelData.own ? Config.colours.active : Config.colours.card

                        Text {
                            id: body

                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 7
                            anchors.bottomMargin: 7
                            text: msg.modelData.text
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            color: msg.modelData.own ? Config.colours.activeText : Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                            font.italic: msg.modelData.evt.decrypted_type === undefined && msg.modelData.evt.type === "m.room.encrypted"
                        }

                        // Sender's avatar beside the first message of a run.
                        Avatar {
                            anchors.right: parent.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            width: 24
                            height: 24
                            visible: msg.modelData.first && !msg.modelData.own
                            name: Matrix.senderName(root.roomId, msg.modelData.evt.sender)
                            source: visible ? Matrix.senderAvatar(root.roomId, msg.modelData.evt.sender) : ""
                        }

                        MouseArea {
                            id: bubbleArea

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: msg.modelData.own ? parent.left : undefined
                            anchors.left: msg.modelData.own ? undefined : parent.right
                            anchors.margins: 8
                            visible: bubbleArea.containsMouse
                            text: root.time(msg.modelData.evt.timestamp)
                            color: Config.colours.muted
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }

            // Message field
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                Layout.bottomMargin: Config.controlCentre.padding
                visible: !!root.room
                implicitHeight: Math.max(38, input.implicitHeight + 20)
                radius: 19
                color: Config.colours.card

                TextEdit {
                    id: input

                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    wrapMode: TextEdit.Wrap
                    color: Config.colours.text
                    selectionColor: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small

                    // Enter sends, Shift+Enter adds a line.
                    Keys.onReturnPressed: event => {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                            return;
                        }
                        Matrix.send(root.roomId, text);
                        text = "";
                    }
                    Keys.onEscapePressed: root.roomId = ""

                    Text {
                        visible: !input.text
                        text: "Message"
                        color: Config.colours.muted
                        font: input.font
                    }
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
