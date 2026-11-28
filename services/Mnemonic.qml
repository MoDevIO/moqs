pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Mnemonics for vocabulary, suggested by a language model behind an OpenAI-compatible
// chat completions API (a local llama.cpp, Ollama or vLLM server, or any hosted one).
// Settings come from ai.json next to shell.qml (services.moqs.ai; the launcher's Assistant
// uses them too):
//   { "url": "http://localhost:11434/v1", "model": "llama3.1:8b",
//     "apiKeyCommand": "pass show llm", "language": "German", "prepareModel": "" }
// "apiKey" works instead of "apiKeyCommand"; neither is needed for a server without keys.
// "language" is what the mnemonics are written in; without it, the translation's language.
//
// Suggestions are asked for on request (suggest()). The model writes little scenes: an
// everyday German word that sounds like the start of the Latin one meets its meaning
// ("Ich zeige auf ein Monster": monstrare = zeigen). It can't hear what words sound like, so
// SoundAlike finds those words, and the model only builds the pictures.
//
// For words missed again and again (Config.vocab.prepareMisses), suggestions are also
// prepared ahead, one word at a time in the background with "prepareModel" (or "model"),
// and kept in mnemonics-cache.json in the vocabulary's folder, so asking shows them at once;
// "Other ideas" asks live.
//
// Every reply, prepared suggestions shown and every mnemonic kept (suggested or one's own) are
// appended to mnemonics-log.jsonl in the vocabulary's folder (see log()), for seeing later
// what works.
//
// The request goes through curl with the key on stdin (curl -K -), which keeps it out of the
// process list. Sent: the word, its translation and note, the sound-alike words, the
// mnemonics kept lately (from the log), and after a mix-up the other word.
Singleton {
    id: root

    readonly property string url: settings.url.replace(/\/+$/, "").replace(/\/chat\/completions$/, "")
    readonly property bool configured: url !== "" && settings.model !== ""
    // The model asked; the launcher's assistant (Assistant) asks it too.
    readonly property string model: settings.model
    readonly property string apiKey: settings.apiKey || commandKey
    property string commandKey

    // The suggestions for the word with key `key`, to pick one from, while loading, and
    // why it failed.
    property string key
    property var suggestions: []
    property bool loading
    property string error
    // The suggestions turned down for this word ("Other ideas"), sent along so the next
    // aren't the same ideas again.
    property var turnedDown: []
    // Bumped per request, so an answer to an old one is dropped.
    property int request

    // How many suggestions to show, and to ask for: some are dropped (see parse()).
    readonly property int count: 4
    readonly property int ask: 6

    // Prepared suggestions, by cardKey(): { "<front>\u0001<back>": { v, list: [mnemonic, …] } }.
    // Older ones (a bare list, or a lower v) still show, and are prepared again.
    property var prepared: ({})
    readonly property string cachePath: `${Vocab.stateDir}/mnemonics-cache.json`
    // The card being prepared, or "".
    property string preparing

    function cardKey(card: var): string {
        return `${card.front}\u0001${card.back}`;
    }

    // How suggestions are prepared now (6: scenes around sound-alike words, or a word from
    // the same root, with the mnemonics kept lately); those from an
    // older way are prepared again.
    readonly property int version: 6

    // The suggestions prepared for `card`, or [].
    function preparedFor(card: var): var {
        const e = card ? prepared[cardKey(card)] : null;
        return Array.isArray(e) ? e : e?.list ?? [];
    }

    // Whether suggestions for `card` are ready to show.
    function ready(card: var): bool {
        return preparedFor(card).length > 0;
    }

    // Suggests mnemonics for `item` (see VocabSession.item): the prepared ones if there are,
    // otherwise (and when asked again for the same word) from the model. `confused` is a card
    // mixed up with it, or null.
    function suggest(item: var, confused: var): void {
        if (!configured || !item)
            return;
        // Asked again for the same word: what was shown is turned down; another word starts
        // afresh.
        const again = key === item.key && suggestions.length > 0;
        if (again)
            turnedDown = [...turnedDown.filter(x => !suggestions.includes(x)), ...suggestions].slice(-12);
        else if (key !== item.key)
            turnedDown = [];
        const id = ++request;
        key = item.key;
        suggestions = [];
        error = "";
        const ready = preparedFor(item.card);
        if (!again && !confused && ready.length) {
            suggestions = ready;
            loading = false;
            log({ event: "shown", source: "prepared", word: item.card.front, meaning: item.card.back, shown: ready });
            return;
        }
        loading = true;
        const words = keywords(item.card, turnedDown);
        call.createObject(root, {
            config: config(item.card, confused, turnedDown, settings.model, words),
            id,
            card: "",
            retries: 1,
            meta: { source: again ? "again" : "live", word: item.card.front, meaning: item.card.back, keywords: words, model: settings.model, confused: confused ? `${confused.front} = ${confused.back}` : undefined, turnedDown: turnedDown.length ? turnedDown : undefined, started: Date.now() }
        });
    }

    // Keeping a mnemonic, `text` ("" when removed): logged, and what was prepared for the word
    // is done with. `own` when typed rather than picked from the suggestions.
    function kept(card: var, text: string, own: bool): void {
        const shown = key.startsWith(`${cardKey(card)}\u0001`) ? suggestions : [];
        if (text)
            keptLately = [...keptLately, { word: card.front, mnemonic: text }].slice(-20);
        log({ event: text ? "kept" : "removed", own, word: card.front, meaning: card.back, mnemonic: text || undefined, index: own ? undefined : shown.indexOf(text), shown: shown.length ? shown : undefined });
        if (!ready(card))
            return;
        const p = Object.assign({}, prepared);
        delete p[cardKey(card)];
        prepared = p;
        saveCache();
    }

    function clear(): void {
        request++;
        key = "";
        turnedDown = [];
        suggestions = [];
        error = "";
        loading = false;
    }

    // "frei sein (von etw.), (etw.) nicht haben" → ["fre", "nic", "hab"]: the meaning's words
    // without their endings, umlauts and a split-off prefix, so "versieht" counts for
    // "versehen" ("vers"), "hält … fern" for "fernhalten" ("hal"), "Rate" for "raten".
    // Articles and notes in brackets don't count.
    readonly property var separable: ["zurück", "nieder", "heraus", "herbei", "hinaus", "voran", "vorbei", "weiter", "zusammen", "weg", "fern", "fest", "frei", "auf", "aus", "bei", "ein", "mit", "nach", "vor", "dar", "her", "hin", "los", "ab", "an", "zu", "um"]

    function meaningStems(back: string): var {
        const skip = ["der", "die", "das", "dem", "den", "des", "ein", "eine", "einen", "etwas", "sich", "sein", "werden", "the", "to", "be"];
        return (fold(String(back).replace(/\([^)]*\)/g, " ")).match(/[a-zß]{3,}/g) ?? []).filter(w => !skip.includes(w)).map(w => {
            const p = separable.find(p => w.startsWith(p) && w.length - p.length >= 4);
            if (p)
                w = w.slice(p.length);
            return w.slice(0, Math.max(3, w.length - 4));
        });
    }

    // Lower case, without umlauts: "Hält" → "halt".
    function fold(s: string): string {
        return s.toLowerCase().replace(/ä/g, "a").replace(/ö/g, "o").replace(/ü/g, "u");
    }

    // ---- The request

    // The sound-alike words for `card`: more of them when asked again, without those
    // already offered.
    function keywords(card: var, down: var): var {
        const offered = down.join(" ").toLowerCase();
        return SoundAlike.find(card.front, down.length ? 12 : 8, []).filter(w => !down.length || !offered.includes(w.toLowerCase())).slice(0, 8);
    }

    // curl's config for suggestions for `card`.
    function config(card: var, confused: var, down: var, model: string, words: var): string {
        const facts = [`Word: ${card.front}`, `Meaning: ${card.back}`];
        if (card.hint)
            facts.push(`Notes: ${card.hint}`);
        facts.push(words.length ? `Sounds like: ${words.join(", ")}` : "Sounds like: (none found; use an everyday word that clearly sounds like its start)");
        const liked = keptLately.filter(k => k.word !== card.front).slice(-8);
        if (liked.length)
            facts.push(`Mnemonics the student picked or wrote lately, for their taste: ${liked.map(k => `${k.word.split(",")[0]}: ${k.mnemonic}`).join(" | ")}`);
        if (card.mnemonic)
            facts.push(`Current mnemonic, which didn't work, so write different ones: ${card.mnemonic}`);
        if (confused)
            facts.push(`The learner mixed it up with: ${confused.front} = ${confused.back}. At least one mnemonic should also tell the two apart.`);
        if (down.length)
            facts.push(`The learner turned these down. Write clearly different ones, with other words:\n${down.map(x => `- ${x}`).join("\n")}`);
        const language = settings.language || "the language of the meaning";
        // A little more variety once suggestions were turned down.
        return curlConfig(model, down.length ? 1.0 : 0.8, [
            "You write mnemonics (Eselsbrücken) for a school student learning vocabulary. Give a few different kinds, so the student can pick the one that clicks.",
            "",
            "1. First, if there is one: an English or German word the student already knows that really comes from this word. Just the word, or a few words with it, as short as possible:",
            "- restituere = wiederherstellen: restore",
            "- obtinēre = erlangen: obtain",
            "- contendere = sich anstrengen: Dieser Content ist echt anstrengend.",
            "Only if you're sure of the derivation; leave it out otherwise.",
            "",
            "2. Scenes. You get everyday words that sound like the word's start, found by sound alone, so some fit badly. Pick the ones that make the clearest pictures and write one short sentence for each, with one of those words and the word's main meaning (the first one) happening in a simple, everyday picture:",
            "- ōra = die Küste: Eine Orange rollt an die Küste.",
            "- mulier = die Frau: Die Frau trägt den Müll hinaus.",
            "- monstrare = zeigen: Ich zeige auf ein Monster.",
            "- ambulare = spazieren: Ich spaziere über die Ampel.",
            "One sound-alike word per sentence, no \"Word:\" in front. Skip names, places and words that make no picture. If you know an everyday word that sounds even more like the start, use it.",
            "",
            "Every mnemonic has the meaning in it, at most 8 words, nothing to explain. Don't repeat the vocabulary word or add \"word = meaning\": the student sees both already.",
            `Write in ${language}. Reply with JSON only: {"mnemonics": ["…"]}, best first, at most ${root.ask}.`
        ].join("\n"), facts.join("\n"));
    }

    // curl's config for a chat completion.
    function curlConfig(model: string, temperature: real, system: string, user: string): string {
        const body = JSON.stringify({
            model,
            temperature,
            // Room for models that think first (deepseek-v4.1-flash thinks for 3000–10000
            // tokens here); the answers themselves are short.
            max_tokens: 16000,
            messages: [
                {
                    role: "system",
                    content: system
                },
                {
                    role: "user",
                    content: user
                }
            ]
        });
        const lines = [`url = ${quote(`${url}/chat/completions`)}`, `header = "Content-Type: application/json"`, `data = ${quote(body)}`];
        if (apiKey)
            lines.push(`header = ${quote(`Authorization: Bearer ${apiKey}`)}`);
        return lines.join("\n") + "\n";
    }

    function quote(s: string): string {
        return `"${String(s).replace(/(["\\])/g, "\\$1").replace(/\n/g, "\\n")}"`;
    }

    // The mnemonics in a reply: its JSON list, or failing that its lines.
    function parse(text: string): var {
        text = text.replace(/<think>[\s\S]*?<\/think>/g, "").replace(/^[\s\S]*<\/think>/, "");
        let list = null;
        try {
            const j = JSON.parse(text.match(/\{[\s\S]*\}|\[[\s\S]*\]/)[0]);
            list = Array.isArray(j) ? j : j.mnemonics ?? j.best;
        } catch (e) {}
        if (!Array.isArray(list))
            list = text.split("\n").map(l => l.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, ""));
        const out = [];
        for (const x of list) {
            const t = tidy(String(x ?? ""));
            if (t && !out.includes(t))
                out.push(t);
        }
        return out;
    }

    // Those of `list` with the meaning `back` in them, at most `count`.
    function withMeaning(list: var, back: string): var {
        const stems = meaningStems(back);
        const fit = list.filter(t => !stems.length || stems.some(s => fold(t).includes(s)));
        // None with it, by this rough look: all of them rather than none.
        return (fit.length ? fit : list).slice(0, count);
    }

    // The last mnemonics kept, from the log: [{ word, mnemonic }], for the model to see the
    // learner's taste.
    property var keptLately: []

    FileView {
        path: root.logPath
        printErrors: false
        onLoaded: root.keptLately = text().split("\n").map(l => {
            try {
                return JSON.parse(l);
            } catch (e) {
                return null;
            }
        }).filter(e => e?.event === "kept" && e.mnemonic).map(e => ({
                    word: e.word,
                    mnemonic: e.mnemonic
                })).slice(-20)
    }

    // Appends `record` to mnemonics-log.jsonl, one JSON object a line, with the time.
    readonly property string logPath: `${Vocab.stateDir}/mnemonics-log.jsonl`

    function log(record: var): void {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" >> "$2"', "sh", JSON.stringify(Object.assign({ t: Date.now() }, record)), logPath]);
    }

    // A mnemonic: without markdown, quotes or labels, on one line.
    function tidy(text: string): string {
        const quotes = /^["„“”'«»]+|["„“”'«»]+$/g;
        return text.replace(/\*+|__|`/g, "").replace(/\s+/g, " ").trim().replace(quotes, "").replace(/^(mnemonic|eselsbrücke|merkhilfe)\s*:\s*/i, "").replace(quotes, "").trim().slice(0, 300);
    }

    // ---- Preparing ahead

    // Cards whose suggestions failed this session, so the queue doesn't retry them forever.
    property var failed: []

    // The next card to prepare: missed often, without a mnemonic, not prepared yet; the most
    // missed first.
    function nextToPrepare(): var {
        let best = null, most = 0;
        for (const c of Vocab.cards) {
            if (c.mnemonic || prepared[cardKey(c)]?.v >= version || failed.includes(cardKey(c)))
                continue;
            const m = Math.max(Vocab.missesOf(Vocab.sched[`${cardKey(c)}\u0001>`]), Vocab.missesOf(Vocab.sched[`${cardKey(c)}\u0001<`]));
            if (m >= Config.vocab.prepareMisses && m > most) {
                best = c;
                most = m;
            }
        }
        return best;
    }

    function prepareNext(): void {
        if (!configured || preparing || !cacheLoaded || !SoundAlike.available)
            return;
        const card = nextToPrepare();
        if (!card)
            return;
        preparing = cardKey(card);
        const model = settings.prepareModel || settings.model;
        const words = keywords(card, []);
        call.createObject(root, {
            config: config(card, null, [], model, words),
            id: -1,
            card: preparing,
            retries: 1,
            meta: { source: "prepare", word: card.front, meaning: card.back, keywords: words, model, started: Date.now() }
        });
    }

    function prepareDone(card: string, found: var): void {
        if (card !== preparing)
            return;
        preparing = "";
        if (found.length) {
            const p = Object.assign({}, prepared);
            p[card] = {
                v: version,
                list: found
            };
            prepared = p;
            saveCache();
        } else {
            failed = [...failed, card];
        }
    }

    function saveCache(): void {
        cache.setText(JSON.stringify(prepared, null, 1));
    }

    property bool cacheLoaded

    FileView {
        id: cache

        path: root.cachePath
        printErrors: false
        onLoaded: {
            try {
                root.prepared = JSON.parse(text()) ?? {};
            } catch (e) {}
            root.cacheLoaded = true;
        }
        onLoadFailed: root.cacheLoaded = true
    }

    // A word at a time, half a minute apart, so the server's limits stay far off.
    Timer {
        running: root.configured && root.cacheLoaded && root.preparing === "" && SoundAlike.available
        interval: 30000
        repeat: true
        onTriggered: root.prepareNext()
    }

    Component {
        id: call

        Process {
            id: proc

            required property string config
            required property int id
            // The card being prepared (see cardKey()), or "" for a suggestion asked for.
            required property string card
            // Tries left after a failure: servers fail now and then (vLLM's "EngineCore").
            required property int retries
            // What's logged with the reply (see log()).
            required property var meta

            command: ["curl", "-sS", "--max-time", "180", "-K", "-"]
            stdinEnabled: true
            running: true

            onStarted: {
                write(config);
                stdinEnabled = false;
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    // A suggestion asked for since: this one's no longer wanted.
                    if (!proc.card && proc.id !== root.request)
                        return;
                    let res = null;
                    try {
                        res = JSON.parse(text);
                    } catch (e) {}
                    const content = res?.choices?.[0]?.message?.content;
                    // A reply that hit the token limit stops mid-sentence: not a mnemonic.
                    const cut = res?.choices?.[0]?.finish_reason === "length";
                    const all = typeof content === "string" && !cut ? root.parse(content) : [];
                    const found = root.withMeaning(all, proc.meta.meaning);
                    const failure = found.length ? "" : res?.error?.message ?? res?.error ?? (cut ? "The answer was cut off" : errors.text.trim().replace(/^curl: \(\d+\) /, "") || "No mnemonics in the answer");
                    root.log(Object.assign({}, proc.meta, {
                        event: "generated",
                        started: undefined,
                        seconds: Math.round((Date.now() - proc.meta.started) / 100) / 10,
                        all,
                        shown: found,
                        error: failure || undefined
                    }));
                    const retry = !found.length && proc.retries > 0 && !cut;
                    if (retry) {
                        call.createObject(root, { config: proc.config, id: proc.id, card: proc.card, retries: proc.retries - 1, meta: Object.assign({}, proc.meta, { started: Date.now() }) });
                        return;
                    }
                    if (proc.card) {
                        root.prepareDone(proc.card, found);
                        return;
                    }
                    root.loading = false;
                    if (found.length)
                        root.suggestions = found;
                    else
                        root.error = failure;
                }
            }

            stderr: StdioCollector {
                id: errors
            }

            onExited: destroy()
        }
    }

    FileView {
        path: Quickshell.shellPath("ai.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: settings

            property string url
            property string model
            property string apiKey
            property string apiKeyCommand
            property string language
            property string prepareModel

            // Set the command here: a binding on it would update only after this handler runs.
            onApiKeyCommandChanged: {
                if (!apiKeyCommand)
                    return;
                keyProc.command = ["sh", "-c", apiKeyCommand];
                keyProc.running = true;
            }
        }
    }

    Process {
        id: keyProc

        stdout: StdioCollector {
            onStreamFinished: root.commandKey = text.split("\n")[0].trim()
        }
    }
}
