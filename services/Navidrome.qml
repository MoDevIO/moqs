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
        const u = (settings.url || urlSecret.value).replace(/\/+$/, "");
        return !u || u.includes("://") ? u : `https://${u}`;
    }
    readonly property string password: settings.password || commandPassword
    readonly property string username: settings.username || usernameSecret.value
    readonly property bool configured: url !== "" && username !== "" && password !== ""
    property string commandPassword
    // Why the Navidrome password command failed (say, the secret isn't readable by this user), or "".
    property bool secretFailed
    property string secretMessage
    readonly property string secretError: (secretFailed ? `Can't read the Navidrome password${secretMessage ? ": " + secretMessage : ""}` : "") || urlSecret.failure || usernameSecret.failure
    property string error

    // Browsing state
    property var albums: []
    property var album: null // { id, name, artist, coverArt, songs }
    property var artist: null // { id, name, coverArt, albums }
    property var results: null // { artists, albums, songs }
    property bool loading: false

    function query(params: var): string {
        const salt = Math.random().toString(36).slice(2, 10);
        const all = Object.assign({
            u: root.username,
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
            error = secretError || "Set up navidrome.json";
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

    function openArtist(id: string): void {
        api("getArtist", { id }, res => {
            const a = res.artist;
            const albums = (a.album ?? []).sort((x, y) => (y.year ?? 0) - (x.year ?? 0));
            artist = { id: a.id, name: a.name, coverArt: a.coverArt, albums, songs: [] };
            // Artists who only appear on other people's albums have none of their own; list
            // their songs instead. Those only credited as e.g. remixer have no songs of their own
            // either, so fall back to the songs that mention them.
            if (albums.length === 0)
                api("search3", { query: a.name, artistCount: 0, albumCount: 0, songCount: 200 }, r => {
                    if (artist?.id !== id)
                        return;
                    const found = r.searchResult3?.song ?? [];
                    const own = found.filter(s => s.artistId === id || (s.artists ?? []).some(x => x.id === id));
                    artist = Object.assign({}, artist, { songs: own.length ? own : found });
                });
        });
    }

    // Every song of an artist, album by album (newest album first), for playing them all.
    function artistSongs(a: var, done: var): void {
        if ((a?.albums ?? []).length === 0) {
            done(a?.songs ?? []);
            return;
        }
        const albums = a.albums;
        const songs = [];
        const next = i => {
            if (i >= albums.length) {
                done(songs);
                return;
            }
            api("getAlbum", { id: albums[i].id }, res => {
                songs.push(...(res.album?.song ?? []));
                next(i + 1);
            });
        };
        next(0);
    }

    property int searchSeq: 0

    function search(text: string): void {
        // Answers to older searches are dropped, including ones still under way when the
        // search is cleared.
        const seq = ++searchSeq;
        if (!text.trim()) {
            results = null;
            return;
        }
        api("search3", { query: text, artistCount: 5, albumCount: 10, songCount: 20 }, res => {
            if (seq !== searchSeq)
                return;
            const r = res.searchResult3 ?? {};
            results = { artists: r.artist ?? [], albums: r.album ?? [], songs: r.song ?? [] };
        });
    }

    // Tells Navidrome what's playing; submission marks it as played.
    function scrobble(id: string, submission: bool): void {
        api("scrobble", { id, submission }, () => {});
    }

    onConfiguredChanged: if (configured) loadAlbums("newest")

    Secret {
        id: urlSecret

        what: "the Navidrome URL"
        path: settings.urlFile
    }

    Secret {
        id: usernameSecret

        what: "the Navidrome username"
        path: settings.usernameFile
    }

    FileView {
        id: file

        path: Quickshell.shellPath("navidrome.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string url
            property string urlFile
            property string username
            property string usernameFile
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

        stderr: StdioCollector {
            onStreamFinished: root.secretMessage = text.trim().split("\n")[0].replace(/^(cat|sh): /, "")
        }

        onStarted: root.secretFailed = false
        onExited: code => root.secretFailed = code !== 0
    }
}
