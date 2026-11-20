pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// The session lock. Locked over IPC, e.g. from a key or hypridle's lock_cmd:
//   qs ipc call session lock
// Only the user's password unlocks it, checked through PAM (the "login" service unless
// settings.json says otherwise, see Settings.lockPam); there is deliberately no IPC unlock.
Singleton {
    id: root

    property bool locked
    // idle, checking or failed
    property string state: "idle"
    property string message
    // The password, from typing it until PAM asks for it.
    property string pending

    function lock(): void {
        if (locked)
            return;
        state = "idle";
        message = "";
        locked = true;
        Weather.refreshIfStale();
        WebUntis.refreshIfStale();
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
            root.lock();
        }
        function isLocked(): bool {
            return root.locked;
        }
    }
}
