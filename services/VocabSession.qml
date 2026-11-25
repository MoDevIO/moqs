import QtQuick

// One vocabulary quiz in progress, shown by VocabQuiz: the launcher's ";" pane has one and
// the lock screen one, shared by all its screens. A word is asked ("ask"); a right answer
// ("right") moves on to the next one, or for the lock (gate) passes; a wrong one, or Enter
// with nothing typed, shows the answer, which has to be typed out ("wrong") before another
// word comes. How long recalling took (until the first key, see typed()) makes a right
// answer Good or Hard (Vocab.speedGrade).
//
// In the pane (not the lock, which asks a new word until one is right), a word answered wrong
// comes back in this session: first after the words left to do, and the more often it was
// wrong, the sooner. Once nothing else is left, these are asked until each is right.
QtObject {
    id: root

    // For the lock: always a word, and passed() on the first right answer.
    property bool gate
    // The word asked (see Vocab.items), or null when nothing is due.
    property var item: null
    // ask, right or wrong
    property string phase: "ask"
    // Said under the answer, e.g. about accents.
    property string note
    // When the word was shown, and when its first key was typed.
    property real shownAt
    property real firstKeyAt
    // Words to ask again: [{ item, fails, wait }], wait counting down the words asked until
    // it's due again.
    property var again: []

    signal passed
    // A wrong answer or retype, for the field to shake.
    signal rejected

    // Moves on to the next word.
    function start(): void {
        const prev = item?.key ?? "";
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
        const next = ready?.item ?? Vocab.pick(gate, prev, queue.map(a => a.item.key)) ?? others.sort((x, y) => x.wait - y.wait)[0]?.item ?? queue[0]?.item ?? null;
        phase = "ask";
        note = "";
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
        // The words left to do today, besides those already coming back.
        const left = Math.max(2, Vocab.dueCount + Vocab.newLeft - again.length);
        const fails = (queued?.fails ?? 0) + 1;
        again = [...again.filter(a => a !== queued), { item, fails, wait: Math.max(2, Math.ceil(left / fails)) }];
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
        item = null;
        again = [];
    }

    // What was typed for the word. Returns whether the field should clear.
    function submit(text: string): bool {
        if (!item) {
            start();
            return false;
        }
        if (phase === "right")
            return false;
        // Nothing typed: show the answer to type out.
        const r = Vocab.check(item, text);
        if (phase === "ask") {
            const days = Vocab.grade(item, r.ok ? Vocab.speedGrade(((firstKeyAt || Date.now()) - shownAt) / 1000) : 1);
            requeue(r.ok);
            if (r.ok) {
                phase = "right";
                const next = days === 1 ? "tomorrow" : `in ${days} days`;
                note = r.note ? `${r.note} · again ${next}` : `Again ${next}`;
                advance.restart();
            } else {
                phase = "wrong";
                note = "";
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

    // Leaves "right" on screen for a moment.
    property Timer advance: Timer {
        interval: 2000
        onTriggered: {
            if (root.gate)
                root.passed();
            else
                root.start();
        }
    }
}
