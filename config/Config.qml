pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property QtObject border: QtObject {
        readonly property int thickness: 8
        readonly property int rounding: 20
        readonly property color colour: "#000000"
    }

    readonly property QtObject bar: QtObject {
        readonly property int height: 36
        readonly property int padding: 12
        // Battery percentage beside the icon at start; clicking the icon toggles it.
        readonly property bool showBatteryPercentage: false
    }

    readonly property QtObject workspaces: QtObject {
        // Workspaces 1..shown are always visible; the rest only when occupied or active.
        readonly property int shown: 5
        // Workspaces per monitor (monitor id * perMonitor + 1..perMonitor).
        readonly property int perMonitor: 10
        readonly property int size: 26
        // Width each workspace takes, and its dot sizes.
        readonly property int slot: 18
        readonly property int dot: 6
        readonly property int activeDot: 10
    }

    readonly property QtObject notifs: QtObject {
        readonly property int width: 360
        readonly property int timeout: 5000
        readonly property int padding: 12
        readonly property int spacing: 8
        // Fraction of the screen height the notification centre may use.
        readonly property real maxHeight: 0.7
        // How close (px) to the top-right screen corner the pointer must get.
        readonly property int hotCorner: 2
    }

    readonly property QtObject controlCentre: QtObject {
        readonly property int width: 380
        readonly property int padding: 12
        readonly property int spacing: 8
    }

    readonly property QtObject music: QtObject {
        readonly property int width: 420
        readonly property int height: 520
    }

    readonly property QtObject matrix: QtObject {
        readonly property int width: 440
        readonly property int height: 580
    }

    readonly property QtObject font: QtObject {
        readonly property string family: "JetBrainsMono Nerd Font"
        // Proportional UI font, for short labels such as the battery percentage.
        readonly property string sans: "Inter"
        readonly property int size: 12
        readonly property int small: 10
        readonly property int icon: 15
    }

    readonly property QtObject colours: QtObject {
        readonly property color text: "#ffffff"
        readonly property color subtext: "#9a9a9a"
        readonly property color muted: "#3c3c3c"
        readonly property color card: "#141414"
        readonly property color button: "#232323"
        readonly property color buttonHover: "#323232"
        readonly property color active: "#ffffff"
        readonly property color activeText: "#000000"
    }

    readonly property QtObject hyprland: QtObject {
        // Outer gap between windows and the frame.
        readonly property int gapsOut: 4
    }
}
