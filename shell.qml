//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import qs.config
import qs.modules

ShellRoot {
    Variants {
        model: Quickshell.screens

        Frame {}
    }

    // Let windows sit flush against the frame.
    Process {
        running: true
        command: ["hyprctl", "eval", `hl.config({ general = { gaps_out = ${Config.hyprland.gapsOut} } })`]
    }
}
