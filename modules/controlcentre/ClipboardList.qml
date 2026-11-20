import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.modules

// Clipboard history, newest first. Typing filters it; click or Enter copies an entry back,
// arrows move through the list.
Item {
    id: root

    signal picked

    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        return Clipboard.entries.filter(e => !q || Clipboard.describe(e).toLowerCase().includes(q)).slice(0, Config.clipboard.shown);
    }

    function pick(entry: var): void {
        if (!entry)
            return;
        Clipboard.copy(entry);
        root.picked();
    }

    implicitHeight: layout.implicitHeight + 12

    Component.onCompleted: search.forceActiveFocus()

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: height / 2
                color: Config.colours.button

                TextInput {
                    id: search

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Config.colours.text
                    selectionColor: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    clip: true

                    onTextChanged: list.currentIndex = 0
                    onAccepted: root.pick(root.shown[list.currentIndex])
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search clipboard"
                        color: Config.colours.muted
                        font: search.font
                    }
                }
            }

            // Clear the whole history.
            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: height / 2
                visible: Clipboard.entries.length > 0
                color: clearArea.containsMouse ? Config.colours.buttonHover : Config.colours.button

                Text {
                    anchors.centerIn: parent
                    text: "\u{F0A7A}"
                    color: clearArea.containsMouse ? Config.colours.red : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                }

                MouseArea {
                    id: clearArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.wipe()
                }
            }
        }

        ListView {
            id: list

            SmoothScroll {
                flickable: list
            }

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 320)
            visible: root.shown.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            model: root.shown

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index
                readonly property var entry: modelData
                readonly property bool current: ListView.isCurrentItem
                readonly property string thumb: Clipboard.thumbs[entry.id] ?? ""

                width: list.width
                implicitHeight: entry.image && thumb ? 72 : 36
                radius: entry.image && thumb ? 18 : height / 2
                color: current ? Config.colours.button : area.containsMouse ? Config.colours.buttonHover : "transparent"

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) list.currentIndex = row.index
                    onClicked: root.pick(row.entry)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 18
                        visible: !row.thumb
                        horizontalAlignment: Text.AlignHCenter
                        text: row.entry.image ? "\u{F02E9}" : "\u{F0219}"
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.size
                    }

                    Image {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 60
                        visible: row.thumb !== ""
                        source: row.thumb
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignLeft
                        sourceSize.width: 192
                        sourceSize.height: 120
                        asynchronous: true
                        smooth: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Clipboard.describe(row.entry)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: row.entry.image ? Config.colours.subtext : Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    // Remove just this entry.
                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: width / 2
                        opacity: row.current ? 1 : 0
                        color: removeArea.containsMouse ? Config.colours.buttonHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\u{F0156}"
                            color: removeArea.containsMouse ? Config.colours.text : Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }

                        MouseArea {
                            id: removeArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Clipboard.remove(row.entry)
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.margins: 8
            visible: root.shown.length === 0
            text: !Clipboard.available ? "cliphist isn't installed" : search.text ? "Nothing matches" : "Nothing copied yet"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }
}
