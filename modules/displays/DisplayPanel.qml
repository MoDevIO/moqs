import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.controlcentre as CC
import qs.services

// The display panel, grown out of the middle of the bar: side by side (drag the displays
// into place; they snap edge to edge) or mirrored. Apply asks to keep the result and goes
// back by itself after Displays.keepSeconds. Escape or a click outside closes it (and goes
// back, while it's asking).
Item {
    id: root

    property bool open
    signal closed

    readonly property real fullHeight: content.implicitHeight + Config.displays.padding * 2

    width: open ? Config.displays.width : Config.launcher.seed
    height: open ? fullHeight : 0
    visible: height > 0
    focus: open

    onOpenChanged: if (open)
        forceActiveFocus()
    Keys.onEscapePressed: closed()

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    CC.Background {
        anchors.fill: parent
    }

    // Content keeps its full size while the panel grows, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.topMargin: Config.displays.padding
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.displays.width - Config.displays.padding * 2
            spacing: 12
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            ColumnLayout {
                spacing: 2

                Text {
                    text: "Displays"
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.size + 2
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: Displays.reason
                    elide: Text.ElideRight
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }

            // Extend or mirror.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: height / 2
                color: Config.colours.card

                Row {
                    anchors.fill: parent
                    anchors.margins: 3

                    Repeater {
                        model: [["extend", "\u{F037A}", "Side by side"], ["mirror", "\u{F11FD}", "Mirror"]]

                        delegate: Rectangle {
                            id: choice

                            required property var modelData
                            readonly property bool on: Displays.mode === modelData[0]

                            width: parent.width / 2
                            height: parent.height
                            radius: height / 2
                            color: on ? Config.colours.active : choiceArea.containsMouse ? Config.colours.buttonHover : "transparent"

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: choice.modelData[1]
                                    color: choice.on ? Config.colours.activeText : Config.colours.text
                                    font.family: Config.font.family
                                    font.pointSize: Config.font.icon
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: choice.modelData[2]
                                    color: choice.on ? Config.colours.activeText : Config.colours.text
                                    font.family: Config.font.family
                                    font.pointSize: Config.font.size
                                    font.bold: choice.on
                                }
                            }

                            MouseArea {
                                id: choiceArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: Displays.countdown === 0
                                onClicked: Displays.mode = choice.modelData[0]
                            }
                        }
                    }
                }
            }

            // The displays, to scale. Side by side they can be dragged; mirrored, a click
            // picks the one the others show.
            Rectangle {
                id: stage

                readonly property var list: Displays.monitors.filter(m => !m.disabled)
                readonly property bool mirror: Displays.mode === "mirror"
                // Bounds of the arrangement (mirrored: the displays in a row) in layout pixels.
                readonly property var boxes: {
                    let x = 0;
                    return list.map(m => {
                        const s = Displays.size(m);
                        const p = mirror ? { x, y: 0 } : (Displays.layout[m.name] ?? { x: m.x, y: m.y });
                        x += s.w + 200;
                        return { name: m.name, x: p.x, y: p.y, w: s.w, h: s.h };
                    });
                }
                readonly property real minX: Math.min(...boxes.map(b => b.x))
                readonly property real minY: Math.min(...boxes.map(b => b.y))
                readonly property real spanW: Math.max(...boxes.map(b => b.x + b.w)) - minX
                readonly property real spanH: Math.max(...boxes.map(b => b.y + b.h)) - minY
                // Room around it, for dragging a display past the others.
                readonly property real zoom: boxes.length ? Math.min((width - 40) / (spanW * 1.4), (height - 40) / (spanH * 1.4)) : 1
                readonly property real originX: (width - spanW * zoom) / 2 - minX * zoom
                readonly property real originY: (height - spanH * zoom) / 2 - minY * zoom

                Layout.fillWidth: true
                implicitHeight: Config.displays.stage
                radius: 14
                color: Config.colours.card
                clip: true

                Repeater {
                    model: stage.boxes

                    delegate: Rectangle {
                        id: screenBox

                        required property var modelData
                        readonly property var monitor: Displays.byName(modelData.name)
                        readonly property bool source: stage.mirror && Displays.mirrorSource === modelData.name
                        readonly property real homeX: stage.originX + modelData.x * stage.zoom
                        readonly property real homeY: stage.originY + modelData.y * stage.zoom

                        x: homeX
                        y: homeY
                        width: modelData.w * stage.zoom
                        height: modelData.h * stage.zoom
                        z: boxArea.drag.active ? 2 : 1
                        radius: 6
                        color: source ? Config.colours.active : boxArea.containsMouse ? Config.colours.buttonHover : Config.colours.button
                        border.width: 1
                        border.color: Config.colours.muted

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            spacing: 1

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: screenBox.modelData.name
                                elide: Text.ElideRight
                                color: screenBox.source ? Config.colours.activeText : Config.colours.text
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: screenBox.monitor ? `${screenBox.monitor.width}×${screenBox.monitor.height}` : ""
                                elide: Text.ElideRight
                                color: screenBox.source ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.small - 1
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                visible: stage.mirror
                                text: screenBox.source ? "Shown on all" : "Mirrors"
                                color: screenBox.source ? Qt.alpha(Config.colours.activeText, 0.6) : Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.small - 1
                            }
                        }

                        MouseArea {
                            id: boxArea

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: Displays.countdown === 0
                            cursorShape: stage.mirror ? Qt.PointingHandCursor : drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            drag.target: stage.mirror ? null : screenBox
                            drag.threshold: 4
                            onClicked: if (stage.mirror)
                                Displays.mirrorSource = screenBox.modelData.name
                            onReleased: {
                                if (!stage.mirror && drag.active)
                                    Displays.move(screenBox.modelData.name, (screenBox.x - stage.originX) / stage.zoom, (screenBox.y - stage.originY) / stage.zoom);
                                screenBox.x = Qt.binding(() => screenBox.homeX);
                                screenBox.y = Qt.binding(() => screenBox.homeY);
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: Displays.countdown > 0 ? `Keep these settings? Going back in ${Displays.countdown} s` : stage.mirror ? "Click the display the others should show" : stage.list.length > 1 ? "Drag the displays to arrange them" : "Only one display is connected"
                wrapMode: Text.Wrap
                color: Displays.countdown > 0 ? Config.colours.text : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                DisplayButton {
                    text: Displays.countdown > 0 ? "Go back" : "Close"
                    onClicked: Displays.countdown > 0 ? Displays.revert() : Displays.close()
                }

                DisplayButton {
                    primary: true
                    enabled: Displays.countdown > 0 || stage.list.length > 1
                    text: Displays.countdown > 0 ? "Keep" : "Apply"
                    onClicked: Displays.countdown > 0 ? Displays.keep() : Displays.apply()
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
