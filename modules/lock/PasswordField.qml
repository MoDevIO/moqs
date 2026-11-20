import QtQuick
import QtQuick.Layouts
import qs.config

// The password pill of the lock and login screens, with a message under it. While checking,
// the lock icon pulses and typing waits; fail() clears the field, shakes it and shows the
// message in red.
ColumnLayout {
    id: root

    property bool checking
    property bool failed
    property string message
    property string placeholder: "Password"
    // Show what's typed, for questions that aren't passwords.
    property bool echo
    readonly property alias text: input.text

    signal submitted(string text)
    // Typing again after a failure.
    signal edited

    function fail(): void {
        input.text = "";
        shake.restart();
    }

    function clear(): void {
        input.text = "";
    }

    function focusField(): void {
        input.forceActiveFocus();
    }

    spacing: 4

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 300
        implicitHeight: 44
        radius: height / 2
        color: Config.colours.button
        border.width: root.failed ? 1.5 : 0
        border.color: Config.colours.red

        transform: Translate {
            id: offset
        }

        SequentialAnimation {
            id: shake

            loops: 2

            NumberAnimation {
                target: offset
                property: "x"
                to: -8
                duration: 50
            }
            NumberAnimation {
                target: offset
                property: "x"
                to: 8
                duration: 80
            }
            NumberAnimation {
                target: offset
                property: "x"
                to: 0
                duration: 50
            }
        }

        Text {
            id: lockIcon

            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0341}"
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.icon

            // Pulses while the password is checked.
            SequentialAnimation on opacity {
                running: root.checking
                loops: Animation.Infinite
                onRunningChanged: if (!running) lockIcon.opacity = 1

                NumberAnimation {
                    to: 0.3
                    duration: 400
                }
                NumberAnimation {
                    to: 1
                    duration: 400
                }
            }
        }

        TextInput {
            id: input

            anchors.left: lockIcon.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 20
            verticalAlignment: TextInput.AlignVCenter
            echoMode: root.echo ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            readOnly: root.checking
            color: Config.colours.text
            selectionColor: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.size
            font.letterSpacing: root.echo ? 0 : 2
            clip: true
            focus: true

            onAccepted: if (text) root.submitted(text)
            onTextChanged: if (text && root.failed) root.edited()
            Keys.onEscapePressed: text = ""

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: root.checking ? "Checking…" : root.placeholder
                color: Config.colours.muted
                font.family: Config.font.family
                font.pointSize: Config.font.size
            }
        }
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        opacity: root.message ? 1 : 0
        text: root.message || " "
        color: root.failed ? Config.colours.red : Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.small

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }
}
