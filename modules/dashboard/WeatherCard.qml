import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Weather now, over the coming hours and over the coming days.
Card {
    id: root

    // Coldest and warmest of the shown days, for the range bars.
    readonly property real low: Math.min(...Weather.days.map(d => d.min))
    readonly property real high: Math.max(...Weather.days.map(d => d.max))

    title: "Weather"
    note: Weather.place

    Text {
        anchors.centerIn: parent
        visible: !Weather.current
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: !Weather.configured ? Weather.locationError || "Set up weather.json" : Weather.error || "Loading…"
        color: Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.small
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!Weather.current
        spacing: Config.dashboard.spacing

        // Now
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 12

            Text {
                text: Weather.current ? Weather.icon(Weather.current.code, Weather.current.day) : ""
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: 30
            }

            Text {
                text: Weather.current ? Weather.degrees(Weather.current.temp) : ""
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: 26
                font.bold: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: Weather.current ? `${Weather.describe(Weather.current.code)} · feels ${Weather.degrees(Weather.current.feels)}` : ""
                    elide: Text.ElideRight
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    // Wind and humidity, each with its icon, so the line stays short.
                    text: Weather.current ? `\u{F059D} ${Math.round(Weather.current.wind)} km/h  \u{F058E} ${Math.round(Weather.current.humidity)}%` : ""
                    elide: Text.ElideRight
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }
        }

        // Coming hours
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: hourRow.implicitHeight + 16
            radius: 14
            color: Config.colours.button

            RowLayout {
                id: hourRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 0

                Repeater {
                    model: Weather.hours

                    ColumnLayout {
                        id: hour

                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: hour.index === 0 ? "Now" : Qt.formatTime(hour.modelData.time, "HH")
                            color: Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Weather.icon(hour.modelData.code, hour.modelData.day)
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.icon
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Weather.degrees(hour.modelData.temp)
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }
        }

        // Coming days
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 0

            Repeater {
                model: Weather.days

                RowLayout {
                    id: day

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Text {
                        Layout.preferredWidth: 44
                        text: day.index === 0 ? "Today" : Qt.formatDate(day.modelData.date, "ddd")
                        color: Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        Layout.preferredWidth: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: Weather.icon(day.modelData.code, true)
                        color: Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.size
                    }

                    // Chance of rain, when there is one worth mentioning.
                    Text {
                        Layout.preferredWidth: 34
                        text: day.modelData.rain >= 20 ? `${Math.round(day.modelData.rain)}%` : ""
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        Layout.preferredWidth: 30
                        horizontalAlignment: Text.AlignRight
                        text: Weather.degrees(day.modelData.min)
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    // The day's range within the coldest and warmest of the shown days.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Config.colours.muted

                        Rectangle {
                            readonly property real span: Math.max(1, root.high - root.low)

                            x: parent.width * (day.modelData.min - root.low) / span
                            width: Math.max(parent.height, parent.width * (day.modelData.max - day.modelData.min) / span)
                            height: parent.height
                            radius: 2
                            color: Config.colours.text
                        }
                    }

                    Text {
                        Layout.preferredWidth: 30
                        text: Weather.degrees(day.modelData.max)
                        color: Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }
            }
        }
    }
}
