import QtQuick
import Quickshell.Io

// A setting read from a file at runtime, such as a sops-nix or agenix secret: the file's
// first line, trimmed. No path, no value. failure says why it couldn't be read.
FileView {
    id: root

    // What it's for, in failure messages: "the WebUntis URL".
    property string what
    property string value
    property string failure

    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onPathChanged: if (!path) {
        value = "";
        failure = "";
    }

    onLoaded: {
        value = text().split("\n")[0].trim();
        failure = "";
    }

    onLoadFailed: error => {
        value = "";
        const why = error === FileViewError.PermissionDenied ? "Permission denied" : error === FileViewError.FileNotFound ? "No such file" : FileViewError.toString(error);
        failure = `Can't read ${what || "a setting"}: ${path}: ${why}`;
    }
}
