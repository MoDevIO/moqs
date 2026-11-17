pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Matrix through a local gomuks-web backend, which does sync and end-to-end encryption.
// Settings come from matrix.json next to shell.qml (the gomuks web login, not the Matrix one):
//   { "url": "http://localhost:29325", "username": "me", "password": "…" }
// or, instead of "password", "passwordCommand": "pass show gomuks".
Singleton {
    id: root

    // A bare "host:port" gets http://, which curl assumes but XMLHttpRequest needs spelled out.
    readonly property string url: {
        const u = (settings.url || "http://localhost:29325").replace(/\/+$/, "");
        return u.includes("://") ? u : `http://${u}`;
    }
    readonly property string password: settings.password || commandPassword
    readonly property bool configured: settings.username !== "" && password !== ""
    property string commandPassword

    // connecting, syncing, ready, error
    property string status: "connecting"
    property string error
    property bool loggedIn: true
    property string userId

    // Plain JS data, mutated in place; `version` bumps tell bindings to re-read it.
    property var rooms: ({}) // room_id -> { meta, timeline: [event rowid] }
    property var events: ({}) // rowid -> event
    property var names: ({}) // room_id -> { user_id -> display name }
    property var avatars: ({}) // room_id -> { user_id -> mxc:// avatar }
    // Lets plain image URLs past gomuks's auth; renewed by the backend every 30 minutes.
    property string imageToken
    property int version: 0

    readonly property var roomList: {
        version;
        return Object.values(rooms).filter(r => r.meta).sort((a, b) => (b.meta.sorting_timestamp ?? 0) - (a.meta.sorting_timestamp ?? 0)).slice(0, 80);
    }

    function roomName(room: var): string {
        return room?.meta?.name || room?.meta?.canonical_alias || room?.meta?.room_id || "";
    }

    // An mxc:// URI through gomuks. This asks for the original image: gomuks's avatar
    // thumbnails are WebP, which this Qt can't decode without qtimageformats.
    // Encrypted media needs the flag; gomuks has the keys from the event.
    function mediaUrl(mxc: string, encrypted: bool): string {
        const m = (mxc ?? "").match(/^mxc:\/\/([^/]+)\/(.+)$/);
        if (!m || !imageToken)
            return "";
        return `${url}/_gomuks/media/${m[1]}/${m[2]}?${encrypted ? "encrypted=true&" : ""}image_auth=${encodeURIComponent(imageToken)}`;
    }

    // { thumb, full, w, h } for images and stickers, else null.
    function image(evt: var): var {
        if (!evt || evt.redacted_by)
            return null;
        const type = evt.decrypted_type || evt.type;
        const c = evt.decrypted ?? evt.content ?? {};
        if (type !== "m.sticker" && !(type === "m.room.message" && c.msgtype === "m.image"))
            return null;
        const full = mediaUrl(c.file?.url ?? c.url, !!c.file);
        const thumbFile = c.info?.thumbnail_file;
        const thumbUrl = c.info?.thumbnail_url;
        return {
            full,
            thumb: thumbFile ? mediaUrl(thumbFile.url, true) : thumbUrl ? mediaUrl(thumbUrl, false) : full,
            w: c.info?.w ?? 0,
            h: c.info?.h ?? 0
        };
    }

    // An image's caption: its body, when that isn't just the file name.
    function caption(evt: var): string {
        const c = evt.decrypted ?? evt.content ?? {};
        return c.filename && c.body && c.body !== c.filename ? c.body : "";
    }

    // Adds the reaction, or takes it back if it's already ours.
    function react(roomId: string, evt: var, key: string): void {
        const own = evt.own_reactions?.[key] ?? [];
        if (own.length > 0) {
            for (const id of own)
                if (!id.startsWith("~"))
                    exec("redact_event", { room_id: roomId, event_id: id }, null);
        } else {
            exec("send_event", {
                room_id: roomId,
                type: "m.reaction",
                content: { "m.relates_to": { rel_type: "m.annotation", event_id: evt.event_id, key } }
            }, null);
        }
    }

    function senderAvatar(roomId: string, userId: string): string {
        return mediaUrl(avatars[roomId]?.[userId] ?? "", false);
    }

    // Members (names, avatars) of a room; fetched from the server if gomuks doesn't have them yet.
    function loadMembers(roomId: string): void {
        const meta = rooms[roomId]?.meta;
        exec("get_room_state", { room_id: roomId, fetch_members: !meta?.has_member_list, include_members: true }, res => {
            for (const evt of res ?? [])
                addEvent(evt, false);
            version++;
        });
    }

    function senderName(roomId: string, userId: string): string {
        return names[roomId]?.[userId] || userId.replace(/^@/, "").split(":")[0];
    }

    // What to show for an event, or "" for events that aren't shown.
    function text(evt: var): string {
        if (!evt)
            return "";
        const type = evt.decrypted_type || evt.type;
        const content = evt.decrypted ?? evt.content ?? {};
        if (evt.redacted_by)
            return "Message deleted";
        if (type === "m.room.encrypted")
            return evt.decryption_error ? "Unable to decrypt" : "Encrypted message";
        if (type === "m.sticker")
            return "Sticker";
        if (type !== "m.room.message" || content["m.relates_to"]?.rel_type === "m.replace")
            return "";
        switch (content.msgtype) {
        case "m.image":
            return "Image";
        case "m.video":
            return "Video";
        case "m.audio":
            return "Audio";
        case "m.file":
            return `File: ${content.body ?? ""}`;
        default:
            return content.body ?? "";
        }
    }

    function exec(command: string, params: var, done: var): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let res = null;
            try {
                res = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status === 200)
                done?.(res);
            else
                error = res?.error ?? `${command} failed (${xhr.status})`;
        };
        xhr.open("POST", `${url}/_gomuks/exec/${command}`);
        xhr.setRequestHeader("Authorization", `Basic ${Qt.btoa(`${settings.username}:${password}`)}`);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify(params));
    }

    // Message search over gomuks's local, decrypted copy, so encrypted rooms are included.
    // null while there's no query.
    property var searchResults: null
    property bool searching: false
    property int searchSeq: 0

    function searchMessages(query: string): void {
        const seq = ++searchSeq;
        const words = query.trim().split(/\s+/).filter(w => w);
        if (words.length === 0) {
            searchResults = null;
            searching = false;
            return;
        }
        // Quote each word so fts5 syntax characters are matched literally; the last word
        // also matches as a prefix, so results show up while typing.
        const term = words.map(w => `"${w.replace(/"/g, '""')}"`).join(" ") + "*";
        searching = true;
        exec("search_local", { search_term: term, limit: 40, sort_by_time: true }, res => {
            // A newer query has started since; drop this answer.
            if (seq !== searchSeq)
                return;
            searching = false;
            const found = (res?.events ?? []).filter(evt => text(evt) || image(evt));
            for (const evt of found)
                addEvent(evt, false);
            searchResults = found;
            // Sender names and avatars for rooms whose members we haven't seen yet.
            for (const id of new Set(found.map(evt => evt.room_id)))
                if (!names[id])
                    loadMembers(id);
        });
    }

    // Rooms whose name contains the query, most recent first.
    function findRooms(query: string): var {
        const q = query.trim().toLowerCase();
        return Object.values(rooms).filter(r => r.meta && roomName(r).toLowerCase().includes(q)).sort((a, b) => (b.meta.sorting_timestamp ?? 0) - (a.meta.sorting_timestamp ?? 0));
    }

    // Shows the message straight away as a pending local echo; gomuks then reports it sent
    // (send_complete) and the server's copy arrives through sync on the same row.
    function send(roomId: string, message: string): void {
        if (!message.trim())
            return;
        exec("send_message", { room_id: roomId, text: message }, evt => {
            if (evt?.rowid) {
                addEvent(evt, true);
                version++;
            }
        });
    }

    // Not yet confirmed by gomuks; and failed for good.
    function pending(evt: var): bool {
        return (evt?.event_id ?? "").startsWith("~") && (!evt.send_error || evt.send_error === "not sent");
    }

    function failed(evt: var): bool {
        return !!evt?.send_error && evt.send_error !== "not sent";
    }

    // Latest messages of a room from gomuks's local copy, merged into what we have.
    function refresh(roomId: string): void {
        exec("paginate", { room_id: roomId, limit: 40 }, res => {
            for (const evt of res?.events ?? [])
                addEvent(evt, true);
            version++;
        });
    }

    function markRead(roomId: string): void {
        const room = rooms[roomId];
        const last = room?.timeline.length ? events[room.timeline[room.timeline.length - 1]] : null;
        if (last?.event_id && !last.event_id.startsWith("~"))
            exec("mark_read", { room_id: roomId, event_id: last.event_id, receipt_type: "m.read" }, null);
    }

    // Loads older messages before the earliest one we have.
    function paginate(roomId: string): void {
        const room = rooms[roomId];
        if (!room || room.paginating || room.noMore)
            return;
        room.paginating = true;
        const first = room.timeline.length ? events[room.timeline[0]] : null;
        exec("paginate", { room_id: roomId, max_timeline_id: first?.timeline_rowid ?? 0, limit: 40 }, res => {
            room.paginating = false;
            room.noMore = !res?.has_more;
            for (const evt of res?.events ?? [])
                addEvent(evt, true);
            version++;
        });
    }

    function ensureRoom(roomId: string): var {
        if (!rooms[roomId])
            rooms[roomId] = { meta: null, timeline: [] };
        return rooms[roomId];
    }

    // Timeline position; events that don't have one yet (local echoes) go last.
    function position(rowid: var): real {
        return events[rowid]?.timeline_rowid || Infinity;
    }

    function addEvent(evt: var, toTimeline: bool): void {
        // Updated copies (e.g. a message whose reactions changed) come straight from gomuks's
        // database without a timeline position; keep the one we know.
        const old = events[evt.rowid];
        if (old?.timeline_rowid && !evt.timeline_rowid)
            evt.timeline_rowid = old.timeline_rowid;
        events[evt.rowid] = evt;
        if (evt.type === "m.room.member" && evt.state_key) {
            if (evt.content?.displayname) {
                if (!names[evt.room_id])
                    names[evt.room_id] = {};
                names[evt.room_id][evt.state_key] = evt.content.displayname;
            }
            if (evt.content?.avatar_url) {
                if (!avatars[evt.room_id])
                    avatars[evt.room_id] = {};
                avatars[evt.room_id][evt.state_key] = evt.content.avatar_url;
            }
        }
        if (evt.transaction_id)
            dropEcho(evt);
        // Pending local echoes have no timeline position yet but belong in the timeline.
        if (toTimeline && (evt.timeline_rowid || evt.transaction_id)) {
            const r = ensureRoom(evt.room_id);
            if (!r.timeline.includes(evt.rowid)) {
                r.timeline.push(evt.rowid);
                sortTimeline(r);
            }
        }
    }

    function sortTimeline(r: var): void {
        r.timeline.sort((a, b) => {
            const pa = position(a);
            const pb = position(b);
            return pa === pb ? 0 : pa < pb ? -1 : 1;
        });
    }

    // gomuks normally confirms a sent message on the echo's own row; should it ever use a new
    // row, remove the echo so the message doesn't show twice.
    function dropEcho(evt: var): void {
        const r = rooms[evt.room_id];
        if (!r)
            return;
        for (const rowid of r.timeline.slice()) {
            const other = events[rowid];
            if (rowid !== evt.rowid && other?.transaction_id === evt.transaction_id) {
                r.timeline.splice(r.timeline.indexOf(rowid), 1);
                delete events[rowid];
            }
        }
    }

    // Resuming the event stream: with these, a reconnect replays only what was missed instead of
    // gomuks resending a fresh state (with empty timelines).
    property string runId
    property int listenerId
    property real lastReceived
    property real lastServerTs
    // Rooms to reload after gomuks did send a fresh state.
    property bool refreshAfterInit

    function streamUrl(): string {
        const q = runId ? `?run_id=${runId}&last_received_event=${lastReceived}&last_server_ts=${lastServerTs}&prev_listener_id=${listenerId}` : "";
        return `${url}/_gomuks/sse${q}`;
    }

    function handle(msg: var): void {
        const data = msg.data;
        // Buffered events count down from -1; the most negative is the newest.
        if (msg.request_id < 0)
            lastReceived = msg.request_id;
        switch (msg.command) {
        case "run_id":
            runId = data?.run_id ?? "";
            listenerId = data?.listener_id ?? 0;
            break;
        case "client_state":
            loggedIn = data?.is_logged_in ?? false;
            userId = data?.user_id ?? "";
            break;
        case "sync_status":
            status = data?.type === "errored" ? "error" : status;
            break;
        case "image_auth_token":
            imageToken = data ?? "";
            break;
        case "init_complete":
            status = "ready";
            // History the fresh state left out, for rooms we had loaded.
            if (refreshAfterInit) {
                refreshAfterInit = false;
                for (const [id, r] of Object.entries(rooms))
                    if (r.timeline.length > 0)
                        refresh(id);
            }
            break;
        case "sync_complete":
            if (data.server_timestamp)
                lastServerTs = data.server_timestamp;
            // A fresh state comes with empty timelines; keep what's loaded (gomuks's row IDs are
            // stable) and reload the latest messages once it's complete.
            if (data.clear_state)
                refreshAfterInit = true;
            for (const [id, sr] of Object.entries(data.rooms ?? {})) {
                const r = ensureRoom(id);
                if (sr.meta)
                    r.meta = sr.meta;
                for (const evt of sr.events ?? [])
                    addEvent(evt, false);
                if (sr.reset)
                    r.timeline = [];
                for (const t of sr.timeline ?? [])
                    if (!r.timeline.includes(t.event_rowid))
                        r.timeline.push(t.event_rowid);
                sortTimeline(r);
                // Only recent history is kept in memory; older messages are paginated in again.
                if (r.timeline.length > 200)
                    r.timeline.splice(0, r.timeline.length - 200);
            }
            for (const id of data.left_rooms ?? [])
                delete rooms[id];
            if (status !== "ready")
                status = "syncing";
            version++;
            break;
        case "events_decrypted":
            for (const evt of data.events ?? [])
                addEvent(evt, false);
            version++;
            break;
        case "send_complete":
            if (data.event)
                addEvent(data.event, true);
            version++;
            break;
        }
    }

    onConfiguredChanged: if (configured) stream.running = true

    FileView {
        path: Quickshell.shellPath("matrix.json")
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

    // Event stream. Credentials go through stdin (curl -K -), so they stay out of the process list.
    Process {
        id: stream

        property real lastData: Date.now()

        command: ["curl", "-sSfN", "--compressed", "-K", "-", "-H", "Accept: application/jsonl", root.streamUrl()]
        stdinEnabled: true

        onStarted: {
            lastData = Date.now();
            root.status = "connecting";
            write(`user = "${settings.username.replace(/(["\\])/g, "\\$1")}:${root.password.replace(/(["\\])/g, "\\$1")}"\n`);
            stdinEnabled = false;
        }

        stdout: SplitParser {
            onRead: line => {
                stream.lastData = Date.now();
                if (line === "null")
                    return;
                try {
                    root.handle(JSON.parse(line));
                } catch (e) {
                    console.warn("matrix: bad event line", e);
                }
            }
        }

        stderr: SplitParser {
            onRead: line => root.error = line.replace(/^curl: \(\d+\) /, "")
        }

        onExited: {
            root.status = "error";
            stdinEnabled = true;
            if (root.configured)
                reconnect.start();
        }
    }

    Timer {
        id: reconnect

        interval: 5000
        onTriggered: {
            root.error = "";
            stream.command = ["curl", "-sSfN", "--compressed", "-K", "-", "-H", "Accept: application/jsonl", root.streamUrl()];
            stream.running = true;
        }
    }

    // gomuks pings every 15 s; a stream silent for much longer has hung, so restart it.
    // Also tells gomuks what we've received, so it can drop it from its replay buffer.
    Timer {
        running: stream.running
        interval: 15000
        repeat: true
        onTriggered: {
            if (Date.now() - stream.lastData > 45000) {
                stream.running = false;
                return;
            }
            if (!root.runId || !root.listenerId || !root.lastReceived)
                return;
            const xhr = new XMLHttpRequest();
            xhr.open("POST", `${root.url}/_gomuks/sse/ping?run_id=${root.runId}&listener_id=${root.listenerId}&last_received_event=${root.lastReceived}`);
            xhr.setRequestHeader("Authorization", `Basic ${Qt.btoa(`${settings.username}:${root.password}`)}`);
            xhr.send();
        }
    }
}
