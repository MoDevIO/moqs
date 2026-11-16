pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Navidrome through the Subsonic API. Settings come from navidrome.json next to shell.qml:
//   { "url": "https://music.example.com", "username": "me", "password": "…" }
// or, instead of "password", "passwordCommand": "pass show navidrome".
Singleton {
    id: root

    readonly property string url: {
        const u = settings.url.replace(/\/+$/, "");
        return !u || u.includes("://") ? u : `https://${u}`;
    }
    readonly property string password: settings.password || commandPassword
    readonly property bool configured: url !== "" && settings.username !== "" && password !== ""
    property string commandPassword
    property string error

    // Browsing state
    property var albums: []
    property var album: null // { id, name, artist, coverArt, songs }
    property var results: null // { albums, songs }
    property bool loading: false

    function query(params: var): string {
        const salt = Math.random().toString(36).slice(2, 10);
        const all = Object.assign({
            u: settings.username,
            t: Qt.md5(password + salt),
            s: salt,
            v: "1.16.1",
            c: "quickshell",
            f: "json"
        }, params);
        return Object.keys(all).map(k => `${encodeURIComponent(k)}=${encodeURIComponent(all[k])}`).join("&");
    }

    function api(endpoint: string, params: var, done: var): void {
        if (!configured) {
            error = "Set up navidrome.json";
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            loading = false;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText)["subsonic-response"];
            } catch (e) {}
            if (!res) {
                error = xhr.status ? `Server error ${xhr.status}` : "Can't reach the server";
            } else if (res.status !== "ok") {
                error = res.error?.message ?? "Request failed";
            } else {
                error = "";
                done(res);
            }
        };
        loading = true;
        xhr.open("GET", `${url}/rest/${endpoint}.view?${query(params)}`);
        xhr.send();
    }

    function streamUrl(id: string): string {
        return `${url}/rest/stream.view?${query({ id })}`;
    }

    function coverUrl(id: string, size: int): string {
        return id ? `${url}/rest/getCoverArt.view?${query({ id, size })}` : "";
    }

    function loadAlbums(type: string): void {
        api("getAlbumList2", { type, size: 60 }, res => albums = res.albumList2?.album ?? []);
    }

    function openAlbum(id: string): void {
        api("getAlbum", { id }, res => {
            const a = res.album;
            album = { id: a.id, name: a.name, artist: a.artist, coverArt: a.coverArt, songs: a.song ?? [] };
        });
    }

    function search(text: string): void {
        if (!text.trim()) {
            results = null;
            return;
        }
        api("search3", { query: text, artistCount: 0, albumCount: 8, songCount: 30 }, res => {
            results = { albums: res.searchResult3?.album ?? [], songs: res.searchResult3?.song ?? [] };
        });
    }

    // Tells Navidrome what's playing; submission marks it as played.
    function scrobble(id: string, submission: bool): void {
        api("scrobble", { id, submission }, () => {});
    }

    onConfiguredChanged: if (configured) loadAlbums("newest")

    FileView {
        id: file

        path: Quickshell.shellPath("navidrome.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string url
            property string username
            property string password
            property string passwordCommand

            // Set the command here: a binding on it would update only after this handler runs.
            onPasswordCommandChanged: {
                if (!passwordCommand)
                    return;
                passwordProc.command = ["sh", "-c", passwordCommand];
                passwordProc.running = true;
            }
        }
    }

    Process {
        id: passwordProc

        stdout: StdioCollector {
            onStreamFinished: root.commandPassword = text.split("\n")[0]
        }
    }
}
