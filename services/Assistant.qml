pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The launcher's assistant: Tab on what's typed asks the language model set up for mnemonics
// (services.moqs.ai, ai.json, read by Mnemonic: the same OpenAI-compatible API and model), which can use tools:
// run shell commands, open apps, list, focus, move and close windows (Hyprland), find and
// control Home Assistant entities, and list, read and send Matrix messages. Its answer, and
// each tool it uses, show in the launcher; a follow-up continues the conversation until the
// launcher closes (reset()).
//
// What can't be taken back waits for a yes first (pending; Enter in the launcher, Esc says
// no): shell commands, closing windows, sending Matrix messages, and Home Assistant services
// outside everyday ones (lights, switches, media, climate, covers, scenes and the like).
Singleton {
    id: root

    readonly property bool configured: Mnemonic.configured
    // The conversation as shown: [{ kind: "user" | "tool" | "answer" | "error", text, detail,
    // icon, ok }]. A tool's ok is undefined while it runs or waits.
    property var view: []
    // A tool call waiting for a yes: { label, detail, run }, or null.
    property var pending: null
    property bool busy
    readonly property bool active: view.length > 0

    // The conversation as the model sees it.
    property var messages: []
    // Rounds of tool calls left before it has to answer; bumped per question.
    property int rounds
    // Bumped by reset(), so answers to an old conversation are dropped.
    property int generation

    function system(): string {
        return `You are the assistant built into the user's desktop shell (Hyprland on NixOS). The user typed a request into the app launcher. Act on it with the tools; don't just explain how. Look things up with the tools rather than guessing (entity IDs, window addresses, room IDs). Answer in the user's language, in one to three short sentences, plain text, no Markdown headings. If something fails, say so plainly. Commands run as the user with sh, without a terminal; for GUI programs prefer open_app. It is ${new Date().toString()}.`;
    }

    readonly property var tools: [
        tool("run_command", "Run a shell command (sh -c) and get its output (stdout and stderr, up to 3000 characters) and exit code. Times out after 30 seconds. The user confirms it first.", {
            command: { type: "string", description: "The command line" }
        }, ["command"]),
        tool("open_app", "Start an installed desktop application by name, e.g. Firefox, Steam, Files.", {
            name: { type: "string" }
        }, ["name"]),
        tool("list_windows", "List the open windows: address, app class, title, workspace, and which is focused.", {}, []),
        tool("window_action", "Act on Hyprland windows and workspaces. focus_workspace needs workspace; focus_window and close_window need address (from list_windows); move_window needs address and workspace.", {
            action: { type: "string", enum: ["focus_workspace", "focus_window", "move_window", "close_window"] },
            address: { type: "string", description: "Window address from list_windows" },
            workspace: { type: "integer" }
        }, ["action"]),
        tool("home_assistant_find", "Find Home Assistant entities whose name or ID matches the words (lenient: umlauts, typos), with their state. Empty query lists all (up to 40).", {
            query: { type: "string" }
        }, ["query"]),
        tool("home_assistant_call", "Call a Home Assistant service on an entity, e.g. light.turn_on with data {brightness_pct: 40}, climate.set_temperature with {temperature: 21}, homeassistant.toggle.", {
            domain: { type: "string" },
            service: { type: "string" },
            entity_id: { type: "string" },
            data: { type: "object", description: "Extra service data" }
        }, ["domain", "service", "entity_id"]),
        tool("matrix_rooms", "List Matrix chats (rooms and direct chats), the most recently active first, each with when it was last active and a preview of its last message, optionally only those whose name contains the query. Read a chat (matrix_read) only when more than the preview is needed.", {
            query: { type: "string" }
        }, []),
        tool("matrix_read", "Read the latest messages of a Matrix room.", {
            room_id: { type: "string" },
            count: { type: "integer", description: "How many, up to 30 (default 10)" }
        }, ["room_id"]),
        tool("matrix_send", "Send a text message to a Matrix room. The user confirms it first.", {
            room_id: { type: "string" },
            text: { type: "string" }
        }, ["room_id", "text"])
    ]

    // Home Assistant and Matrix load on first use; here, before the first question.
    Component.onCompleted: {
        HomeAssistant.configured;
        Matrix.configured;
    }

    function tool(name: string, description: string, properties: var, required: var): var {
        return { type: "function", function: { name, description, parameters: { type: "object", properties, required } } };
    }

    // ---- The conversation

    function ask(text: string): void {
        text = text.trim();
        if (!text || busy)
            return;
        if (!configured) {
            show({ kind: "error", text: "No language model is set up (services.moqs.ai)" });
            return;
        }
        if (!messages.length)
            messages = [{ role: "system", content: system() }];
        messages = [...messages, { role: "user", content: text }];
        show({ kind: "user", text });
        rounds = 8;
        next();
    }

    function reset(): void {
        generation++;
        messages = [];
        view = [];
        pending = null;
        busy = false;
    }

    function show(entry: var): int {
        view = [...view, entry];
        return view.length - 1;
    }

    function update(index: int, changes: var): void {
        const v = view.slice();
        v[index] = Object.assign({}, v[index], changes);
        view = v;
    }

    // Asks the model, with the conversation so far.
    function next(): void {
        const gen = generation;
        if (rounds-- <= 0) {
            busy = false;
            show({ kind: "error", text: "Stopped: too many steps" });
            return;
        }
        busy = true;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || gen !== root.generation)
                return;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch (e) {}
            const msg = res?.choices?.[0]?.message;
            if (!msg) {
                busy = false;
                show({ kind: "error", text: res?.error?.message ?? res?.message ?? (xhr.status ? `The model answered ${xhr.status}` : "Can't reach the model") });
                return;
            }
            const calls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];
            messages = [...messages, { role: "assistant", content: msg.content ?? "", tool_calls: calls.length ? calls : undefined }];
            const text = String(msg.content ?? "").replace(/<think>[\s\S]*?<\/think>/g, "").trim();
            if (text && calls.length)
                show({ kind: "note", text });
            if (!calls.length) {
                busy = false;
                show({ kind: "answer", text: text || "Done." });
                return;
            }
            runCalls(calls, 0, gen);
        };
        xhr.open("POST", `${Mnemonic.url}/chat/completions`);
        xhr.timeout = 120000;
        xhr.setRequestHeader("Content-Type", "application/json");
        if (Mnemonic.apiKey)
            xhr.setRequestHeader("Authorization", `Bearer ${Mnemonic.apiKey}`);
        xhr.send(JSON.stringify({
            model: Mnemonic.model,
            messages,
            tools,
            tool_choice: "auto",
            temperature: 0.2,
            max_tokens: 4000,
            // Fast: no thinking first (deepseek and qwen chat templates).
            chat_template_kwargs: { thinking: false, enable_thinking: false }
        }));
    }

    // Runs the tool calls one after another, then asks the model again with their results.
    function runCalls(calls: var, i: int, gen: int): void {
        if (gen !== generation)
            return;
        if (i >= calls.length) {
            next();
            return;
        }
        const c = calls[i];
        let args = {};
        try {
            args = typeof c.function?.arguments === "string" ? JSON.parse(c.function.arguments || "{}") : c.function?.arguments ?? {};
        } catch (e) {}
        const done = result => {
            if (gen !== root.generation)
                return;
            messages = [...messages, { role: "tool", tool_call_id: c.id, content: typeof result === "string" ? result : JSON.stringify(result) }];
            runCalls(calls, i + 1, gen);
        };
        runTool(c.function?.name ?? "", args, done);
    }

    // Asks for a yes first: shows what would happen; confirm() runs it, decline() doesn't.
    function ask_(label: string, detail: string, icon: string, run: var, done: var): void {
        const at = show({ kind: "tool", text: label, detail, icon });
        pending = {
            label,
            detail,
            yes: () => {
                pending = null;
                update(at, { ok: true });
                run(at, done);
            },
            no: () => {
                pending = null;
                update(at, { ok: false, text: `${label} · declined` });
                done("The user declined this. Don't try it another way unless asked.");
            }
        };
    }

    function confirm(): void {
        pending?.yes();
    }

    function decline(): void {
        pending?.no();
    }

    // ---- Tools

    function runTool(name: string, a: var, done: var): void {
        switch (name) {
        case "run_command":
            ask_(`Run ${a.command}`, String(a.command ?? ""), "\u{F018D}", (at, d) => command(String(a.command ?? ""), at, d), done);
            return;
        case "open_app":
            {
                const q = String(a.name ?? "").toLowerCase();
                const apps = DesktopEntries.applications.values.filter(x => !x.noDisplay);
                const app = apps.find(x => x.name.toLowerCase() === q) ?? apps.find(x => x.name.toLowerCase().startsWith(q)) ?? apps.find(x => x.name.toLowerCase().includes(q) || x.id.toLowerCase().includes(q) || (x.genericName ?? "").toLowerCase().includes(q));
                if (!app) {
                    show({ kind: "tool", text: `Open ${a.name}`, icon: "\u{F0BAD}", ok: false });
                    done(`No installed app matches "${a.name}"`);
                    return;
                }
                app.execute();
                Launcher.used(app.id);
                show({ kind: "tool", text: `Opened ${app.name}`, icon: "\u{F0BAD}", ok: true });
                done(`Started ${app.name}`);
                return;
            }
        case "list_windows":
            // Hyprland's snapshot of the windows is taken anew first.
            Hyprland.refreshToplevels();
            later.createObject(root, { run: () => {
                const list = Hyprland.toplevels.values.filter(t => t.lastIpcObject?.class !== undefined && t.workspace?.name !== GameGate.hideaway).map(t => ({
                            address: t.address,
                            class: t.lastIpcObject.class,
                            title: t.title || t.lastIpcObject.title,
                            workspace: t.workspace?.id,
                            focused: Hyprland.activeToplevel === t
                        }));
                show({ kind: "tool", text: `Looked at ${list.length} window${list.length === 1 ? "" : "s"}`, icon: "\u{F05AF}", ok: true });
                done({ windows: list, workspace: Hyprland.focusedMonitor?.activeWorkspace?.id });
            } });
            return;
        case "window_action":
            windowAction(a, done);
            return;
        case "home_assistant_find":
            haFind(String(a.query ?? ""), done);
            return;
        case "home_assistant_call":
            haCall(a, done);
            return;
        case "matrix_rooms":
            {
                if (!Matrix.configured) {
                    show({ kind: "tool", text: "Matrix isn't set up", icon: "\u{F0368}", ok: false });
                    done("Matrix isn't set up");
                    return;
                }
                const q = String(a.query ?? "").toLowerCase();
                const rooms = Matrix.roomList.filter(r => !q || Matrix.roomName(r).toLowerCase().includes(q)).slice(0, 20);
                show({ kind: "tool", text: q ? `Looked for chats "${a.query}"` : "Looked at the chats", icon: "\u{F0368}", ok: true });
                done(rooms.map(r => {
                    const last = Matrix.events[r.meta.preview_event_rowid];
                    return {
                        room_id: r.meta.room_id,
                        name: Matrix.roomName(r),
                        unread: r.meta.unread_messages ?? 0,
                        last_active: r.meta.sorting_timestamp ? new Date(r.meta.sorting_timestamp).toLocaleString() : undefined,
                        last_message: last ? `${Matrix.senderName(r.meta.room_id, last.sender ?? "")}: ${Matrix.text(last).slice(0, 120)}` : undefined
                    };
                }));
                return;
            }
        case "matrix_read":
            matrixRead(String(a.room_id ?? ""), Math.max(1, Math.min(30, a.count ?? 10)), done);
            return;
        case "matrix_send":
            {
                const room = Matrix.rooms[a.room_id];
                const name = room ? Matrix.roomName(room) : String(a.room_id ?? "");
                if (!room) {
                    done("No such room; look it up with matrix_rooms");
                    return;
                }
                ask_(`Send to ${name}`, String(a.text ?? ""), "\u{F0368}", (at, d) => {
                    Matrix.quickSend(a.room_id, String(a.text ?? ""));
                    update(at, { text: `Sent to ${name}` });
                    d("Sent");
                }, done);
                return;
            }
        default:
            done(`No tool ${name}`);
        }
    }

    function windowAction(a: var, done: var): void {
        const win = Hyprland.toplevels.values.find(t => t.address === String(a.address ?? "").replace(/^0x/, ""));
        const what = win ? (win.title || win.lastIpcObject?.class || "the window") : "";
        switch (a.action) {
        case "focus_workspace":
            if (!a.workspace)
                return done("Give a workspace");
            Overview.focusWorkspace(a.workspace);
            show({ kind: "tool", text: `Went to workspace ${a.workspace}`, icon: "\u{F05AF}", ok: true });
            return done("Done");
        case "focus_window":
            if (!win)
                return done("No such window; look it up with list_windows");
            Overview.focusWindow(win.address);
            show({ kind: "tool", text: `Focused ${what}`, icon: "\u{F05AF}", ok: true });
            return done("Done");
        case "move_window":
            if (!win || !a.workspace)
                return done("Give a window address (list_windows) and a workspace");
            Overview.moveWindow(win.address, a.workspace, Hyprland.focusedMonitor?.activeWorkspace?.id ?? 0);
            show({ kind: "tool", text: `Moved ${what} to workspace ${a.workspace}`, icon: "\u{F05AF}", ok: true });
            return done("Done");
        case "close_window":
            if (!win)
                return done("No such window; look it up with list_windows");
            ask_(`Close ${what}`, "", "\u{F05AF}", (at, d) => {
                const ws = Hyprland.focusedMonitor?.activeWorkspace?.id;
                Overview.focusWindow(win.address);
                Hyprland.dispatch("hl.dsp.window.close()");
                if (ws !== undefined)
                    Overview.focusWorkspace(ws);
                d("Closed");
            }, done);
            return;
        default:
            done(`Unknown action ${a.action}`);
        }
    }

    // ---- Home Assistant

    // Services run without asking: everyday ones, easy to undo.
    readonly property var everyday: ["light", "switch", "fan", "media_player", "climate", "cover", "vacuum", "scene", "input_boolean", "input_number", "input_select", "input_button", "button", "number", "select", "humidifier", "water_heater"]

    function haFind(query: string, done: var): void {
        if (!HomeAssistant.configured) {
            show({ kind: "tool", text: "Home Assistant isn't set up", icon: "\u{F07D0}", ok: false });
            return done("Home Assistant isn't set up");
        }
        HomeAssistant.request("GET", "/api/states", null, list => {
            const words = HomeAssistant.fold(query).split(/\s+/).filter(w => w);
            const found = (list ?? []).filter(s => {
                const hay = HomeAssistant.fold(`${s.entity_id} ${s.attributes?.friendly_name ?? ""}`);
                const parts = hay.split(/[\s._-]+/);
                return words.every(w => hay.includes(w) || parts.some(p => HomeAssistant.oneOff(p, w)));
            }).slice(0, 40).map(s => ({
                    entity_id: s.entity_id,
                    name: s.attributes?.friendly_name,
                    state: s.state,
                    unit: s.attributes?.unit_of_measurement,
                    brightness_pct: s.attributes?.brightness !== undefined ? Math.round(s.attributes.brightness / 2.55) : undefined,
                    temperature: s.attributes?.temperature,
                    current_temperature: s.attributes?.current_temperature
                }));
            show({ kind: "tool", text: `Looked for "${query}" in Home Assistant · ${found.length} found`, icon: "\u{F07D0}", ok: true });
            done(found.length ? found : "Nothing matches; try other words");
        });
    }

    function haCall(a: var, done: var): void {
        if (!HomeAssistant.configured) {
            show({ kind: "tool", text: "Home Assistant isn't set up", icon: "\u{F07D0}", ok: false });
            return done("Home Assistant isn't set up");
        }
        const domain = String(a.domain ?? ""), service = String(a.service ?? ""), id = String(a.entity_id ?? "");
        const data = Object.assign({}, a.data ?? {}, { entity_id: id });
        const name = HomeAssistant.states[id]?.attributes?.friendly_name ?? id;
        const label = `${name}: ${service.replace(/_/g, " ")}${a.data && Object.keys(a.data).length ? ` ${Object.values(a.data).join(" ")}` : ""}`;
        const run = (at, d0) => {
            let answered = false;
            const d = r => {
                if (!answered) {
                    answered = true;
                    d0(r);
                }
            };
            HomeAssistant.request("POST", `/api/services/${domain}/${service}`, data, res => {
                HomeAssistant.update(res ?? []);
                update(at, { ok: true });
                d((res ?? []).map(s => ({ entity_id: s.entity_id, state: s.state })));
            });
            // A failed call never calls back; its error shows instead.
            failCheck.createObject(root, { at, done: d });
        };
        const safe = everyday.includes(domain) || domain === "homeassistant" && ["turn_on", "turn_off", "toggle"].includes(service) && everyday.includes(id.split(".")[0]);
        if (safe)
            run(show({ kind: "tool", text: label, icon: "\u{F07D0}" }), done);
        else
            ask_(label, `${domain}.${service} on ${id}`, "\u{F07D0}", run, done);
    }

    // After a Home Assistant call: if it hasn't answered in 10 s (or failed, which calls
    // nothing back), the model hears so.
    Component {
        id: failCheck

        Timer {
            required property int at
            required property var done

            running: true
            interval: 10000
            onTriggered: {
                if (root.view[at] && root.view[at].ok === undefined) {
                    root.update(at, { ok: false });
                    done(`Failed: ${HomeAssistant.error || "no answer"}`);
                }
                destroy();
            }
        }
    }

    // ---- Matrix

    function matrixRead(roomId: string, count: int, done: var): void {
        const room = Matrix.rooms[roomId];
        if (!room)
            return done("No such room; look it up with matrix_rooms");
        Matrix.exec("paginate", { room_id: roomId, limit: count * 2 }, res => {
            const evts = (res?.events ?? []).slice().sort((x, y) => (x.timeline_rowid ?? 0) - (y.timeline_rowid ?? 0));
            const out = evts.map(e => ({ from: Matrix.senderName(roomId, e.sender ?? ""), text: Matrix.text(e), time: e.timestamp ? new Date(e.timestamp).toLocaleString() : undefined })).filter(m => m.text).slice(-count);
            show({ kind: "tool", text: `Read ${Matrix.roomName(room)}`, icon: "\u{F0368}", ok: true });
            done(out.length ? out : "No messages");
        }, () => done("Couldn't load the messages"));
    }

    // Runs `run` a moment later.
    Component {
        id: later

        Timer {
            required property var run

            running: true
            interval: 250
            onTriggered: {
                run();
                destroy();
            }
        }
    }

    // ---- Shell commands

    function command(cmd: string, at: int, done: var): void {
        shellRun.createObject(root, { cmd, at, done });
    }

    Component {
        id: shellRun

        Process {
            id: proc

            required property string cmd
            required property int at
            required property var done

            command: ["timeout", "30", "sh", "-c", cmd]
            running: true
            stdout: StdioCollector {
                id: out
            }
            stderr: StdioCollector {
                id: err
            }
            onExited: code => {
                const text = `${out.text}${err.text ? `\n${err.text}` : ""}`.trim();
                root.update(proc.at, { ok: code === 0, detail: text.split("\n").slice(-3).join("\n") });
                proc.done({ exit_code: code === 124 ? "timed out" : code, output: text.length > 3000 ? `…${text.slice(-3000)}` : text });
                destroy();
            }
        }
    }
}
