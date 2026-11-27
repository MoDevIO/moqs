pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Behaviour settings from settings.json next to shell.qml:
//   { "dragToOpen": { "notifications": false, "music": true, "matrix": true },
//     "launcher": { "search": "https://duckduckgo.com/?q=%s" }, "lock": { "pam": "login" },
//     "updates": { "flake": "/home/me/nixos-config", "host": "laptop" },
//     "capture": { "ocr": ["eng", "deu"] }, "vocab": { "server": "http://worker-03" } }
// dragToOpen: the corner's panel is pulled out of the border, like the dashboard, instead
// of opening when the pointer reaches the corner.
// launcher.search: the launcher's web search ("?…"), %s standing for the query. Without
// it, Config.launcher.search.
// lock.pam: the PAM service (a file in /etc/pam.d) the lock screen checks passwords with.
// updates: the system flake the control centre's Updates tile updates and rebuilds, and its
// nixosConfigurations name (this machine's hostname without one); see Updates.
// capture.ocr: the languages Capture's "Copy text" reads, tesseract's codes; English and
// German without it.
// vocab.server: a moqs-vocab server whose words, schedule and sessions the vocabulary
// trainer uses instead of the files in ~/.local/state/moqs (see Vocab). Empty: those files.
Singleton {
    readonly property alias dragToOpen: settings.dragToOpen
    readonly property string search: settings.launcher.search.includes("%s") ? settings.launcher.search : Config.launcher.search
    readonly property string lockPam: settings.lock.pam || "login"
    readonly property string updatesFlake: settings.updates.flake
    readonly property string updatesHost: settings.updates.host
    readonly property string ocrLanguages: Array.from(settings.capture.ocr ?? []).join("+") || "eng+deu"
    readonly property string vocabServer: settings.vocab.server.trim().replace(/\/+$/, "")

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

            property JsonObject capture: JsonObject {
                property var ocr: []
            }

            property JsonObject vocab: JsonObject {
                property string server
            }
        }
    }
}
