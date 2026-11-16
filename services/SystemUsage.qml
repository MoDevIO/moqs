pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU and RAM usage from /proc, 0..1.
Singleton {
    id: root

    property real cpu: 0
    property real ram: 0

    property real lastTotal: 0
    property real lastIdle: 0

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 2000
        onTriggered: {
            stat.reload();
            meminfo.reload();
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
