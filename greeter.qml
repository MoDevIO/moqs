import Quickshell
import qs.config
import qs.modules.greeter

// The login screen, run by greetd instead of the shell (see services.moqs.greeter in the
// NixOS module): quickshell -p greeter.qml, inside a kiosk compositor such as cage.
ShellRoot {
    FloatingWindow {
        title: "moqs greeter"
        color: Config.border.colour

        GreeterContent {
            anchors.fill: parent
        }
    }
}
