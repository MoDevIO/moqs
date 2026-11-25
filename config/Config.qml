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
        // Download or upload rate (bytes per second) above which the bar shows the rates.
        readonly property real netThreshold: 100000
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
        // Width each workspace takes as an icon or number, the icon's size, and the size of
        // the active number's disc.
        readonly property int wideSlot: 28
        readonly property int icon: 16
        readonly property int activeBadge: 24
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

    readonly property QtObject launcher: QtObject {
        readonly property int width: 560
        // Width it starts growing from, so it swells out of the bar rather than a point.
        readonly property int seed: 200
        readonly property int padding: 12
        // Height of one app row, and how many rows show before the list scrolls.
        readonly property int row: 44
        readonly property int shown: 8
        // Web search for "?…", %s being the query, unless settings.json sets launcher.search
        // (the Nix option services.moqs.launcher.searchEngine).
        readonly property string search: "https://duckduckgo.com/?q=%s"
    }

    // The level shown in place of the clock while volume or brightness changes.
    readonly property QtObject osd: QtObject {
        // Width of the level bar.
        readonly property int width: 140
        // How much one up or down changes the level, 0..1.
        readonly property real step: 0.05
        // ms the level stays after the last change, unless pressed.
        readonly property int timeout: 1500
    }

    readonly property QtObject clipboard: QtObject {
        // Most entries the clipboard list shows.
        readonly property int shown: 50
    }

    readonly property QtObject music: QtObject {
        readonly property int width: 420
        readonly property int height: 520
    }

    readonly property QtObject matrix: QtObject {
        readonly property int width: 440
        readonly property int height: 580
    }

    readonly property QtObject dashboard: QtObject {
        readonly property int width: 1400
        readonly property int height: 420
        // How far it peeks out while the pointer rests on the bottom border.
        readonly property int peek: 14
        // Fraction of its height it must be pulled up to stay open on release; the same goes
        // for corner panels set to be pulled out (dragToOpen in settings.json).
        readonly property real openAt: 0.3
        readonly property int padding: 12
        readonly property int spacing: 8
    }

    readonly property QtObject webuntis: QtObject {
        // Days ahead fetched to find the next school day, and homework looked at.
        readonly property int days: 14
        // Days ahead exams are looked for.
        readonly property int examDays: 120
        // Back-to-back lessons with the same details merge into one if the break between
        // them is at most this many minutes.
        readonly property int mergeGap: 15
        // Minutes between refreshes.
        readonly property int refresh: 15
    }

    readonly property QtObject weather: QtObject {
        // Days in the forecast (today included) and hours in the hourly row.
        readonly property int days: 7
        readonly property int hours: 6
        // Minutes between refreshes.
        readonly property int refresh: 15
    }

    readonly property QtObject overview: QtObject {
        // Width of one workspace, workspaces per row, and the space around and between them.
        readonly property int cell: 300
        readonly property int columns: 3
        readonly property int padding: 12
        readonly property int spacing: 10
    }

    readonly property QtObject displays: QtObject {
        // The display popup's width, the space inside it, and the height of the arrangement.
        readonly property int width: 520
        readonly property int padding: 18
        readonly property int stage: 240
    }

    readonly property QtObject nightLight: QtObject {
        // Colour temperature in kelvin while on.
        readonly property int temperature: 4000
        // When it's on without a location for the weather (or where the sun doesn't set).
        readonly property string from: "20:00"
        readonly property string until: "07:00"
    }

    readonly property QtObject visualizer: QtObject {
        // How high (px) the bars reach at full level until it's set in the control centre (the
        // bottom border and the gap above it), and the most the slider goes to.
        readonly property int height: 12
        readonly property int maxHeight: 200
        readonly property int bars: 64
        readonly property int framerate: 30
        // Space between bars, and how strongly they show.
        readonly property int gap: 3
        readonly property real opacity: 0.55
    }

    readonly property QtObject vocab: QtObject {
        // New words a day, minutes until a wrong one is asked again, and seconds the lock's
        // word step waits before offering an emergency unlock.
        readonly property int newPerDay: 20
        readonly property int relearn: 10
        readonly property int emergency: 60
        // FSRS: the chance of still remembering a word when it's asked again, and the most
        // days between two asks.
        readonly property real retention: 0.9
        readonly property int maxInterval: 365
        // Seconds to the first key above which a right answer counts as Hard, until there
        // are ten right answers to compare with.
        readonly property real slow: 6
        // Hours between notifications about words due for review; 0 turns them off.
        readonly property real notifyEvery: 3
    }

    readonly property QtObject capture: QtObject {
        // Where screenshots and recordings go.
        readonly property string dir: "~/Pictures/Screenshots"
    }

    readonly property QtObject updates: QtObject {
        // Days nixpkgs is behind its branch before the bar shows it.
        readonly property int days: 3
    }

    readonly property QtObject hass: QtObject {
        // Seconds between Home Assistant updates while the dashboard is open.
        readonly property int poll: 5
    }

    readonly property QtObject power: QtObject {
        // Battery level (0..1) at which power saver is offered, on balanced or performance.
        readonly property real lowBattery: 0.2
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
        // Cancelled lessons and homework due today or overdue, tomorrow, within three days.
        readonly property color red: "#ff5f57"
        readonly property color orange: "#ff9f43"
        readonly property color yellow: "#f9d65c"
        // A right answer.
        readonly property color green: "#5fd068"
    }

    readonly property QtObject hyprland: QtObject {
        // Outer gap between windows and the frame.
        readonly property int gapsOut: 4
    }
}
