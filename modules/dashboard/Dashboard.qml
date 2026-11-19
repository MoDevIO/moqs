import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Pulled up from the bottom border: timetable and homework from WebUntis. Home Assistant
// and weather go here later.
Item {
    id: root

    property bool open: false
    // Pointer resting on the bottom border: a sliver shows that it can be pulled up.
    property bool peek: false
    // Height while the border is being dragged, or -1 when not dragging.
    property real dragHeight: -1
    // Keeps it open after a drag until the pointer has been over it: a pull past its full
    // height leaves the pointer above it, outside the frame, which would otherwise close it.
    property bool holdOpen

    readonly property bool dragging: dragHeight >= 0
    readonly property real fullHeight: Config.dashboard.height
    readonly property real targetWidth: open || dragging || peek ? Config.dashboard.width : 0
    readonly property real targetHeight: open ? fullHeight : 0

    // Follows the pointer while dragging; on release opens if pulled far enough.
    function dragTo(h: real): void {
        dragHeight = Math.max(0, Math.min(fullHeight, h));
    }

    function release(): void {
        open = dragHeight >= fullHeight * Config.dashboard.openAt;
        holdOpen = open;
        dragHeight = -1;
    }

    onOpenChanged: {
        if (!open)
            holdOpen = false;
        else
            WebUntis.refreshIfStale();
    }

    width: targetWidth
    height: dragging ? dragHeight : open ? fullHeight : peek ? Config.dashboard.peek : 0
    visible: width > 0 && height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        enabled: !root.dragging

        Anim {}
    }

    Background {
        anchors.fill: parent
    }

    // Content keeps its full size while the panel animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: content

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Config.dashboard.width
            height: root.fullHeight

            // Grab handle.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
                width: 40
                height: 4
                radius: 2
                color: Config.colours.muted
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Config.dashboard.padding
                anchors.topMargin: Config.dashboard.padding + 10
                spacing: Config.dashboard.spacing
                opacity: root.open || root.dragging ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }

                Timetable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                }

                Homework {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
