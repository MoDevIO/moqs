import QtQuick

// Pulls a panel out of the frame: dragging away from the border grows it with the pointer,
// and on release it opens if pulled far enough. The panel has dragHeight, dragTo(height)
// and release().
MouseArea {
    id: root

    required property Item panel
    // Pulled downwards, out of the top border; otherwise upwards.
    property bool downwards
    property real startY
    property real startHeight

    function sceneY(mouse: var): real {
        return mapToItem(null, mouse.x, mouse.y).y;
    }

    hoverEnabled: true
    cursorShape: Qt.SizeVerCursor
    onPressed: mouse => {
        startY = sceneY(mouse);
        startHeight = panel.height;
        panel.dragTo(startHeight);
    }
    onPositionChanged: mouse => {
        if (pressed)
            panel.dragTo(startHeight + (downwards ? sceneY(mouse) - startY : startY - sceneY(mouse)));
    }
    onReleased: panel.release()
    onCanceled: panel.release()
}
