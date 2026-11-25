pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.config

// The session lock. Locked over IPC, e.g. from a key or hypridle's lock_cmd:
//   qs ipc call session lock
// lockNow skips the pane coming down over the screen first, for before_sleep_cmd.
// qs ipc call session menu opens the session menu (lock, suspend, log out, restart, power off).
// Only the user's password unlocks it, checked through PAM (the "login" service unless
// settings.json says otherwise, see Settings.lockPam); there is deliberately no IPC unlock.
// With Vocab.lockGate on (and words to ask), a right password is followed by a word to
// translate ("vocab"): a wrong answer shows the right one to type out, then another word,
// until one is right. After Config.vocab.emergency seconds an emergency button unlocks.
Singleton {
    id: root

    property bool locked
    // The lock pane coming down over the screen, just before locking (see Frame).
    property bool closing
    readonly property int closeDuration: 300
    // idle, checking, failed or vocab
    property string state: "idle"
    property string message
    // The password, from typing it until PAM asks for it.
    property string pending
    // The word asked after the password, the same on every screen.
    readonly property VocabSession gate: VocabSession {
        gate: true
        onPassed: root.finishVocab()
    }
    // When the word step began, and whether its emergency button works yet.
    property real vocabSince
    property bool emergencyReady

    // Brings the lock pane down over the screen, then locks. now locks at once, e.g. before sleep,
    // when there may be no time for the animation.
    function lock(now: bool): void {
        if (locked)
            return;
        state = "idle";
        message = "";
        emergencyTimer.stop();
        emergencyReady = false;
        gate.stop();
        Weather.refreshIfStale();
        WebUntis.refreshIfStale();
        if (now) {
            closeTimer.stop();
            locked = true;
            closing = false;
        } else if (!closing) {
            closing = true;
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer

        interval: root.closeDuration
        onTriggered: {
            root.locked = true;
            root.closing = false;
        }
    }

    // The session menu, which grows out of the bar on the focused monitor and stays there.
    property bool menuOpen
    property string menuScreen

    function toggleMenu(): void {
        if (menuOpen) {
            menuOpen = false;
            return;
        }
        menuScreen = Hyprland.focusedMonitor?.name ?? "";
        Launcher.open = false;
        menuOpen = true;
    }

    // Visible on this screen's frame.
    function menuOn(s: ShellScreen): bool {
        return menuOpen && (menuScreen === "" || s.name === menuScreen);
    }

    // What the session menu's buttons do.
    function run(action: string): void {
        menuOpen = false;
        if (action === "lock")
            lock(false);
        else if (action === "suspend")
            // hypridle's before_sleep_cmd locks first, if set up.
            Quickshell.execDetached(["systemctl", "suspend"]);
        else if (action === "logout")
            // Hyprland's Lua config takes hl.dsp.exit(), the older one plain exit.
            Quickshell.execDetached(["sh", "-c", "case $(hyprctl dispatch 'hl.dsp.exit()') in ok*) ;; *) hyprctl dispatch exit ;; esac"]);
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    function unlock(password: string): void {
        if (!locked || pam.active || password === "" || state === "vocab")
            return;
        pending = password;
        state = "checking";
        message = "";
        if (!pam.start()) {
            pending = "";
            state = "failed";
            message = "Couldn't check the password";
        }
    }

    // After the right password: a word to translate before unlocking.
    function startVocab(): void {
        state = "vocab";
        message = "";
        vocabSince = Date.now();
        emergencyReady = false;
        emergencyTimer.restart();
        gate.start();
    }

    function finishVocab(): void {
        if (state !== "vocab")
            return;
        emergencyTimer.stop();
        emergencyReady = false;
        gate.stop();
        state = "idle";
        locked = false;
    }

    function emergencyUnlock(): void {
        if (emergencyReady)
            finishVocab();
    }

    Timer {
        id: emergencyTimer

        interval: Config.vocab.emergency * 1000
        onTriggered: root.emergencyReady = true
    }

    // The words file emptied while one is asked: nothing left to ask.
    Connections {
        target: Vocab

        function onCardsChanged(): void {
            if (root.state === "vocab" && Vocab.cards.length === 0)
                root.finishVocab();
        }
    }

    PamContext {
        id: pam

        config: Settings.lockPam

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            // A second question (e.g. a one-time code) can't be answered here and fails.
            respond(root.pending);
            root.pending = "";
        }

        onCompleted: result => {
            root.pending = "";
            if (result === PamResult.Success && Vocab.lockGate && Vocab.cards.length > 0) {
                root.startVocab();
            } else if (result === PamResult.Success) {
                root.state = "idle";
                root.locked = false;
            } else {
                root.state = "failed";
                root.message = result === PamResult.MaxTries ? "Too many tries" : "Wrong password";
            }
        }

        onError: () => {
            root.pending = "";
            root.state = "failed";
            root.message = "Couldn't check the password";
        }
    }

    IpcHandler {
        target: "session"

        function lock(): void {
            root.lock(false);
        }
        // For before_sleep_cmd and the like: no animation, locked when this returns.
        function lockNow(): void {
            root.lock(true);
        }
        function menu(): void {
            root.toggleMenu();
        }
        function isLocked(): bool {
            return root.locked;
        }
    }
}
