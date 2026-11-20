pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Behaviour settings from settings.json next to shell.qml:
//   { "dragToOpen": { "notifications": false, "music": true, "matrix": true },
//     "launcher": { "search": "https://duckduckgo.com/?q=%s" } }
// dragToOpen: the corner's panel is pulled out of the border, like the dashboard, instead
// of opening when the pointer reaches the corner.
// launcher.search: the launcher's web search ("?…"), %s standing for the query. Without
// it, Config.launcher.search.
Singleton {
    readonly property alias dragToOpen: settings.dragToOpen
    readonly property string search: settings.launcher.search.includes("%s") ? settings.launcher.search : Config.launcher.search

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
        }
    }
}
