pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// The session lock. Locked over IPC, e.g. from a key or hypridle's lock_cmd:
//   qs ipc call session lock
// lockNow skips the pane coming down over the screen first, for before_sleep_cmd.
// Only the user's password unlocks it, checked through PAM (the "login" service unless
// settings.json says otherwise, see Settings.lockPam); there is deliberately no IPC unlock.
Singleton {
    id: root

    property bool locked
    // The lock pane coming down over the screen, just before locking (see Frame).
    property bool closing
    readonly property int closeDuration: 300
    // idle, checking or failed
    property string state: "idle"
    property string message
    // The password, from typing it until PAM asks for it.
    property string pending

    // Brings the lock pane down over the screen, then locks. now locks at once, e.g. before sleep,
    // when there may be no time for the animation.
    function lock(now: bool): void {
        if (locked)
            return;
        state = "idle";
        message = "";
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

    function unlock(password: string): void {
        if (!locked || pam.active || password === "")
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
            if (result === PamResult.Success) {
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
        function isLocked(): bool {
            return root.locked;
        }
    }
}
