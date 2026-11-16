import QtQuick
import qs.config

// Thick slider with its icon inside the track. Clicking the icon calls iconClicked.
Item {
    id: root

    property real value
    property string icon
    property bool dimmed

    signal moved(real value)
    signal iconClicked

    implicitHeight: 36

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: Config.colours.card
        clip: true

        Rectangle {
            // Never narrower than the icon area, so the handle stays round.
            width: Math.max(track.height, track.width * Math.min(1, root.value))
            height: parent.height
            radius: height / 2
            color: root.dimmed ? Config.colours.subtext : Config.colours.active

            Behavior on width {
                enabled: !drag.pressed

                NumberAnimation {
                    duration: 120
                }
            }
        }
    }

    MouseArea {
        id: drag

        function update(x: real): void {
            root.moved(Math.max(0, Math.min(1, x / width)));
        }

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (mouse.x > track.height)
                update(mouse.x);
        }
        onPositionChanged: mouse => update(mouse.x)
        onClicked: mouse => {
            if (mouse.x <= track.height)
                root.iconClicked();
        }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }

    Text {
        x: (track.height - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: Config.colours.activeText
        font.family: Config.font.family
        font.pointSize: Config.font.icon
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: `${Math.round(root.value * 100)}`
        color: root.value > 0.88 ? Config.colours.activeText : Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.small
    }
}
