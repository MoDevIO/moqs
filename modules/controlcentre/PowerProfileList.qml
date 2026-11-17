import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Power profiles to pick from; the current one is white.
Rectangle {
    id: root

    implicitHeight: layout.implicitHeight + 12
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Repeater {
            model: PowerProfiles.order.filter(p => PowerProfiles.profiles.includes(p))

            ListRow {
                required property string modelData

                Layout.fillWidth: true
                active: PowerProfiles.profile === modelData
                icon: PowerProfiles.icon(modelData)
                title: PowerProfiles.name(modelData)
                onClicked: PowerProfiles.set(modelData)
            }
        }
    }
}
