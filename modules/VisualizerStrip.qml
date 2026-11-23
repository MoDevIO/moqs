import QtQuick
import qs.config
import qs.services

// Audio bars rising out of the bottom border while something plays, from cava.
Item {
    id: root

    readonly property int count: Visualizer.levels.length

    opacity: Visualizer.running && count > 0 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 400
        }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Config.visualizer.gap

        Repeater {
            model: root.count

            delegate: Rectangle {
                required property int index

                anchors.bottom: parent.bottom
                width: Math.max(1, (root.width - Config.visualizer.gap * (root.count - 1)) / root.count)
                height: Math.max(1, root.height * (Visualizer.levels[index] ?? 0))
                radius: Math.min(width / 2, 2)
                color: Qt.alpha(Config.colours.active, Config.visualizer.opacity)
            }
        }
    }
}
