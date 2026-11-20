pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// WebUntis timetable, homework and exams, plus homework and exams kept locally in a text file.
// Settings come from webuntis.json next to shell.qml:
//   { "url": "https://mese.webuntis.com", "school": "Example-School", "username": "me",
//     "passwordCommand": "pass show webuntis", "homeworkFile": "/path/to/homework.txt" }
// "password" works instead of "passwordCommand". Optional: "homeworkFile",
// "cancelledRooms": ["Eva"] to show lessons in those rooms as cancelled, and
// "subjects": [{ "name": "Eng", "untis": "Englisch" }], short names to type for new homework.
//
// Requests go through curl with the credentials and session cookie on stdin (curl -K -),
// which keeps them out of the process list. The homework endpoint needs the session cookie,
// which XMLHttpRequest isn't allowed to set.
Singleton {
    id: root

    readonly property string url: {
        const u = (settings.url || urlSecret.value).replace(/\/+$/, "").replace(/\/WebUntis.*$/, "");
        return !u || u.includes("://") ? u : `https://${u}`;
    }
    readonly property string password: settings.password || commandPassword
    readonly property string school: settings.school || schoolSecret.value
    readonly property string username: settings.username || usernameSecret.value
    readonly property bool configured: url !== "" && school !== "" && username !== "" && password !== ""
    property string commandPassword
    // Why the WebUntis password command failed (say, the secret isn't readable by this user), or "".
    property bool secretFailed
    property string secretMessage
    readonly property string secretError: (secretFailed ? `Can't read the WebUntis password${secretMessage ? ": " + secretMessage : ""}` : "") || urlSecret.failure || schoolSecret.failure || usernameSecret.failure
    property string error
    property bool loading
    property real lastRefresh: 0

    // Lessons of the fetched days, double lessons merged:
    // [{ date, start, end, subject, teachers, rooms, text, cancelled, changed }]
    // date is YYYYMMDD, start and end are HHMM, as WebUntis has them.
    property var lessons: []
    // Dates whose lessons have been fetched (date: true), so browsing knows what to load.
    property var loaded: ({})
    property bool loadingWeek
    // WebUntis homework due today or later: [{ id, subject, text, due, completed }], subject
    // as its short name.
    property var remoteHomework: []
    // Short subject name to long name, from the school's subject list and the timetable.
    property var subjectNames: ({})

    // Local homework from the text file: [{ text, subject, due, done }], and the WebUntis
    // homework ticked off.
    property var localHomework: []
    property var ticked: ({})

    // WebUntis exams from today on: [{ key, subject, name, text, date, start }], subject as
    // its short name. WebUntis gives students no exam IDs, so key is made from date, subject
    // and name.
    property var remoteExams: []
    // Own exams from the text file: [{ text, subject, date, progress }], and how far along the
    // learning for WebUntis exams is, by key. Progress is 0..100.
    property var localExams: []
    property var examProgress: ({})

    // Own and WebUntis exams from today on, soonest first.
    readonly property var exams: [
        ...localExams.map((e, i) => ({ local: true, index: i, subject: e.subject, text: e.text, date: e.date, progress: e.progress })),
        ...remoteExams.map(e => ({ local: false, key: e.key, subject: longName(e.subject), text: [e.name, e.text].filter(x => x).join(" · "), date: e.date, progress: examProgress[e.key] ?? 0 }))
    ].filter(e => e.date >= today).sort((a, b) => a.date - b.date)

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
    // A day picked with the arrows, or 0 for shownDate.
    property int selectedDate: 0
    readonly property int viewDate: selectedDate || shownDate
    readonly property var shownLessons: lessons.filter(l => l.date === viewDate)

    // Rooms whose lessons count as cancelled, lower case.
    readonly property var cancelledRooms: Array.from(settings.cancelledRooms ?? []).map(r => String(r).toLowerCase())

    // Own and WebUntis homework together: open before done, then by due date (none last).
    readonly property var homework: [
        ...localHomework.map((h, i) => ({ local: true, index: i, text: h.text, subject: h.subject, due: h.due, done: h.done, locked: false })),
        ...remoteHomework.map(h => ({ local: false, id: h.id, text: h.text, subject: longName(h.subject), due: h.due, done: h.completed || !!ticked[h.id], locked: h.completed }))
    ].sort((a, b) => a.done - b.done || (a.due || 99999999) - (b.due || 99999999))

    // Short names to type for new homework, with their WebUntis names.
    readonly property var subjects: Array.from(settings.subjects ?? []).map(x => ({ name: String(x.name ?? ""), untis: String(x.untis ?? x.name ?? "") })).filter(x => x.name || x.untis)

    readonly property string homeworkPath: {
        const set = settings.homeworkFile.replace(/^~(?=\/)/, Quickshell.env("HOME"));
        if (set)
            return set;
        const state = Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`;
        return `${state}/moqs/homework.txt`;
    }

    // Open homework due in a lesson: due that day, for the lesson's subject.
    function homeworkFor(lesson: var): var {
        const subjects = lesson.subject.toLowerCase().split(", ");
        return homework.filter(h => !h.done && h.due === lesson.date && subjects.includes(h.subject.toLowerCase()));
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

    // How soon homework is due: "late" (overdue or today), "soon" (tomorrow), "near" (within
    // three days) or "".
    function urgency(due: int): string {
        if (!due)
            return "";
        if (due <= today)
            return "late";
        if (due === addDays(today, 1))
            return "soon";
        return due <= addDays(today, 3) ? "near" : "";
    }

    // How soon an exam is: "late" (within two days), "soon" (within a week), "near" (within
    // two weeks) or "". Exams need more lead time than homework.
    function examUrgency(date: int): string {
        if (date <= addDays(today, 2))
            return "late";
        if (date <= addDays(today, 7))
            return "soon";
        return date <= addDays(today, 14) ? "near" : "";
    }

    // "Today", "Tomorrow", "in 5 days", "in 3 weeks".
    function countdown(n: int): string {
        const days = Math.round((toDate(n) - toDate(today)) / 86400000);
        if (days <= 0)
            return "Today";
        if (days === 1)
            return "Tomorrow";
        return days < 21 ? `in ${days} days` : `in ${Math.round(days / 7)} weeks`;
    }

    // Reads a new homework entry: a subject (a short name from "subjects" or its WebUntis name)
    // and a due date are picked out of the text and removed from it. Without a date, the
    // subject's next lesson sets it. Starting with "exam:" (or "test:", "klausur:") makes it an
    // exam. Returns { exam, subject, due, guessed, text }.
    function parseEntry(input: string): var {
        const prefix = input.match(/^\s*(?:exam|test|klausur|klassenarbeit|kursarbeit)\s*:/i);
        const exam = !!prefix;
        if (prefix)
            input = input.slice(prefix[0].length);
        let text = " " + input.replace(/\s+/g, " ") + " ";
        const take = re => {
            const m = text.match(re);
            if (m)
                text = text.slice(0, m.index) + " " + text.slice(m.index + m[0].length);
            return m;
        };
        const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        // Whole words, with the space or punctuation before them (Qt's JavaScript has no
        // lookbehind, and \b doesn't know umlauts).
        const word = (s, end) => new RegExp(`[\\s,;:(]${s}(?=${end ?? "[\\s,;:.!?)]"})`, "i");
        // A date may come with a linking word ("bis 21.11."), which goes too.
        const date = (s, end) => word(`(?:(?:bis|zum|zu|am|für|fuer|until|due|by|on)\\s+)?${s}`, end);

        // Subject, longest names first so "Evangelische Religion" beats "Religion".
        let subject = "";
        const names = [];
        for (const sub of subjects)
            for (const n of [sub.name, sub.untis])
                if (n)
                    names.push({ n, untis: sub.untis || sub.name });
        names.sort((a, b) => b.n.length - a.n.length);
        for (const c of names)
            if (take(word(esc(c.n)))) {
                subject = c.untis;
                break;
            }

        // Due date: 2026-11-21, 21.11.2026, 21.11., today/tomorrow, or a weekday.
        let due = 0;
        let m;
        if ((m = take(date("(\\d{4})-(\\d{1,2})-(\\d{1,2})")))) {
            due = Number(m[1]) * 10000 + Number(m[2]) * 100 + Number(m[3]);
        } else if ((m = take(date("(\\d{1,2})\\.(\\d{1,2})\\.(\\d{4}|\\d{2})?", "[\\s,;:!?)]")))) {
            const year = m[3] ? (m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])) : Math.floor(today / 10000);
            due = year * 10000 + Number(m[2]) * 100 + Number(m[1]);
            // Without a year, a date that has passed means next year's.
            if (!m[3] && due < today)
                due += 10000;
        } else if (take(date("(?:übermorgen|uebermorgen)"))) {
            due = addDays(today, 2);
        } else if (take(date("(?:morgen|tomorrow)"))) {
            due = addDays(today, 1);
        } else if (take(date("(?:heute|today)"))) {
            due = today;
        } else {
            const days = [["sonntag", "sunday"], ["montag", "monday"], ["dienstag", "tuesday"], ["mittwoch", "wednesday"], ["donnerstag", "thursday"], ["freitag", "friday"], ["samstag", "saturday"]];
            for (let i = 0; i < 7 && !due; i++)
                if (take(date(`(?:${days[i].join("|")})`))) {
                    // The coming one; today's weekday means next week.
                    due = addDays(today, (i - toDate(today).getDay() + 7) % 7 || 7);
                }
        }
        // Only real dates (no 31.02.).
        if (due && dateInt(toDate(due)) !== due)
            due = 0;

        let guessed = false;
        if (!due && subject) {
            const next = lessons.find(l => l.date > today && !l.cancelled && l.subject.toLowerCase() === subject.toLowerCase());
            if (next) {
                due = next.date;
                guessed = true;
            }
        }
        return { exam, subject, due, guessed, text: text.replace(/\s+/g, " ").replace(/^[\s,;:\-–]+|[\s,;:\-–]+$/g, "") };
    }

    function isoDate(n: int): string {
        return `${Math.floor(n / 10000)}-${String(Math.floor(n / 100) % 100).padStart(2, "0")}-${String(n % 100).padStart(2, "0")}`;
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
        if (n === addDays(today, -1))
            return "Yesterday";
        const d = toDate(n);
        return n > today && n < addDays(today, 7) ? Qt.formatDate(d, "dddd") : Qt.formatDate(d, "ddd d MMM");
    }

    // The previous or next school day (weekends skipped), fetching its week if needed.
    function step(direction: int): void {
        let d = addDays(viewDate || today, direction);
        while ([0, 6].includes(toDate(d).getDay()))
            d = addDays(d, direction);
        selectedDate = d;
        if (!loaded[d])
            loadWeek(d);
    }

    function loadWeek(d: int): void {
        if (!configured || loadingWeek)
            return;
        const monday = addDays(d, -((toDate(d).getDay() + 6) % 7));
        loadingWeek = true;
        session((cookie, element, done) => timetable(cookie, element, monday, addDays(monday, 6), done), () => loadingWeek = false);
    }

    // Logs in, runs work(cookie, element, done) and logs out once work calls done.
    function session(work: var, finished: var): void {
        rpc("", "authenticate", { user: root.username, password: password, client: "moqs" }, auth => {
            const cookie = `JSESSIONID=${auth.sessionId}; schoolname="_${Qt.btoa(root.school)}"`;
            // Students see their own timetable; other accounts fall back to their class.
            const element = auth.personId ? { id: auth.personId, type: auth.personType } : { id: auth.klasseId, type: 1 };
            work(cookie, element, () => {
                rpc(cookie, "logout", {}, () => {});
                finished();
            });
        }, finished);
    }

    // Fetches the lessons from start to end and puts them in place of those days' old ones.
    function timetable(cookie: string, element: var, start: int, end: int, done: var): void {
        rpc(cookie, "getTimetable", {
            options: {
                element,
                startDate: start,
                endDate: end,
                showLsText: true,
                showSubstText: true,
                showInfo: true,
                subjectFields: ["name", "longname"],
                teacherFields: ["name"],
                roomFields: ["name"]
            }
        }, res => {
            lessons = lessons.filter(l => l.date < start || l.date > end).concat(merge(res ?? [])).sort((a, b) => a.date - b.date || a.start - b.start);
            const marks = Object.assign({}, loaded);
            for (let d = start; d <= end; d = addDays(d, 1))
                marks[d] = true;
            loaded = marks;
            const names = Object.assign({}, subjectNames);
            for (const l of res ?? [])
                for (const su of l.su ?? [])
                    if (su.name && su.longname && !names[su.name])
                        names[su.name] = su.longname;
            subjectNames = names;
            done();
        }, done);
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
        session((cookie, element, done) => {
            let pending = 4;
            const finish = () => {
                if (--pending === 0)
                    done();
            };
            // From a week back, for browsing to past days.
            timetable(cookie, element, addDays(today, -7), addDays(today, Config.webuntis.days), finish);
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
            // Students see their own exams; other accounts their class's.
            const who = element.type === 5 ? `studentId=${element.id}&klasseId=-1` : `studentId=-1&klasseId=${element.id}`;
            rest(cookie, `/WebUntis/api/exams?startDate=${today}&endDate=${addDays(today, Config.webuntis.examDays)}&${who}&withGrades=true`, res => {
                const list = res?.data?.exams;
                if (Array.isArray(list))
                    remoteExams = list.filter(e => e.examDate >= today).map(e => ({
                        key: e.id ? String(e.id) : `${e.examDate}:${e.subject ?? ""}:${e.name ?? ""}`.replace(/\s+/g, "_"),
                        subject: e.subject ?? "",
                        name: (e.name || e.examType || "").trim(),
                        text: (e.text ?? "").trim(),
                        date: e.examDate,
                        start: e.startTime ?? 0
                    }));
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
            cancelled: l.code === "cancelled" || (l.ro ?? []).some(r => root.cancelledRooms.includes(String(r.name ?? "").toLowerCase())),
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
        const lines = [`url = ${quote(`${url}/WebUntis/jsonrpc.do?school=${encodeURIComponent(root.school)}`)}`, `header = "Content-Type: application/json"`, `data = ${quote(body)}`];
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

    // Local homework file. One entry per line, "[ ]" to do and "[x]" done:
    //   [ ] 2026-11-21 | Englisch | S. 42 Nr. 3
    // Date and subject may be empty ("[ ] - | | text"), or left out for plain "[ ] text".
    // "[x] untis:<id>" ticks off a WebUntis homework; anything after the id is a reminder.
    // Exams have the learning progress in the brackets, own ones the same fields as homework:
    //   [exam 40%] 2026-12-03 | Mathematik | Kurvendiskussion
    //   [exam 60%] untis:<key>
    function parseHomework(text: string): void {
        const local = [];
        const marks = {};
        const exams = [];
        const progress = {};
        for (const line of text.split("\n")) {
            const x = line.match(/^\s*\[exam(?:\s+(\d+)%?)?\]\s?(.*)$/i);
            if (x) {
                const p = Math.max(0, Math.min(100, Number(x[1] ?? 0)));
                const remote = x[2].match(/^untis:(\S+)/);
                const parts = x[2].match(/^\s*(\d{4}-\d{2}-\d{2})\s*\|\s*(.*?)\s*\|\s*(.*)$/);
                if (remote)
                    progress[remote[1]] = p;
                else if (parts)
                    exams.push({ date: Number(parts[1].replace(/-/g, "")), subject: parts[2], text: parts[3].trim(), progress: p });
                continue;
            }
            const m = line.match(/^\s*\[([ xX])\]\s?(.*)$/);
            if (!m)
                continue;
            const done = m[1] !== " ";
            const remote = m[2].match(/^untis:(\S+)/);
            if (remote) {
                if (done)
                    marks[remote[1]] = true;
            } else if (m[2].trim()) {
                const parts = m[2].match(/^\s*(\d{4}-\d{2}-\d{2}|-)?\s*\|\s*(.*?)\s*\|\s*(.*)$/);
                const due = parts?.[1] && parts[1] !== "-" ? Number(parts[1].replace(/-/g, "")) : 0;
                local.push(parts ? { text: parts[3].trim(), subject: parts[2], due, done } : { text: m[2].trim(), subject: "", due: 0, done });
            }
        }
        localHomework = local;
        ticked = marks;
        localExams = exams;
        examProgress = progress;
    }

    function saveHomework(): void {
        const lines = ["# moqs homework. One per line, \"[ ]\" to do and \"[x]\" done: \"[ ] 2026-11-21 | Englisch | S. 42 Nr. 3\".", "# \"[x] untis:<id>\" ticks off a WebUntis homework.", "# Exams with how far the learning is: \"[exam 40%] 2026-12-03 | Mathematik | Kurvendiskussion\", \"[exam 40%] untis:<key>\".", ...localHomework.map(h => `[${h.done ? "x" : " "}] ${h.due ? isoDate(h.due) : "-"} | ${h.subject.replace(/\|/g, "/")} | ${h.text}`)];
        for (const id of Object.keys(ticked)) {
            const h = remoteHomework.find(r => r.id === id);
            lines.push(`[x] untis:${id}${h ? `  ${[h.subject, h.text].filter(x => x).join(": ").replace(/\s+/g, " ").slice(0, 80)}` : ""}`);
        }
        for (const e of localExams)
            lines.push(`[exam ${e.progress}%] ${isoDate(e.date)} | ${e.subject.replace(/\|/g, "/")} | ${e.text}`);
        for (const key of Object.keys(examProgress)) {
            const e = remoteExams.find(r => r.key === key);
            // Exams that have passed drop out once WebUntis no longer lists them.
            if (e || Number(key.slice(0, 8)) >= today || !/^\d{8}:/.test(key))
                lines.push(`[exam ${examProgress[key]}%] untis:${key}${e ? `  ${[longName(e.subject), e.name].filter(x => x).join(": ")}` : ""}`);
        }
        homeworkFile.setText(lines.join("\n") + "\n");
    }

    // Adds an entry from typed text; false (and nothing added) without a subject or date.
    function addHomework(input: string): bool {
        const e = parseEntry(input);
        if (!e.subject || !e.due)
            return false;
        if (e.exam) {
            localExams = [...localExams, { text: e.text, subject: e.subject, date: e.due, progress: 0 }];
            saveHomework();
            return true;
        }
        localHomework = [{ text: e.text, subject: e.subject, due: e.due, done: false }, ...localHomework];
        saveHomework();
        return true;
    }

    function removeHomework(index: int): void {
        localHomework = localHomework.filter((_, i) => i !== index);
        saveHomework();
    }

    function removeExam(index: int): void {
        localExams = localExams.filter((_, i) => i !== index);
        saveHomework();
    }

    // Sets how far the learning for an exam (an entry of exams) is, 0..100.
    function setExamProgress(exam: var, value: int): void {
        value = Math.max(0, Math.min(100, Math.round(value)));
        if (exam.local) {
            localExams = localExams.map((e, i) => i === exam.index ? Object.assign({}, e, { progress: value }) : e);
        } else {
            const p = Object.assign({}, examProgress);
            p[exam.key] = value;
            examProgress = p;
        }
        saveHomework();
    }

    function toggle(entry: var): void {
        if (entry.local) {
            localHomework = localHomework.map((h, i) => i === entry.index ? Object.assign({}, h, { done: !h.done }) : h);
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

    Secret {
        id: urlSecret

        what: "the WebUntis URL"
        path: settings.urlFile
    }

    Secret {
        id: schoolSecret

        what: "the WebUntis school"
        path: settings.schoolFile
    }

    Secret {
        id: usernameSecret

        what: "the WebUntis username"
        path: settings.usernameFile
    }

    FileView {
        path: Quickshell.shellPath("webuntis.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string url
            property string urlFile
            property string school
            property string schoolFile
            property string username
            property string usernameFile
            property string password
            property string passwordCommand
            property string homeworkFile
            property var cancelledRooms: []
            property var subjects: []

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
