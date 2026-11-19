pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// WebUntis timetable and homework, plus homework kept locally in a text file.
// Settings come from webuntis.json next to shell.qml:
//   { "url": "https://mese.webuntis.com", "school": "Example-School", "username": "me",
//     "passwordCommand": "pass show webuntis", "homeworkFile": "/path/to/homework.txt" }
// "password" works instead of "passwordCommand"; "homeworkFile" is optional.
//
// Requests go through curl with the credentials and session cookie on stdin (curl -K -),
// which keeps them out of the process list. The homework endpoint needs the session cookie,
// which XMLHttpRequest isn't allowed to set.
Singleton {
    id: root

    readonly property string url: {
        const u = settings.url.replace(/\/+$/, "").replace(/\/WebUntis.*$/, "");
        return !u || u.includes("://") ? u : `https://${u}`;
    }
    readonly property string password: settings.password || commandPassword
    readonly property bool configured: url !== "" && settings.school !== "" && settings.username !== "" && password !== ""
    property string commandPassword
    property string error
    property bool loading
    property real lastRefresh: 0

    // Lessons of the fetched days, double lessons merged:
    // [{ date, start, end, subject, teachers, rooms, text, cancelled, changed }]
    // date is YYYYMMDD, start and end are HHMM, as WebUntis has them.
    property var lessons: []
    // WebUntis homework due today or later: [{ id, subject, text, due, completed }], subject
    // as its short name.
    property var remoteHomework: []
    // Short subject name to long name, from the school's subject list and the timetable.
    property var subjectNames: ({})

    // Local homework from the text file: [{ text, done }], and the WebUntis homework ticked off.
    property var localHomework: []
    property var ticked: ({})

    // Today's date and time, updated every minute.
    property date now: new Date()
    readonly property int today: dateInt(now)
    readonly property int time: now.getHours() * 100 + now.getMinutes()

    // Today until its last lesson has ended, then the next day with lessons.
    readonly property int shownDate: {
        const todays = lessons.filter(l => l.date === today && !l.cancelled);
        if (todays.length && time < Math.max(...todays.map(l => l.end)))
            return today;
        const next = lessons.find(l => l.date > today);
        return next ? next.date : 0;
    }
    readonly property var shownLessons: lessons.filter(l => l.date === shownDate)

    // Local homework first, then WebUntis homework by due date.
    readonly property var homework: [
        ...localHomework.map((h, i) => ({ local: true, index: i, text: h.text, subject: "", due: 0, done: h.done, locked: false })),
        ...remoteHomework.map(h => ({ local: false, id: h.id, text: h.text, subject: longName(h.subject), due: h.due, done: h.completed || !!ticked[h.id], locked: h.completed }))
    ]

    readonly property string homeworkPath: {
        const set = settings.homeworkFile.replace(/^~(?=\/)/, Quickshell.env("HOME"));
        if (set)
            return set;
        const state = Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`;
        return `${state}/moqs/homework.txt`;
    }

    function longName(short: string): string {
        return subjectNames[short] || short;
    }

    function dateInt(d: var): int {
        return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
    }

    function toDate(n: int): var {
        return new Date(Math.floor(n / 10000), Math.floor(n / 100) % 100 - 1, n % 100);
    }

    function addDays(n: int, days: int): int {
        const d = toDate(n);
        d.setDate(d.getDate() + days);
        return dateInt(d);
    }

    function minutes(hhmm: int): int {
        return Math.floor(hhmm / 100) * 60 + hhmm % 100;
    }

    function clock(hhmm: int): string {
        return `${String(Math.floor(hhmm / 100)).padStart(2, "0")}:${String(hhmm % 100).padStart(2, "0")}`;
    }

    // "Today", "Tomorrow", a weekday within the week, otherwise the date.
    function dayName(n: int): string {
        if (!n)
            return "";
        if (n === today)
            return "Today";
        if (n === addDays(today, 1))
            return "Tomorrow";
        const d = toDate(n);
        return n < addDays(today, 7) ? Qt.formatDate(d, "dddd") : Qt.formatDate(d, "ddd d MMM");
    }

    // Refresh when shown, unless the data is only a few minutes old.
    function refreshIfStale(): void {
        if (Date.now() - lastRefresh > 2 * 60 * 1000)
            refresh();
    }

    function refresh(): void {
        if (!configured || loading)
            return;
        loading = true;
        // Also on failure, so a wrong password isn't retried every minute.
        lastRefresh = Date.now();
        rpc("", "authenticate", { user: settings.username, password: password, client: "moqs" }, auth => {
            const cookie = `JSESSIONID=${auth.sessionId}; schoolname="_${Qt.btoa(settings.school)}"`;
            // Students see their own timetable; other accounts fall back to their class.
            const element = auth.personId ? { id: auth.personId, type: auth.personType } : { id: auth.klasseId, type: 1 };
            let pending = 3;
            const finish = () => {
                if (--pending > 0)
                    return;
                rpc(cookie, "logout", {}, () => {});
                loading = false;
            };
            rpc(cookie, "getTimetable", {
                options: {
                    element,
                    startDate: today,
                    endDate: addDays(today, Config.webuntis.days),
                    showLsText: true,
                    showSubstText: true,
                    showInfo: true,
                    subjectFields: ["name", "longname"],
                    teacherFields: ["name"],
                    roomFields: ["name"]
                }
            }, res => {
                lessons = merge(res ?? []);
                const names = Object.assign({}, subjectNames);
                for (const l of res ?? [])
                    for (const su of l.su ?? [])
                        if (su.name && su.longname && !names[su.name])
                            names[su.name] = su.longname;
                subjectNames = names;
                finish();
            }, finish);
            rpc(cookie, "getSubjects", {}, res => {
                const names = Object.assign({}, subjectNames);
                for (const su of res ?? [])
                    if (su.name && su.longName)
                        names[su.name] = su.longName;
                subjectNames = names;
                finish();
            }, () => {
                // Some accounts may not list subjects; the timetable's names still apply.
                error = "";
                finish();
            });
            rest(cookie, `/WebUntis/api/homeworks/lessons?startDate=${addDays(today, -Config.webuntis.days)}&endDate=${addDays(today, Config.webuntis.days)}`, res => {
                const data = res?.data ?? {};
                const subjects = {};
                for (const l of data.lessons ?? [])
                    subjects[l.id] = l.subject ?? "";
                remoteHomework = (data.homeworks ?? []).filter(h => h.dueDate >= today).map(h => ({
                    id: String(h.id),
                    subject: subjects[h.lessonId] ?? "",
                    text: (h.text ?? "").trim(),
                    due: h.dueDate,
                    completed: !!h.completed
                })).sort((a, b) => a.due - b.due);
                finish();
            }, finish);
        }, () => loading = false);
    }

    // Lessons with the same details, one right after the other (up to a break of
    // Config.webuntis.mergeGap minutes), become one long lesson.
    function merge(raw: var): var {
        const names = (list, field) => (list ?? []).map(x => x[field] || x.name || "").filter(x => x);
        const all = raw.map(l => ({
            date: l.date,
            start: l.startTime,
            end: l.endTime,
            subject: names(l.su, "longname").join(", ") || l.lstext || l.activityType || "Lesson",
            teachers: names(l.te, "name").join(", "),
            rooms: names(l.ro, "name").join(", "),
            text: [l.substText, l.lstext, l.info].filter(x => x).join(" · "),
            cancelled: l.code === "cancelled",
            changed: l.code === "irregular"
        })).sort((a, b) => a.date - b.date || a.start - b.start);
        const key = l => [l.subject, l.teachers, l.rooms, l.text, l.cancelled, l.changed].join("\u0001");
        const out = [];
        for (const l of all) {
            const prev = out[out.length - 1];
            if (prev && prev.date === l.date && key(prev) === key(l) && minutes(l.start) - minutes(prev.end) <= Config.webuntis.mergeGap)
                prev.end = Math.max(prev.end, l.end);
            else
                out.push(l);
        }
        return out;
    }

    function quote(s: string): string {
        return `"${String(s).replace(/(["\\])/g, "\\$1")}"`;
    }

    function rpc(cookie: string, method: string, params: var, done: var, failed: var): void {
        const body = JSON.stringify({ id: method, method, params, jsonrpc: "2.0" });
        const lines = [`url = ${quote(`${url}/WebUntis/jsonrpc.do?school=${encodeURIComponent(settings.school)}`)}`, `header = "Content-Type: application/json"`, `data = ${quote(body)}`];
        if (cookie)
            lines.push(`cookie = ${quote(cookie)}`);
        curl(lines, res => {
            if (res?.error) {
                error = res.error.code === -8504 ? "Wrong WebUntis username or password" : res.error.message || "WebUntis request failed";
                failed?.();
            } else if (res && "result" in res) {
                error = "";
                done(res.result);
            } else {
                error = "Unexpected answer from WebUntis";
                failed?.();
            }
        }, failed);
    }

    function rest(cookie: string, path: string, done: var, failed: var): void {
        curl([`url = ${quote(url + path)}`, `cookie = ${quote(cookie)}`], done, failed);
    }

    function curl(lines: var, done: var, failed: var): void {
        request.createObject(root, { config: lines.join("\n") + "\n", done, failed: failed ?? (() => {}) });
    }

    Component {
        id: request

        Process {
            id: proc

            required property string config
            required property var done
            required property var failed

            command: ["curl", "-sS", "--compressed", "--max-time", "20", "-K", "-"]
            stdinEnabled: true
            running: true

            onStarted: {
                write(config);
                stdinEnabled = false;
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    let res = null;
                    try {
                        res = JSON.parse(text);
                    } catch (e) {}
                    if (res !== null) {
                        proc.done(res);
                    } else {
                        root.error = errors.text.trim().replace(/^curl: \(\d+\) /, "") || "Can't reach WebUntis";
                        proc.failed();
                    }
                }
            }

            stderr: StdioCollector {
                id: errors
            }

            onExited: destroy()
        }
    }

    // Local homework file. One entry per line: "[ ] text" to do, "[x] text" done.
    // "[x] untis:<id>" ticks off a WebUntis homework; anything after the id is a reminder.
    function parseHomework(text: string): void {
        const local = [];
        const marks = {};
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*\[([ xX])\]\s?(.*)$/);
            if (!m)
                continue;
            const done = m[1] !== " ";
            const remote = m[2].match(/^untis:(\S+)/);
            if (remote) {
                if (done)
                    marks[remote[1]] = true;
            } else if (m[2].trim()) {
                local.push({ text: m[2].trim(), done });
            }
        }
        localHomework = local;
        ticked = marks;
    }

    function saveHomework(): void {
        const lines = ["# moqs homework. One per line: \"[ ] text\" to do, \"[x] text\" done.", "# \"[x] untis:<id>\" ticks off a WebUntis homework.", ...localHomework.map(h => `[${h.done ? "x" : " "}] ${h.text}`)];
        for (const id of Object.keys(ticked)) {
            const h = remoteHomework.find(r => r.id === id);
            lines.push(`[x] untis:${id}${h ? `  ${[h.subject, h.text].filter(x => x).join(": ").replace(/\s+/g, " ").slice(0, 80)}` : ""}`);
        }
        homeworkFile.setText(lines.join("\n") + "\n");
    }

    function addHomework(text: string): void {
        const t = text.replace(/\s+/g, " ").trim();
        if (!t)
            return;
        localHomework = [{ text: t, done: false }, ...localHomework];
        saveHomework();
    }

    function removeHomework(index: int): void {
        localHomework = localHomework.filter((_, i) => i !== index);
        saveHomework();
    }

    function toggle(entry: var): void {
        if (entry.local) {
            localHomework = localHomework.map((h, i) => i === entry.index ? { text: h.text, done: !h.done } : h);
        } else if (!entry.locked) {
            const t = Object.assign({}, ticked);
            if (t[entry.id])
                delete t[entry.id];
            else
                t[entry.id] = true;
            ticked = t;
        }
        saveHomework();
    }

    onConfiguredChanged: if (configured) refresh()
    onHomeworkPathChanged: Quickshell.execDetached(["mkdir", "-p", homeworkPath.replace(/\/[^\/]*$/, "")])

    Timer {
        running: true
        repeat: true
        interval: 60 * 1000
        onTriggered: {
            const day = root.today;
            root.now = new Date();
            // A new day needs a new timetable.
            if (root.today !== day || Date.now() - root.lastRefresh > Config.webuntis.refresh * 60 * 1000)
                root.refresh();
        }
    }

    FileView {
        id: homeworkFile

        path: root.homeworkPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseHomework(text())
    }

    FileView {
        path: Quickshell.shellPath("webuntis.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string url
            property string school
            property string username
            property string password
            property string passwordCommand
            property string homeworkFile

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
