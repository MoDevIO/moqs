pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.config

// Power profile through powerprofilesctl (power-profiles-daemon).
Singleton {
    id: root

    property string profile
    // As powerprofilesctl lists them; empty when the daemon isn't there.
    property list<string> profiles: []
    readonly property bool available: profiles.length > 0

    // In the order clicking the tile cycles through them.
    readonly property list<string> order: ["power-saver", "balanced", "performance"]

    function name(p: string): string {
        return { "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" }[p] ?? p;
    }

    function icon(p: string): string {
        return { "power-saver": "\u{F032A}", "balanced": "\u{F05D1}", "performance": "\u{F04C5}" }[p] ?? "\u{F0425}";
    }

    function refresh(): void {
        get.running = true;
        if (!available)
            list.running = true;
    }

    function set(p: string): void {
        profile = p;
        setter.command = ["powerprofilesctl", "set", p];
        setter.running = true;
    }

    // The next available profile after the current one.
    function cycle(): void {
        const avail = order.filter(p => profiles.includes(p));
        if (avail.length)
            set(avail[(avail.indexOf(profile) + 1) % avail.length]);
    }

    Component.onCompleted: refresh()

    // Low battery: offer power saver once per discharge, while on balanced or performance.
    readonly property real batteryLevel: UPower.displayDevice?.percentage ?? 1
    readonly property bool lowBattery: UPower.onBattery && (UPower.displayDevice?.isLaptopBattery ?? false) && batteryLevel <= Config.power.lowBattery
    property bool asked

    onLowBatteryChanged: checkLowBattery()
    onProfileChanged: checkLowBattery()

    function checkLowBattery(): void {
        // Charging, or being on power saver, starts over: leaving power saver again while
        // still low asks again.
        if (!UPower.onBattery || profile === "power-saver")
            asked = false;
        if (!lowBattery || asked || !available || profile === "" || profile === "power-saver" || prompt.running)
            return;
        asked = true;
        prompt.command = ["notify-send", "-a", "Power", "-u", "critical", "-i", "battery-caution",
            "-A", "saver=Turn on", "-A", "dismiss=Not now",
            "Battery low", `${Math.round(batteryLevel * 100)}% left. Turn on power saver?`];
        prompt.running = true;
    }

    Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            root.checkLowBattery();
        }
    }

    Process {
        id: prompt

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "saver")
                    root.set("power-saver");
            }
        }
    }

    // Picks up changes made outside the shell.
    Timer {
        running: true
        repeat: true
        interval: 10000
        onTriggered: root.refresh()
    }

    Process {
        id: get

        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: root.profile = text.trim()
        }
    }

    Process {
        id: list

        // Profile lines look like "* performance:" or "  balanced:"; driver details are indented.
        command: ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.profiles = text.split("\n").map(l => l.match(/^[* ]\s?([a-z-]+):\s*$/)?.[1]).filter(p => p)
        }
    }

    Process {
        id: setter

        onExited: get.running = true
    }
}
