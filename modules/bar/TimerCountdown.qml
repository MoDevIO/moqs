import QtQuick
import qs.config
import qs.services

// The soonest timer counting down (and how many more run); a click asks "Cancel?", a second
// one cancels it.
Item {
    id: root

    property bool asking

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: Timers.next !== null

    onVisibleChanged: asking = false

    Timer {
        id: askTimer

        interval: 3000
        onTriggered: root.asking = false
    }

    Row {
        id: row

        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F13AB}"
            color: root.asking ? Config.colours.red : area.containsMouse ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.size
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !Timers.next ? "" : root.asking ? "Cancel?" : Timers.format(Timers.next.end - Timers.now) + (Timers.timers.length > 1 ? ` +${Timers.timers.length - 1}` : "")
            color: root.asking ? Config.colours.red : area.containsMouse ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.asking && Timers.next) {
                Timers.cancel(Timers.next.id);
                root.asking = false;
            } else {
                root.asking = true;
                askTimer.restart();
            }
        }
    }
}
