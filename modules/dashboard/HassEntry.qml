import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// One Home Assistant entity on a row: icon, name, and a value or state on the right.
Rectangle {
    id: entry

    property var item
    property bool active
    property bool clickable: true
    property string trailing

    signal clicked

    implicitHeight: 36
    radius: height / 2
    color: active ? Config.colours.active : clickable && hover.hovered ? Config.colours.buttonHover : Config.colours.button

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    HoverHandler {
        id: hover

        cursorShape: entry.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: entry.clickable
        onTapped: entry.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 14
        spacing: 10

        Text {
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            text: entry.item ? HomeAssistant.icon(entry.item) : ""
            color: entry.active ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.size
        }

        Text {
            Layout.fillWidth: true
            text: entry.item ? HomeAssistant.name(entry.item) : ""
            elide: Text.ElideRight
            color: entry.active ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Text {
            visible: text !== ""
            text: entry.trailing
            color: entry.active ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }
}
