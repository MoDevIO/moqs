import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// The session lock: while Lock.locked, every screen shows LockContent and nothing else gets
// input. Unlocking goes through Lock.unlock, which checks the password.
Scope {
    WlSessionLock {
        locked: Lock.locked

        WlSessionLockSurface {
            color: Config.border.colour

            LockContent {
                anchors.fill: parent
            }
        }
    }
}
