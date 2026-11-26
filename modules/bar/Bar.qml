import QtQuick
import Quickshell
import qs.config
import qs.services

// Bar content area inside the thick top border.
Item {
    id: root

    required property ShellScreen screen

    signal clockClicked
    // The update status, for its details.
    signal updatesClicked

    Workspaces {
        anchors.left: parent.left
        anchors.leftMargin: Config.bar.padding
        anchors.verticalCenter: parent.verticalCenter
        screen: root.screen
    }

    Clock {
        id: clock

        anchors.centerIn: parent
        onClicked: root.clockClicked()
    }

    // Left of the clock: a recording running, and timers.
    Row {
        anchors.right: clock.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        PrivacyDot {
            anchors.verticalCenter: parent.verticalCenter
        }

        RecordingDot {
            anchors.verticalCenter: parent.verticalCenter
        }

        TimerCountdown {
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    VocabDue {
        anchors.left: clock.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Config.bar.padding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        UpdatesDue {
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.updatesClicked()
        }

        NetSpeed {
            anchors.verticalCenter: parent.verticalCenter
        }

        UsageBar {
            anchors.verticalCenter: parent.verticalCenter
            label: "CPU"
            value: SystemUsage.cpu
        }

        UsageBar {
            anchors.verticalCenter: parent.verticalCenter
            label: "RAM"
            value: SystemUsage.ram
        }

        Battery {
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
