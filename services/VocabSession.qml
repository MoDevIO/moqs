import QtQuick

// One vocabulary quiz in progress, shown by VocabQuiz: the launcher's ";" pane has one and
// the lock screen one, shared by all its screens. A word is asked ("ask"); a right answer
// ("right") moves on to the next one, or for the lock (gate) passes; a wrong one, or Enter
// with nothing typed, shows the answer, which has to be typed out ("wrong") before another
// word comes. How long recalling took (until the first key, see typed()) makes a right
// answer Good or Hard (Vocab.speedGrade).
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

    signal passed
    // A wrong answer or retype, for the field to shake.
    signal rejected

    function start(): void {
        phase = "ask";
        note = "";
        item = Vocab.pick(gate, item?.key ?? "");
        shownAt = Date.now();
        firstKeyAt = 0;
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
            if (r.ok) {
                phase = "right";
                const next = days === 1 ? "tomorrow" : `in ${days} days`;
                note = r.note ? `${r.note} · again ${next}` : `Right · again ${next}`;
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
        interval: 1400
        onTriggered: {
            if (root.gate)
                root.passed();
            else
                root.start();
        }
    }
}
