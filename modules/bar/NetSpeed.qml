import QtQuick
import qs.config
import qs.services

// Download and upload rates, shown while either is above Config.bar.netThreshold (and a
// few seconds after, so it doesn't flicker).
Row {
    id: root

    readonly property bool busy: Math.max(SystemUsage.rx, SystemUsage.tx) >= Config.bar.netThreshold
    property bool shown

    onBusyChanged: {
        if (busy) {
            linger.stop();
            shown = true;
        } else {
            linger.restart();
        }
    }

    function rate(b: real): string {
        if (b >= 1e6)
            return `${(b / 1e6).toFixed(b >= 1e7 ? 0 : 1)} MB/s`;
        return `${Math.round(b / 1e3)} kB/s`;
    }

    spacing: 8
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 250
        }
    }

    Timer {
        id: linger

        interval: 6000
        onTriggered: root.shown = false
    }

    Repeater {
        model: [["\u{F0045}", SystemUsage.rx], ["\u{F005D}", SystemUsage.tx]]

        delegate: Row {
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData[0]
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.rate(modelData[1])
                color: Config.colours.text
                font.family: Config.font.sans
                font.pointSize: 8
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }
    }
}
