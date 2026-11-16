import QtQuick
import Quickshell.Widgets
import qs.config

// Rounded album art with a placeholder note while it loads or when there is none.
ClippingRectangle {
    id: root

    property alias source: image.source

    radius: Math.min(width, height) / 4
    color: Config.colours.button

    Text {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: "\u{F075A}"
        color: Config.colours.muted
        font.family: Config.font.family
        font.pointSize: Math.max(8, root.height / 3)
    }

    Image {
        id: image

        anchors.fill: parent
        sourceSize: Qt.size(root.width * 2, root.height * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }
}
