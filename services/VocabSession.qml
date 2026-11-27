import QtQuick
import qs.config

// One vocabulary quiz in progress, shown by VocabQuiz: the launcher's ";" pane has one, the
// lock screen one (shared by all its screens) and the game gate one. It goes as in Anki with
// the answer typed: a word is asked ("ask"); a wrong answer, or Enter with nothing typed,
// counts as Again and shows the answer, which has to be typed out ("wrong") before the next
// word; after a right one the learner rates it ("rate"): Hard, Good or Easy, each with the
// interval it gives (see choices()). Then comes the next word, or for the lock and games
// (gate) the way through. Words missed come back by Anki's learning steps (Vocab.pick()).
// A wrong answer that is another word's answer is a mix-up (`confused`), which the card
// points out.
//
// In the pane, an answer judged wrong can be counted as right after all (overrule(), "I got
// it right"), say a synonym the list doesn't have: the Again is taken back and it's rated.
// The last answer can be undone too (undoLast(), Ctrl+Z as in Anki): the word is asked again.
//
// Every answer goes to Vocab.log().
QtObject {
    id: root

    // For the lock and games: always a word, and passed() after the first one rated.
    property bool gate
    // Where it's asked, for the log: pane, lock or game.
    property string where: "pane"
    // The word asked (see Vocab.items), or null when nothing is due.
    property var item: null
    // ask, rate or wrong
    property string phase: "ask"
    // Said under the answer, e.g. about accents.
    property string note
    // The card whose answer was typed by mistake, or null.
    property var confused: null
    // When the word was shown, and when its first key was typed.
    property real shownAt
    property real firstKeyAt
    // The right answer to rate: what was typed and how it was checked, for the log.
    property var answered: null
    // After an answer judged wrong (something typed, not for the lock or a game): what it
    // changed, for overrule(). Else null.
    property var undo: null
    readonly property bool canOverrule: !gate && phase === "wrong" && undo !== null
    // What was typed for a wrong answer, shown against the right one.
    property string typedWrong
    // The last answer graded, for undoLast(): { snap, item, t, right }. Else null.
    property var last: null
    readonly property bool canUndo: !gate && last !== null
    // Answers in this session, and right ones.
    property int answers
    property int rights

    signal passed
    // A wrong answer or retype, for the field to shake.
    signal rejected

    // Moves on to the next word.
    function start(): void {
        const prev = item?.key ?? "";
        phase = "ask";
        note = "";
        confused = null;
        answered = null;
        undo = null;
        typedWrong = "";
        item = Vocab.pick(gate, prev, []);
        shownAt = Date.now();
        firstKeyAt = 0;
    }

    // Something was typed in the field.
    function typed(): void {
        if (!firstKeyAt && phase === "ask")
            firstKeyAt = Date.now();
    }

    function stop(): void {
        last = null;
        answers = 0;
        rights = 0;
        typedWrong = "";
        phase = "ask";
        note = "";
        confused = null;
        answered = null;
        undo = null;
        item = null;
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
        // Enter while rating: Good, as in Anki.
        if (phase === "rate") {
            rate(3);
            return true;
        }
        const r = Vocab.check(item, text);
        if (phase === "ask") {
            if (r.ok) {
                answered = { text, r, took: Date.now() - shownAt };
                phase = "rate";
                note = r.note;
                return true;
            }
            // Wrong, or nothing typed: Again.
            const t = Date.now();
            const snap = Object.assign(Vocab.snapshot(item), { t, text, r });
            const before = Vocab.sched[item.key] ? Object.assign({}, Vocab.sched[item.key]) : null;
            confused = Vocab.mixup(item, text);
            last = { snap: Vocab.snapshot(item), item, t, right: false };
            answers++;
            typedWrong = text.trim();
            Vocab.grade(item, 1);
            Vocab.log(record(text, r, { t, grade: 1, before, after: Vocab.sched[item.key] }));
            phase = "wrong";
            note = "";
            undo = !gate && text.trim() ? snap : null;
            rejected();
            return true;
        }
        // Typing out the answer shown.
        if (r.ok)
            start();
        else
            rejected();
        return true;
    }

    // The intervals Hard, Good and Easy would give the word shown: [{ grade, label, when }].
    function choices(): var {
        if (!item || phase !== "rate")
            return [];
        return [[2, "Hard"], [3, "Good"], [4, "Easy"]].map(([grade, label]) => ({
                    grade,
                    label,
                    when: Vocab.span(Vocab.next(item, grade))
                }));
    }

    // Rates the right answer: 2 Hard, 3 Good or 4 Easy.
    function rate(g: int): void {
        if (phase !== "rate" || !answered)
            return;
        const before = Vocab.sched[item.key] ? Object.assign({}, Vocab.sched[item.key]) : null;
        const t = Date.now();
        last = { snap: Vocab.snapshot(item), item, t, right: true };
        answers++;
        rights++;
        Vocab.grade(item, g);
        Vocab.log(Object.assign(record(answered.text, answered.r, { t, grade: g, before, after: Vocab.sched[item.key] }), { took: Math.round(answered.took) }));
        answered = null;
        if (gate)
            passed();
        else
            start();
    }

    // Takes the last answer back and asks its word again, as Anki's undo.
    function undoLast(): void {
        if (!canUndo)
            return;
        const l = last;
        last = null;
        Vocab.restore(l.snap);
        Vocab.log({ t: Date.now(), day: Vocab.today(), where, key: l.item.key, undoes: l.t });
        answers = Math.max(0, answers - 1);
        if (l.right)
            rights = Math.max(0, rights - 1);
        phase = "ask";
        note = "";
        confused = null;
        answered = null;
        undo = null;
        typedWrong = "";
        item = l.item;
        shownAt = Date.now();
        firstKeyAt = 0;
    }

    // The answer judged wrong was right: takes the Again back, to be rated instead.
    function overrule(): void {
        if (!canOverrule)
            return;
        const snap = undo;
        undo = null;
        confused = null;
        Vocab.log({ t: Date.now(), day: Vocab.today(), where, key: item.key, overrules: snap.t });
        Vocab.restore(snap);
        answers--;
        last = null;
        typedWrong = "";
        answered = { text: snap.text, r: { ok: true, note: "Counted as right" }, took: snap.t - shownAt };
        phase = "rate";
        note = "Counted as right";
    }
}
