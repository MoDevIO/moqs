import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.controlcentre as CC
import qs.modules.lock
import qs.services

// A polkit request (Auth): what wants permission, and the password field of the lock screen,
// in a pane that grows out of the middle of the bar like the control centre. Enter answers,
// Escape (or Cancel) refuses.
Item {
    id: root

    property bool open
    readonly property var flow: Auth.flow

    onOpenChanged: {
        if (open) {
            field.clear();
            Qt.callLater(field.focusField);
        }
    }

    Connections {
        target: root.flow

        function onAuthenticationFailed(): void {
            field.fail();
        }
    }

    readonly property real fullWidth: Config.controlCentre.width
    readonly property real targetWidth: open ? fullWidth : Config.launcher.seed
    readonly property real targetHeight: open ? content.implicitHeight + Config.controlCentre.padding * 2 : 0

    width: targetWidth
    height: targetHeight
    visible: height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    CC.Background {
        anchors.fill: parent
    }

    // Content keeps its full size while the pane animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.topMargin: Config.controlCentre.padding
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.fullWidth - Config.controlCentre.padding * 2
            spacing: 12
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12

                Text {
                    text: "\u{F099D}"
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: 20
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Permission needed"
                        color: Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.size
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.flow?.message ?? ""
                        wrapMode: Text.Wrap
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }
            }

            PasswordField {
                id: field

                Layout.alignment: Qt.AlignHCenter
                placeholder: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password"
                echo: root.flow?.responseVisible ?? false
                checking: root.open && !(root.flow?.isResponseRequired ?? true)
                failed: root.flow?.failed ?? false
                message: root.flow?.supplementaryMessage || (root.flow?.failed ? "Wrong password, try again" : "")
                onSubmitted: text => root.flow?.submit(text)
                onEscaped: root.flow?.cancelAuthenticationRequest()
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 2
                text: "Cancel"
                color: cancel.containsMouse ? Config.colours.text : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small

                MouseArea {
                    id: cancel

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.flow?.cancelAuthenticationRequest()
                }
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
