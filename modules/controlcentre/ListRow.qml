import QtQuick
import QtQuick.Layouts
import qs.config

// One selectable entry in a control centre list.
Rectangle {
    id: root

    property string icon
    property string title
    property string subtitle
    property string trailing
    property bool active

    signal clicked

    implicitHeight: 36
    radius: height / 2
    color: active ? Config.colours.active : area.containsMouse ? Config.colours.buttonHover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 10

        Text {
            Layout.preferredWidth: 18
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.active ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.size
        }

        Text {
            Layout.fillWidth: true
            text: root.title
            elide: Text.ElideRight
            color: root.active ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Text {
            visible: text !== ""
            text: root.subtitle
            color: root.active ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Text {
            visible: text !== ""
            text: root.trailing
            color: root.active ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }
}
