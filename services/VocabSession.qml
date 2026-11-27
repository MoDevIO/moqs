import QtQuick
import qs.config

// One vocabulary quiz in progress, shown by VocabQuiz: the launcher's ";" pane has one, the
// lock screen one (shared by all its screens) and the game gate one. It runs on the server
// (Vocab.server, a session there) and this follows what the server says of it (its "view").
// It goes as in Anki with the answer typed: a word is asked ("ask"); a wrong answer, or
// Enter with nothing typed, counts as Again and shows the answer, which has to be typed out
// ("wrong") before the next word; after a right one the learner rates it ("rate"): Hard,
// Good or Easy, each with the interval it gives (choices()). Then comes the next word, or
// for the lock and games (gate) the way through. A wrong answer that is another word's
// answer is a mix-up (`confused`), which the card points out.
//
// In the pane, an answer judged wrong can be counted as right after all (overrule(), "I got
// it right"), say a synonym the list doesn't have: the Again is taken back and it's rated.
// The last answer can be undone too (undoLast(), Ctrl+Z as in Anki): the word is asked again.
//
// If the server can't be reached, the lock and games let through rather than shut out, and
// the pane says why (Vocab.serverError).
QtObject {
    id: root

    // For the lock and games: always a word, and passed() after the first one rated.
    property bool gate
    // Where it's asked, for the server's log: pane, lock or game.
    property string where: "pane"
    // The word asked, { key, prompt, answer, dir, card, hard, lapses }, or null when nothing
    // is due.
    property var item: null
    // ask, rate or wrong
    property string phase: "ask"
    // Said under the answer, e.g. about accents.
    property string note
    // The card whose answer was typed by mistake, { front, back }, or null.
    property var confused: null
    // When the word was shown, and when its first key was typed.
    property real shownAt
    property real firstKeyAt
    // What was typed for a wrong answer, and it against the right one: [{ c, k: ok, wrong,
    // extra or missing }], or null.
    property string typedWrong
    property var compare: null
    readonly property bool canOverrule: !!view?.canOverrule && phase === "wrong"
    readonly property bool canUndo: !!view?.canUndo
    // Answers in this session, and right ones.
    property int answers
    property int rights
    // The session's id on the server (and which server), what it last said, and whether a
    // call is out.
    property string sid
    property string sidServer
    property var view: null
    property bool busy

    signal passed
    // A wrong answer or retype, for the field to shake.
    signal rejected

    // Calls the session's `path` (after creating it on the server if need be) and takes the
    // view it returns; then(reply) after. A session the server lost (it restarted) is made
    // anew, with a new word.
    function call(method: string, path: string, body: var, then: var): void {
        const server = Vocab.server;
        const fail = () => {
            busy = false;
            if (gate)
                passed();
        };
        const send = () => Vocab.api(method, `/api/sessions/${sid}${path}`, body, (status, r) => {
            if (Vocab.server !== server)
                return;
            busy = false;
            if (status === 404) {
                sid = "";
                start();
            } else if (status === 200 && r) {
                take(r);
                if (then)
                    then(r);
            } else if (status === 409) {
                // Out of step with the server (an answer elsewhere went first): ask again.
                start();
            } else if (status === 0 || status >= 500) {
                fail();
            }
        });
        busy = true;
        if (sidServer !== server)
            sid = "";
        if (sid) {
            send();
            return;
        }
        Vocab.api("POST", "/api/sessions", { where, gate }, (status, r) => {
            if (Vocab.server !== server)
                return;
            if (status === 201 && r?.id) {
                sid = r.id;
                sidServer = server;
                send();
            } else {
                fail();
            }
        });
    }

    // What the server says the session is.
    function take(v: var): void {
        const was = item;
        view = v;
        const it = v.item;
        if (!it)
            item = null;
        else if (!was || was.key !== it.key || JSON.stringify(was.card) !== JSON.stringify(it.card) || was.hard !== it.hard)
            item = it;
        if (!was || !it || was.key !== it.key || v.phase === "ask" && phase !== "ask") {
            shownAt = Date.now();
            firstKeyAt = 0;
        }
        note = v.note ?? "";
        confused = v.mixup ? { front: v.mixup.front, back: v.mixup.back } : null;
        typedWrong = v.typed ?? "";
        compare = v.compare ?? null;
        answers = v.answers ?? 0;
        rights = v.rights ?? 0;
        if (v.phase === "passed") {
            passed();
            return;
        }
        phase = v.phase;
    }

    // Moves on to the next word (or, while one is shown unanswered, stays with it).
    function start(): void {
        if (busy)
            return;
        if (!Vocab.server) {
            if (gate)
                passed();
            return;
        }
        phase = "ask";
        call("GET", `/next?gate=${gate ? 1 : 0}`, null, null);
    }

    // Something was typed in the field.
    function typed(): void {
        if (!firstKeyAt && phase === "ask")
            firstKeyAt = Date.now();
    }

    function stop(): void {
        if (sid)
            Vocab.api("DELETE", `/api/sessions/${sid}`, null, null);
        sid = "";
        view = null;
        busy = false;
        answers = 0;
        rights = 0;
        typedWrong = "";
        compare = null;
        phase = "ask";
        note = "";
        confused = null;
        item = null;
    }

    // What was typed for the word. Returns whether the field should clear.
    function submit(text: string): bool {
        if (!item) {
            start();
            return false;
        }
        if (busy)
            return false;
        // Enter while rating: Good, as in Anki.
        if (phase === "rate") {
            rate(3);
            return true;
        }
        const now = Date.now();
        Vocab.lastAnswer = now;
        call("POST", "/answer", { key: item.key, typed: text, firstKeyMs: firstKeyAt ? firstKeyAt - shownAt : undefined, tookMs: now - shownAt }, r => {
            if (!r.ok)
                rejected();
        });
        return true;
    }

    // The intervals Hard, Good and Easy would give the word shown: [{ grade, label, when }].
    function choices(): var {
        if (!item || phase !== "rate")
            return [];
        return view?.choices ?? [];
    }

    // Rates the right answer: 2 Hard, 3 Good or 4 Easy.
    function rate(g: int): void {
        if (phase === "rate" && item && !busy)
            call("POST", "/rate", { key: item.key, grade: g }, null);
    }

    // Takes the last answer back and asks its word again, as Anki's undo.
    function undoLast(): void {
        if (canUndo && !busy)
            call("POST", "/undo", null, null);
    }

    // The answer judged wrong was right: takes the Again back, to be rated instead.
    function overrule(): void {
        if (canOverrule && !busy)
            call("POST", "/overrule", null, null);
    }
}
