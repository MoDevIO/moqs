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
//
// The launcher's ">" reaches every entity: "> desk lamp" toggles it, "> desk lamp off",
// "> desk lamp 40" dims it, "> heater 21" sets a thermostat, "> lights off" all lights.
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

    // Every entity ID Home Assistant has, for the launcher; loaded by loadAll().
    property var allEntities: []

    function loadAll(): void {
        if (!configured)
            return;
        request("GET", "/api/states", null, list => {
            update(list ?? []);
            allEntities = (list ?? []).map(s => s.entity_id).filter(x => x).sort();
        });
    }

    // Words for all entities of a domain, as in "lights off".
    readonly property var groups: ({ lights: "light", switches: "switch", fans: "fan", covers: "cover", blinds: "cover" })

    // What the launcher's ">query" can do, best match first: [{ entity, all, name, action,
    // value, glyph, detail }]. The query is a name, then optionally on, off (or an, aus),
    // toggle, or a number: brightness or volume in percent, a temperature, a position.
    function commands(query: string): var {
        let q = query.trim().toLowerCase();
        let word = "";
        let num = NaN;
        let m = q.match(/^(.*?)\s+(on|off|an|aus|toggle)$/);
        if (m) {
            q = m[1];
            word = ({ an: "on", aus: "off" })[m[2]] ?? m[2];
        } else if ((m = q.match(/^(.*?)\s+(-?\d+(?:[.,]\d+)?)\s*(?:%|°\s*c?)?$/))) {
            q = m[1];
            num = Number(m[2].replace(",", "."));
        }
        const out = [];
        const group = groups[q];
        if (group && (word === "on" || word === "off")) {
            out.push({ entity: group, all: true, name: `All ${q}`, action: word, value: 0, glyph: glyph(group === "light" ? "lightbulb-group" : "home-automation"), detail: `Enter turns all ${word}`, score: 200 });
        }
        const ids = q ? allEntities : entities;
        for (const id of ids) {
            const label = root.name({ entity: id, name: "" });
            const n = label.toLowerCase();
            let sc = !q ? 50 : n === q ? 100 : n.startsWith(q) ? 90 : n.split(/[\s\-_.]+/).some(w => w.startsWith(q)) ? 80 : n.includes(q) ? 70 : q.split(/\s+/).every(w => n.includes(w)) ? 60 : id.includes(q.replace(/\s+/g, "_")) ? 40 : 0;
            if (!sc)
                continue;
            const act = actionFor(id, word, num);
            if (!act)
                continue;
            // Things that do something before sensors, the dashboard's own first.
            sc += (act.action !== "copy" ? 5 : 0) + (entities.includes(id) ? 3 : 0) - (state(id)?.state === "unavailable" ? 20 : 0);
            out.push(Object.assign({ entity: id, all: false, name: label, glyph: icon({ entity: id, icon: "" }), score: sc }, act));
        }
        const shown = out.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name)).slice(0, 30);
        // Entities that share a name show their ID too.
        const names = {};
        for (const c of shown)
            names[c.name] = (names[c.name] ?? 0) + 1;
        return shown.map(c => c.all || names[c.name] < 2 ? c : Object.assign({}, c, { detail: `${c.entity} · ${c.detail}` }));
    }

    // What Enter does to an entity for a word or number, or null if it can't.
    function actionFor(id: string, word: string, num: real): var {
        const domain = id.split(".")[0];
        const s = state(id);
        const now = describe(id);
        const say = text => ({ detail: now ? `${now} · ${text}` : text });
        if (!isNaN(num)) {
            const pct = Math.max(0, Math.min(100, Math.round(num)));
            const unit = s?.attributes?.temperature_unit ?? "°";
            const set = {
                light: ["brightness", pct, `Enter sets ${pct}%`],
                fan: ["percentage", pct, `Enter sets ${pct}%`],
                cover: ["position", pct, `Enter opens to ${pct}%`],
                media_player: ["volume", pct, `Enter sets the volume to ${pct}%`],
                climate: ["temperature", num, `Enter sets ${num}${unit}`],
                water_heater: ["temperature", num, `Enter sets ${num}${unit}`],
                input_number: ["value", num, `Enter sets ${num}`],
                number: ["value", num, `Enter sets ${num}`]
            }[domain];
            return set ? Object.assign({ action: set[0], value: set[1] }, say(set[2])) : null;
        }
        const switchable = ["light", "switch", "fan", "input_boolean", "automation", "cover", "media_player", "climate", "water_heater", "humidifier", "siren", "remote", "vacuum"].includes(domain);
        if (word === "on" || word === "off")
            return switchable ? Object.assign({ action: word, value: 0 }, say(`Enter turns ${word}`)) : null;
        if (["scene", "script", "button", "input_button"].includes(domain))
            return word ? null : Object.assign({ action: "press", value: 0 }, say(domain.endsWith("button") ? "Enter presses" : "Enter runs"));
        if (switchable)
            return Object.assign({ action: "toggle", value: 0 }, say(word === "toggle" || !s ? "Enter toggles" : `Enter turns ${s.state === "on" || s.state === "open" || s.state === "playing" ? "off" : "on"}`));
        return word ? null : Object.assign({ action: "copy", value: 0 }, say("Enter copies"));
    }

    // An entity's state in a few words: "On · 60%", "21.5 °C → 22°", "Playing".
    function describe(id: string): string {
        const s = state(id);
        if (!s)
            return "";
        const a = s.attributes ?? {};
        const domain = id.split(".")[0];
        if (["sensor", "number", "input_number"].includes(domain))
            return value(id);
        if (domain === "climate" || domain === "water_heater") {
            const t = a.temperature ?? a.target_temp_high;
            return [a.current_temperature != null ? `${a.current_temperature}°` : "", t != null ? `→ ${t}°` : "", s.state].filter(x => x).join(" ");
        }
        if (["scene", "script", "button", "input_button"].includes(domain))
            return "";
        const st = s.state === "unavailable" ? "Unavailable" : s.state.charAt(0).toUpperCase() + s.state.slice(1).replace(/_/g, " ");
        if (domain === "light" && s.state === "on" && a.brightness != null)
            return `${st} · ${Math.round(a.brightness / 2.55)}%`;
        if (domain === "cover" && a.current_position != null)
            return `${st} · ${a.current_position}%`;
        return st;
    }

    // Runs one of commands()' results (except "copy", which the launcher does).
    function run(c: var): void {
        const id = c.entity;
        const domain = c.all ? id : id.split(".")[0];
        switch (c.action) {
        case "toggle":
            toggle(id);
            break;
        case "on":
        case "off":
            if (c.all) {
                call(domain, `turn_${c.action}`, { entity_id: "all" });
            } else {
                const s = state(id);
                if (s && ["light", "switch", "fan", "input_boolean"].includes(domain))
                    update([Object.assign({}, s, { state: c.action })]);
                call("homeassistant", `turn_${c.action}`, { entity_id: id });
            }
            break;
        case "press":
            press(id);
            break;
        case "brightness":
            call("light", c.value > 0 ? "turn_on" : "turn_off", c.value > 0 ? { entity_id: id, brightness_pct: c.value } : { entity_id: id });
            break;
        case "percentage":
            call("fan", "set_percentage", { entity_id: id, percentage: c.value });
            break;
        case "position":
            call("cover", "set_cover_position", { entity_id: id, position: c.value });
            break;
        case "volume":
            call("media_player", "volume_set", { entity_id: id, volume_level: c.value / 100 });
            break;
        case "temperature":
            call(domain, "set_temperature", { entity_id: id, temperature: c.value });
            break;
        case "value":
            call(domain, "set_value", { entity_id: id, value: c.value });
            break;
        }
    }

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
