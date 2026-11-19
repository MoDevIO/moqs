import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Homework, your own and WebUntis's, by due date and coloured by how soon it's due. Everything
// can be ticked off; ticks and own entries live in a local text file. New entries need a
// subject and a date, both picked out of the typed text (see WebUntis.parseEntry).
Card {
    id: root

    function dueColour(due: int): color {
        return ({ late: Config.colours.red, soon: Config.colours.orange, near: Config.colours.yellow })[WebUntis.urgency(due)] ?? Config.colours.subtext;
    }

    title: "Homework"
    note: {
        const open = WebUntis.homework.filter(h => !h.done).length;
        return open ? `${open} open` : "";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Config.dashboard.spacing

        // New entry
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: height / 2
            color: Config.colours.button

            Text {
                id: plus

                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F0415}"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.size
            }

            TextInput {
                id: input

                anchors.left: plus.right
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Config.colours.text
                selectionColor: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
                clip: true

                onAccepted: {
                    if (WebUntis.addHomework(text))
                        text = "";
                }
                Keys.onEscapePressed: text = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text
                    text: "Add homework: Eng S. 42 bis 21.11."
                    color: Config.colours.muted
                    font: input.font
                }
            }
        }

        // What the typed text becomes: subject and due date, then the rest as the description.
        ColumnLayout {
            id: preview

            readonly property var entry: WebUntis.parseEntry(input.text)
            readonly property string names: WebUntis.subjects.map(s => s.name).slice(0, 4).join(", ")

            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            visible: input.text.trim() !== ""
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: preview.entry.subject || (preview.names ? `Subject? (${preview.names}…)` : "Subject? Set \"subjects\"")
                    color: preview.entry.subject ? Config.colours.text : Config.colours.red
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    font.bold: !!preview.entry.subject
                }

                Text {
                    Layout.fillWidth: true
                    text: preview.entry.due ? WebUntis.dayName(preview.entry.due) + (preview.entry.guessed ? " (next lesson)" : "") : "Date?"
                    elide: Text.ElideRight
                    color: preview.entry.due ? root.dueColour(preview.entry.due) : Config.colours.red
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: preview.entry.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: WebUntis.loading ? "Loading…" : "Nothing to do"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            ListView {
                id: list

                anchors.fill: parent
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: WebUntis.homework

                delegate: Rectangle {
                    id: entry

                    required property var modelData

                    width: list.width
                    implicitHeight: row.implicitHeight + 16
                    radius: 14
                    color: hover.hovered ? Config.colours.buttonHover : Config.colours.button

                    HoverHandler {
                        id: hover
                    }

                    // Due soon: a coloured edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 4
                        width: 3
                        height: parent.height - 16
                        radius: 1.5
                        visible: !entry.modelData.done && WebUntis.urgency(entry.modelData.due) !== ""
                        color: root.dueColour(entry.modelData.due)
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: entry.modelData.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: WebUntis.toggle(entry.modelData)
                    }

                    RowLayout {
                        id: row

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        // Tick
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 1
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: entry.modelData.done ? Config.colours.active : "transparent"
                            border.width: entry.modelData.done ? 0 : 1.5
                            border.color: Config.colours.subtext

                            Text {
                                anchors.centerIn: parent
                                visible: entry.modelData.done
                                text: "\u{F012C}"
                                color: Config.colours.activeText
                                font.family: Config.font.family
                                font.pointSize: Config.font.small - 1
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                visible: entry.modelData.subject !== "" || entry.modelData.due !== 0
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.subject
                                    elide: Text.ElideRight
                                    color: entry.modelData.done ? Config.colours.subtext : Config.colours.text
                                    font.family: Config.font.family
                                    font.pointSize: Config.font.small
                                    font.bold: true
                                }

                                Text {
                                    visible: entry.modelData.due !== 0
                                    text: WebUntis.dayName(entry.modelData.due)
                                    color: entry.modelData.done ? Config.colours.subtext : root.dueColour(entry.modelData.due)
                                    font.family: Config.font.family
                                    font.pointSize: Config.font.small
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: entry.modelData.text
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                color: entry.modelData.done ? Config.colours.subtext : Config.colours.text
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                                font.strikeout: entry.modelData.done
                            }
                        }

                        // Own entries can be deleted.
                        Text {
                            Layout.alignment: Qt.AlignTop
                            visible: entry.modelData.local && hover.hovered
                            text: "\u{F0156}"
                            color: remove.containsMouse ? Config.colours.text : Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small

                            MouseArea {
                                id: remove

                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: WebUntis.removeHomework(entry.modelData.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
