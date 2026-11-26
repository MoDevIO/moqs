import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

// A vocabulary card for a VocabSession: the word, a field for the translation, and after a
// wrong answer the right one, to be typed out. In the launcher (manage) it also takes
// "+word = translation" to add a word, Ctrl+Delete to remove the one shown, and shows what's
// due and the settings (a click switches them), and the stats in place of the card.
ColumnLayout {
    id: root

    required property VocabSession session
    property bool manage
    readonly property var item: session.item
    readonly property string phase: session.phase
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

    function focusInput(): void {
        input.forceActiveFocus();
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

            Text {
                visible: root.manage
                text: `${Vocab.dueCount} due · ${Vocab.newLeft} new · ${Vocab.cards.length} words`
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
            text: root.item ? root.item.prompt : Vocab.cards.length ? "All caught up" : "No words yet"
            color: root.item ? Config.colours.text : Config.colours.subtext
            font.family: Config.font.sans
            font.pointSize: root.item ? 22 : Config.font.size + 2
            font.bold: root.item !== null
        }

        Text {
            Layout.fillWidth: true
            visible: !root.item
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Vocab.cards.length ? (Vocab.nextDue ? `The next word is due ${root.when(Vocab.nextDue)}` : "") : `Type +word = translation below, or add lines like that to ${Vocab.wordsPath.replace(Quickshell.env("HOME"), "~")}`
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
            text: !root.item || root.phase === "ask" ? " " : root.phase === "right" ? `\u{F012C} ${root.item.answer}` : root.item.answer
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

        // Under a right answer: anything about how it was typed, and when it's asked again.
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -6
            visible: root.phase === "right"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.session.note
            color: Config.colours.subtext
            font.family: Config.font.family
            font.pointSize: Config.font.small
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
                readOnly: root.phase === "right"
                color: Config.colours.text
                selectionColor: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.size
                clip: true
                focus: true

                onTextChanged: if (text) root.session.typed()
                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                Keys.onEscapePressed: root.escaped()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && input.text === "") {
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
                    text: root.phase === "wrong" ? "Type it out to go on" : root.item ? "Translation · Enter alone shows it" : root.manage ? "+word = translation" : ""
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
        spacing: 16

        Text {
            Layout.fillWidth: true
            text: root.added
            elide: Text.ElideRight
            color: Config.colours.muted
            font.family: Config.font.family
            font.pointSize: Config.font.small
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
