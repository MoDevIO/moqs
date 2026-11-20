import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.modules

// Homework, your own and WebUntis's, by due date and coloured by how soon it's due. Everything
// can be ticked off; ticks and own entries live in a local text file. New entries need a
// subject and a date, both picked out of the typed text (see WebUntis.parseEntry). Below,
// a smaller list of exams, WebUntis's and your own ("exam: …" in the same field), each with
// a slider for how far the learning is.
Card {
    id: root

    readonly property var colours: ({ late: Config.colours.red, soon: Config.colours.orange, near: Config.colours.yellow })

    function dueColour(due: int): color {
        return colours[WebUntis.urgency(due)] ?? Config.colours.subtext;
    }

    function examColour(date: int): color {
        return colours[WebUntis.examUrgency(date)] ?? Config.colours.subtext;
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
                    text: "Eng S. 42 bis 21.11. · exam: M 3.12."
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

                // Marks an exam.
                Rectangle {
                    visible: preview.entry.exam
                    implicitWidth: examLabel.implicitWidth + 12
                    implicitHeight: examLabel.implicitHeight + 2
                    radius: height / 2
                    color: Config.colours.active

                    Text {
                        id: examLabel

                        anchors.centerIn: parent
                        text: "Exam"
                        color: Config.colours.activeText
                        font.family: Config.font.family
                        font.pointSize: Config.font.small - 1
                        font.bold: true
                    }
                }

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
                    color: !preview.entry.due ? Config.colours.red : preview.entry.exam ? root.examColour(preview.entry.due) : root.dueColour(preview.entry.due)
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

                SmoothScroll {
                    flickable: list
                }

                anchors.fill: parent
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: WebUntis.homework

                delegate: Rectangle {
                    id: entry

                    required property var modelData

                    width: list.width
                    implicitHeight: row.implicitHeight + 12
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
                        height: parent.height - 14
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

        // Exams: one compact line each, the learning progress as a slider along the bottom
        // edge. Two show, the rest scroll.
        ColumnLayout {
            Layout.fillWidth: true
            visible: WebUntis.exams.length > 0
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 8

                Text {
                    text: "Exams"
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Config.colours.button
                }
            }

            ListView {
                id: examList

                SmoothScroll {
                    flickable: examList
                }

                readonly property int rowHeight: 36
                readonly property int rows: Math.min(count, 2)

                Layout.fillWidth: true
                Layout.preferredHeight: rows * rowHeight + Math.max(0, rows - 1) * spacing
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: WebUntis.exams

                delegate: Rectangle {
                    id: exam

                    required property var modelData
                    readonly property bool ready: modelData.progress >= 100

                    width: examList.width
                    height: examList.rowHeight
                    radius: 12
                    color: examHover.hovered ? Config.colours.buttonHover : Config.colours.button

                    HoverHandler {
                        id: examHover
                    }

                    // Coming up soon: a coloured edge, as on homework.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 4
                        width: 3
                        height: parent.height - 14
                        radius: 1.5
                        visible: WebUntis.examUrgency(exam.modelData.date) !== "" && !exam.ready
                        color: root.examColour(exam.modelData.date)
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 5
                        spacing: 8

                        Text {
                            text: exam.modelData.subject
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: exam.modelData.text
                            elide: Text.ElideRight
                            color: Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }

                        // The learning progress while pointed at, a tick once done.
                        Text {
                            visible: examHover.hovered || exam.ready
                            text: exam.ready ? "\u{F012C}" : `${slider.shown}%`
                            color: exam.ready ? Config.colours.text : Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }

                        // The date itself while pointed at.
                        Text {
                            text: dateHover.hovered ? WebUntis.dayName(exam.modelData.date) : WebUntis.countdown(exam.modelData.date)
                            color: root.examColour(exam.modelData.date)
                            font.family: Config.font.family
                            font.pointSize: Config.font.small

                            HoverHandler {
                                id: dateHover
                            }
                        }

                        // Own exams can be deleted.
                        Text {
                            visible: exam.modelData.local && examHover.hovered
                            text: "\u{F0156}"
                            color: removeExam.containsMouse ? Config.colours.text : Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small

                            MouseArea {
                                id: removeExam

                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: WebUntis.removeExam(exam.modelData.index)
                            }
                        }
                    }

                    ProgressSlider {
                        id: slider

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 3
                        value: exam.modelData.progress
                        onCommitted: v => WebUntis.setExamProgress(exam.modelData, v)
                    }
                }
            }
        }
    }

    // How far the learning is, 0..100 in steps of 5: drag or click the track. Scrolling
    // passes through to the list.
    // committed fires once the value is let go of, so the file isn't rewritten on every move.
    component ProgressSlider: Item {
        id: slider

        property int value
        property int dragged: -1
        readonly property int shown: dragged >= 0 ? dragged : value
        readonly property bool active: area.containsMouse || area.pressed

        signal committed(int value)

        function at(x: real): int {
            return Math.round(Math.max(0, Math.min(1, x / width)) * 20) * 5;
        }

        implicitHeight: 10

        // Track
        Rectangle {
            id: track

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: slider.active ? 5 : 3
            radius: height / 2
            color: Config.colours.muted

            Behavior on height {
                NumberAnimation {
                    duration: 120
                }
            }

            Rectangle {
                width: slider.shown > 0 ? Math.max(parent.height, parent.width * slider.shown / 100) : 0
                height: parent.height
                radius: parent.radius
                color: Config.colours.text

                Behavior on width {
                    enabled: !area.pressed

                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Knob, shown while pointed at.
        Rectangle {
            x: Math.max(0, Math.min(slider.width - width, slider.width * slider.shown / 100 - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: Config.colours.text
            border.width: 2
            border.color: Config.colours.button
            scale: slider.active ? 1 : 0
            visible: scale > 0

            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutBack
                }
            }

            Behavior on x {
                enabled: !area.pressed

                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => slider.dragged = slider.at(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    slider.dragged = slider.at(mouse.x);
            }
            onReleased: {
                const v = slider.dragged;
                slider.dragged = -1;
                if (v !== slider.value)
                    slider.committed(v);
            }
            onCanceled: slider.dragged = -1
        }
    }
}
