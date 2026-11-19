import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Today's lessons from WebUntis until the last one is over, then the next school day's.
Card {
    id: root

    title: "Timetable"
    note: WebUntis.dayName(WebUntis.shownDate)

    Text {
        anchors.centerIn: parent
        visible: list.count === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: !WebUntis.configured ? "Set up webuntis.json" : WebUntis.error || (WebUntis.loading ? "Loading…" : `No lessons in the next ${Config.webuntis.days} days`)
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
        model: WebUntis.shownLessons

        delegate: Rectangle {
            id: lesson

            required property var modelData
            readonly property bool current: modelData.date === WebUntis.today && WebUntis.time >= modelData.start && WebUntis.time < modelData.end && !modelData.cancelled
            readonly property color fg: current ? Config.colours.activeText : modelData.cancelled ? Config.colours.subtext : Config.colours.text
            readonly property color dim: current ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext

            width: list.width
            implicitHeight: row.implicitHeight + 16
            radius: 14
            color: current ? Config.colours.active : Config.colours.button

            RowLayout {
                id: row

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: WebUntis.clock(lesson.modelData.start)
                        color: lesson.fg
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        text: WebUntis.clock(lesson.modelData.end)
                        color: lesson.dim
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: lesson.modelData.subject
                            elide: Text.ElideRight
                            color: lesson.fg
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                            font.bold: true
                            font.strikeout: lesson.modelData.cancelled
                        }

                        Text {
                            visible: lesson.modelData.cancelled || lesson.modelData.changed
                            text: lesson.modelData.cancelled ? "Cancelled" : "Changed"
                            color: lesson.dim
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: [lesson.modelData.teachers, lesson.modelData.rooms].filter(x => x).join(" · ")
                        elide: Text.ElideRight
                        color: lesson.dim
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: lesson.modelData.text
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: lesson.dim
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                        font.italic: true
                    }
                }
            }
        }
    }
}
