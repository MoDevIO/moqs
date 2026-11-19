import QtQuick
import QtQuick.Layouts
import qs.config

// Toggle tile: white when on.
Rectangle {
    id: root

    property bool checked
    property string icon
    property string title
    property string subtitle
    property bool enabled: true
    property bool expanded
    // The chevron, for a popover to open from.
    readonly property Item expandButton: expand

    signal clicked
    signal expandClicked

    implicitHeight: 56
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: checked ? Config.colours.active : area.containsMouse && enabled ? Config.colours.buttonHover : Config.colours.card
    opacity: enabled ? 1 : 0.5

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 12

        Text {
            text: root.icon
            color: root.checked ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.icon
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                color: root.checked ? Config.colours.activeText : Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.size
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                elide: Text.ElideRight
                color: root.checked ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }

        // Opens the device list.
        ExpandButton {
            id: expand

            expanded: root.expanded
            inverted: root.checked
            enabled: root.enabled
            onClicked: root.expandClicked()
        }
    }
}
