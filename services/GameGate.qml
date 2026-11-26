pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Steam games ask a vocabulary word before they show (Vocab.games, on by default). A window
// opening from a Steam game (its process has SteamGameId, or its class is steam_app_N; never
// Steam itself) is moved to a hidden special workspace, and a full-screen card (GameGateScreen)
// asks a word as the lock does: a wrong answer shows the right one to type out, then another
// word, until one is right, with an emergency button after Config.vocab.emergency seconds.
// Then the game's windows go back to where they opened, and its later windows pass until it
// has closed them all.
Singleton {
    id: root

    readonly property string hideaway: "special:moqs-vocab"
    // The card is up, for the game titled `game`, on monitor `screen`.
    property bool active
    property string game
    property string screen
    // Windows waiting: [{ address, workspace, gameId }]
    property var hidden: []
    // Window address -> SteamGameId, for every window of a game seen, and the games passed.
    property var gameOf: ({})
    property var passed: ({})
    property real since
    property bool emergencyReady

    readonly property VocabSession session: VocabSession {
        gate: true
        where: "game"
        onPassed: root.release()
    }

    function opened(data: string): void {
        // ADDRESS,WORKSPACE,CLASS,TITLE (the title may have commas of its own).
        const [address, , cls] = data.split(",");
        if (!address || /^steam$/i.test(cls ?? ""))
            return;
        clients.createObject(root, { address, cls: cls ?? "" });
    }

    function closed(address: string): void {
        const id = gameOf[address];
        if (id === undefined)
            return;
        const rest = Object.assign({}, gameOf);
        delete rest[address];
        gameOf = rest;
        hidden = hidden.filter(h => h.address !== address);
        // The game is gone: it asks again next time.
        if (!Object.values(rest).includes(id)) {
            const p = Object.assign({}, passed);
            delete p[id];
            passed = p;
        }
        if (active && !hidden.length)
            stop();
    }

    // A window of game `id` opened on `workspace`.
    function gate(address: string, workspace: int, title: string, id: string): void {
        gameOf = Object.assign({}, gameOf, { [address]: id });
        if (passed[id] || !Vocab.games || !Vocab.cards.length)
            return;
        Hyprland.dispatch(`hl.dsp.window.move({window = "address:0x${address}", workspace = "${hideaway}", follow = false})`);
        hidden = [...hidden, { address, workspace, gameId: id }];
        if (active)
            return;
        game = title;
        screen = Hyprland.focusedMonitor?.name ?? "";
        since = Date.now();
        emergencyReady = false;
        emergencyTimer.restart();
        active = true;
        session.start();
    }

    // Right answer, or the emergency button: the windows go back, the last one focused.
    function release(): void {
        const back = hidden;
        for (const h of back) {
            passed = Object.assign({}, passed, { [h.gameId]: true });
            const ws = h.workspace > 0 ? h.workspace : (Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1);
            Hyprland.dispatch(`hl.dsp.window.move({window = "address:0x${h.address}", workspace = ${ws}, follow = ${h === back[back.length - 1]}})`);
        }
        stop();
    }

    function emergencyUnlock(): void {
        if (emergencyReady)
            release();
    }

    function stop(): void {
        hidden = [];
        active = false;
        emergencyTimer.stop();
        emergencyReady = false;
        session.stop();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "openwindow")
                root.opened(event.data);
            else if (event.name === "closewindow")
                root.closed(event.data);
        }
    }

    Timer {
        id: emergencyTimer

        interval: Config.vocab.emergency * 1000
        onTriggered: root.emergencyReady = true
    }

    // Looks the new window up (its process and workspace), then that process for Steam's
    // SteamGameId.
    Component {
        id: clients

        Process {
            id: lookup

            required property string address
            required property string cls

            running: true
            command: ["hyprctl", "clients", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let c = null;
                    try {
                        c = JSON.parse(text).find(x => x.address === `0x${lookup.address}`) ?? null;
                    } catch (e) {}
                    if (c)
                        steamId.createObject(root, { address: lookup.address, cls: lookup.cls, workspace: c.workspace?.id ?? 0, title: c.title ?? "", command: ["sh", "-c", "tr '\\0' '\\n' < /proc/$1/environ 2>/dev/null | sed -n 's/^SteamGameId=//p' | head -n 1", "sh", String(c.pid)] });
                }
            }
            onExited: destroy()
        }
    }

    Component {
        id: steamId

        Process {
            id: env

            required property string address
            required property string cls
            required property int workspace
            required property string title

            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    const id = text.trim() || ((env.cls.match(/^steam_app_(\d+)$/) ?? [])[1] ?? "");
                    if (id && id !== "0")
                        root.gate(env.address, env.workspace, env.title, id);
                }
            }
            onExited: destroy()
        }
    }

    IpcHandler {
        target: "gamegate"

        function active(): bool {
            return root.active;
        }
    }
}
