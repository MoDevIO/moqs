import QtQuick
import QtQuick.Layouts
import qs.config

// A song or album in the music lists.
Rectangle {
    id: root

    property string cover
    property string title
    property string subtitle
    property string trailing
    property bool active

    signal clicked

    implicitHeight: 44
    radius: 12
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
        anchors.leftMargin: 6
        anchors.rightMargin: 12
        spacing: 10

        Cover {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            visible: root.cover !== ""
            source: root.cover
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                color: root.active ? Config.colours.activeText : Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.small
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                elide: Text.ElideRight
                color: root.active ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
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
