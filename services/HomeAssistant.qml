pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Home Assistant over its REST API with a long-lived access token. Settings and the card's
// layout come from hass.json next to shell.qml:
//   {
//     "url": "http://homeassistant.local:8123",
//     "tokenCommand": "pass show hass",
//     "sections": [
//       { "type": "toggle", "entity": "light.mo" },
//       { "type": "sensors", "title": "Energy", "entities": [
//         { "entity": "sensor.foxess_pvenergytotal", "name": "Produced", "icon": "mdi:solar-power" },
//         "sensor.foxess_load"
//       ] }
//     ]
//   }
// "token" works instead of "tokenCommand". Sections show top to bottom:
//   toggle   switch an entity on and off; lights that dim get a brightness slider
//   button   run a scene, script or button
//   sensor   one value on its own row
//   sensors  several values side by side in one block
// Each entity is an ID or { "entity", "name", "icon" }; name and icon default to Home
// Assistant's. Icons are Material Design Icons names ("mdi:solar-power").
Singleton {
    id: root

    readonly property string url: {
        const u = settings.url.replace(/\/+$/, "");
        return !u || u.includes("://") ? u : `http://${u}`;
    }
    readonly property string token: settings.token || commandToken
    readonly property bool configured: url !== "" && token !== ""
    property string commandToken
    // Why the Home Assistant token command failed (say, the secret isn't readable by this user), or "".
    property bool secretFailed
    property string secretMessage
    readonly property string secretError: secretFailed ? `Can't read the Home Assistant token${secretMessage ? ": " + secretMessage : ""}` : ""
    property string error

    // Sections as [{ type, title, items: [{ entity, name, icon }] }]; a section with a single
    // "entity" gets it as its only item.
    readonly property var sections: Array.from(settings.sections ?? []).map(sec => ({
        type: sec.type ?? "sensor",
        title: sec.title ?? "",
        items: Array.from(sec.entities ?? (sec.entity ? [sec] : [])).map(e => typeof e === "string" ? { entity: e, name: "", icon: "" } : { entity: e.entity ?? "", name: e.name ?? "", icon: e.icon ?? "" }).filter(e => e.entity)
    })).filter(sec => sec.items.length)
    readonly property var entities: [...new Set([].concat(...sections.map(sec => sec.items.map(e => e.entity))))]

    // Material Design Icons name to code point, generated from the Nerd Font.
    property var mdi: ({})

    // Entity ID to its state object ({ state, attributes }) as Home Assistant reports it.
    property var states: ({})
    // Polls while true; the dashboard sets it while it's open.
    property bool active

    function state(id: string): var {
        return states[id] ?? null;
    }

    function isOn(id: string): bool {
        return state(id)?.state === "on";
    }

    function name(item: var): string {
        return item.name || state(item.entity)?.attributes?.friendly_name || item.entity;
    }

    function glyph(name: string): string {
        const code = mdi[name.replace(/^mdi:/, "")];
        return code ? String.fromCodePoint(parseInt(code, 16)) : "";
    }

    // The configured icon, else a battery showing the charge, else Home Assistant's icon,
    // else one for the kind of entity.
    function icon(item: var): string {
        const s = state(item.entity);
        const a = s?.attributes ?? {};
        if (item.icon)
            return glyph(item.icon) || item.icon;
        if (a.device_class === "battery" && !isNaN(Number(s.state))) {
            const tenth = Math.round(Number(s.state) / 10);
            return glyph(tenth >= 10 ? "battery" : tenth <= 0 ? "battery-outline" : `battery-${tenth * 10}`);
        }
        if (a.icon && glyph(a.icon))
            return glyph(a.icon);
        const domain = item.entity.split(".")[0];
        const on = s?.state === "on";
        const byClass = { energy: "lightning-bolt", power: "flash", temperature: "thermometer", humidity: "water-percent", battery: "battery" }[a.device_class];
        const byDomain = { light: on ? "lightbulb" : "lightbulb-outline", switch: on ? "toggle-switch" : "toggle-switch-off-outline", fan: "fan", scene: "palette", script: "script-text-outline", button: "gesture-tap-button", input_boolean: on ? "toggle-switch" : "toggle-switch-off-outline", sensor: "eye", binary_sensor: on ? "checkbox-marked-circle" : "checkbox-blank-circle-outline" }[domain];
        return glyph(byClass ?? byDomain ?? "home-assistant");
    }

    // Brightness 0..1, or -1 if the light can't be dimmed.
    function brightness(id: string): real {
        const a = state(id)?.attributes;
        const modes = a?.supported_color_modes ?? [];
        if (!modes.length || modes.every(m => m === "onoff"))
            return -1;
        return isOn(id) ? (a.brightness ?? 0) / 255 : 0;
    }

    // A sensor's value with its unit, as text.
    function value(id: string): string {
        const s = state(id);
        if (!s || s.state === "unavailable" || s.state === "unknown")
            return "–";
        let n = Number(s.state);
        let unit = s.attributes?.unit_of_measurement ?? "";
        // Large power and energy values in the next unit up: 12345 kWh as 12.3 MWh.
        const steps = { W: "kW", kW: "MW", MW: "GW", Wh: "kWh", kWh: "MWh", MWh: "GWh" };
        while (!isNaN(n) && Math.abs(n) >= 1000 && steps[unit]) {
            n /= 1000;
            unit = steps[unit];
        }
        const shown = isNaN(n) ? s.state : n.toLocaleString(Qt.locale(), "f", Math.abs(n) >= 100 || Number.isInteger(n) ? 0 : 1);
        return unit === "%" ? `${shown}%` : unit ? `${shown} ${unit}` : shown;
    }

    function number(id: string): real {
        return Number(state(id)?.state);
    }

    function unit(id: string): string {
        return state(id)?.attributes?.unit_of_measurement ?? "";
    }

    function request(method: string, path: string, body: var, done: var): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status === 200 || xhr.status === 201) {
                error = "";
                done?.(res);
            } else if (xhr.status === 401) {
                error = "Home Assistant refused the token";
            } else if (xhr.status === 404) {
                error = `Home Assistant doesn't know ${path.replace(/^.*\//, "")}`;
            } else {
                error = xhr.status ? `Home Assistant error ${xhr.status}` : "Can't reach Home Assistant";
            }
        };
        xhr.open(method, `${url}${path}`);
        xhr.setRequestHeader("Authorization", `Bearer ${token}`);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : "");
    }

    function update(list: var): void {
        const next = Object.assign({}, states);
        for (const s of list)
            if (s?.entity_id)
                next[s.entity_id] = s;
        states = next;
    }

    function refresh(): void {
        if (!configured)
            return;
        for (const id of entities)
            request("GET", `/api/states/${id}`, null, s => update([s]));
    }

    // Service calls answer with the states they changed.
    function call(domain: string, service: string, data: var): void {
        request("POST", `/api/services/${domain}/${service}`, data, res => {
            update(res ?? []);
            // Some integrations report the new state only a moment later.
            settle.restart();
        });
    }

    function toggle(id: string): void {
        // Shown right away; the answer confirms or corrects it.
        const s = state(id);
        if (s)
            update([Object.assign({}, s, { state: s.state === "on" ? "off" : "on" })]);
        call("homeassistant", "toggle", { entity_id: id });
    }

    // Scenes and scripts run, buttons get pressed.
    function press(id: string): void {
        const domain = id.split(".")[0];
        if (domain === "button" || domain === "input_button")
            call(domain, "press", { entity_id: id });
        else
            call("homeassistant", "turn_on", { entity_id: id });
    }

    function setBrightness(id: string, level: real): void {
        const s = state(id);
        if (s)
            update([Object.assign({}, s, { state: level > 0 ? "on" : "off", attributes: Object.assign({}, s.attributes, { brightness: Math.round(level * 255) }) })]);
        pendingLight = id;
        pendingLevel = level;
        brightnessDelay.restart();
    }

    // Dragging sends one call per pause, not one per pixel.
    property string pendingLight
    property real pendingLevel

    Timer {
        id: brightnessDelay

        interval: 150
        onTriggered: {
            const pct = Math.round(root.pendingLevel * 100);
            if (pct > 0)
                root.call("light", "turn_on", { entity_id: root.pendingLight, brightness_pct: pct });
            else
                root.call("light", "turn_off", { entity_id: root.pendingLight });
        }
    }

    Timer {
        id: settle

        interval: 1500
        onTriggered: root.refresh()
    }

    Timer {
        running: root.active && root.configured
        repeat: true
        triggeredOnStart: true
        interval: Config.hass.poll * 1000
        onTriggered: root.refresh()
    }

    onConfiguredChanged: refresh()
    onEntitiesChanged: refresh()

    FileView {
        path: Quickshell.shellPath("hass.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string url
            property string token
            property string tokenCommand
            property var sections: []

            // Set the command here: a binding on it would update only after this handler runs.
            onTokenCommandChanged: {
                if (!tokenCommand)
                    return;
                tokenProc.command = ["sh", "-c", tokenCommand];
                tokenProc.running = true;
            }
        }
    }

    FileView {
        path: Quickshell.shellPath("assets/mdi.json")
        onLoaded: root.mdi = JSON.parse(text())
    }

    Process {
        id: tokenProc

        stdout: StdioCollector {
            onStreamFinished: root.commandToken = text.split("\n")[0]
        }

        stderr: StdioCollector {
            onStreamFinished: root.secretMessage = text.trim().split("\n")[0].replace(/^(cat|sh): /, "")
        }

        onStarted: root.secretFailed = false
        onExited: code => root.secretFailed = code !== 0
    }
}
