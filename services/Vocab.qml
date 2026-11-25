pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Vocabulary learnt by spaced repetition, in the launcher's ";" pane and, if set, as a step
// after the password on the lock screen. Words are in $XDG_STATE_HOME/moqs/vocab.txt, one per
// line as "word = translation" (or tab-separated, as Anki exports); "," "/" or ";" separates
// answers that each count, and a part in brackets may be left out: "(to) run, sprint".
// A word is asked as written (word -> translation), or also the other way round; due and new
// words come in the list's order, or at random.
//
// When a word is due comes from FSRS (the scheduler Anki uses): each word has a stability (the
// days until the chance of remembering it falls to 90 %) and a difficulty, which every answer
// updates; it's asked again when that chance falls to Config.vocab.retention. A wrong answer
// (or none) counts as Again and brings the word back after Config.vocab.relearn minutes. A
// right one counts as Good, or as Hard when it took long to recall: the time until the first
// key is slower than three quarters of the last right answers (Config.vocab.slow seconds
// until there are a few).
//
// While words are due for review, a notification says so (clicking it opens the pane), at
// most every Config.vocab.notifyEvery hours and not while practising.
//
// The schedule is kept in vocab.json next to the words, with the settings. Over IPC:
//   qs ipc call vocab open                 (the ";" pane)
//   qs ipc call vocab toggleLock           (also setLock true|false, lockEnabled)
//   qs ipc call vocab toggleBothWays       (also setBothWays true|false, bothWays)
//   qs ipc call vocab toggleRandom         (also setRandom true|false, random)
//   qs ipc call vocab add "word" "translation"
//   qs ipc call vocab stats
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs`
    readonly property string wordsPath: `${stateDir}/vocab.txt`
    readonly property real day: 86400000

    // [{ front, back, line }], line being its index in vocab.txt.
    property var cards: []
    // Card key -> { due, last (ms), s (stability, days), d (difficulty, 1..10), reps, lapses }.
    property var sched: ({})
    // New words first asked today, and the day it counts for.
    property string newDay
    property int newToday
    // The lock asks for a word after the password.
    property bool lockGate
    // Words are also asked translation -> word.
    property bool bothWays
    // Due and new words at random rather than in order.
    property bool random
    // Seconds until the first key in the last right answers, newest last.
    property var times: []
    // When the last answer was given, and the last notification about due words sent (ms).
    property real lastAnswer
    property real lastNotified
    // Bumped whenever cards or sched change, for bindings.
    property int version
    // The time, a minute at a time, for what's due.
    property real now: Date.now()

    // Each card as asked, one way or both: [{ key, prompt, answer, dir, card }]. The other
    // way keeps its schedule while it isn't asked.
    readonly property var items: {
        version;
        const out = [];
        for (const c of cards) {
            out.push({ key: `${c.front}\u0001${c.back}\u0001>`, prompt: c.front, answer: c.back, dir: ">", card: c });
            if (bothWays)
                out.push({ key: `${c.front}\u0001${c.back}\u0001<`, prompt: c.back, answer: c.front, dir: "<", card: c });
        }
        return out;
    }

    readonly property int dueCount: {
        version;
        return items.filter(i => sched[i.key] && sched[i.key].due <= now).length;
    }
    readonly property int freshCount: {
        version;
        return items.filter(i => !sched[i.key]).length;
    }
    readonly property int newLeft: {
        version;
        const fresh = items.filter(i => !sched[i.key]).length;
        return Math.max(0, Math.min(fresh, Config.vocab.newPerDay - (newDay === today() ? newToday : 0)));
    }
    // When the next one is due, or 0.
    readonly property real nextDue: {
        version;
        let next = 0;
        for (const i of items) {
            const s = sched[i.key];
            if (s && s.due > now && (!next || s.due < next))
                next = s.due;
        }
        return next;
    }

    function today(): string {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    function any(list: var): var {
        return list[Math.floor(Math.random() * list.length)];
    }

    // The next word to ask: due ones first, then new ones (so many a day). For the lock,
    // which always needs one, any other word when none is due. Never the word of `exclude`
    // (a key), either way round, if there's another.
    function pick(gate: bool, exclude: string): var {
        now = Date.now();
        const word = exclude.slice(0, -1);
        const all = items.filter(i => !exclude || i.key.slice(0, -1) !== word);
        const due = all.filter(i => sched[i.key] && sched[i.key].due <= now);
        if (due.length)
            return random ? any(due) : due.sort((a, b) => sched[a.key].due - sched[b.key].due)[0];
        if (newLeft > 0) {
            const fresh = all.filter(i => !sched[i.key]);
            if (fresh.length)
                return random ? any(fresh) : fresh[0];
        }
        if (!gate)
            return null;
        if (!all.length)
            return items[0] ?? null;
        // A random one of those due soonest, so it isn't always the same.
        return any(all.slice().sort((a, b) => (sched[a.key]?.due ?? 0) - (sched[b.key]?.due ?? 0)).slice(0, 5));
    }

    // ---- Checking answers

    function clean(s: string): string {
        return s.toLowerCase().replace(/[’`´]/g, "'").replace(/\s+/g, " ").replace(/[.!?¡¿]+/g, "").trim();
    }

    // The ways an umlaut may be typed, all as good: ä, ae or a (and ß, ss).
    function spellings(s: string): var {
        const ae = s.replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss");
        const plain = s.replace(/ä/g, "a").replace(/ö/g, "o").replace(/ü/g, "u").replace(/ß/g, "ss");
        return [ae, plain];
    }

    // Without any accents (Latin's macrons, French accents): close, but worth a note.
    function bare(s: string): string {
        try {
            return s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/ß/g, "ss");
        } catch (e) {
            return s;
        }
    }

    // The answer's alternatives: split at "," "/" ";" or "|", but not inside brackets, so
    // "(einer Sache / Person) würdig" stays whole.
    function parts(answer: string): var {
        const out = [];
        let depth = 0, cur = "";
        for (const ch of answer) {
            if (ch === "(")
                depth++;
            else if (ch === ")")
                depth = Math.max(0, depth - 1);
            if (depth === 0 && ",/;|".includes(ch)) {
                out.push(cur);
                cur = "";
            } else {
                cur += ch;
            }
        }
        out.push(cur);
        return out;
    }

    // Every way of writing the answer that counts: all of it, or any one alternative, with
    // or without what's in brackets, and German nouns also without their article.
    function accepted(answer: string): var {
        const out = [clean(answer.replace(/[()]/g, ""))];
        for (const part of parts(answer)) {
            for (const v of [clean(part.replace(/[()]/g, "")), clean(part.replace(/\([^)]*\)/g, ""))]) {
                out.push(v);
                const m = v.match(/^(?:der|die|das) (.+)$/);
                if (m)
                    out.push(m[1]);
            }
        }
        return out.filter((x, i, a) => x && a.indexOf(x) === i);
    }

    function distance(a: string, b: string): int {
        const row = Array.from({ length: b.length + 1 }, (_, i) => i);
        for (let i = 1; i <= a.length; i++) {
            let prev = row[0];
            row[0] = i;
            for (let j = 1; j <= b.length; j++) {
                const t = row[j];
                row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
                prev = t;
            }
        }
        return row[b.length];
    }

    // { ok, note }: right however umlauts are typed, also without accents or with one typo
    // in a longer word, which the note then points out (the whole answer is shown anyway).
    function check(item: var, text: string): var {
        // Brackets typed as shown count too.
        const t = clean(text.replace(/[()]/g, ""));
        if (!t)
            return { ok: false, note: "" };
        const ok = accepted(item.answer);
        const typed = spellings(t);
        if (ok.some(x => spellings(x).some(v => typed.includes(v))))
            return { ok: true, note: "" };
        if (ok.some(x => bare(x) === bare(t)))
            return { ok: true, note: "Mind the accents" };
        if (ok.some(x => spellings(x).some(v => v.length >= 5 && typed.some(u => distance(v, u) === 1))))
            return { ok: true, note: "Almost: mind the spelling" };
        return { ok: false, note: "" };
    }

    // The grade of a right answer from how long recalling it took (seconds until the first
    // key): Hard (2) if slower than three quarters of the last ones, else Good (3). Remembers
    // the time, capped so a walk away doesn't skew the rest.
    function speedGrade(secs: real): int {
        const sorted = times.slice().sort((a, b) => a - b);
        const slow = sorted.length >= 10 ? sorted[Math.floor(sorted.length * 0.75)] : Config.vocab.slow;
        times = [...times, Math.round(Math.min(secs, 60) * 10) / 10].slice(-100);
        return secs > slow ? 2 : 3;
    }

    // ---- FSRS-5, with its default weights

    readonly property var w: [0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621]
    readonly property real decay: -0.5
    readonly property real factor: 19 / 81

    // The chance of remembering a word of stability s after `days`.
    function recall(days: real, s: real): real {
        return Math.pow(1 + factor * days / s, decay);
    }

    // Days until that chance falls to the retention aimed for; a little random beyond a few
    // days, so words learnt together don't stay together.
    function interval(s: real): int {
        let days = s / factor * (Math.pow(Config.vocab.retention, 1 / decay) - 1);
        if (days >= 3)
            days *= 0.95 + Math.random() * 0.1;
        return Math.max(1, Math.min(Config.vocab.maxInterval, Math.round(days)));
    }

    function clampD(d: real): real {
        return Math.max(1, Math.min(10, d));
    }

    function firstD(g: int): real {
        return clampD(w[4] - Math.exp(w[5] * (g - 1)) + 1);
    }

    function nextD(d: real, g: int): real {
        const moved = d - w[6] * (g - 3) * (10 - d) / 9;
        return clampD(w[7] * firstD(4) + (1 - w[7]) * moved);
    }

    function rememberedS(d: real, s: real, r: real, g: int): real {
        return s * (1 + Math.exp(w[8]) * (11 - d) * Math.pow(s, -w[9]) * (Math.exp(w[10] * (1 - r)) - 1) * (g === 2 ? w[15] : 1) * (g === 4 ? w[16] : 1));
    }

    function forgottenS(d: real, s: real, r: real): real {
        return Math.min(s, w[11] * Math.pow(d, -w[12]) * (Math.pow(s + 1, w[13]) - 1) * Math.exp(w[14] * (1 - r)));
    }

    // Again the same day, e.g. typed right after being shown it.
    function sameDayS(s: real, g: int): real {
        return s * Math.exp(w[17] * (g - 3 + w[18]));
    }

    // Entries from before FSRS: { due, ivl, ease, reps, lapses }.
    function upgrade(old: var): var {
        if (!old || old.s)
            return old;
        const ivl = old.ivl ?? 0;
        return { due: old.due, last: ivl > 0 ? old.due - ivl * day : old.due - Config.vocab.relearn * 60000, s: ivl > 0 ? ivl : w[0], d: old.lapses ? 6 : 5, reps: old.reps ?? 0, lapses: old.lapses ?? 0 };
    }

    // Schedules a word after an answer graded 1 (Again), 2 (Hard) or 3 (Good). Returns the
    // days until it's asked again, 0 for minutes.
    function grade(item: var, g: int): int {
        now = Date.now();
        lastAnswer = now;
        const old = upgrade(sched[item.key]);
        let s, d;
        if (!old) {
            if (newDay !== today()) {
                newDay = today();
                newToday = 0;
            }
            newToday++;
            s = w[g - 1];
            d = firstD(g);
        } else {
            const days = (now - old.last) / day;
            if (days < 1)
                s = sameDayS(old.s, g);
            else if (g === 1)
                s = forgottenS(old.d, old.s, recall(days, old.s));
            else
                s = rememberedS(old.d, old.s, recall(days, old.s), g);
            d = nextD(old.d, g);
        }
        s = Math.max(0.01, s);
        const ivl = g === 1 ? 0 : interval(s);
        sched[item.key] = {
            due: g === 1 ? now + Config.vocab.relearn * 60000 : now + ivl * day,
            last: now,
            s: Math.round(s * 1000) / 1000,
            d: Math.round(d * 1000) / 1000,
            reps: (old?.reps ?? 0) + 1,
            lapses: (old?.lapses ?? 0) + (g === 1 ? 1 : 0)
        };
        version++;
        save.restart();
        return ivl;
    }

    // ---- Settings and words

    // Another day's worth of new words today, once those are done.
    function learnMore(): void {
        if (newDay !== today()) {
            newDay = today();
            newToday = 0;
        }
        newToday = Math.min(newToday, Config.vocab.newPerDay) - Config.vocab.newPerDay;
        version++;
        save.restart();
    }

    function setLock(on: bool): void {
        lockGate = on;
        save.restart();
    }

    function setBothWays(on: bool): void {
        bothWays = on;
        save.restart();
    }

    function setRandom(on: bool): void {
        random = on;
        save.restart();
    }

    function add(front: string, back: string): bool {
        front = front.trim();
        back = back.trim();
        if (!front || !back || front.includes("\n") || back.includes("\n"))
            return false;
        let text = wordsFile.text();
        if (!text.trim())
            text = "# moqs vocabulary, one per line as \"word = translation\".\n";
        if (!text.endsWith("\n"))
            text += "\n";
        wordsFile.setText(`${text}${front} = ${back}\n`);
        parse(`${text}${front} = ${back}\n`);
        return true;
    }

    function remove(card: var): void {
        const lines = wordsFile.text().split("\n");
        if (lines[card.line] === undefined)
            return;
        lines.splice(card.line, 1);
        wordsFile.setText(lines.join("\n"));
        parse(lines.join("\n"));
    }

    function parse(text: string): void {
        const out = [];
        text.split("\n").forEach((line, i) => {
            if (/^\s*(#|$)/.test(line))
                return;
            const m = line.match(/^\s*([^\t]+?)\s*\t\s*([^\t]+?)\s*(\t.*)?$/) ?? line.match(/^\s*(.+?)\s*=\s*(.+?)\s*$/);
            if (m)
                out.push({ front: m[1], back: m[2], line: i });
        });
        cards = out;
        version++;
    }

    // Words due for review: not the ones coming back minutes after a mistake.
    function reviewsDue(): int {
        return items.filter(i => {
            const s = sched[i.key];
            return s && s.due <= now && s.due - s.last >= day / 2;
        }).length;
    }

    // Tells about due words, unless it did lately or they're being practised.
    function notifyDue(): void {
        const every = Config.vocab.notifyEvery * 3600000;
        if (!every || notification.running || now - lastNotified < every || now - lastAnswer < 15 * 60000)
            return;
        const n = reviewsDue();
        if (!n)
            return;
        lastNotified = now;
        save.restart();
        notification.command = ["notify-send", "-a", "Vocabulary", "-i", "accessories-dictionary", "-A", "default=Practise",
            `${n} word${n === 1 ? "" : "s"} to review`, newLeft ? `And ${newLeft} new ones. Click to practise.` : "Click to practise."];
        notification.running = true;
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    Timer {
        running: true
        repeat: true
        interval: 60000
        onTriggered: {
            root.now = Date.now();
            root.notifyDue();
        }
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

    Timer {
        id: save

        interval: 500
        onTriggered: schedFile.setText(JSON.stringify({ lockGate: root.lockGate, bothWays: root.bothWays, random: root.random, times: root.times, lastNotified: root.lastNotified, newDay: root.newDay, newToday: root.newToday, cards: root.sched }) + "\n")
    }

    FileView {
        id: wordsFile

        path: root.wordsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
    }

    FileView {
        id: schedFile

        path: `${root.stateDir}/vocab.json`
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.lockGate = s.lockGate === true;
                root.bothWays = s.bothWays === true;
                root.random = s.random === true;
                root.times = Array.isArray(s.times) ? s.times.filter(t => typeof t === "number") : [];
                root.lastNotified = s.lastNotified ?? 0;
                root.newDay = s.newDay ?? "";
                root.newToday = s.newToday ?? 0;
                root.sched = s.cards && typeof s.cards === "object" ? s.cards : {};
                root.version++;
            } catch (e) {}
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

        function add(word: string, translation: string): string {
            return root.add(word, translation) ? `added ${word} = ${translation}` : "give a word and its translation";
        }

        function stats(): string {
            return `${root.cards.length} words, ${root.dueCount} due, ${root.newLeft} new today, lock ${root.lockGate ? "on" : "off"}, ${root.bothWays ? "both ways" : "one way"}, ${root.random ? "random" : "in order"}`;
        }
    }
}
