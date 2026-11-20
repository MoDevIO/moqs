import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.modules.lock

// The login screen: the lock screen's clock and password field, with who logs in above it
// and the session (Hyprland, GNOME, Steam, …) below. Power buttons sit in the corner, the
// weather at the bottom when weather.json is there.
Item {
    id: root

    property bool picking

    // A known session's icon, else a screen.
    function sessionIcon(s: var): string {
        const k = `${s?.key ?? ""} ${s?.name ?? ""}`.toLowerCase();
        if (k.includes("steam") || k.includes("gamescope"))
            return "\u{F04D3}";
        if (k.includes("gnome"))
            return "\u{F02AC}";
        if (k.includes("hyprland"))
            return "\u{F05AF}";
        return "\u{F0379}";
    }

    opacity: 0
    Component.onCompleted: {
        opacity = 1;
        field.focusField();
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: Greeter

        function onStateChanged(): void {
            if (Greeter.state === "failed")
                field.fail();
        }

        function onQuestionChanged(): void {
            field.clear();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.picking = false;
            field.focusField();
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.08
        spacing: 34

        Clock {
            Layout.alignment: Qt.AlignHCenter
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            // Who logs in; the arrows (or clicking the name) switch between users.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Chevron {
                    visible: Greeter.users.length > 1
                    icon: "\u{F0141}"
                    onClicked: Greeter.cycleUser(-1)
                }

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 14
                    color: Config.colours.button

                    Text {
                        anchors.centerIn: parent
                        text: Greeter.displayName(Greeter.user).charAt(0).toUpperCase()
                        color: Config.colours.text
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                        font.bold: true
                    }
                }

                Text {
                    text: Greeter.displayName(Greeter.user) || "No users"
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    font.bold: true

                    MouseArea {
                        anchors.fill: parent
                        enabled: Greeter.users.length > 1
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: Greeter.cycleUser(1)
                    }
                }

                Chevron {
                    visible: Greeter.users.length > 1
                    icon: "\u{F0142}"
                    onClicked: Greeter.cycleUser(1)
                }
            }

            PasswordField {
                id: field

                Layout.alignment: Qt.AlignHCenter
                checking: Greeter.state === "checking" || Greeter.state === "launching"
                failed: Greeter.state === "failed"
                message: Greeter.message
                placeholder: Greeter.question || "Password"
                echo: Greeter.question !== "" && Greeter.questionEcho
                onSubmitted: text => Greeter.submit(text)
                onEdited: {
                    Greeter.state = "idle";
                    Greeter.message = "";
                }
            }

            // The session to start; a click lists the others.
            Rectangle {
                id: sessionChip

                Layout.alignment: Qt.AlignHCenter
                implicitWidth: sessionRow.implicitWidth + 28
                implicitHeight: 32
                radius: height / 2
                color: sessionArea.containsMouse || root.picking ? Config.colours.buttonHover : "transparent"

                RowLayout {
                    id: sessionRow

                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: root.sessionIcon(Greeter.currentSession)
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.size
                    }

                    Text {
                        text: Greeter.currentSession?.name ?? "No sessions found"
                        color: Config.colours.subtext
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }

                    Text {
                        visible: Greeter.sessions.length > 1
                        text: "\u{F0140}"
                        color: Config.colours.muted
                        font.family: Config.font.family
                        font.pointSize: Config.font.small
                    }
                }

                MouseArea {
                    id: sessionArea

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: Greeter.sessions.length > 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picking = !root.picking
                }

                // The sessions, under the chip.
                Rectangle {
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 260
                    height: sessionList.implicitHeight + 12
                    radius: Config.border.rounding - 6
                    color: Config.colours.card
                    visible: root.picking
                    z: 10

                    Column {
                        id: sessionList

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: 2

                        Repeater {
                            model: Greeter.sessions

                            Rectangle {
                                id: option

                                required property var modelData
                                readonly property bool chosen: Greeter.currentSession?.key === modelData.key && Greeter.currentSession?.type === modelData.type

                                width: parent.width
                                height: 34
                                radius: height / 2
                                color: optionArea.containsMouse ? Config.colours.buttonHover : chosen ? Config.colours.button : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Text {
                                        text: root.sessionIcon(option.modelData)
                                        color: Config.colours.subtext
                                        font.family: Config.font.family
                                        font.pointSize: Config.font.size
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: option.modelData.name
                                        elide: Text.ElideRight
                                        color: Config.colours.text
                                        font.family: Config.font.family
                                        font.pointSize: Config.font.small
                                        font.bold: option.chosen
                                    }
                                }

                                MouseArea {
                                    id: optionArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Greeter.pickSession(option.modelData.key);
                                        root.picking = false;
                                        field.focusField();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Weather, if weather.json is there.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        visible: Weather.configured && Weather.current !== null
        implicitWidth: weatherRow.implicitWidth + 32
        implicitHeight: 52
        radius: Config.border.rounding - Config.dashboard.padding / 2
        color: Config.colours.card
        Component.onCompleted: Weather.refreshIfStale()

        RowLayout {
            id: weatherRow

            anchors.centerIn: parent
            spacing: 10

            Text {
                text: Weather.current ? Weather.icon(Weather.current.code, Weather.current.day) : ""
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.icon + 2
            }

            Text {
                text: Weather.current ? `${Weather.degrees(Weather.current.temp)}  ${Weather.describe(Weather.current.code)}` : ""
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }
    }

    // Suspend, restart, power off.
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        spacing: 8

        Repeater {
            model: [
                { icon: "\u{F0904}", command: ["systemctl", "suspend"] },
                { icon: "\u{F0709}", command: ["systemctl", "reboot"] },
                { icon: "\u{F0425}", command: ["systemctl", "poweroff"] }
            ]

            Rectangle {
                id: power

                required property var modelData

                width: 40
                height: 40
                radius: 20
                color: powerArea.containsMouse ? Config.colours.buttonHover : Config.colours.button

                Text {
                    anchors.centerIn: parent
                    text: power.modelData.icon
                    color: powerArea.containsMouse ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.icon
                }

                MouseArea {
                    id: powerArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(power.modelData.command)
                }
            }
        }
    }

    component Chevron: Text {
        id: chevron

        property string icon
        signal clicked

        text: icon
        color: chevronArea.containsMouse ? Config.colours.text : Config.colours.muted
        font.family: Config.font.family
        font.pointSize: Config.font.size

        MouseArea {
            id: chevronArea

            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chevron.clicked()
        }
    }
}
