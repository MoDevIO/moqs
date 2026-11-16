import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs.config

Rectangle {
    id: root

    required property var modelData
    readonly property Notification notif: modelData.notification
    readonly property string image: notif?.image || Quickshell.iconPath(notif?.appIcon ?? "", true)
    property date now: new Date()

    function ago(): string {
        const mins = Math.floor((now - modelData.time) / 60000);
        if (mins < 1)
            return "now";
        if (mins < 60)
            return `${mins}m`;
        const hours = Math.floor(mins / 60);
        return hours < 24 ? `${hours}h` : `${Math.floor(hours / 24)}d`;
    }

    implicitHeight: layout.implicitHeight + Config.notifs.padding * 2
    radius: Config.border.rounding - Config.notifs.padding / 2
    color: Config.colours.card

    Timer {
        running: true
        repeat: true
        interval: 30000
        onTriggered: root.now = new Date()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const action = root.notif?.actions.find(a => a.identifier === "default");
            if (action)
                action.invoke();
            else
                root.modelData.popup = false;
        }
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Config.notifs.padding
        spacing: Config.notifs.padding

        Image {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            visible: root.image !== "" && status !== Image.Error
            source: root.image
            sourceSize: Qt.size(72, 72)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: `${root.notif?.appName || "Notification"} · ${root.ago()}`
                    elide: Text.ElideRight
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                Text {
                    text: "󰅖"
                    color: close.containsMouse ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size

                    MouseArea {
                        id: close

                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.notif?.dismiss()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.notif?.summary ?? ""
                elide: Text.ElideRight
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.size
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.notif?.body ?? ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Config.colours.subtext
                linkColor: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.small
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: actions.count > 0
                spacing: 6

                Repeater {
                    id: actions

                    // The default action is triggered by clicking the card itself.
                    model: root.notif?.actions.filter(a => a.identifier !== "default") ?? []

                    Rectangle {
                        id: button

                        required property NotificationAction modelData

                        // Sized by label, then stretched to share the row.
                        Layout.fillWidth: true
                        implicitWidth: label.implicitWidth + 16
                        implicitHeight: label.implicitHeight + 12
                        radius: height / 2
                        color: buttonArea.containsMouse ? Config.colours.buttonHover : Config.colours.button

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Text {
                            id: label

                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: button.modelData.text
                            elide: Text.ElideRight
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }

                        MouseArea {
                            id: buttonArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: button.modelData.invoke()
                        }
                    }
                }
            }
        }
    }
}
