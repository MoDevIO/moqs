import QtQuick
import QtQuick.Layouts
import qs.config

// A dashboard widget: rounded card with a title, a note on the right and the content below.
Rectangle {
    id: root

    property string title
    property string note
    default property alias content: body.data

    radius: Config.border.rounding
    color: Config.colours.card

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Config.dashboard.padding
        spacing: Config.dashboard.spacing

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4

            Text {
                text: root.title
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.size
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: root.note
                elide: Text.ElideLeft
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }

        Item {
            id: body

            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
