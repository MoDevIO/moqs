import QtQuick
import qs.config

// One vocabulary quiz in progress, shown by VocabQuiz: the launcher's ";" pane has one and
// the lock screen one, shared by all its screens. A word is asked ("ask"); a right answer
// ("right") moves on to the next one, or for the lock (gate) passes; a wrong one, or Enter
// with nothing typed, shows the answer, which has to be typed out ("wrong") before another
// word comes. How long recalling took (until the first key, see typed()) makes a right
// answer Good or Hard (Vocab.speedGrade). A wrong answer that is another word's answer is a
// mix-up (`confused`), which the card points out.
//
// In the pane, an answer judged wrong can be counted as right after all (overrule(), "I got
// it right"), say a synonym the list doesn't have: the miss is taken back.
//
// In the pane (not the lock, which asks a new word until one is right), a word answered wrong
// comes back in this session: first after the words left to do, and the more often it was
// wrong, the sooner. With no other word left to put in between, a missed word comes back
// only after Config.vocab.retryGap seconds (`waitUntil`), and then for practice (`retrying`):
// right after typing it out, a right answer would say nothing; it counts once it's due again
// (Vocab's learning steps). When all is done comes a final round: the words missed in the
// session once more, for practice, until each is right; not those still being learnt, which
// come back for real anyway, nor the one just answered.
//
// Every answer goes to Vocab.log().
QtObject {
    id: root

    // For the lock: always a word, and passed() on the first right answer.
    property bool gate
    // Where it's asked, for the log: pane, lock or game.
    property string where: "pane"
    // The word asked (see Vocab.items), or null when nothing is due.
    property var item: null
    // ask, right or wrong
    property string phase: "ask"
    // Said under the answer, e.g. about accents.
    property string note
    // The card whose answer was typed by mistake, or null.
    property var confused: null
    // When the word was shown, and when its first key was typed.
    property real shownAt
    property real firstKeyAt
    // Words to ask again: [{ item, fails, wait }], wait counting down the words asked until
    // it's due again.
    property var again: []
    // Words missed in this session, and the final round's words left (null before it).
    property var missed: []
    property var round: null
    // The word asked is the final round's.
    property bool practice
    // The word asked is the one just missed, again for practice, nothing else being left.
    property bool retrying
    // Waiting before asking the word with key waitKey again, until waitUntil (ms); clock
    // ticks meanwhile for the countdown.
    property string waitKey
    property real waitUntil
    property real clock
    // After an answer judged wrong (something typed, not the pane's lock or game): what it
    // changed, for overrule(). Else null.
    property var undo: null
    readonly property bool canOverrule: !gate && phase === "wrong" && undo !== null
    // A right answer stays on screen until Enter (see pause()).
    property bool paused

    signal passed
    // A wrong answer or retype, for the field to shake.
    signal rejected

    // Moves on to the next word.
    function start(): void {
        advance.stop();
        const prev = item?.key ?? waitKey;
        // Words removed, or no longer asked this way round, drop out.
        const keys = Vocab.items.map(i => i.key);
        const queue = again.filter(a => keys.includes(a.item.key));
        for (const a of queue)
            a.wait--;
        again = queue;
        const others = queue.filter(a => a.item.key !== prev);
        // Due back now, the most failed first; else a word as usual; else, nothing else left,
        // the one due back soonest.
        const ready = others.filter(a => a.wait <= 0).sort((x, y) => y.fails - x.fails)[0];
        let next = ready?.item ?? Vocab.pick(gate, prev, queue.map(a => a.item.key)) ?? others.sort((x, y) => x.wait - y.wait)[0]?.item ?? null;
        // Only the word just missed is left: after a pause, and for practice until it's due.
        let retry = false;
        if (!next && queue.length) {
            const at = (queue[0].missedAt ?? 0) + Config.vocab.retryGap * 1000;
            if (Date.now() < at) {
                wait(queue[0].item.key, at);
                return;
            }
            next = queue[0].item;
            retry = (Vocab.sched[next.key]?.due ?? 0) > Date.now();
        }
        // All done: the final round, the missed words once more in a new order.
        if (!next && !gate && missed.length) {
            if (round === null)
                round = missed.filter(i => keys.includes(i.key) && i.key !== prev && !Vocab.sched[i.key]?.learning).map(i => ({ i, r: Math.random() })).sort((a, b) => a.r - b.r).map(x => x.i);
            else
                round = round.filter(i => keys.includes(i.key));
            next = round.find(i => i.key !== prev) ?? round[0] ?? null;
        }
        practice = !!next && round !== null && round.includes(next);
        retrying = retry;
        waitKey = "";
        waitUntil = 0;
        retryTimer.stop();
        phase = "ask";
        note = "";
        confused = null;
        undo = null;
        paused = false;
        item = next;
        shownAt = Date.now();
        firstKeyAt = 0;
    }

    // After an answer: a wrong word joins the queue (or moves up it), a right one leaves it.
    function requeue(right: bool): void {
        if (gate)
            return;
        const queued = again.find(a => a.item.key === item.key);
        if (right) {
            again = again.filter(a => a !== queued);
            return;
        }
        if (!missed.some(i => i.key === item.key))
            missed = [...missed, item];
        // The words left to do today, besides those already coming back (which aren't due
        // yet, as a mistake brings a word back only after minutes, so they aren't counted).
        const waiting = again.map(a => a.item.key);
        const left = Math.max(2, Vocab.items.filter(i => !waiting.includes(i.key) && Vocab.sched[i.key]?.due <= Vocab.now).length + Vocab.newLeft);
        const fails = (queued?.fails ?? 0) + 1;
        again = [...again.filter(a => a !== queued), { item, fails, wait: Math.max(2, Math.ceil(left / fails)), missedAt: Date.now() }];
    }

    // Nothing to ask until `at`, then the word with `key` again.
    function wait(key: string, at: real): void {
        phase = "ask";
        note = "";
        confused = null;
        undo = null;
        paused = false;
        practice = false;
        retrying = false;
        item = null;
        waitKey = key;
        waitUntil = at;
        clock = Date.now();
        retryTimer.restart();
    }

    // Something was typed in the field.
    function typed(): void {
        if (!firstKeyAt && phase === "ask")
            firstKeyAt = Date.now();
    }

    function stop(): void {
        advance.stop();
        phase = "ask";
        note = "";
        confused = null;
        undo = null;
        paused = false;
        item = null;
        again = [];
        missed = [];
        round = null;
        practice = false;
        retrying = false;
        waitKey = "";
        waitUntil = 0;
        retryTimer.stop();
    }

    // The log's record of an answer to the word shown.
    function record(text: string, r: var, extra: var): var {
        return Object.assign({
            t: Date.now(),
            day: Vocab.today(),
            where,
            key: item.key,
            word: item.prompt,
            answer: item.answer,
            dir: item.dir,
            typed: text.trim(),
            ok: r.ok,
            note: r.note || undefined,
            mixup: confused ? `${confused.front} = ${confused.back}` : undefined,
            firstKey: firstKeyAt ? Math.round(firstKeyAt - shownAt) : undefined,
            took: Math.round(Date.now() - shownAt)
        }, extra);
    }

    // What was typed for the word. Returns whether the field should clear.
    function submit(text: string): bool {
        if (!item) {
            start();
            return false;
        }
        if (phase === "right") {
            // Held for a mnemonic: Enter goes on.
            if (paused)
                proceed();
            return false;
        }
        // Nothing typed: show the answer to type out.
        const r = Vocab.check(item, text);
        if (phase === "ask" && (practice || retrying)) {
            // The final round, or the word just missed again: practice, the schedule stays.
            const t = Date.now();
            confused = r.ok ? null : Vocab.mixup(item, text);
            Vocab.log(record(text, r, { t, practice: true }));
            if (r.ok) {
                if (retrying) {
                    // It's asked for real once due.
                    again = again.filter(a => a.item.key !== item.key);
                    right([r.note, countsWhen()].filter(x => x).join(" · "));
                } else {
                    round = round.filter(i => i.key !== item.key);
                    right(r.note);
                }
            } else {
                if (retrying) {
                    const queued = again.find(a => a.item.key === item.key);
                    if (queued)
                        queued.missedAt = t;
                } else {
                    // To the end of the round.
                    round = [...round.filter(i => i.key !== item.key), item];
                }
                phase = "wrong";
                note = "";
                undo = text.trim() ? { practice: true, retry: retrying, t } : null;
                rejected();
            }
            return true;
        }
        if (phase === "ask") {
            const repeat = again.some(a => a.item.key === item.key);
            const secs = ((firstKeyAt || Date.now()) - shownAt) / 1000;
            const before = Vocab.sched[item.key] ? Object.assign({}, Vocab.sched[item.key]) : null;
            const t = Date.now();
            const snap = Object.assign(Vocab.snapshot(item), { again, missed, repeat, secs, t });
            const g = r.ok ? Vocab.speedGrade(secs, repeat) : 1;
            confused = r.ok ? null : Vocab.mixup(item, text);
            Vocab.grade(item, g);
            Vocab.log(record(text, r, { t, grade: g, before, after: Vocab.sched[item.key] }));
            requeue(r.ok);
            if (r.ok) {
                right(`${r.note ? `${r.note} · ` : ""}${comesBack()}`);
            } else {
                phase = "wrong";
                note = "";
                undo = !gate && text.trim() ? snap : null;
                rejected();
            }
            return true;
        }
        // Typing out the answer shown.
        if (r.ok)
            start();
        else
            rejected();
        return true;
    }

    // When the word shown comes back, after a right answer: minutes while it's still being
    // learnt after misses today, else days.
    function comesBack(): string {
        const e = Vocab.sched[item.key];
        if (!e)
            return "";
        if (e.learning) {
            const left = Math.min(e.missesToday ?? 1, Config.vocab.steps.length + 1) - (e.stepRight ?? 0);
            return `Not learnt yet: right ${left} more time${left === 1 ? "" : "s"} · next in ${Math.max(1, Math.round((e.due - Date.now()) / 60000))} min`;
        }
        const days = Vocab.daysBetween(Date.now(), e.due);
        return `Again ${days <= 1 ? "tomorrow" : `in ${days} days`}`;
    }

    // After practising the word just missed: when it's asked for real.
    function countsWhen(): string {
        const due = Vocab.sched[item.key]?.due ?? 0;
        return `Practice only: it counts when asked again in ${Math.max(1, Math.round((due - Date.now()) / 60000))} min`;
    }

    // Shows a right answer, then moves on. In the final round, says how many are left.
    function right(said: string): void {
        phase = "right";
        const left = round?.length ? `· ${round.length} left` : "done";
        note = !practice ? said : said ? `${said} · final round ${left}` : `Final round ${left}`;
        advance.restart();
    }

    // The answer judged wrong was right: takes the miss back and grades it as a right one.
    function overrule(): void {
        if (!canOverrule)
            return;
        const snap = undo;
        undo = null;
        confused = null;
        Vocab.log({ t: Date.now(), day: Vocab.today(), where, key: item.key, overrules: snap.t });
        if (snap.retry) {
            again = again.filter(a => a.item.key !== item.key);
            right(`Counted as right · ${countsWhen()}`);
            return;
        }
        if (snap.practice) {
            round = round.filter(i => i.key !== item.key);
            right("Counted as right");
            return;
        }
        Vocab.restore(snap);
        again = snap.again;
        missed = snap.missed;
        Vocab.grade(item, Vocab.speedGrade(snap.secs, snap.repeat));
        requeue(true);
        right(`Counted as right · ${comesBack()}`);
    }

    // Keeps a right answer on screen until Enter (proceed()), e.g. to read a mnemonic.
    function pause(): void {
        if (phase !== "right" || gate)
            return;
        advance.stop();
        paused = true;
    }

    function proceed(): void {
        advance.stop();
        paused = false;
        if (gate)
            passed();
        else
            start();
    }

    // The countdown before the word just missed comes back.
    property Timer retryTimer: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            root.clock = Date.now();
            if (root.clock >= root.waitUntil)
                root.start();
        }
    }

    // Leaves "right" on screen for a moment.
    property Timer advance: Timer {
        interval: 2000
        onTriggered: root.proceed()
    }
}
