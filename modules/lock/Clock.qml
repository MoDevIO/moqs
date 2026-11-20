import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config

// The big time and the date under it, for the lock and login screens.
ColumnLayout {
    spacing: 6

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Config.colours.text
        font.family: Config.font.family
        font.pointSize: 84
        font.weight: Font.Light
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
        color: Config.colours.subtext
        font.family: Config.font.family
        font.pointSize: Config.font.size + 2
    }
}
