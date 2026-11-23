pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU and RAM usage from /proc, 0..1, and the network's download and upload rates in bytes
// per second, over the wired, Wi-Fi and mobile interfaces.
Singleton {
    id: root

    property real cpu: 0
    property real ram: 0

    property real rx: 0
    property real tx: 0

    property real lastTotal: 0
    property real lastIdle: 0
    property real lastRx: -1
    property real lastTx: -1
    property real lastNet: 0

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 2000
        onTriggered: {
            stat.reload();
            meminfo.reload();
            netdev.reload();
        }
    }

    FileView {
        id: stat

        path: "/proc/stat"
        onLoaded: {
            // cpu  user nice system idle iowait irq softirq steal ...
            const fields = text().split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number);
            const total = fields.reduce((a, b) => a + b, 0);
            const idle = fields[3] + fields[4];
            const dTotal = total - root.lastTotal;
            if (root.lastTotal > 0 && dTotal > 0)
                root.cpu = Math.max(0, Math.min(1, 1 - (idle - root.lastIdle) / dTotal));
            root.lastTotal = total;
            root.lastIdle = idle;
        }
    }

    FileView {
        id: netdev

        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0;
            let tx = 0;
            for (const line of text().split("\n").slice(2)) {
                const m = line.match(/^\s*([^:\s]+):\s*(.*)$/);
                if (!m || !/^(en|eth|wl|ww|usb)/.test(m[1]))
                    continue;
                const f = m[2].trim().split(/\s+/).map(Number);
                rx += f[0];
                tx += f[8];
            }
            const now = Date.now();
            const secs = (now - root.lastNet) / 1000;
            if (root.lastRx >= 0 && secs > 0) {
                root.rx = Math.max(0, (rx - root.lastRx) / secs);
                root.tx = Math.max(0, (tx - root.lastTx) / secs);
            }
            root.lastRx = rx;
            root.lastTx = tx;
            root.lastNet = now;
        }
    }

    FileView {
        id: meminfo

        path: "/proc/meminfo"
        onLoaded: {
            const total = Number(text().match(/MemTotal:\s+(\d+)/)?.[1] ?? 0);
            const available = Number(text().match(/MemAvailable:\s+(\d+)/)?.[1] ?? 0);
            if (total > 0)
                root.ram = 1 - available / total;
        }
    }
}
