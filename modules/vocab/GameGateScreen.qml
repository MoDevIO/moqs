import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// The card a Steam game waits behind (GameGate), full screen on the monitor it opened on.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData
        // Seconds until the emergency button works.
        property int emergencyLeft

        screen: modelData
        visible: GameGate.active && (GameGate.screen === "" || modelData.name === GameGate.screen)
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: Config.border.colour
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "moqs-vocab-gate"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) Qt.callLater(quiz.focusInput)

        Timer {
            running: win.visible && !GameGate.emergencyReady
            repeat: true
            triggeredOnStart: true
            interval: 250
            onTriggered: win.emergencyLeft = Math.max(0, Math.ceil((GameGate.since + Config.vocab.emergency * 1000 - Date.now()) / 1000))
        }

        MouseArea {
            anchors.fill: parent
            onClicked: quiz.focusInput()
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: 420
            spacing: 22

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: `\u{F0297}  One word, then ${GameGate.game || "the game"}`
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.size
            }

            VocabQuiz {
                id: quiz

                Layout.fillWidth: true
                session: GameGate.session
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: GameGate.emergencyReady ? "\u{F0026}  Emergency: start it now" : `Emergency in ${win.emergencyLeft} s`
                color: !GameGate.emergencyReady ? Config.colours.muted : emergency.containsMouse ? Config.colours.text : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small

                MouseArea {
                    id: emergency

                    anchors.fill: parent
                    anchors.margins: -6
                    enabled: GameGate.emergencyReady
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GameGate.emergencyUnlock()
                }
            }
        }
    }
}
