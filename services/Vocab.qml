pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Vocabulary learnt by spaced repetition, in the launcher's ";" pane and, if set, as a step
// after the password on the lock screen and before Steam games. It all lives on a moqs-vocab
// server (settings.json vocab.server, the Nix option services.moqs.vocab.server, e.g.
// "http://worker-03"), which also has a web app for it: words, schedule (Anki's, with
// FSRS-6), settings, stats and the answer log are kept there, sessions run there
// (VocabSession), and this follows its API and events, so practising in the web app shows
// here at once. Without a server set there are no words.
//
// Words are lines "word = translation" in the server's vocab.txt; "," "/" or ";" separates
// answers that each count, a part in brackets may be left out, after " # " comes a note
// (grammar, say) and a word's mnemonic as " # mnemonic: …"; a comment line ("# Lektion 3")
// heads the words below it, for the stats. A word forgotten in reviews again and again is a
// hard word (Anki's leech): it's marked while asked and the pane offers a mnemonic for it
// (Mnemonic, which suggests them from here).
//
// A day starts at Config.vocab.dayStart (4 am), as in Anki and on the server.
//
// While words are due for review, a notification says so (clicking it opens the pane), at
// most every Config.vocab.notifyEvery hours and not while practising.
//
// Over IPC:
//   qs ipc call vocab open                 (the ";" pane)
//   qs ipc call vocab toggleLock           (also setLock true|false, lockEnabled)
//   qs ipc call vocab toggleBothWays       (also setBothWays true|false, bothWays)
//   qs ipc call vocab toggleRandom         (also setRandom true|false, random)
//   qs ipc call vocab toggleGames          (also setGames true|false, games: Steam games
//                                           ask a word first, see GameGate)
//   qs ipc call vocab add "word" "translation"
//   qs ipc call vocab stats
//   qs ipc call vocab hardWords
Singleton {
    id: root

    // Where Mnemonic keeps its suggestions prepared ahead and its log.
    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs`
    readonly property real day: 86400000

    // The moqs-vocab server, or "" when none is set.
    readonly property string server: Settings.vocabServer
    // The server's /api/state and /api/stats, as last heard; null until then.
    property var serverState: null
    property var serverStats: null
    // Why the server can't be used right now, or "".
    property string serverError

    // [{ front, back, hint, mnemonic, section, line }], line being its index in vocab.txt, section
    // the comment heading it, hint its note (e.g. grammar) and mnemonic its mnemonic.
    property var cards: []
    // Card key ("front\u0001back\u0001>", "<" the other way) -> { state, due, s, d, reps,
    // lapses, leech }, for the ways seen so far.
    property var sched: ({})
    // The lock asks for a word after the password.
    property bool lockGate
    // Words are also asked translation -> word.
    property bool bothWays
    // Due and new words at random rather than in order.
    property bool random
    // Steam games ask a word before they show (GameGate).
    property bool games: true
    // When the last answer was given here, and the last notification about due words sent (ms).
    property real lastAnswer
    property real lastNotified
    // Bumped whenever cards or sched change, for bindings.
    property int version
    // The time, a minute at a time.
    property real now: Date.now()

    // What's left now, as Anki counts it: new words still to see today, words in learning
    // steps due (or soon), and reviews due.
    readonly property int learningCount: serverState?.counts?.learning ?? 0
    readonly property int reviewCount: serverState?.counts?.review ?? 0
    readonly property int newLeft: serverState?.counts?.new ?? 0
    readonly property int dueCount: serverState?.due ?? 0
    // Words never asked yet, today's limit aside.
    readonly property int freshCount: serverState?.fresh ?? 0
    // When the next one is due, or 0.
    readonly property real nextDue: serverState?.nextDue ?? 0
    // Today's answers and right ones (Again aside).
    readonly property var todayAnswers: serverState?.today ?? { n: 0, r: 0 }

    // For the pane's stats: { total, seen, learnt (remembered 21 days or more), streak (days
    // in a row with answers), recall (share right in the last 7 days, or -1), forecast (words
    // due on each of the next 7 days, today with those overdue), sections: [{ name, total,
    // seen, learnt }], hard: [{ prompt, answer, lapses }] }
    readonly property var stats: serverStats ?? { total: cards.length, seen: 0, learnt: 0, streak: 0, recall: -1, forecast: [0, 0, 0, 0, 0, 0, 0], sections: [], hard: [] }

    // Misses of a schedule entry, as far as the server tells them: its lapses, the first try
    // of a new word maybe among them.
    function missesOf(e: var): int {
        return e ? Math.max(0, (e.lapses ?? 0) - 1) : 0;
    }

    // The start of the day `n` days after that of `ms`.
    function dayAfter(ms: real, n: int): real {
        const d = new Date(ms - Config.vocab.dayStart * 3600000);
        d.setHours(Config.vocab.dayStart, 0, 0, 0);
        d.setDate(d.getDate() + n);
        return d.getTime();
    }

    // ---- Settings and words

    // Another day's worth of new words today, once those are done.
    function learnMore(): void {
        api("POST", "/api/learn-more", {}, (status, r) => {
            if (status === 200)
                root.takeState(r);
        });
    }

    function setting(name: string, on: bool): void {
        root[name] = on;
        api("PATCH", "/api/settings", { [name]: on }, null);
    }

    function setLock(on: bool): void {
        setting("lockGate", on);
    }

    function setBothWays(on: bool): void {
        setting("bothWays", on);
    }

    function setRandom(on: bool): void {
        setting("random", on);
    }

    function setGames(on: bool): void {
        setting("games", on);
    }

    function add(front: string, back: string): bool {
        front = front.trim();
        back = back.trim();
        if (!server || !front || !back || front.includes("\n") || back.includes("\n") || cards.some(c => c.front === front && c.back === back))
            return false;
        cards = [...cards, { front, back, hint: "", mnemonic: "", section: cards[cards.length - 1]?.section ?? "", line: -1 }];
        version++;
        api("POST", "/api/cards", { front, back }, () => fetchCards.restart());
        return true;
    }

    // Sets a word's mnemonic (shown with the answer), keeping its note; "" removes it. Returns
    // the card as it is now, or null.
    function setMnemonic(card: var, mnemonic: string): var {
        mnemonic = mnemonic.replace(/\s+/g, " ").replace(/ # /g, " – ").trim();
        const i = cards.findIndex(c => c.front === card.front && c.back === card.back);
        if (i < 0)
            return null;
        const list = cards.slice();
        list[i] = Object.assign({}, list[i], { mnemonic });
        cards = list;
        version++;
        api("PUT", "/api/cards/mnemonic", { front: card.front, back: card.back, mnemonic }, () => fetchCards.restart());
        return list[i];
    }

    function remove(card: var): void {
        cards = cards.filter(c => !(c.front === card.front && c.back === card.back));
        version++;
        // Qt's XMLHttpRequest sends no body with DELETE.
        remover.command = ["curl", "-sS", "--max-time", "15", "-X", "DELETE", "-H", "Content-Type: application/json", "--data-binary", JSON.stringify({ front: card.front, back: card.back }), `${server}/api/cards`];
        remover.running = true;
    }

    // Tells about due words, unless it did lately or they're being practised.
    function notifyDue(): void {
        const every = Config.vocab.notifyEvery * 3600000;
        if (!serverState || !every || notification.running || now - lastNotified < every || now - lastAnswer < 15 * 60000)
            return;
        const n = reviewCount;
        if (!n)
            return;
        lastNotified = now;
        notification.command = ["notify-send", "-a", "Vocabulary", "-i", "accessories-dictionary", "-A", "default=Practise",
            `${n} word${n === 1 ? "" : "s"} to review`, newLeft ? `And ${newLeft} new ones. Click to practise.` : "Click to practise."];
        notification.running = true;
    }

    // ---- The server

    // Calls the server's API: done(status, the JSON reply or null), status 0 when it can't be
    // reached in time (or no server is set).
    function api(method: string, path: string, body: var, done: var): void {
        const url = server;
        if (!url) {
            if (done)
                done(0, null);
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let r = null;
            try {
                r = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (url !== root.server)
                return;
            if (xhr.status === 0)
                root.serverError = `Can't reach ${url}`;
            else if (xhr.status >= 500)
                root.serverError = r?.error ?? `${url} answered ${xhr.status}`;
            else
                root.serverError = "";
            if (done)
                done(xhr.status, r);
        };
        xhr.open(method, `${url}${path}`);
        xhr.timeout = 15000;
        if (body !== null && body !== undefined)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body === null || body === undefined ? "" : JSON.stringify(body));
    }

    // The server's /api/state: counts, settings and, when it changed, the words again.
    function takeState(st: var): void {
        if (!st || typeof st !== "object")
            return;
        const changed = st.version !== serverState?.version;
        serverState = st;
        if (st.settings) {
            lockGate = st.settings.lockGate === true;
            bothWays = st.settings.bothWays === true;
            random = st.settings.random === true;
            games = st.settings.games !== false;
        }
        now = Date.now();
        if (changed)
            fetchCards.restart();
    }

    // The server's /api/cards: the words, and each way's schedule as far as it tells it.
    function takeCards(list: var): void {
        const out = [];
        const s = {};
        for (const c of list) {
            out.push({ front: c.front, back: c.back, hint: c.hint ?? "", mnemonic: c.mnemonic ?? "", section: c.section ?? "", line: c.line });
            if (c.forward)
                s[`${c.front}\u0001${c.back}\u0001>`] = c.forward;
            if (c.backward)
                s[`${c.front}\u0001${c.back}\u0001<`] = c.backward;
        }
        cards = out;
        sched = s;
        version++;
    }

    // Another server (or none): nothing of the last one stays.
    onServerChanged: {
        events.running = false;
        serverState = null;
        serverStats = null;
        serverError = "";
        cards = [];
        sched = {};
        version++;
        if (server !== "")
            fetchState.restart();
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", stateDir]);
        if (server !== "")
            fetchState.restart();
    }

    Timer {
        running: true
        repeat: true
        interval: 60000
        onTriggered: {
            root.now = Date.now();
            root.notifyDue();
        }
    }

    // The state, at start and again when the events stop (the server restarted, say).
    Timer {
        id: fetchState

        interval: 50
        onTriggered: root.api("GET", "/api/state", null, (status, r) => {
            if (status === 200)
                root.takeState(r);
            if (!events.running && root.server !== "")
                events.running = true;
        })
    }

    Timer {
        id: fetchCards

        interval: 100
        onTriggered: {
            root.api("GET", "/api/cards", null, (status, r) => {
                if (status === 200 && Array.isArray(r?.cards))
                    root.takeCards(r.cards);
            });
            root.api("GET", "/api/stats", null, (status, r) => {
                if (status === 200 && r)
                    root.serverStats = r;
            });
        }
    }

    // The server's events: "state" whenever anything changes there, here or in the web app.
    Process {
        id: events

        property string event

        command: ["curl", "-sSN", "--connect-timeout", "10", "--keepalive-time", "30", `${root.server}/api/events`]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("event:"))
                    events.event = line.slice(6).trim();
                else if (line.startsWith("data:") && events.event === "state") {
                    try {
                        root.takeState(JSON.parse(line.slice(5)));
                        root.serverError = "";
                    } catch (e) {}
                }
            }
        }
        onExited: if (root.server !== "")
            reconnect.restart()
    }

    Timer {
        id: reconnect

        interval: 5000
        onTriggered: if (root.server !== "")
            fetchState.restart()
    }

    Process {
        id: remover

        onExited: fetchCards.restart()
    }

    // notify-send waits for a click on the notification and prints the action.
    Process {
        id: notification

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "default")
                    Launcher.showWith(";");
            }
        }
    }

    IpcHandler {
        target: "vocab"

        function open(): void {
            Launcher.showWith(";");
        }

        function toggleLock(): bool {
            root.setLock(!root.lockGate);
            return root.lockGate;
        }

        function setLock(on: bool): bool {
            root.setLock(on);
            return root.lockGate;
        }

        function lockEnabled(): bool {
            return root.lockGate;
        }

        function toggleBothWays(): bool {
            root.setBothWays(!root.bothWays);
            return root.bothWays;
        }

        function setBothWays(on: bool): bool {
            root.setBothWays(on);
            return root.bothWays;
        }

        function bothWays(): bool {
            return root.bothWays;
        }

        function toggleRandom(): bool {
            root.setRandom(!root.random);
            return root.random;
        }

        function setRandom(on: bool): bool {
            root.setRandom(on);
            return root.random;
        }

        function random(): bool {
            return root.random;
        }

        function toggleGames(): bool {
            root.setGames(!root.games);
            return root.games;
        }

        function setGames(on: bool): bool {
            root.setGames(on);
            return root.games;
        }

        function games(): bool {
            return root.games;
        }

        function add(word: string, translation: string): string {
            return root.add(word, translation) ? `added ${word} = ${translation}` : "give a word and its translation (and a server)";
        }

        // The hard words, most missed first, one per line.
        function hardWords(): string {
            return root.stats.hard.map(h => `${h.prompt} = ${h.answer} (forgotten ${h.lapses}×)`).join("\n") || "no hard words";
        }

        function stats(): string {
            if (!root.server)
                return "no vocabulary server set (services.moqs.vocab.server)";
            if (!root.serverState)
                return root.serverError || "not loaded yet";
            return `${root.cards.length} words, ${root.dueCount} due, ${root.newLeft} new today, lock ${root.lockGate ? "on" : "off"}, ${root.bothWays ? "both ways" : "one way"}, ${root.random ? "random" : "in order"}`;
        }
    }
}
