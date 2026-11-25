import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// What the Capture tile can take: a screenshot of a window or region (picked on
// CaptureSelect), the screen or the active window, or a recording of a picked one or the screen.
Rectangle {
    id: root

    signal picked

    implicitHeight: layout.implicitHeight + 12
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Repeater {
            model: [
                { icon: "\u{F019E}", title: "Screenshot: pick a window or region", run: () => Capture.screenshot("pick") },
                { icon: "\u{F0379}", title: "Screenshot of the screen", run: () => Capture.screenshot("screen") },
                { icon: "\u{F0614}", title: "Screenshot of the active window", run: () => Capture.screenshot("window") },
                { icon: "\u{F0EC2}", title: "Record: pick a window or region", run: () => Capture.record("pick"), record: true },
                { icon: "\u{F0EC2}", title: "Record the screen", run: () => Capture.record("screen"), record: true }
            ].filter(x => !x.record || Capture.canRecord)

            ListRow {
                required property var modelData

                Layout.fillWidth: true
                icon: modelData.icon
                title: modelData.title
                onClicked: {
                    root.picked();
                    modelData.run();
                }
            }
        }
    }
}
