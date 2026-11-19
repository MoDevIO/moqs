pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Weather from Open-Meteo, which needs no API key. Settings come from weather.json next to
// shell.qml:
//   { "location": "Berlin" }
// The location is a place name, optionally narrowed down by country or region
// ("Springfield, Illinois", "Frankfurt, DE"), a GeoNames ID (the number in a geonames.org
// link, e.g. "2925533"), or "latitude,longitude".
Singleton {
    id: root

    readonly property string location: settings.location.trim()
    readonly property bool configured: location !== ""
    property string error
    property bool loading
    property real lastRefresh: 0

    // The place found for the location, shown with the forecast.
    property string place
    property real latitude: NaN
    property real longitude: NaN

    // { temp, feels, code, day, wind, humidity }
    property var current: null
    // Coming hours from now: [{ time (Date), temp, code, day, rain }]
    property var hours: []
    // Coming days from today: [{ date (Date), code, max, min, rain }]
    property var days: []

    // Nerd Font icon for a WMO weather code.
    function icon(code: int, day: bool): string {
        if (code === 0 || code === 1)
            return day ? "\u{F0599}" : "\u{F0594}";
        if (code === 2)
            return day ? "\u{F0595}" : "\u{F0F31}";
        if (code === 3)
            return "\u{F0590}";
        if (code === 45 || code === 48)
            return "\u{F0591}";
        if (code === 56 || code === 57 || code === 66 || code === 67)
            return "\u{F067F}";
        if (code === 65 || code === 82)
            return "\u{F0596}";
        if (code >= 51 && code <= 82)
            return "\u{F0597}";
        if (code === 75 || code === 86)
            return "\u{F0F36}";
        if (code >= 71 && code <= 86)
            return "\u{F0598}";
        if (code === 95)
            return "\u{F067E}";
        if (code === 96 || code === 99)
            return "\u{F0592}";
        return "\u{F0590}";
    }

    function describe(code: int): string {
        return {
            0: "Clear",
            1: "Mainly clear",
            2: "Partly cloudy",
            3: "Overcast",
            45: "Fog",
            48: "Freezing fog",
            51: "Light drizzle",
            53: "Drizzle",
            55: "Heavy drizzle",
            56: "Freezing drizzle",
            57: "Freezing drizzle",
            61: "Light rain",
            63: "Rain",
            65: "Heavy rain",
            66: "Freezing rain",
            67: "Freezing rain",
            71: "Light snow",
            73: "Snow",
            75: "Heavy snow",
            77: "Snow grains",
            80: "Light showers",
            81: "Showers",
            82: "Heavy showers",
            85: "Snow showers",
            86: "Heavy snow showers",
            95: "Thunderstorm",
            96: "Thunderstorm with hail",
            99: "Thunderstorm with hail"
        }[code] ?? "";
    }

    function degrees(t: real): string {
        return `${Math.round(t)}°`;
    }

    // Open-Meteo gives local times without a zone ("2026-11-19T17:00"); read them as local.
    function parse(s: string): var {
        const [d, t] = s.split("T");
        const [y, m, day] = d.split("-").map(Number);
        const [h, min] = (t ?? "0:0").split(":").map(Number);
        return new Date(y, m - 1, day, h, min);
    }

    function get(url: string, done: var): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status === 200 && res) {
                done(res);
            } else {
                error = res?.reason ?? (xhr.status ? `Weather server error ${xhr.status}` : "Can't reach the weather server");
                loading = false;
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // Refresh when shown, unless the forecast is only a few minutes old.
    function refreshIfStale(): void {
        if (Date.now() - lastRefresh > 5 * 60 * 1000)
            refresh();
    }

    function refresh(): void {
        if (!configured || loading)
            return;
        loading = true;
        lastRefresh = Date.now();
        if (!isNaN(latitude)) {
            forecast();
            return;
        }
        const coords = location.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
        if (coords) {
            latitude = Number(coords[1]);
            longitude = Number(coords[2]);
            place = "";
            forecast();
            return;
        }
        if (/^\d+$/.test(location)) {
            get(`https://geocoding-api.open-meteo.com/v1/get?id=${location}&language=en&format=json`, res => {
                if (res.latitude === undefined) {
                    error = `No place with GeoNames ID ${location}`;
                    loading = false;
                    return;
                }
                latitude = res.latitude;
                longitude = res.longitude;
                place = res.name;
                forecast();
            });
            return;
        }
        // The geocoder matches only the name, so the rest ("…, DE") picks among its results.
        const [name, ...qualifiers] = location.split(",").map(s => s.trim().toLowerCase());
        get(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=20&language=en&format=json`, res => {
            const results = res.results ?? [];
            const fits = r => qualifiers.every(q => [r.country_code, r.country, r.admin1, r.admin2, r.admin3, r.admin4].some(x => (x ?? "").toLowerCase() === q));
            const hit = results.find(fits);
            if (!hit) {
                error = `Can't find "${location}"`;
                loading = false;
                return;
            }
            latitude = hit.latitude;
            longitude = hit.longitude;
            place = hit.name;
            forecast();
        });
    }

    function forecast(): void {
        const params = [
            `latitude=${latitude}`,
            `longitude=${longitude}`,
            "current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m",
            "hourly=temperature_2m,weather_code,is_day,precipitation_probability",
            "daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "timezone=auto",
            `forecast_days=${Config.weather.days}`
        ];
        get(`https://api.open-meteo.com/v1/forecast?${params.join("&")}`, res => {
            const c = res.current;
            current = {
                temp: c.temperature_2m,
                feels: c.apparent_temperature,
                code: c.weather_code,
                day: !!c.is_day,
                wind: c.wind_speed_10m,
                humidity: c.relative_humidity_2m
            };
            // From the hour that's under way.
            const h = res.hourly;
            const from = Date.now() - 60 * 60 * 1000;
            const all = h.time.map((t, i) => ({ time: parse(t), temp: h.temperature_2m[i], code: h.weather_code[i], day: !!h.is_day[i], rain: h.precipitation_probability[i] ?? 0 }));
            hours = all.filter(x => x.time.getTime() > from).slice(0, Config.weather.hours);
            const d = res.daily;
            days = d.time.map((t, i) => ({ date: parse(t), code: d.weather_code[i], max: d.temperature_2m_max[i], min: d.temperature_2m_min[i], rain: d.precipitation_probability_max[i] ?? 0 }));
            error = "";
            loading = false;
        });
    }

    // A new location needs geocoding again.
    onLocationChanged: {
        latitude = NaN;
        longitude = NaN;
        place = "";
        current = null;
        hours = [];
        days = [];
        loading = false;
        refresh();
    }

    Timer {
        running: root.configured
        repeat: true
        interval: Config.weather.refresh * 60 * 1000
        onTriggered: root.refresh()
    }

    FileView {
        path: Quickshell.shellPath("weather.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string location
        }
    }
}
