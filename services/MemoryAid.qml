pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Memory aids for vocabulary, suggested by a language model behind an OpenAI-compatible
// chat completions API (a local llama.cpp, Ollama or vLLM server, or any hosted one).
// Settings come from aids.json next to shell.qml:
//   { "url": "http://localhost:11434/v1", "model": "llama3.1:8b",
//     "apiKeyCommand": "pass show llm", "language": "German" }
// "apiKey" works instead of "apiKeyCommand"; neither is needed for a server without keys.
// "language" is what the aids are written in; without it, the translation's language.
//
// The request goes through curl with the key on stdin (curl -K -), which keeps it out of the
// process list. Only the word, its translation, its note and, after a mix-up, the other
// word are sent.
Singleton {
    id: root

    readonly property string url: settings.url.replace(/\/+$/, "").replace(/\/chat\/completions$/, "")
    readonly property bool configured: url !== "" && settings.model !== ""
    readonly property string apiKey: settings.apiKey || commandKey
    property string commandKey

    // The suggestion for the word with key `key`, while loading, and why it failed.
    property string key
    property string suggestion
    property bool loading
    property string error
    // Bumped per request, so an answer to an old one is dropped.
    property int request

    // Asks for a memory aid for `item` (see Vocab.items); `confused` is a card mixed up with
    // it, or null.
    function suggest(item: var, confused: var): void {
        if (!configured || !item)
            return;
        const id = ++request;
        key = item.key;
        suggestion = "";
        error = "";
        loading = true;
        const card = item.card;
        const facts = [`Word: ${card.front}`, `Meaning: ${card.back}`];
        if (card.hint)
            facts.push(`Notes: ${card.hint}`);
        if (card.section)
            facts.push(`From: ${card.section}`);
        if (card.aid)
            facts.push(`Current memory aid, which didn't work, so write a different one: ${card.aid}`);
        if (confused)
            facts.push(`The learner mixed it up with: ${confused.front} = ${confused.back}. Help tell the two apart.`);
        const language = settings.language || "the language of the meaning";
        const body = JSON.stringify({
            model: settings.model,
            temperature: 0.8,
            max_tokens: 400,
            messages: [
                {
                    role: "system",
                    content: `You write memory aids (mnemonics) for a learner who keeps forgetting a vocabulary word. Reply with one memory aid only: at most two short sentences, no preamble, no quotes, no markdown. Good aids: a word in German or English derived from it or sharing its root (e.g. Latin dēcipere → English deception), or a vivid, slightly absurd picture linking how the word sounds to what it means. Never invent false etymology; if you aren't sure of a derivation, use a sound-alike picture instead. Write in ${language}.`
                },
                {
                    role: "user",
                    content: facts.join("\n")
                }
            ]
        });
        const lines = [`url = ${quote(`${url}/chat/completions`)}`, `header = "Content-Type: application/json"`, `data = ${quote(body)}`];
        if (apiKey)
            lines.push(`header = ${quote(`Authorization: Bearer ${apiKey}`)}`);
        call.createObject(root, { config: lines.join("\n") + "\n", id });
    }

    function clear(): void {
        request++;
        key = "";
        suggestion = "";
        error = "";
        loading = false;
    }

    function quote(s: string): string {
        return `"${String(s).replace(/(["\\])/g, "\\$1").replace(/\n/g, "\\n")}"`;
    }

    // The aid in a reply: without a model's thinking, quotes or labels, on one line.
    function tidy(text: string): string {
        const quotes = /^["„“”'«»]+|["„“”'«»]+$/g;
        return text.replace(/<think>[\s\S]*?<\/think>/g, "").replace(/^[\s\S]*<\/think>/, "").replace(/\*+|__|`/g, "").replace(/\s+/g, " ").trim().replace(quotes, "").replace(/^(memory aid|mnemonic|eselsbrücke|merkhilfe)\s*:\s*/i, "").replace(quotes, "").trim().slice(0, 300);
    }

    Component {
        id: call

        Process {
            id: proc

            required property string config
            required property int id

            command: ["curl", "-sS", "--max-time", "60", "-K", "-"]
            stdinEnabled: true
            running: true

            onStarted: {
                write(config);
                stdinEnabled = false;
            }

            stdout: StdioCollector {
                onStreamFinished: {
                    if (proc.id !== root.request)
                        return;
                    root.loading = false;
                    let res = null;
                    try {
                        res = JSON.parse(text);
                    } catch (e) {}
                    const content = res?.choices?.[0]?.message?.content;
                    const aid = typeof content === "string" ? root.tidy(content) : "";
                    if (aid)
                        root.suggestion = aid;
                    else
                        root.error = res?.error?.message ?? res?.error ?? (errors.text.trim().replace(/^curl: \(\d+\) /, "") || "No memory aid in the answer");
                }
            }

            stderr: StdioCollector {
                id: errors
            }

            onExited: destroy()
        }
    }

    FileView {
        path: Quickshell.shellPath("aids.json")
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
