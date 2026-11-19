import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Homework: your own entries on top, then WebUntis's by due date. Everything can be ticked
// off; ticks and own entries live in a local text file.
Card {
    id: root

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
                    WebUntis.addHomework(text);
                    text = "";
                }
                Keys.onEscapePressed: text = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text
                    text: "Add homework"
                    color: Config.colours.muted
                    font: input.font
                }
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
                                    color: Config.colours.subtext
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
