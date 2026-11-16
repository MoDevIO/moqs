pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// AirDrop through the owly CLI. The radio itself (awdl0) is held up by owlyd/owly-radio.service.
Singleton {
    id: root

    property bool radioUp: false
    readonly property alias receiving: receiver.running
    property string error: ""

    // Nearby AirDrop receivers: [{ name, addr }]
    property var devices: []
    // Set by the UI while nearby devices should be looked for.
    property bool browse: false
    readonly property bool browsing: browser.running

    // Sending: the device picked in the control centre, { name, addr }, or null.
    property var target: null
    // idle, sending, delivered, declined, failed
    property string sendState: "idle"
    property string sendDetail: ""

    // Files take priority; links are only sent when no files were given.
    function send(files: var, urls: var): void {
        if (!target || sender.running || (files.length === 0 && urls.length === 0))
            return;
        const cmd = ["owly", "send", "--to", target.name];
        if (files.length > 0)
            cmd.push("--", ...files);
        else
            for (const u of urls)
                cmd.push("--url", u);
        sender.to = target.name;
        sender.error = "";
        sender.command = cmd;
        sendState = "sending";
        sendDetail = `Looking for ${target.name}…`;
        sender.running = true;
    }

    function pick(device: var): void {
        target = device;
        if (!sender.running)
            sendState = "idle";
    }

    // A send already under way carries on and reports through a notification.
    function closeSend(): void {
        target = null;
        if (!sender.running)
            sendState = "idle";
    }

    function setReceiving(on: bool): void {
        error = "";
        receiver.running = on;
    }

    // Rust Debug-formatted string contents -> plain text.
    function unquote(s: string): string {
        return s.replace(/\\u\{([0-9a-fA-F]+)\}/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
            .replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\(["'\\])/g, "$1");
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: root.browse ? 2000 : 10000
        onTriggered: radioCheck.running = true
    }

    Process {
        id: radioCheck

        command: ["test", "-d", "/sys/class/net/awdl0"]
        onExited: code => {
            root.radioUp = code === 0;
            if (!root.radioUp)
                root.devices = [];
        }
    }

    // Receiving

    Process {
        id: receiver

        property var request: null

        command: ["owly", "receive", "--dir", `${Quickshell.env("HOME")}/Downloads`]
        stdinEnabled: true

        // Received file paths and links.
        stdout: SplitParser {
            onRead: line => {
                const url = line.match(/^"(.*)"$/);
                if (url)
                    linkPrompt.createObject(root, { link: root.unquote(url[1]) });
                else
                    notify.exec(["notify-send", "-a", "AirDrop", "-i", "document-save", "File received", line]);
            }
        }

        stderr: SplitParser {
            onRead: line => {
                const ask = line.match(/^"(.*)" \("(.*)"\) wants to send:$/);
                if (ask) {
                    receiver.request = { sender: root.unquote(ask[1]), items: [] };
                    askDelay.restart();
                    return;
                }
                const item = line.match(/^  "((?:[^"\\]|\\.)*)"/);
                if (item && receiver.request) {
                    receiver.request.items.push(root.unquote(item[1]));
                    return;
                }
                if (line.includes("timed out") || line.includes("withdrawn")) {
                    prompt.answered = true;
                    prompt.running = false;
                } else if (line.startsWith("owly: ")) {
                    root.error = line.slice(6);
                }
            }
        }

        onExited: request = null
    }

    // Item lines arrive right after the request line; ask once they're in.
    Timer {
        id: askDelay

        interval: 150
        onTriggered: {
            const r = receiver.request;
            if (!r)
                return;
            prompt.answered = false;
            // Owly declines by itself after 15 s; the prompt is transient and expires with it.
            prompt.command = ["notify-send", "-a", "AirDrop", "-i", "document-send", "-e", "-t", "15000",
                "-A", "accept=Accept", "-A", "decline=Decline", `${r.sender} wants to send`, r.items.join("\n")];
            prompt.running = true;
        }
    }

    Process {
        id: prompt

        property bool answered: true

        stdout: StdioCollector {
            onStreamFinished: {
                if (prompt.answered || !receiver.running)
                    return;
                prompt.answered = true;
                receiver.write(text.trim() === "accept" ? "y\n" : "n\n");
            }
        }
    }

    Process {
        id: notify
    }

    // A received link, with Open and Copy buttons. notify-send waits for the click and prints it.
    Component {
        id: linkPrompt

        Process {
            id: prompt

            required property string link

            running: true
            command: ["notify-send", "-a", "AirDrop", "-i", "document-save", "-A", "open=Open", "-A", "copy=Copy", "Link received", link]
            stdout: StdioCollector {
                onStreamFinished: {
                    const action = text.trim();
                    if (action === "open")
                        Qt.openUrlExternally(prompt.link);
                    else if (action === "copy")
                        // wl-copy rather than Quickshell.clipboardText: Wayland only lets a focused
                        // window set the clipboard, and the shell usually isn't focused.
                        Quickshell.execDetached(["wl-copy", "--", prompt.link]);
                }
            }
            onExited: destroy()
        }
    }

    Process {
        id: sender

        property string to
        property string error

        stderr: SplitParser {
            onRead: line => {
                if (line.startsWith("sending to"))
                    root.sendDetail = `Waiting for ${sender.to} to accept…`;
                else if (line === "accepted")
                    root.sendDetail = "Sending…";
                else if (line.startsWith("owly: "))
                    sender.error = line.slice(6);
            }
        }

        // delivered | declined | failed: reason
        stdout: SplitParser {
            onRead: line => {
                if (line === "delivered")
                    root.finishSend("delivered", `Sent to ${sender.to}`);
                else if (line === "declined")
                    root.finishSend("declined", `${sender.to} declined`);
                else if (line.startsWith("failed: "))
                    root.finishSend("failed", line.slice(8));
            }
        }

        onExited: if (root.sendState === "sending") root.finishSend("failed", error || "Couldn't send")
    }

    function finishSend(state: string, detail: string): void {
        sendState = state;
        sendDetail = detail;
        // With the panel closed, tell the user some other way.
        if (!target)
            notify.exec(["notify-send", "-a", "AirDrop", "-i", "document-send", "AirDrop", detail]);
        else
            sendReset.restart();
    }

    // Back to "drop here" after showing the result.
    Timer {
        id: sendReset

        interval: 4000
        onTriggered: if (root.sendState !== "sending") root.sendState = "idle"
    }

    // Browsing

    Timer {
        running: root.browse && root.radioUp && !browser.running
        interval: 1500
        triggeredOnStart: true
        onTriggered: browser.running = true
    }

    Process {
        id: browser

        property var found: []

        command: ["owly", "browse", "--seconds", "8"]
        onStarted: found = []

        // instance "Name" (addr)
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^(\S+)\s+"(.*)" \((.*)\)$/);
                if (!m)
                    return;
                const dev = { name: root.unquote(m[2]), addr: m[3] };
                browser.found.push(dev);
                if (!root.devices.some(d => d.addr === dev.addr))
                    root.devices = [...root.devices, dev];
            }
        }

        // Keep only what answered this round.
        onExited: root.devices = found
    }
}
