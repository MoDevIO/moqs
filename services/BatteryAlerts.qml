pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Warns when the battery runs low: a notification at 15 %, an urgent one at 5 %, each once
// until the laptop is plugged in or the battery is back above it. Also the time left (to
// empty, or to full while charging) for the bar's battery, as "2:13".
Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool laptop: device?.isLaptopBattery ?? false
    readonly property real level: device?.percentage ?? 1
    readonly property bool onBattery: UPower.onBattery
    // Hours and minutes left, or "" while UPower doesn't know yet.
    readonly property string timeLeft: {
        const secs = onBattery ? device?.timeToEmpty ?? 0 : device?.timeToFull ?? 0;
        if (!secs || secs < 60)
            return "";
        const min = Math.round(secs / 60);
        return `${Math.floor(min / 60)}:${String(min % 60).padStart(2, "0")}`;
    }

    property bool warnedLow
    property bool warnedCritical

    function check(): void {
        if (!laptop)
            return;
        if (!onBattery || level > 0.18) {
            warnedLow = false;
            warnedCritical = false;
        } else if (level > 0.07) {
            warnedCritical = false;
        }
        if (!onBattery)
            return;
        const left = timeLeft ? `About ${timeLeft} h left. ` : "";
        if (level <= 0.05 && !warnedCritical) {
            warnedCritical = true;
            warnedLow = true;
            Quickshell.execDetached(["notify-send", "-a", "Battery", "-u", "critical", "-i", "battery-caution", `Battery at ${Math.round(level * 100)} %`, `${left}Plug in now, or save your work.`]);
        } else if (level <= 0.15 && !warnedLow) {
            warnedLow = true;
            Quickshell.execDetached(["notify-send", "-a", "Battery", "-i", "battery-low", `Battery at ${Math.round(level * 100)} %`, `${left}Time to plug in.`]);
        }
    }

    onLevelChanged: check()
    onOnBatteryChanged: check()
    Component.onCompleted: check()
}
