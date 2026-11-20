import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.controlcentre
import qs.services
import qs.modules

// Home Assistant: the sections hass.json lists, top to bottom.
Card {
    id: root

    title: "Home"
    note: HomeAssistant.configured ? HomeAssistant.error : ""

    Text {
        anchors.centerIn: parent
        visible: !HomeAssistant.configured || HomeAssistant.sections.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: HomeAssistant.configured ? "No sections in hass.json" : HomeAssistant.secretError || "Set up hass.json"
        color: Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.small
    }

    Flickable {
        id: flick

        SmoothScroll {
            flickable: flick
        }

        anchors.fill: parent
        visible: HomeAssistant.configured
        clip: true
        contentHeight: sections.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: sections

            width: parent.width
            spacing: Config.dashboard.spacing

            Repeater {
                model: HomeAssistant.sections

                ColumnLayout {
                    id: section

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.leftMargin: 4
                        visible: text !== ""
                        // A lone slider has no room for its name, so it goes above.
                        text: section.modelData.title || (section.modelData.type === "toggle" && section.modelData.items.length === 1 && HomeAssistant.brightness(section.modelData.items[0].entity) >= 0 ? HomeAssistant.name(section.modelData.items[0]) : "")
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: ({ toggle: toggles, button: buttons, sensor: sensorRows, sensors: sensorBlock })[section.modelData.type] ?? sensorRows

                        property var items: section.modelData.items
                    }
                }
            }
        }
    }

    // Toggles: a brightness slider for lights that dim, else an on/off row.
    Component {
        id: toggles

        ColumnLayout {
            id: toggleList

            readonly property var entries: parent ? parent.items ?? [] : []

            spacing: 4

            Repeater {
                model: toggleList.entries

                Item {
                    id: toggle

                    required property var modelData
                    readonly property string entity: modelData.entity
                    readonly property bool on: HomeAssistant.isOn(entity)
                    readonly property real level: HomeAssistant.brightness(entity)

                    Layout.fillWidth: true
                    implicitHeight: 36

                    Slider {
                        anchors.fill: parent
                        visible: toggle.level >= 0
                        trackColour: Config.colours.button
                        value: toggle.level
                        dimmed: !toggle.on
                        icon: HomeAssistant.icon(toggle.modelData)
                        onMoved: v => HomeAssistant.setBrightness(toggle.entity, v)
                        onIconClicked: HomeAssistant.toggle(toggle.entity)
                    }

                    HassEntry {
                        anchors.fill: parent
                        visible: toggle.level < 0
                        item: toggle.modelData
                        active: toggle.on
                        trailing: HomeAssistant.state(toggle.entity) ? (toggle.on ? "On" : "Off") : ""
                        onClicked: HomeAssistant.toggle(toggle.entity)
                    }
                }
            }
        }
    }

    Component {
        id: buttons

        ColumnLayout {
            id: buttonList

            readonly property var entries: parent ? parent.items ?? [] : []

            spacing: 4

            Repeater {
                model: buttonList.entries

                HassEntry {
                    required property var modelData

                    Layout.fillWidth: true
                    item: modelData
                    onClicked: HomeAssistant.press(modelData.entity)
                }
            }
        }
    }

    Component {
        id: sensorRows

        ColumnLayout {
            id: sensorList

            readonly property var entries: parent ? parent.items ?? [] : []

            spacing: 4

            Repeater {
                model: sensorList.entries

                HassEntry {
                    required property var modelData

                    Layout.fillWidth: true
                    item: modelData
                    clickable: false
                    trailing: HomeAssistant.value(modelData.entity)
                }
            }
        }
    }

    // Several values side by side in one block.
    Component {
        id: sensorBlock

        Rectangle {
            id: block

            readonly property var entries: parent ? parent.items ?? [] : []

            implicitHeight: blockRow.implicitHeight + 24
            radius: 14
            color: Config.colours.button

            // Equal columns, whatever their values' lengths.
            Row {
                id: blockRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Repeater {
                    model: block.entries

                    Column {
                        id: value

                        required property var modelData

                        width: blockRow.width / Math.max(1, block.entries.length)
                        spacing: 4

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: HomeAssistant.icon(value.modelData)
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.icon + 2
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: HomeAssistant.value(value.modelData.entity)
                            elide: Text.ElideRight
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.size
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: HomeAssistant.name(value.modelData)
                            elide: Text.ElideRight
                            color: Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }
        }
    }
}
