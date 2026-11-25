import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// How the bar shows workspaces; the current style is white.
Rectangle {
    id: root

    signal picked

    implicitHeight: layout.implicitHeight + 12
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Repeater {
            model: WorkspaceStyle.styles

            ListRow {
                required property string modelData

                Layout.fillWidth: true
                active: WorkspaceStyle.style === modelData
                icon: WorkspaceStyle.icon(modelData)
                title: WorkspaceStyle.name(modelData)
                onClicked: {
                    WorkspaceStyle.set(modelData);
                    root.picked();
                }
            }
        }
    }
}
