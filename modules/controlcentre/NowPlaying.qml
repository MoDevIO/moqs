import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.config
import qs.modules.music
import qs.services

// Media from any MPRIS player plus the shell's own Navidrome player. Shows what's playing,
// or the source picked with the switcher when there are several.
Rectangle {
    id: root

    // Every source as { key, name, player? }; no `player` means the Navidrome player.
    readonly property var sources: {
        const list = [];
        if (Player.current)
            list.push({ key: "moqs", name: "Navidrome" });
        for (const p of Mpris.players.values) {
            // playerctld only mirrors another player, and our own mpv is already the
            // Navidrome source.
            if (p.dbusName.endsWith(".playerctld") || p.dbusName.startsWith("org.mpris.MediaPlayer2.mpv.Navidrome."))
                continue;
            list.push({ key: p.dbusName, name: p.identity || "Player", player: p });
        }
        return list;
    }

    // Set by the switcher; otherwise whatever is playing wins.
    property string pinned
    readonly property var source: {
        const s = sources;
        return s.find(x => x.key === pinned) ?? s.find(x => isPlaying(x)) ?? s[0] ?? null;
    }
    readonly property var player: source?.player ?? null
    readonly property bool own: source?.key === "moqs"

    readonly property string title: own ? Player.current?.title ?? "" : player?.trackTitle ?? ""
    readonly property string artist: own ? Player.current?.artist ?? "" : player?.trackArtist ?? ""
    readonly property string art: own ? Navidrome.coverUrl(Player.current?.coverArt ?? "", 160) : player?.trackArtUrl ?? ""
    readonly property bool playing: !!source && isPlaying(source)
    readonly property real position: own ? Player.position : player?.position ?? 0
    readonly property real length: own ? Player.duration : player?.lengthSupported ? player.length : 0
    readonly property bool canSeek: own || (player?.canSeek ?? false)

    function isPlaying(s: var): bool {
        return s.key === "moqs" ? Player.playing : s.player.isPlaying;
    }

    function toggle(): void {
        if (own)
            Player.toggle();
        else if (player?.canTogglePlaying)
            player.togglePlaying();
    }

    function next(): void {
        if (own)
            Player.next();
        else if (player?.canGoNext)
            player.next();
    }

    function previous(): void {
        if (own)
            Player.previous();
        else if (player?.canGoPrevious)
            player.previous();
    }

    function seek(seconds: real): void {
        if (own)
            Player.seek(seconds);
        else if (player?.canSeek)
            player.position = seconds;
    }

    function cycle(): void {
        const i = sources.findIndex(x => x.key === source?.key);
        pinned = sources[(i + 1) % sources.length].key;
    }

    function time(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    visible: source !== null
    implicitHeight: layout.implicitHeight + Config.controlCentre.padding * 2
    radius: Config.border.rounding - Config.controlCentre.padding / 2
    color: Config.colours.card

    // MPRIS doesn't announce position changes while playing, so ask for them.
    Timer {
        running: root.visible && root.playing && !root.own && (root.player?.positionSupported ?? false)
        repeat: true
        interval: 1000
        onTriggered: root.player.positionChanged()
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Config.controlCentre.padding
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Cover {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                source: root.art
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.title || "Nothing playing"
                    elide: Text.ElideRight
                    color: root.title ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.artist
                    elide: Text.ElideRight
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }

                // Source; click to switch when there's more than one.
                Text {
                    text: root.sources.length > 1 ? `${root.source?.name ?? ""}  \u{F04E1}` : root.source?.name ?? ""
                    color: switchArea.containsMouse ? Config.colours.text : Config.colours.muted
                    font.family: Config.font.family
                    font.pointSize: Config.font.small

                    MouseArea {
                        id: switchArea

                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: root.sources.length > 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cycle()
                    }
                }
            }

            Row {
                spacing: 2

                Control {
                    icon: "\u{F04AE}"
                    onClicked: root.previous()
                }

                Control {
                    icon: root.playing ? "\u{F03E4}" : "\u{F040A}"
                    primary: true
                    onClicked: root.toggle()
                }

                Control {
                    icon: "\u{F04AD}"
                    onClicked: root.next()
                }
            }
        }

        // Progress; click to seek where the player allows it.
        RowLayout {
            Layout.fillWidth: true
            visible: root.length > 0
            spacing: 8

            Text {
                text: root.time(root.position)
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 14

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Config.colours.button

                    Rectangle {
                        width: parent.width * Math.min(1, root.position / root.length)
                        height: parent.height
                        radius: 2
                        color: Config.colours.active
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.canSeek
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => root.seek(root.length * mouse.x / width)
                }
            }

            Text {
                text: root.time(root.length)
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }
        }
    }

    component Control: Rectangle {
        id: control

        property string icon
        property bool primary

        signal clicked

        width: 32
        height: 32
        radius: 16
        color: primary ? Config.colours.active : controlArea.containsMouse ? Config.colours.buttonHover : "transparent"

        Text {
            anchors.centerIn: parent
            text: control.icon
            color: control.primary ? Config.colours.activeText : Config.colours.text
            font.family: Config.font.family
            font.pointSize: Config.font.icon
        }

        MouseArea {
            id: controlArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.clicked()
        }
    }
}
