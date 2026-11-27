import QtQuick
import QtQuick.Layouts
import qs.config

// One of the vocabulary pane's rating buttons, as Anki's: its key, the rating in its colour
// (Hard orange, Good green, Easy blue) and when it brings the word back.
Rectangle {
    id: root

    property string key
    property string label
    property string when
    property color tint
    // Enter's choice, outlined.
    property bool chosen

    signal clicked

    implicitHeight: 52
    radius: 12
    color: area.pressed ? Config.colours.buttonHover : area.containsMouse ? Config.colours.buttonHover : Config.colours.button
    border.width: chosen ? 1.5 : 0
    border.color: Qt.alpha(root.tint, 0.6)

    Behavior on color {
        ColorAnimation {
            duration: 100
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 2

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            // The key, in a small box.
            Rectangle {
                implicitWidth: 16
                implicitHeight: 16
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: Config.colours.muted

                Text {
                    anchors.centerIn: parent
                    text: root.key
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small - 1
                }
            }

            Text {
                text: root.label
                color: root.tint
                font.family: Config.font.family
                font.pointSize: Config.font.size
                font.bold: true
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.when
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
