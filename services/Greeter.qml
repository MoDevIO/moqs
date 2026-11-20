pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// The login screen's side of greetd (see greeter.qml): who logs in, into which session, and
// the password exchange. Sessions are the .desktop files in the directories listed in
// $MOQS_SESSIONS, as "wayland=<dir>:x11=<dir>:…" (the NixOS module passes NixOS's session
// list); X11 sessions start through $MOQS_XSESSION_WRAPPER (e.g. "startx /usr/bin/env") and
// are left out without one. The last user and session are remembered in
// $XDG_STATE_HOME/moqs/greeter.json; before there is one, $MOQS_DEFAULT_SESSION (the name of
// a .desktop file, e.g. "hyprland") is the session.
Singleton {
    id: root

    // [{ name, display }], from /etc/passwd: uid 1000 and up, with a login shell.
    property var users: []
    // [{ key, name, type, exec, desktops }], sorted by name.
    property var sessions: []
    property string user
    property string session: Quickshell.env("MOQS_DEFAULT_SESSION") ?? ""

    readonly property var currentSession: sessions.find(s => s.key === session) ?? sessions[0] ?? null
    readonly property string xWrapper: Quickshell.env("MOQS_XSESSION_WRAPPER") ?? ""

    // idle, checking, failed or launching
    property string state: "idle"
    property string message
    // A further question from PAM (a one-time code, say) to answer in the field.
    property string question
    property bool questionEcho
    property string pending

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/moqs`

    function displayName(name: string): string {
        return users.find(u => u.name === name)?.display || name;
    }

    // Steps to the next or previous user or session.
    function cycleUser(step: int): void {
        const i = users.findIndex(u => u.name === user);
        if (users.length)
            user = users[(i + step + users.length) % users.length].name;
        reset();
    }

    function pickSession(key: string): void {
        session = key;
    }

    function reset(): void {
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        state = "idle";
        message = "";
        question = "";
        pending = "";
    }

    // Logs in with the password, or answers the question asked after it.
    function submit(text: string): void {
        if (!Greetd.available) {
            state = "failed";
            message = "greetd isn't running";
            return;
        }
        if (question) {
            question = "";
            state = "checking";
            Greetd.respond(text);
            return;
        }
        if (!user || !currentSession || state === "checking" || state === "launching")
            return;
        pending = text;
        state = "checking";
        message = "";
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        Greetd.createSession(user);
    }

    function launch(): void {
        const s = currentSession;
        state = "launching";
        message = `Starting ${s.name}…`;
        save();
        const desktop = s.desktops || s.key;
        const env = [`XDG_SESSION_TYPE=${s.type}`, `XDG_SESSION_DESKTOP=${s.key}`, `XDG_CURRENT_DESKTOP=${desktop}`];
        const exec = s.type === "x11" ? `${xWrapper} ${s.exec}` : s.exec;
        // The session's output goes to the journal (journalctl -t moqs-session), as with GDM;
        // otherwise it's printed on the console and lost.
        const script = `if command -v systemd-cat >/dev/null; then exec systemd-cat -t moqs-session -- ${exec}; else exec ${exec}; fi`;
        // greetd runs the command as "<source profiles>; exec <arguments joined with spaces>",
        // so each argument is quoted to survive being joined and read back by the shell.
        Greetd.launch(["/bin/sh", "-c", script].map(quote), env, true);
    }

    function quote(arg: string): string {
        return `'${arg.replace(/'/g, "'\\''")}'`;
    }

    function save(): void {
        Quickshell.execDetached(["mkdir", "-p", stateDir]);
        stateFile.setText(JSON.stringify({ user, session: currentSession?.key ?? "" }) + "\n");
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (!responseRequired) {
                root.message = message;
                return;
            }
            if (root.pending) {
                Greetd.respond(root.pending);
                root.pending = "";
                return;
            }
            // Asked something more: show it and let the field answer.
            root.state = "idle";
            root.question = message.trim().replace(/:$/, "");
            root.questionEcho = echoResponse;
            root.message = "";
        }

        function onReadyToLaunch(): void {
            root.launch();
        }

        function onAuthFailure(message: string): void {
            root.pending = "";
            root.question = "";
            root.state = "failed";
            root.message = message && !/authentication failure/i.test(message) ? message : "Wrong password";
        }

        function onError(error: string): void {
            root.pending = "";
            root.question = "";
            root.state = "failed";
            root.message = error || "Couldn't log in";
        }
    }

    // Users
    FileView {
        path: "/etc/passwd"
        printErrors: false
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const f = line.split(":");
                const uid = Number(f[2]);
                if (f.length < 7 || uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6]))
                    continue;
                out.push({ name: f[0], display: f[4].split(",")[0] || f[0] });
            }
            root.users = out;
            if (!root.users.some(u => u.name === root.user))
                root.user = out[0]?.name ?? "";
        }
    }

    // Sessions: "type\tfile\tKey=value" for the keys that matter, from each directory.
    Process {
        running: true
        environment: ({
                MOQS_SESSIONS: Quickshell.env("MOQS_SESSIONS") || "wayland=/run/current-system/sw/share/wayland-sessions:wayland=/usr/share/wayland-sessions:x11=/run/current-system/sw/share/xsessions:x11=/usr/share/xsessions"
            })
        command: ["sh", "-c", `
            IFS=:
            for spec in $MOQS_SESSIONS; do
                type=\${spec%%=*}; dir=\${spec#*=}
                for f in "$dir"/*.desktop; do
                    [ -f "$f" ] || continue
                    sed -n '/^\\[Desktop Entry\\]/,/^\\[/{/^\\(Name\\|Exec\\|DesktopNames\\|NoDisplay\\|Hidden\\)=/p}' "$f" | sed "s|^|$type\t$f\t|"
                done
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const byFile = {};
                for (const line of text.split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 3)
                        continue;
                    const type = parts[0];
                    const file = parts[1];
                    const kv = parts.slice(2).join("\t");
                    const eq = kv.indexOf("=");
                    const s = byFile[file] ?? (byFile[file] = { type, key: file.replace(/^.*\//, "").replace(/\.desktop$/, "") });
                    const key = kv.slice(0, eq);
                    // The first of each key, in the [Desktop Entry] group.
                    if (!(key in s))
                        s[key] = kv.slice(eq + 1);
                }
                const seen = {};
                const out = [];
                for (const s of Object.values(byFile)) {
                    if (!s.Exec || s.NoDisplay === "true" || s.Hidden === "true" || (s.type === "x11" && !root.xWrapper))
                        continue;
                    // The same session from two directories counts once.
                    if (seen[`${s.type}:${s.key}`])
                        continue;
                    seen[`${s.type}:${s.key}`] = true;
                    out.push({
                        key: s.key,
                        name: (s.Name || s.key) + (s.type === "x11" ? " (X11)" : ""),
                        type: s.type,
                        exec: s.Exec.replace(/\s+%[fFuUdDnNickvm]/g, ""),
                        desktops: (s.DesktopNames || "").replace(/;$/, "").replace(/;/g, ":")
                    });
                }
                root.sessions = out.sort((a, b) => a.name.localeCompare(b.name));
            }
        }
    }

    // The last user and session.
    FileView {
        id: stateFile

        path: `${root.stateDir}/greeter.json`
        printErrors: false
        onLoaded: {
            try {
                const st = JSON.parse(text());
                if (st.user)
                    root.user = st.user;
                if (st.session)
                    root.session = st.session;
            } catch (e) {}
        }
    }
}
