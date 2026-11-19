pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Behaviour settings from settings.json next to shell.qml:
//   { "dragToOpen": { "notifications": false, "music": true, "matrix": true } }
// dragToOpen: the corner's panel is pulled out of the border, like the dashboard, instead
// of opening when the pointer reaches the corner.
Singleton {
    readonly property alias dragToOpen: settings.dragToOpen

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
        }
    }
}
