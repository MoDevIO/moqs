//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import qs.config
import qs.modules
import qs.modules.lock
import qs.modules.vocab

ShellRoot {
    Variants {
        model: Quickshell.screens

        Frame {}
    }

    LockScreen {}

    // Steam games wait behind a vocabulary word.
    GameGateScreen {}

    // One shell at a time: two would each reserve the frame's space, doubling the margins.
    // The newest wins, so starting a copy (qs -p .) replaces the installed one and a rebuild
    // starting the service replaces the copy. Another moqs is known by this marker line:
    // moqs-single-instance. The service is stopped rather than killed, so systemd doesn't
    // bring it back. MOQS_ALLOW_DUPLICATE=1 skips this, for side-by-side test copies.
    Process {
        running: Quickshell.env("MOQS_ALLOW_DUPLICATE") !== "1"
        command: ["sh", "-c", `
            service=$(systemctl --user show quickshell -p MainPID --value 2>/dev/null)
            qs list --all 2>/dev/null | sed -n 's/^ *Process ID: //p; s/^ *Config path: //p' | paste - - |
            while IFS="$(printf '\\t')" read -r pid path; do
                [ "$pid" = "$1" ] && continue
                grep -qs moqs-single-instance "$path" || continue
                if [ "$pid" = "$service" ]; then
                    systemctl --user stop quickshell
                else
                    kill "$pid"
                fi
            done`, "sh", String(Quickshell.processId)]
    }

    // Let windows sit flush against the frame.
    Process {
        running: true
        command: ["hyprctl", "eval", `hl.config({ general = { gaps_out = ${Config.hyprland.gapsOut} } })`]
    }
}
