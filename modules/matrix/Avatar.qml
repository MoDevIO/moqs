import QtQuick
import Quickshell.Widgets
import qs.config

// Round avatar; shows the name's initial until the picture has loaded, or if there is none.
ClippingRectangle {
    id: root

    property alias source: image.source
    property string name

    radius: width / 2
    color: Config.colours.button

    Text {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: root.name.replace(/^[#@!]/, "").charAt(0).toUpperCase()
        color: Config.colours.text
        font.family: Config.font.family
        font.pointSize: Math.max(7, root.height / 3)
        font.bold: true
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
