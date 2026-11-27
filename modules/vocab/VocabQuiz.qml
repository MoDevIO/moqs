import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

// A vocabulary card for a VocabSession: the word, a field for the translation, and after a
// wrong answer the right one, to be typed out, with the word it was mixed up with; after a
// right one, Hard, Good and Easy to rate it, as in Anki (1, 2 or 3; Enter is Good), each
// with when it would come back. Once answered, the word's note and mnemonic show. In the launcher (manage) it also takes
// "+word = translation" to add a word, "# mnemonic" to set the one shown's mnemonic, Ctrl+Delete
// to remove it, "I got it right" (or Ctrl+Enter) to count an answer judged wrong as right, and
// shows what's left (new, learning, review, coloured as in Anki), Ctrl+Z to undo the last
// answer, the settings (a click switches them), and the stats in place of the card. With Mnemonic set up, it suggests mnemonics once answered, on a click or Tab; a
// click or 1–4 keeps one (Alt+1–4 while rating, where the numbers rate).
ColumnLayout {
    id: root

    required property VocabSession session
    property bool manage
    readonly property var item: session.item
    readonly property string phase: session.phase
    // Forgotten again and again (a leech, as Anki calls it).
    readonly property bool hard: item?.hard ?? false
    // A mnemonic suggested for the word shown, or being thought of.
    readonly property bool mnemonicHere: item !== null && Mnemonic.key === item.key
    readonly property bool suggested: mnemonicHere && Mnemonic.suggestions.length > 0
    property string added
    // The stats show in place of the card.
    property bool showStats

    function toggleStats(): void {
        showStats = !showStats;
        if (showStats)
            statsView.forceActiveFocus();
        else
            Qt.callLater(focusInput);
    }

    // Escape, and Backspace in an empty field.
    signal escaped
    signal backedOut

    // "at 14:05" today, "Thu 09:30" later.
    function when(ms: real): string {
        const d = new Date(ms);
        return d.toDateString() === new Date().toDateString() ? `at ${Qt.formatTime(d, "hh:mm")}` : Qt.formatDateTime(d, "ddd hh:mm");
    }

    // What was typed against the nearest right answer, as the server compared them
    // (session.compare) and Anki shows it: right letters dim, wrong ones red, extra ones struck
    // out, missing ones orange. StyledText.
    function paint(letters: var): string {
        const esc = c => c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "&" ? "&amp;" : c;
        const font = (c, colour) => `<font color="${colour}">${esc(c)}</font>`;
        return (letters ?? []).map(l => l.k === "ok" ? font(l.c, Config.colours.subtext) : l.k === "wrong" ? font(l.c, Config.colours.red) : l.k === "extra" ? `<s>${font(l.c, Config.colours.red)}</s>` : `<u>${font(l.c, Config.colours.orange)}</u>`).join("");
    }

    function focusInput(): void {
        input.forceActiveFocus();
    }

    // Asks for a mnemonic for the word shown; a right answer waits for it.
    function suggestMnemonic(): void {
        if (!item || !Mnemonic.configured)
            return;
        Mnemonic.suggest(item, session.confused);
    }

    // Keeps the suggested mnemonic at `index` with the word.
    function keepMnemonic(index: int): void {
        const text = suggested ? Mnemonic.suggestions[index] : undefined;
        if (!text)
            return;
        const card = item.card;
        const updated = Vocab.setMnemonic(card, text);
        if (updated) {
            Mnemonic.kept(card, text, false);
            added = "Mnemonic kept";
            Mnemonic.clear();
            // The word again, with its mnemonic.
            session.item = Object.assign({}, session.item, { card: updated });
        }
    }

    // Suggestions are only asked for on request (the button or Tab), once answered.
    readonly property bool canSuggest: manage && item !== null && phase !== "ask" && Mnemonic.configured && !Mnemonic.loading
    onItemChanged: if (Mnemonic.key && Mnemonic.key !== item?.key)
        Mnemonic.clear()

    function enter(event: var): void {
        if (event.modifiers & Qt.ControlModifier && manage && session.canOverrule) {
            session.overrule();
            input.text = "";
        } else {
            submit();
        }
    }

    function submit(): void {
        const t = input.text;
        const add = t.match(/^\+\s*(.+?)\s*(?:=|\t)\s*(.+?)\s*$/);
        if (manage && t.startsWith("+")) {
            if (add && Vocab.add(add[1], add[2])) {
                added = `Added ${add[1]} = ${add[2]}`;
                input.text = "";
                if (!session.item)
                    session.start();
            } else {
                shake.restart();
            }
            return;
        }
        // A mnemonic of one's own for the word shown.
        if (manage && t.startsWith("#") && item) {
            const card = item.card;
            const updated = Vocab.setMnemonic(card, t.slice(1));
            if (updated) {
                Mnemonic.kept(card, t.slice(1).trim(), true);
                added = t.slice(1).trim() ? "Mnemonic saved" : "Mnemonic removed";
                Mnemonic.clear();
                input.text = "";
                // The word again, with its new note.
                session.item = Object.assign({}, session.item, { card: updated });
            } else {
                shake.restart();
            }
            return;
        }
        added = "";
        if (session.submit(t))
            input.text = "";
    }

    spacing: 10

    Connections {
        target: root.session

        function onRejected(): void {
            shake.restart();
        }
    }

    // A word that came due or was added while nothing was shown. Later, as picking a word
    // updates what's due, which would start this again.
    function resume(): void {
        if (root.visible && !root.session.item && Vocab.cards.length)
            root.session.start();
    }

    Connections {
        target: Vocab

        function onVersionChanged(): void {
            Qt.callLater(root.resume);
        }

        function onDueCountChanged(): void {
            if (Vocab.dueCount > 0)
                Qt.callLater(root.resume);
        }
    }

    // The card, or the stats in its place.
    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.showStats
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            visible: root.item !== null || root.manage

            Text {
                Layout.fillWidth: true
                text: !root.item ? "Vocabulary" : root.item.dir === ">" ? "Translate" : "Translate back"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            // Left now, as Anki shows it: new, learning, to review.
            Text {
                visible: root.manage
                textFormat: Text.StyledText
                text: [[Vocab.newLeft, Config.colours.blue, "new"], [Vocab.learningCount, Config.colours.red, "learning"], [Vocab.reviewCount, Config.colours.green, "review"]].map(([n, c, what]) => `<font color="${n ? c : Config.colours.muted}">${n}</font> ${what}`).join(" · ")
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }

        // The word, or what to do without one.
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 6
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.item ? root.item.prompt : Vocab.cards.length ? "All caught up" : !Vocab.server || Vocab.serverError ? "No words" : !Vocab.serverState ? "Loading…" : "No words yet"
            color: root.item ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.sans
            font.pointSize: root.item ? 22 : Config.font.size + 2
            font.bold: root.item !== null
        }

        // A leech, under its word.
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -8
            visible: root.hard
            horizontalAlignment: Text.AlignHCenter
            text: `hard word · forgotten ${root.item?.lapses ?? 0}×`
            color: Config.colours.red
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        Text {
            Layout.fillWidth: true
            visible: !root.item
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: !Vocab.server ? "No vocabulary server is set: services.moqs.vocab.server" : Vocab.serverError ? Vocab.serverError : !Vocab.serverState ? "" : Vocab.cards.length ? [Vocab.todayAnswers.n ? `Today: ${Vocab.todayAnswers.n} answered, ${Math.round(Vocab.todayAnswers.r / Vocab.todayAnswers.n * 100)} % right` : "", Vocab.nextDue ? `The next word is due ${root.when(Vocab.nextDue)}` : ""].filter(x => x).join("\n") : `Type +word = translation below, or add words on ${Vocab.server}`
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // Caught up with words still unseen: held for 3 s, another day's worth of new ones.
        HoldButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            visible: root.manage && !root.item && Vocab.freshCount > 0
            text: `Learn more · hold`
            onHeld: {
                Vocab.learnMore();
                root.session.start();
                root.focusInput();
            }
        }

        // The whole answer once answered: red after a wrong one, to type out, green with a tick
        // after a right one, so the other meanings show too.
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            opacity: root.item && root.phase !== "ask" ? 1 : 0
            text: !root.item || root.phase === "ask" ? " " : root.phase === "rate" ? `\u{F012C} ${root.item.answer}` : root.item.answer
            color: root.phase === "wrong" ? Config.colours.red : Config.colours.green
            font.family: Config.font.family
            font.pointSize: Config.font.size + 4
            font.bold: true

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        // A wrong answer that is another word's: which one.
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -6
            visible: root.phase === "wrong" && root.session.confused !== null
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: !root.session.confused ? "" : root.item?.dir === "<" ? `You typed ${root.session.confused.front}, which is ${root.session.confused.back}` : `Mixed up: that's ${root.session.confused.front} = ${root.session.confused.back}`
            color: Config.colours.yellow
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // What was typed, against the answer.
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -6
            visible: root.phase === "wrong" && root.session.compare !== null && root.session.confused === null
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: visible ? `<font color="${Config.colours.subtext}">You typed </font>${root.paint(root.session.compare)}` : ""
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // After an answer judged wrong, in the pane: it was right after all (a synonym, say).
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.manage && root.session.canOverrule
            implicitWidth: overruleText.implicitWidth + 24
            implicitHeight: 28
            radius: height / 2
            color: overruleArea.containsMouse ? Config.colours.buttonHover : Config.colours.button

            Text {
                id: overruleText

                anchors.centerIn: parent
                text: "\u{F012C} I got it right · Ctrl+Enter"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            MouseArea {
                id: overruleArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.session.overrule();
                    root.focusInput();
                }
            }
        }

        // Under a right answer: anything about how it was typed, then Hard, Good and Easy with
        // when each brings it back.
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -6
            visible: root.phase === "rate" && root.session.note !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.session.note
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.phase === "rate"
            spacing: 8

            Repeater {
                model: root.phase === "rate" ? root.session.choices() : []

                RateButton {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    key: index + 1
                    label: modelData.label
                    when: modelData.when
                    tint: modelData.grade === 2 ? Config.colours.orange : modelData.grade === 3 ? Config.colours.green : Config.colours.blue
                    chosen: modelData.grade === 3
                    onClicked: {
                        root.session.rate(modelData.grade);
                        root.focusInput();
                    }
                }
            }
        }

        // The word's note, e.g. its grammar, once answered.
        Text {
            Layout.fillWidth: true
            visible: root.item !== null && root.phase !== "ask" && (root.item?.card.hint ?? "") !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.item?.card.hint ?? ""
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
            font.italic: true
        }

        // The word's mnemonic, once answered.
        Text {
            Layout.fillWidth: true
            visible: root.item !== null && root.phase !== "ask" && (root.item?.card.mnemonic ?? "") !== "" && !root.suggested
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: `\u{F0335} ${root.item?.card.mnemonic ?? ""}`
            color: Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // Mnemonics being thought of, or why there are none, in the pane.
        Text {
            Layout.fillWidth: true
            visible: root.manage && root.mnemonicHere && root.phase !== "ask" && (Mnemonic.loading || (!root.suggested && Mnemonic.error !== ""))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Mnemonic.loading ? "Thinking of mnemonics…" : `No mnemonics: ${Mnemonic.error}`
            color: Config.colours.muted
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // The suggested mnemonics, numbered: a click or the number keeps one.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.manage && root.suggested && root.phase !== "ask"
            spacing: 4

            Repeater {
                model: root.suggested ? Mnemonic.suggestions : []

                Text {
                    id: suggestion

                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: `${suggestion.index + 1}  ${suggestion.modelData}`
                    color: pick.containsMouse ? Config.colours.text : Config.colours.yellow
                    font.family: Config.font.family
                    font.pointSize: Config.font.small

                    MouseArea {
                        id: pick

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.keepMnemonic(suggestion.index);
                            root.focusInput();
                        }
                    }
                }
            }
        }

        // A hard word without mnemonics set up: how to keep one of one's own.
        Text {
            Layout.fillWidth: true
            visible: root.manage && root.item !== null && root.phase !== "ask" && root.hard && !Mnemonic.configured && !(root.item?.card.mnemonic ?? "")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Hard to remember? Type # and a mnemonic (a sentence with a word that sounds like it)"
            color: Config.colours.muted
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // What can be done about a mnemonic, once answered, in the pane.
        RowLayout {
            Layout.maximumWidth: parent.width
            Layout.alignment: Qt.AlignHCenter
            visible: root.manage && root.item !== null && root.phase !== "ask"
            spacing: 16

            Text {
                visible: root.suggested
                text: `${root.phase === "rate" ? "Alt+" : ""}1–${Mnemonic.suggestions.length} keeps one`
                color: Config.colours.muted
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            VocabOption {
                visible: root.canSuggest
                text: `${root.suggested ? "Other ideas" : Mnemonic.ready(root.item?.card) ? "\u{F0335} Mnemonics ready" : root.item?.card.mnemonic ? "Suggest better mnemonics" : "\u{F0335} Suggest mnemonics"} · Tab`
                onClicked: {
                    root.suggestMnemonic();
                    root.focusInput();
                }
            }

        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: height / 2
            color: Config.colours.button
            border.width: root.phase === "wrong" ? 1.5 : 0
            border.color: Config.colours.red

            transform: Translate {
                id: offset
            }

            SequentialAnimation {
                id: shake

                loops: 2

                NumberAnimation {
                    target: offset
                    property: "x"
                    to: -8
                    duration: 50
                }
                NumberAnimation {
                    target: offset
                    property: "x"
                    to: 8
                    duration: 80
                }
                NumberAnimation {
                    target: offset
                    property: "x"
                    to: 0
                    duration: 50
                }
            }

            Text {
                id: icon

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F05CA}"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.icon
            }

            TextInput {
                id: input

                anchors.left: icon.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 10
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                color: Config.colours.text
                selectionColor: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.size
                clip: true
                focus: true

                // Typing a note isn't recalling the word.
                onTextChanged: if (text && !text.startsWith("#")) root.session.typed()
                // Ctrl+Enter after an answer judged wrong: it was right.
                Keys.onReturnPressed: event => root.enter(event)
                // Tab asks for mnemonics, or other ones.
                Keys.onTabPressed: event => {
                    if (root.canSuggest)
                        root.suggestMnemonic();
                    else
                        event.accepted = false;
                }
                Keys.onEnterPressed: event => root.enter(event)
                Keys.onEscapePressed: root.escaped()
                Keys.onPressed: event => {
                    // While rating, 1, 2 and 3 in the empty field are Hard, Good and Easy; else a
                    // number keeps that suggested mnemonic (Alt and a number always does).
                    const n = event.key - Qt.Key_1;
                    const alt = event.modifiers & Qt.AltModifier;
                    if (event.key === Qt.Key_Z && event.modifiers & Qt.ControlModifier && input.text === "" && root.session.canUndo) {
                        root.session.undoLast();
                        event.accepted = true;
                    } else if (root.phase === "rate" && !alt && input.text === "" && n >= 0 && n < 3) {
                        root.session.rate(n + 2);
                        event.accepted = true;
                    } else if (root.manage && root.suggested && (input.text === "" || alt) && n >= 0 && n < Mnemonic.suggestions.length) {
                        root.keepMnemonic(n);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace && input.text === "") {
                        root.backedOut();
                        event.accepted = true;
                    } else if (root.manage && event.key === Qt.Key_Delete && event.modifiers & Qt.ControlModifier && root.item) {
                        Vocab.remove(root.item.card);
                        root.added = `Removed ${root.item.card.front} = ${root.item.card.back}`;
                        root.session.start();
                        event.accepted = true;
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text
                    text: root.phase === "wrong" ? "Type it out to go on" : root.phase === "rate" ? "Enter is Good" : root.item ? "Translation · Enter alone shows it" : root.manage ? "+word = translation" : ""
                    color: Config.colours.muted
                    font: input.font
                }
            }
        }
    }

    VocabStats {
        id: statsView

        Layout.fillWidth: true
        Layout.topMargin: 4
        visible: root.showStats
        // Escape closes; any other key goes back to the card.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.escaped();
            else
                root.toggleStats();
            event.accepted = true;
        }
    }

    // What the field takes or what was added, and the settings.
    RowLayout {
        Layout.fillWidth: true
        visible: root.manage
        spacing: 14

        Text {
            Layout.fillWidth: true
            text: root.added
            elide: Text.ElideRight
            color: Config.colours.muted
            font.family: Config.font.family
            font.pointSize: Config.font.small
        }

        // Takes the last answer back, as Anki's undo.
        VocabOption {
            visible: root.session.canUndo
            text: "\u{F054C} Undo"
            on: true
            onClicked: {
                root.session.undoLast();
                root.focusInput();
            }
        }

        VocabOption {
            text: `\u{F049D} ${Vocab.random ? "Random" : "In order"}`
            on: Vocab.random
            onClicked: {
                Vocab.setRandom(!Vocab.random);
                root.focusInput();
            }
        }

        VocabOption {
            text: `\u{F04E1} ${Vocab.bothWays ? "Both ways" : "One way"}`
            on: Vocab.bothWays
            onClicked: {
                Vocab.setBothWays(!Vocab.bothWays);
                // The word shown may no longer be asked.
                if (!Vocab.bothWays && root.item?.dir === "<")
                    root.session.start();
                root.focusInput();
            }
        }

        VocabOption {
            text: `\u{F033E} Lock ${Vocab.lockGate ? "on" : "off"}`
            on: Vocab.lockGate
            onClicked: {
                Vocab.setLock(!Vocab.lockGate);
                root.focusInput();
            }
        }

        VocabOption {
            text: `\u{F0297} Games ${Vocab.games ? "on" : "off"}`
            on: Vocab.games
            onClicked: {
                Vocab.setGames(!Vocab.games);
                root.focusInput();
            }
        }

        VocabOption {
            text: `\u{F0128} Stats`
            on: root.showStats
            onClicked: root.toggleStats()
        }
    }
}
