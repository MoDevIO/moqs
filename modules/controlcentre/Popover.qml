import QtQuick
import Quickshell
import qs.config

// A menu that pops out from where its button was clicked, over everything else, like on
// macOS. It closes on a click outside it, on Escape, or through close().
PopupWindow {
    id: root

    default property alias content: body.data
    property real contentWidth: 340
    // True while openAt closes the popover to reopen it for another button.
    property bool reopening

    // Opens at point (x, y) of item, growing down and to the left of it.
    function openAt(item: Item, x: real, y: real): void {
        closing.stop();
        // Already up for another button: a popup can't move once shown, so it reopens.
        if (visible && anchor.item !== item) {
            reopening = true;
            visible = false;
            reopening = false;
        }
        anchor.item = item;
        anchor.rect.x = x;
        anchor.rect.y = y;
        visible = true;
        // Animated once the window is on screen; started together with it, the first part
        // of the animation would play before anything shows and look like a stutter.
        appear.restart();
    }

    function close(): void {
        if (visible && card.shown) {
            card.shown = false;
            closing.restart();
        }
    }

    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Left
    // Flipped or slid back onto the screen when there's no room.
    anchor.adjustment: PopupAdjustment.All
    grabFocus: true
    color: "transparent"
    implicitWidth: contentWidth
    // Never 0: a popup without a size is a Wayland protocol error.
    implicitHeight: Math.max(1, body.implicitHeight)

    // Dismissed by the compositor (a click outside): reset for the next opening.
    onVisibleChanged: if (!visible) card.shown = false

    Timer {
        id: appear

        interval: 16
        onTriggered: card.shown = true
    }

    // Lets the fade-out finish before the window goes.
    Timer {
        id: closing

        interval: 120
        onTriggered: root.visible = false
    }

    Rectangle {
        id: card

        property bool shown

        anchors.fill: parent
        // Rows inside are pills 6px in; this keeps the corners running parallel to theirs.
        radius: 18 + 6
        color: Config.colours.card
        border.width: 1
        border.color: Config.colours.muted
        // Grows out of the corner at the click.
        transformOrigin: Item.TopRight
        scale: shown ? 1 : 0.94
        opacity: shown ? 1 : 0

        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: body

            anchors.fill: parent
            implicitHeight: childrenRect.height
            focus: true

            Keys.onEscapePressed: root.close()
        }
    }
}
