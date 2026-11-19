pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Clipboard history through cliphist. The shell records the clipboard itself while it runs,
// so nothing else needs to be set up; a cliphist watcher started elsewhere does no harm, as
// cliphist drops duplicates. Password managers mark their copies as sensitive, and cliphist
// leaves those out.
Singleton {
    id: root

    // Newest first: [{ id, text, image: { kind, size, width, height } or null }]
    property var entries: []
    property bool available: true
    // Image entries' decoded files, by entry ID.
    property var thumbs: ({})
    // The list is only read while someone looks at it.
    property bool active

    readonly property string thumbDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/moqs/clipboard`

    // "[[ binary data 128 B png 40x20 ]]" is how cliphist previews an image.
    function parse(line: string): var {
        const tab = line.indexOf("\t");
        if (tab < 0)
            return null;
        const id = line.slice(0, tab);
        const text = line.slice(tab + 1);
        const bin = text.match(/^\[\[ binary data (.+) ([a-z0-9+.-]+) (\d+)x(\d+) \]\]$/);
        return {
            id,
            text,
            image: bin ? { size: bin[1], kind: bin[2], width: Number(bin[3]), height: Number(bin[4]) } : null
        };
    }

    // A short line for the entry: its text, or what kind of image it is.
    function describe(entry: var): string {
        if (!entry)
            return "";
        if (entry.image)
            return entry.image.width ? `Image, ${entry.image.width}×${entry.image.height}` : `${entry.image.kind.toUpperCase()} data, ${entry.image.size}`;
        return entry.text.trim();
    }

    function refresh(): void {
        lister.running = true;
    }

    // Puts the entry back on the clipboard; cliphist then moves it to the top.
    function copy(entry: var): void {
        run(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", entry.id]);
    }

    function remove(entry: var): void {
        entries = entries.filter(e => e.id !== entry.id);
        run(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist delete', "sh", entry.id]);
    }

    function wipe(): void {
        entries = [];
        thumbs = {};
        run(["sh", "-c", 'cliphist wipe; rm -rf "$1"', "sh", thumbDir]);
    }

    function run(command: var): void {
        const proc = runner.createObject(root, { command });
        proc.running = true;
    }

    // Decodes the images that don't have a file yet, for their thumbnails.
    function decodeImages(): void {
        const missing = entries.filter(e => e.image && e.image.width && !thumbs[e.id]).slice(0, Config.clipboard.shown);
        if (!missing.length || decoder.running)
            return;
        decoder.ids = missing.map(e => e.id);
        decoder.command = ["sh", "-c", 'dir=$1; shift; mkdir -p "$dir"; for id; do [ -s "$dir/$id" ] || cliphist decode "$id" > "$dir/$id"; done', "sh", thumbDir, ...decoder.ids];
        decoder.running = true;
    }

    onActiveChanged: if (active) refresh()

    // Records the clipboard; prints a line each time, so an open list can follow along.
    Process {
        id: watcher

        running: root.available
        command: ["wl-paste", "--watch", "sh", "-c", "cliphist store && echo"]
        stdout: SplitParser {
            onRead: if (root.active) root.refresh()
        }
        // Gone (wl-paste missing, compositor restarting): try again in a while.
        onExited: restart.start()
    }

    Timer {
        id: restart

        interval: 5000
        onTriggered: watcher.running = root.available
    }

    Process {
        id: lister

        command: ["sh", "-c", "command -v cliphist >/dev/null || exit 127; cliphist list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").map(root.parse).filter(e => e);
                root.decodeImages();
            }
        }
        onExited: code => root.available = code !== 127
    }

    Process {
        id: decoder

        property var ids: []

        onExited: {
            const next = Object.assign({}, root.thumbs);
            for (const id of ids)
                next[id] = `file://${root.thumbDir}/${id}`;
            root.thumbs = next;
            // More may have come in meanwhile.
            root.decodeImages();
        }
    }

    Component {
        id: runner

        Process {
            onExited: {
                if (root.active)
                    root.refresh();
                destroy();
            }
        }
    }

    Component.onCompleted: refresh()
}
