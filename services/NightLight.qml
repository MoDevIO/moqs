pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// A warmer screen at night, through hyprsunset: from sunset to sunrise at the weather's
// location (worked out here, so it needs no network once the place is known), or from
// Config.nightLight.from to .until without one. The control centre tile turns it on or off
// until the schedule next changes. Leaving the shell stops hyprsunset, which puts the
// colours back.
Singleton {
    id: root

    // hyprsunset is installed.
    property bool available: true

    property date now: new Date()
    // Today's sunrise and sunset, or null where the sun doesn't set (or rise) today.
    readonly property var sun: sunTimes(now, Weather.latitude, Weather.longitude)
    readonly property date rise: sun?.rise ?? at(now, Config.nightLight.until)
    readonly property date set: sun?.set ?? at(now, Config.nightLight.from)
    readonly property bool scheduled: now < rise || now >= set

    // On or off by hand (true or false) until the schedule next changes, or null.
    property var override: null
    readonly property bool active: available && (override ?? scheduled)

    onScheduledChanged: override = null

    function toggle(): void {
        override = active ? false : true;
        if (override === scheduled)
            override = null;
    }

    // "Until 07:41", "From 16:38", for the tile.
    readonly property string status: {
        if (!available)
            return "hyprsunset isn't installed";
        const clock = d => Qt.formatTime(d, "hh:mm");
        if (active)
            return scheduled ? `Until ${clock(rise)}` : "On until sunrise";
        return scheduled ? "Off tonight" : `From ${clock(set)}`;
    }

    // Today at "HH:MM".
    function at(day: date, hhmm: string): date {
        const [h, m] = hhmm.split(":").map(Number);
        const d = new Date(day);
        d.setHours(h, m, 0, 0);
        return d;
    }

    // Sunrise and sunset on the day of `day` (the sun's upper edge at the horizon, with
    // refraction), as in the usual NOAA approximation. null for a polar day or night, or
    // without a location.
    function sunTimes(day: date, lat: real, lng: real): var {
        if (isNaN(lat) || isNaN(lng))
            return null;
        const rad = Math.PI / 180;
        const dayMs = 86400000;
        const J1970 = 2440588;
        const J2000 = 2451545;
        const J0 = 0.0009;
        const noonish = new Date(day);
        noonish.setHours(12, 0, 0, 0);
        const d = noonish.valueOf() / dayMs - 0.5 + J1970 - J2000;
        const lw = rad * -lng;
        const phi = rad * lat;
        const n = Math.round(d - J0 - lw / (2 * Math.PI));
        const ds = J0 + lw / (2 * Math.PI) + n;
        const M = rad * (357.5291 + 0.98560028 * ds);
        const C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M));
        const L = M + C + rad * 102.9372 + Math.PI;
        const dec = Math.asin(Math.sin(rad * 23.4397) * Math.sin(L));
        const noon = J2000 + ds + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
        const cosW = (Math.sin(rad * -0.833) - Math.sin(phi) * Math.sin(dec)) / (Math.cos(phi) * Math.cos(dec));
        if (cosW < -1 || cosW > 1)
            return null;
        const w = Math.acos(cosW);
        const setJ = J2000 + J0 + (w + lw) / (2 * Math.PI) + n + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
        const riseJ = noon - (setJ - noon);
        const toDate = j => new Date((j + 0.5 - J1970) * dayMs);
        return { rise: toDate(riseJ), set: toDate(setJ) };
    }

    // The weather service finds its place only when asked for a forecast.
    function locate(): void {
        if (Weather.configured && isNaN(Weather.latitude))
            Weather.refreshIfStale();
    }

    Connections {
        target: Weather

        function onConfiguredChanged(): void {
            root.locate();
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 30 * 1000
        onTriggered: {
            root.now = new Date();
            root.locate();
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: code => root.available = code === 0
    }

    Process {
        running: root.active
        command: ["hyprsunset", "-t", String(Config.nightLight.temperature)]
    }
}
