import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.services

// Matrix client in the bottom-right corner: rooms, then a conversation with a message field.
Item {
    id: root

    required property ShellScreen screen
    property bool open: false
    property string roomId
    // Opened by a notification's Reply: the frame then takes the keyboard so the message field
    // gets typing straight away, until the panel closes.
    property bool replying
    // Keeps the panel open after a Reply until the pointer has arrived on it: on the way the
    // pointer leaves the frame (the clicked popup vanishes), which would otherwise close it.
    property bool holdOpen
    // Room list search: filters rooms by name and searches messages.
    property string query

    readonly property real targetWidth: open ? Config.matrix.width : 0
    readonly property real targetHeight: open ? Config.matrix.height : 0

    readonly property var room: {
        Matrix.version;
        return roomId ? Matrix.rooms[roomId] ?? null : null;
    }

    // Shown messages of the open room, newest last: [{ evt, text, image, own, first }]
    readonly property var messages: {
        Matrix.version;
        const out = [];
        let prev = "";
        // gomuks's timeline, then messages just sent that it doesn't have yet.
        const pending = (room?.pending ?? []).filter(rowid => !(room?.timeline ?? []).includes(rowid));
        for (const rowid of [...(room?.timeline ?? []), ...pending]) {
            const evt = Matrix.events[rowid];
            if (!evt)
                continue;
            const image = Matrix.image(evt);
            const text = image ? Matrix.caption(evt) : Matrix.text(evt);
            if (!text && !image)
                continue;
            out.push({ evt, text, image, own: evt.sender === Matrix.userId, first: evt.sender !== prev });
            prev = evt.sender;
        }
        return out;
    }

    // The message whose reaction picker is open.
    property string pickerFor
    readonly property list<string> quickReactions: ["👍", "❤️", "😂", "😮", "😢", "🎉"]

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

    function clearSearch(): void {
        search.text = "";
    }

    function openRoom(id: string): void {
        roomId = id;
        pickerFor = "";
        Matrix.markRead(id);
        Matrix.loadMembers(id);
        input.forceActiveFocus();
    }

    function time(ts: real): string {
        const d = new Date(ts);
        return new Date().toDateString() === d.toDateString() ? Qt.formatTime(d, "HH:mm") : Qt.formatDate(d, "d MMM");
    }

    onOpenChanged: {
        Matrix.panelOpen = open;
        if (!open) {
            replying = false;
            holdOpen = false;
        }
    }

    HoverHandler {
        onHoveredChanged: if (hovered) root.holdOpen = false
    }

    // Reply from a message notification, on the screen that has focus: move the pointer into the
    // panel (it stays open while the pointer is over it), open the chat and focus the field.
    Connections {
        target: Matrix

        function onReplyRequested(id: string): void {
            if (Hyprland.focusedMonitor?.name !== root.screen.name)
                return;
            root.holdOpen = true;
            root.replying = true;
            root.open = true;
            root.clearSearch();
            root.openRoom(id);
            // Move the pointer once the panel has grown, so it lands on the panel.
            pointerDelay.restart();
            holdLimit.restart();
        }
    }

    Timer {
        id: pointerDelay

        interval: 300
        onTriggered: {
            const side = Config.border.thickness;
            const x = Math.round(root.screen.x + root.screen.width - side - Config.matrix.width / 2);
            const y = Math.round(root.screen.y + root.screen.height - side - 60);
            Hyprland.dispatch(`hl.dsp.cursor.move({x = ${x}, y = ${y}})`);
            focusDelay.restart();
        }
    }

    // Once the frame has the keyboard.
    Timer {
        id: focusDelay

        interval: 200
        onTriggered: input.forceActiveFocus()
    }

    // In case the pointer never arrives, normal closing takes over again.
    Timer {
        id: holdLimit

        interval: 3000
        onTriggered: root.holdOpen = false
    }

    // The service mirrors gomuks's timeline for whichever room is open here.
    onRoomIdChanged: Matrix.openTimeline(roomId)

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

            // Search
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                visible: Matrix.configured && Matrix.loggedIn && !root.roomId
                implicitHeight: 36
                radius: height / 2
                color: Config.colours.card

                Text {
                    id: searchIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0349}"
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                }

                TextInput {
                    id: search

                    anchors.left: searchIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: Config.colours.text
                    selectionColor: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    clip: true

                    onTextChanged: {
                        root.query = text.trim();
                        searchDelay.restart();
                    }
                    Keys.onEscapePressed: text = ""

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search rooms and messages"
                        color: Config.colours.muted
                        font: search.font
                    }

                    // Rooms filter as you type; messages wait for a pause.
                    Timer {
                        id: searchDelay

                        interval: 300
                        onTriggered: Matrix.searchMessages(search.text)
                    }
                }
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
                model: {
                    Matrix.version;
                    return root.query ? Matrix.findRooms(root.query) : Matrix.roomList;
                }

                header: Text {
                    width: rooms.width
                    height: visible ? implicitHeight : 0
                    visible: root.query !== "" && rooms.count > 0
                    leftPadding: 8
                    bottomPadding: 4
                    text: "Rooms"
                    color: Config.colours.muted
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                // Message results under the matching rooms.
                footer: Column {
                    width: rooms.width
                    visible: root.query !== ""
                    height: visible ? implicitHeight : 0
                    topPadding: 8
                    spacing: 2

                    Text {
                        leftPadding: 8
                        bottomPadding: 4
                        text: "Messages"
                        color: Config.colours.muted
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        visible: !Matrix.searchResults?.length
                        leftPadding: 8
                        text: Matrix.searching || !Matrix.searchResults ? "Searching…" : "No messages found"
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Repeater {
                        model: Matrix.searchResults ?? []

                        Rectangle {
                            id: hit

                            required property var modelData
                            readonly property var room: Matrix.rooms[modelData.room_id]

                            width: rooms.width
                            implicitHeight: hitLayout.implicitHeight + 16
                            radius: 14
                            color: hitArea.containsMouse ? Config.colours.buttonHover : "transparent"

                            MouseArea {
                                id: hitArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const id = hit.modelData.room_id;
                                    root.clearSearch();
                                    root.openRoom(id);
                                }
                            }

                            RowLayout {
                                id: hitLayout

                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 12
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 10

                                Avatar {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    name: Matrix.senderName(hit.modelData.room_id, hit.modelData.sender)
                                    source: Matrix.senderAvatar(hit.modelData.room_id, hit.modelData.sender)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            Layout.fillWidth: true
                                            text: `${Matrix.senderName(hit.modelData.room_id, hit.modelData.sender)} · ${Matrix.roomName(hit.room)}`
                                            elide: Text.ElideRight
                                            color: Config.colours.text
                                            font.family: Config.font.family
                                            font.pointSize: Config.font.small
                                            font.bold: true
                                        }

                                        Text {
                                            text: root.time(hit.modelData.timestamp)
                                            color: Config.colours.muted
                                            font.family: Config.font.family
                                            font.pointSize: Config.font.small
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: Matrix.text(hit.modelData) || Matrix.caption(hit.modelData) || "Image"
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        color: Config.colours.subtext
                                        font.family: Config.font.family
                                        font.pointSize: Config.font.small
                                    }
                                }
                            }
                        }
                    }
                }

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
                            source: Matrix.mediaUrl(roomRow.meta.avatar ?? "", false)
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

                // Older messages when scrolled to the top, and while what's loaded doesn't fill
                // the view yet (a page can be mostly reactions and other hidden events).
                onAtYEndChanged: if (atYEnd && root.roomId) Matrix.paginate(root.roomId)
                onContentHeightChanged: fillDelay.restart()
                onCountChanged: fillDelay.restart()

                Timer {
                    id: fillDelay

                    interval: 100
                    onTriggered: if (root.roomId && timeline.visible && timeline.contentHeight < timeline.height) Matrix.paginate(root.roomId)
                }

                delegate: Column {
                    id: msg

                    required property var modelData
                    readonly property var evt: modelData.evt
                    readonly property bool own: modelData.own
                    // Room for the avatar beside others' messages.
                    readonly property int indent: own ? 0 : 32
                    readonly property var reactions: Object.entries(evt.reactions ?? {}).filter(([, n]) => n > 0)

                    width: timeline.width
                    topPadding: modelData.first ? 8 : 0
                    spacing: 4

                    HoverHandler {
                        id: hover
                    }

                    Text {
                        visible: msg.modelData.first && !msg.own
                        leftPadding: msg.indent + 10
                        text: Matrix.senderName(root.roomId, msg.evt.sender)
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                        font.bold: true
                    }

                    Item {
                        width: parent.width
                        height: bubble.height

                        Rectangle {
                            id: bubble

                            readonly property real maxWidth: timeline.width * 0.75 - msg.indent

                            x: msg.own ? parent.width - width : msg.indent
                            // Dimmed until gomuks confirms it was sent.
                            opacity: Matrix.pending(msg.evt) ? 0.55 : 1
                            width: Math.max(picture.visible ? picture.width + 8 : 0, body.visible ? Math.min(body.implicitWidth, maxWidth) + 24 : 0)
                            height: content.implicitHeight + (body.visible ? 14 : 8)
                            radius: 14
                            color: msg.own ? Config.colours.active : Config.colours.card

                            Column {
                                id: content

                                anchors.centerIn: parent
                                spacing: 6

                                // Image or sticker, scaled to fit; click for the full size.
                                ClippingRectangle {
                                    id: picture

                                    readonly property real ratio: msg.modelData.image && msg.modelData.image.w > 0 ? msg.modelData.image.h / msg.modelData.image.w : 0.75
                                    readonly property real fitWidth: Math.min(240, bubble.maxWidth, msg.modelData.image?.w || 240)

                                    visible: !!msg.modelData.image
                                    width: fitWidth * ratio > 280 ? 280 / ratio : fitWidth
                                    height: width * ratio
                                    radius: 10
                                    color: Config.colours.button

                                    Text {
                                        anchors.centerIn: parent
                                        visible: pic.status !== Image.Ready
                                        text: pic.status === Image.Error ? "Can't show image" : "\u{F02E9}"
                                        color: Config.colours.subtext
                                        font.family: Config.font.family
                                        font.pointSize: pic.status === Image.Error ? Config.font.small : 18
                                    }

                                    Image {
                                        id: pic

                                        anchors.fill: parent
                                        source: msg.modelData.image?.thumb ?? ""
                                        sourceSize: Qt.size(parent.width * 2, parent.height * 2)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally(msg.modelData.image.full)
                                    }
                                }

                                Text {
                                    id: body

                                    visible: text !== ""
                                    width: Math.min(implicitWidth, bubble.maxWidth)
                                    text: msg.modelData.text
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                    color: msg.own ? Config.colours.activeText : Config.colours.text
                                    font.family: Config.font.family
                                    font.pointSize: Config.font.small
                                    font.italic: msg.evt.type === "m.room.encrypted" && !msg.evt.decrypted_type
                                }
                            }
                        }

                        // Sender's avatar beside the first message of a run.
                        Avatar {
                            anchors.right: bubble.left
                            anchors.rightMargin: 8
                            anchors.top: bubble.top
                            width: 24
                            height: 24
                            visible: msg.modelData.first && !msg.own
                            name: Matrix.senderName(root.roomId, msg.evt.sender)
                            source: visible ? Matrix.senderAvatar(root.roomId, msg.evt.sender) : ""
                        }

                        // Time and react button on the free side of the bubble while hovered.
                        Row {
                            anchors.verticalCenter: bubble.verticalCenter
                            anchors.right: msg.own ? bubble.left : undefined
                            anchors.left: msg.own ? undefined : bubble.right
                            anchors.margins: 8
                            layoutDirection: msg.own ? Qt.RightToLeft : Qt.LeftToRight
                            spacing: 6
                            visible: hover.hovered || root.pickerFor === msg.evt.event_id

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.time(msg.evt.timestamp)
                                color: Config.colours.muted
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                            }

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                visible: !msg.evt.event_id.startsWith("~")
                                color: reactArea.containsMouse || root.pickerFor === msg.evt.event_id ? Config.colours.buttonHover : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{F01F5}"
                                    color: Config.colours.subtext
                                    font.family: Config.font.family
                                    font.pointSize: Config.font.size
                                }

                                MouseArea {
                                    id: reactArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pickerFor = root.pickerFor === msg.evt.event_id ? "" : msg.evt.event_id
                                }
                            }
                        }
                    }

                    Text {
                        x: msg.own ? parent.width - width : msg.indent
                        visible: Matrix.failed(msg.evt)
                        rightPadding: 6
                        leftPadding: 6
                        text: "Failed to send"
                        color: "#ff6b6b"
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    // Quick reaction picker
                    Row {
                        x: msg.own ? parent.width - width : msg.indent
                        visible: root.pickerFor === msg.evt.event_id
                        spacing: 2

                        Repeater {
                            model: root.quickReactions

                            Rectangle {
                                required property string modelData

                                width: 32
                                height: 32
                                radius: 16
                                color: pickArea.containsMouse ? Config.colours.buttonHover : Config.colours.card

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    font.pointSize: Config.font.size
                                }

                                MouseArea {
                                    id: pickArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Matrix.react(root.roomId, msg.evt, parent.modelData);
                                        root.pickerFor = "";
                                    }
                                }
                            }
                        }
                    }

                    // Reactions; yours are white. Click one to add or take back yours.
                    Flow {
                        x: msg.own ? parent.width - width : msg.indent
                        width: Math.min(implicitWidth, parent.width - msg.indent)
                        visible: msg.reactions.length > 0
                        spacing: 4
                        layoutDirection: msg.own ? Qt.RightToLeft : Qt.LeftToRight

                        Repeater {
                            model: msg.reactions

                            Rectangle {
                                id: chip

                                required property var modelData
                                readonly property bool mine: (msg.evt.own_reactions?.[modelData[0]]?.length ?? 0) > 0

                                // Custom emoji reactions use an image (mxc://) as their key.
                                readonly property bool custom: modelData[0].startsWith("mxc://")

                                width: chipRow.implicitWidth + 16
                                height: 24
                                radius: 12
                                color: mine ? Config.colours.active : chipArea.containsMouse ? Config.colours.buttonHover : Config.colours.card

                                Row {
                                    id: chipRow

                                    anchors.centerIn: parent
                                    spacing: 4

                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: chip.custom
                                        width: 16
                                        height: 16
                                        sourceSize: Qt.size(32, 32)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        source: chip.custom ? Matrix.mediaUrl(chip.modelData[0], false) : ""
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.custom ? `${chip.modelData[1]}` : `${chip.modelData[0]} ${chip.modelData[1]}`
                                        color: chip.mine ? Config.colours.activeText : Config.colours.text
                                        font.family: Config.font.family
                                        font.pointSize: Config.font.small
                                    }
                                }

                                MouseArea {
                                    id: chipArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Matrix.react(root.roomId, msg.evt, chip.modelData[0])
                                }
                            }
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
