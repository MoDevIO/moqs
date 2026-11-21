import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.controlcentre as CC
import qs.services

// Lock, suspend, log out, restart and power off, in a pane that grows out of the middle of
// the bar like the launcher. Opened with qs ipc call session menu. Arrows (or Tab) move,
// Enter picks, the first letter picks directly, Escape or a click outside closes. Logging
// out, restarting and powering off ask once more: pick them twice.
Item {
    id: root

    property bool open
    signal closed

    // The one asking "Sure?", until picked again or the moment passes.
    property string confirming
    property int current: 0

    readonly property var actions: [
        { key: "lock", label: "Lock", icon: "\u{F033E}", confirm: false },
        { key: "suspend", label: "Suspend", icon: "\u{F04B2}", confirm: false },
        { key: "logout", label: "Log out", icon: "\u{F0343}", confirm: true },
        { key: "reboot", label: "Restart", icon: "\u{F0709}", confirm: true },
        { key: "poweroff", label: "Power off", icon: "\u{F0425}", confirm: true }
    ]

    function pick(index: int): void {
        const a = actions[index];
        current = index;
        if (a.confirm && confirming !== a.key) {
            confirming = a.key;
            confirmTimer.restart();
            return;
        }
        confirming = "";
        closed();
        Lock.run(a.key);
    }

    onOpenChanged: {
        confirming = "";
        if (open) {
            current = 0;
            keys.forceActiveFocus();
        }
    }

    readonly property real fullWidth: content.implicitWidth + Config.launcher.padding * 2
    readonly property real targetWidth: open ? fullWidth : Math.min(Config.launcher.seed, fullWidth)
    readonly property real targetHeight: open ? content.implicitHeight + Config.launcher.padding * 2 : 0

    width: targetWidth
    height: targetHeight
    visible: height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    Timer {
        id: confirmTimer

        interval: 3000
        onTriggered: root.confirming = ""
    }

    CC.Background {
        anchors.fill: parent
    }

    // Takes the keys while open.
    Item {
        id: keys

        focus: root.open

        Keys.onEscapePressed: root.closed()
        Keys.onLeftPressed: root.current = (root.current + root.actions.length - 1) % root.actions.length
        Keys.onRightPressed: root.current = (root.current + 1) % root.actions.length
        Keys.onTabPressed: root.current = (root.current + 1) % root.actions.length
        Keys.onBacktabPressed: root.current = (root.current + root.actions.length - 1) % root.actions.length
        Keys.onReturnPressed: root.pick(root.current)
        Keys.onEnterPressed: root.pick(root.current)
        Keys.onPressed: event => {
            // l, s, o (log out), r, p.
            const i = ["l", "s", "o", "r", "p"].indexOf(event.text.toLowerCase());
            if (i >= 0) {
                root.pick(i);
                event.accepted = true;
            }
        }
    }

    // Content keeps its full size while the pane animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        RowLayout {
            id: content

            anchors.top: parent.top
            anchors.topMargin: Config.launcher.padding
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            Repeater {
                model: root.actions

                Rectangle {
                    id: button

                    required property var modelData
                    required property int index
                    readonly property bool asking: root.confirming === modelData.key
                    readonly property bool selected: root.current === index

                    implicitWidth: 92
                    implicitHeight: 84
                    radius: 14
                    color: asking ? Config.colours.red : selected ? Config.colours.active : hover.hovered ? Config.colours.buttonHover : Config.colours.button

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    HoverHandler {
                        id: hover

                        onHoveredChanged: if (hovered)
                            root.current = button.index
                    }

                    TapHandler {
                        onTapped: root.pick(button.index)
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: button.modelData.icon
                            color: button.selected || button.asking ? Config.colours.activeText : Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: 20
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: button.asking ? "Sure?" : button.modelData.label
                            color: button.selected || button.asking ? Config.colours.activeText : Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
