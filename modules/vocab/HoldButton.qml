import QtQuick
import qs.config

// A pill that has to be held down for `duration` ms before it acts, filling up meanwhile;
// letting go early empties it again.
Rectangle {
    id: root

    property string text
    property int duration: 3000

    signal held

    function letGo(): void {
        grow.stop();
        if (fill.progress > 0)
            shrink.start();
    }

    implicitWidth: label.implicitWidth + 40
    implicitHeight: 36
    radius: height / 2
    color: area.containsMouse ? Config.colours.buttonHover : Config.colours.button
    clip: true

    Rectangle {
        id: fill

        property real progress

        width: parent.width * progress
        height: parent.height
        radius: parent.radius
        color: Config.colours.active

        NumberAnimation on progress {
            id: grow

            running: false
            to: 1
            onFinished: {
                if (fill.progress >= 1) {
                    root.held();
                    fill.progress = 0;
                }
            }
        }

        NumberAnimation on progress {
            id: shrink

            running: false
            to: 0
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: area.pressed ? `Hold… ${Math.ceil(root.duration * (1 - fill.progress) / 1000)}` : root.text
        color: fill.progress > 0.5 ? Config.colours.activeText : Config.colours.text
        font.family: Config.font.family
        font.pointSize: Config.font.small
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            shrink.stop();
            grow.duration = root.duration * (1 - fill.progress);
            grow.start();
        }
        onReleased: root.letGo()
        onCanceled: root.letGo()
    }
}
