import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// The launcher's conversation with the assistant (Assistant): each question, each tool it
// used (✓ done, ✗ failed or declined), its answers, and what waits for a yes, newest at the
// bottom, scrolled there as it grows.
Flickable {
    id: root

    implicitHeight: Math.min(column.implicitHeight, 420)
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

    ColumnLayout {
        id: column

        width: root.width
        spacing: 8

        Repeater {
            model: Assistant.view

            // A question, a tool used (with a command's last lines of output), or text: an
            // answer, a note on the way, an error.
            delegate: ColumnLayout {
                id: entry

                required property var modelData
                readonly property string kind: modelData.kind

                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    visible: entry.kind === "user"
                    text: `› ${entry.modelData.text}`
                    wrapMode: Text.Wrap
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: entry.kind === "tool"
                    spacing: 8

                    Text {
                        text: entry.modelData.icon ?? ""
                        color: Config.colours.muted
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        Layout.fillWidth: true
                        text: entry.modelData.text
                        elide: Text.ElideRight
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        text: entry.modelData.ok === true ? "\u{F012C}" : entry.modelData.ok === false ? "\u{F0156}" : ""
                        color: entry.modelData.ok ? Config.colours.green : Config.colours.red
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22
                    visible: entry.kind === "tool" && entry.modelData.ok !== undefined && !!entry.modelData.detail
                    text: entry.modelData.detail ?? ""
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Config.colours.muted
                    font.family: Config.font.family
                    font.pointSize: Config.font.small - 1
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: entry.kind === "answer" ? 4 : 0
                    visible: entry.kind === "answer" || entry.kind === "note" || entry.kind === "error"
                    text: entry.modelData.text
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: entry.kind === "error" ? Config.colours.red : entry.kind === "note" ? Config.colours.subtext : Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: entry.kind === "answer" ? Config.font.size : Config.font.small
                    lineHeight: 1.15
                }
            }
        }

        // Working on it.
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: Assistant.busy && !Assistant.pending
            text: "Thinking…"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small

            SequentialAnimation on opacity {
                running: Assistant.busy
                loops: Animation.Infinite

                NumberAnimation {
                    to: 0.4
                    duration: 600
                }

                NumberAnimation {
                    to: 1
                    duration: 600
                }
            }
        }

        // Waiting for a yes.
        Rectangle {
            Layout.fillWidth: true
            visible: !!Assistant.pending
            implicitHeight: pendingColumn.implicitHeight + 20
            radius: 12
            color: Config.colours.card
            border.width: 1
            border.color: Qt.alpha(Config.colours.orange, 0.6)

            ColumnLayout {
                id: pendingColumn

                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    visible: !!Assistant.pending?.detail
                    text: Assistant.pending?.detail ?? ""
                    wrapMode: Text.WrapAnywhere
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: `<font color="${Config.colours.orange}">${Assistant.pending?.label ?? ""}?</font>&nbsp;&nbsp;<font color="${Config.colours.subtext}">Enter yes · Esc no</font>`
                    wrapMode: Text.Wrap
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }
        }
    }
}
