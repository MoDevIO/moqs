pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Behaviour settings from settings.json next to shell.qml:
//   { "dragToOpen": { "notifications": false, "music": true, "matrix": true },
//     "launcher": { "search": "https://duckduckgo.com/?q=%s" }, "lock": { "pam": "login" },
//     "updates": { "flake": "/home/me/nixos-config", "host": "laptop" } }
// dragToOpen: the corner's panel is pulled out of the border, like the dashboard, instead
// of opening when the pointer reaches the corner.
// launcher.search: the launcher's web search ("?…"), %s standing for the query. Without
// it, Config.launcher.search.
// lock.pam: the PAM service (a file in /etc/pam.d) the lock screen checks passwords with.
// updates: the system flake the control centre's Updates tile updates and rebuilds, and its
// nixosConfigurations name (this machine's hostname without one); see Updates.
Singleton {
    readonly property alias dragToOpen: settings.dragToOpen
    readonly property string search: settings.launcher.search.includes("%s") ? settings.launcher.search : Config.launcher.search
    readonly property string lockPam: settings.lock.pam || "login"
    readonly property string updatesFlake: settings.updates.flake
    readonly property string updatesHost: settings.updates.host

    FileView {
        path: Quickshell.shellPath("settings.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property JsonObject dragToOpen: JsonObject {
                property bool notifications
                property bool music
                property bool matrix
            }

            property JsonObject launcher: JsonObject {
                property string search
            }

            property JsonObject lock: JsonObject {
                property string pam
            }

            property JsonObject updates: JsonObject {
                property string flake
                property string host
            }
        }
    }
}
