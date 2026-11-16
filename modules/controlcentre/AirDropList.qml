import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Nearby AirDrop receivers. Click one to open the send panel for it.
Rectangle {
    id: root

    property bool active

    signal picked(var device)

    // Look for receivers only while the list is shown.
    onActiveChanged: Owly.browse = active

    implicitHeight: layout.implicitHeight + 12
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Text {
            Layout.margins: 8
            visible: Owly.devices.length === 0
            text: !Owly.radioUp ? "Radio unavailable" : Owly.browsing ? "Searching…" : "No devices found"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Repeater {
            model: Owly.devices

            ListRow {
                required property var modelData

                Layout.fillWidth: true
                icon: "\u{F011C}"
                title: modelData.name
                trailing: "\u{F0142}"
                onClicked: root.picked(modelData)
            }
        }
    }
}
