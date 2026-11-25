import QtQuick
import Quickshell
import qs.config
import qs.services

// Bar content area inside the thick top border.
Item {
    id: root

    required property ShellScreen screen

    signal clockClicked

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
