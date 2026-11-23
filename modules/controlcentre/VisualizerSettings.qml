import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// How high the visualizer's bars reach; the bars follow as the slider moves.
Rectangle {
    id: root

    implicitHeight: layout.implicitHeight + 24
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Text {
            text: "Height"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Slider {
            Layout.fillWidth: true
            trackColour: Config.colours.button
            value: (Visualizer.height - Visualizer.minHeight) / (Visualizer.maxHeight - Visualizer.minHeight)
            valueText: `${Visualizer.height} px`
            icon: "\u{F147D}"
            onMoved: v => Visualizer.setHeight(Math.round(Visualizer.minHeight + v * (Visualizer.maxHeight - Visualizer.minHeight)))
        }
    }
}
