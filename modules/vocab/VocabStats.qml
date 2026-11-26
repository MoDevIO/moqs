import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Progress in the vocabulary pane (see Vocab.stats): words seen and learnt, the streak and
// recall, what's due in the next days, and how far along each lesson is.
ColumnLayout {
    id: root

    readonly property var stats: Vocab.stats
    readonly property int most: Math.max(1, ...stats.forecast)
    // Lessons with words, named short: "Lektion 12" as "12".
    readonly property var sections: stats.sections.filter(s => s.total > 0).map(s => Object.assign({}, s, { short: (s.name.match(/(\d+)\s*$/) ?? [])[1] ?? (s.name.slice(0, 3) || "–") }))

    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Figure {
            value: `${root.stats.seen}`
            caption: `seen of ${root.stats.total}`
        }

        Figure {
            value: `${root.stats.learnt}`
            caption: "learnt"
        }

        Figure {
            value: `${root.stats.streak}`
            caption: root.stats.streak === 1 ? "day streak" : "days streak"
        }

        Figure {
            value: root.stats.recall < 0 ? "–" : `${Math.round(root.stats.recall * 100)} %`
            caption: "right, 7 days"
        }
    }

    Label {
        text: "Due in the next days"
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 74
        spacing: 6

        Repeater {
            model: root.stats.forecast

            ColumnLayout {
                id: dayColumn

                required property int modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: dayColumn.modelData
                    color: dayColumn.modelData ? Config.colours.text : Config.colours.muted
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, 28)
                        height: Math.max(2, parent.height * dayColumn.modelData / root.most)
                        radius: 4
                        color: dayColumn.index === 0 ? Config.colours.active : Config.colours.subtext
                        opacity: dayColumn.modelData ? 1 : 0.3
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: dayColumn.index === 0 ? "Today" : Qt.formatDate(new Date(Vocab.dayAfter(Vocab.now, dayColumn.index)), "ddd")
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }
        }
    }

    Label {
        visible: root.sections.length > 1
        text: "Lessons · grey seen, green learnt (3 weeks or more)"
    }

    GridLayout {
        Layout.fillWidth: true
        visible: root.sections.length > 1
        columns: 10
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            model: root.sections

            Rectangle {
                id: cell

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 6
                color: Config.colours.button
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * cell.modelData.seen / cell.modelData.total
                    color: Qt.alpha(Config.colours.subtext, 0.35)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * cell.modelData.learnt / cell.modelData.total
                    color: Qt.alpha(Config.colours.green, 0.55)
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.short
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }
        }
    }

    Label {
        visible: root.stats.hard.length > 0
        text: `Hard words · ${root.stats.hard.length}, missed most first`
        Layout.fillWidth: true
        wrapMode: Text.Wrap
    }

    Repeater {
        model: root.stats.hard.slice(0, 8)

        RowLayout {
            id: hardRow

            required property var modelData

            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: `${hardRow.modelData.prompt} = ${hardRow.modelData.answer}`
                elide: Text.ElideRight
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Text {
                text: `${hardRow.modelData.misses}×`
                color: Config.colours.red
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }
    }

    Text {
        visible: root.stats.hard.length > 8
        text: `and ${root.stats.hard.length - 8} more (qs ipc call vocab hardWords)`
        color: Config.colours.muted
        font.family: Config.font.family
        font.pointSize: Config.font.small
    }

    // A big number with a caption under it.
    component Figure: ColumnLayout {
        id: figure

        property string value
        property string caption

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: figure.value
            color: Config.colours.text
            font.family: Config.font.sans
            font.pointSize: 18
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: figure.caption
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }

    component Label: Text {
        color: Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.small
    }
}
