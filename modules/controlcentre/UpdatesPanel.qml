import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

// Behind the Updates tile, and opened by the bar's snowflake: how far nixpkgs is behind, the
// update running or last run (its steps, the inputs it moved, the packages whose version
// changes, and its last output when it failed), and buttons to check, update (asked twice,
// as it takes a while) and open the log.
Item {
    id: root

    property bool confirming
    property real now: Date.now()

    readonly property var stepOrder: ["inputs", "build", "switch"]
    readonly property var stepNames: ({ inputs: "Update the flake's inputs", build: "Build the new system", switch: "Switch to it" })
    readonly property bool ran: Updates.running || Updates.step !== ""
    readonly property bool upToDateRun: Updates.step === "done" && Updates.message === "Already up to date"

    function day(ms: real): string {
        return ms ? Qt.formatDate(new Date(ms), "ddd d MMM") : "?";
    }

    function shortDate(iso: string): string {
        return iso ? Qt.formatDate(new Date(`${iso}T12:00:00`), "d MMM") : "";
    }

    // "4 min", "1 h 12 min".
    function duration(ms: real): string {
        const min = Math.max(0, Math.floor(ms / 60000));
        return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`;
    }

    // Each step's state: done, running, failed, skipped or todo.
    function stepState(name: string): string {
        const i = Updates.reached.indexOf(name);
        const last = Updates.reached.filter(s => stepOrder.includes(s)).slice(-1)[0];
        if (Updates.running)
            return name === Updates.step ? "running" : i >= 0 ? "done" : "todo";
        if (Updates.step === "failed")
            return name === last ? "failed" : i >= 0 ? "done" : "todo";
        if (Updates.step === "done")
            return i >= 0 ? "done" : "skipped";
        return "todo";
    }

    implicitHeight: layout.implicitHeight + 24

    Timer {
        running: Updates.running
        repeat: true
        triggeredOnStart: true
        interval: 10000
        onTriggered: root.now = Date.now()
    }

    Timer {
        id: confirmTimer

        interval: 3000
        onTriggered: root.confirming = false
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // How far behind.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: Updates.behind < 0 ? (Updates.checkError || "Checking nixpkgs…") : Updates.behind === 0 ? "nixpkgs is up to date" : `nixpkgs is ${Updates.behind} day${Updates.behind === 1 ? "" : "s"} behind`
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.size
                font.bold: true
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: Updates.locked > 0
                text: `Yours from ${root.day(Updates.locked)}${Updates.latest ? ` · newest on ${Updates.branch || "its branch"} from ${root.day(Updates.latest)}` : ""}`
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                text: `${Updates.flake.replace(Quickshell.env("HOME"), "~")} · ${Updates.host}`
                color: Config.colours.muted
                font.family: Config.font.family
                font.pointSize: Config.font.small
                elide: Text.ElideMiddle
            }
        }

        // The update running or last run.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.ran
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: Updates.running ? `Updating · ${root.duration(root.now - Updates.startedAt)}` : Updates.step === "failed" ? `Last update failed${Updates.endedAt ? ` · ${Qt.formatDateTime(new Date(Updates.endedAt), "ddd hh:mm")}` : ""}` : `Last update · ${Updates.message || "done"}${Updates.endedAt ? ` · ${Qt.formatDateTime(new Date(Updates.endedAt), "ddd hh:mm")}` : ""}${Updates.endedAt && Updates.startedAt ? `, took ${root.duration(Updates.endedAt - Updates.startedAt)}` : ""}`
                color: Updates.step === "failed" ? Config.colours.red : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.stepOrder

                RowLayout {
                    id: stepRow

                    required property string modelData
                    readonly property string state: root.stepState(modelData)

                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: ({ done: "\u{F012C}", running: "\u{F0996}", failed: "\u{F0156}", skipped: "\u{F0374}", todo: "\u{F0766}" })[stepRow.state]
                        color: ({ done: Config.colours.green, running: Config.colours.text, failed: Config.colours.red })[stepRow.state] ?? Config.colours.muted
                        font.family: Config.font.family
                        font.pointSize: Config.font.small

                        SequentialAnimation on opacity {
                            running: stepRow.state === "running"
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) parent.opacity = 1

                            NumberAnimation {
                                to: 0.3
                                duration: 600
                            }
                            NumberAnimation {
                                to: 1
                                duration: 600
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.stepNames[stepRow.modelData] + (stepRow.state === "skipped" && root.upToDateRun ? " · nothing changed" : "")
                        color: stepRow.state === "todo" || stepRow.state === "skipped" ? Config.colours.muted : Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }
            }
        }

        // The inputs nix flake update moved.
        ColumnLayout {
            Layout.fillWidth: true
            visible: Updates.inputs.length > 0
            spacing: 2

            Text {
                text: `Inputs updated · ${Updates.inputs.length}`
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Repeater {
                model: Updates.inputs

                RowLayout {
                    id: inputRow

                    required property var modelData

                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: inputRow.modelData.name
                        elide: Text.ElideRight
                        color: Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        text: inputRow.modelData.added ? `new · ${root.shortDate(inputRow.modelData.to)}` : `${root.shortDate(inputRow.modelData.from)} → ${root.shortDate(inputRow.modelData.to)}`
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }
            }
        }

        // The packages whose version changes, from comparing the new system with this one.
        ColumnLayout {
            Layout.fillWidth: true
            visible: Updates.changes.length > 0 || Updates.resized > 0
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: `New versions · ${Updates.changes.length}${Updates.resized ? ` · ${Updates.resized} more changed in size only` : ""}`
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
                wrapMode: Text.Wrap
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(changeList.implicitHeight, 180)
                contentHeight: changeList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: changeList

                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: Updates.changes

                        RowLayout {
                            id: changeRow

                            required property var modelData

                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: changeRow.modelData.name
                                elide: Text.ElideRight
                                color: Config.colours.text
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                            }

                            Text {
                                Layout.maximumWidth: 190
                                text: !changeRow.modelData.from ? `new · ${changeRow.modelData.to}` : !changeRow.modelData.to ? `removed · was ${changeRow.modelData.from}` : `${changeRow.modelData.from} → ${changeRow.modelData.to}`
                                elide: Text.ElideLeft
                                color: !changeRow.modelData.to ? Config.colours.red : Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                            }
                        }
                    }
                }
            }
        }

        // What it said last, when it failed.
        Rectangle {
            Layout.fillWidth: true
            visible: Updates.step === "failed" && Updates.tail.length > 0
            implicitHeight: tailText.implicitHeight + 12
            radius: 8
            color: Config.colours.button

            Text {
                id: tailText

                anchors.fill: parent
                anchors.margins: 6
                text: Updates.tail.join("\n")
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 12
                elide: Text.ElideRight
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small - 1
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Button {
                visible: !Updates.running
                text: root.confirming ? "Click again to update" : "Update now"
                primary: true
                onClicked: {
                    if (!root.confirming) {
                        root.confirming = true;
                        confirmTimer.restart();
                        return;
                    }
                    root.confirming = false;
                    Updates.update();
                }
            }

            Button {
                visible: !Updates.running
                text: "Check"
                onClicked: Updates.check()
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                visible: root.ran
                text: "Log"
                onClicked: Qt.openUrlExternally(`file://${Updates.logPath}`)
            }
        }
    }

    component Button: Rectangle {
        id: button

        property string text
        property bool primary

        signal clicked

        implicitWidth: label.implicitWidth + 24
        implicitHeight: 30
        radius: height / 2
        color: primary ? (area.containsMouse ? Qt.lighter(Config.colours.active, 1.1) : Config.colours.active) : area.containsMouse ? Config.colours.buttonHover : Config.colours.button

        Text {
            id: label

            anchors.centerIn: parent
            text: button.text
            color: button.primary ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
