import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

// Navidrome client in the bottom-left corner: now playing on top, then search and browsing.
Item {
    id: root

    property bool open: false

    readonly property real targetWidth: open ? Config.music.width : 0
    readonly property real targetHeight: open ? Config.music.height : 0

    // Leaving the search swaps the list out and destroys the row that was clicked, so these
    // take the ID up front and run here, not in the row.
    function openAlbum(id: string): void {
        // From search results, back should lead to the album list, not an artist page left
        // open earlier.
        if (Navidrome.results)
            Navidrome.artist = null;
        leaveSearch();
        Navidrome.openAlbum(id);
    }

    function openArtist(id: string): void {
        leaveSearch();
        Navidrome.album = null;
        Navidrome.openArtist(id);
    }

    function leaveSearch(): void {
        searchDelay.stop();
        search.text = "";
        Navidrome.search("");
        list.positionViewAtBeginning();
    }

    function time(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    // Entries for the list below the search field: { kind: header|album|song, data, list, index }
    readonly property var entries: {
        const out = [];
        const r = Navidrome.results;
        if (r) {
            // Bigger matches first: artists, then albums, then single songs.
            if (r.artists.length)
                out.push({ kind: "header", data: "Artists" });
            r.artists.forEach(a => out.push({ kind: "artist", data: a }));
            if (r.albums.length)
                out.push({ kind: "header", data: "Albums" });
            r.albums.forEach(a => out.push({ kind: "album", data: a }));
            if (r.songs.length)
                out.push({ kind: "header", data: "Songs" });
            r.songs.forEach((s, i) => out.push({ kind: "song", data: s, list: r.songs, index: i }));
        } else if (Navidrome.album) {
            Navidrome.album.songs.forEach((s, i) => out.push({ kind: "song", data: s, list: Navidrome.album.songs, index: i }));
        } else if (Navidrome.artist) {
            const a = Navidrome.artist;
            a.albums.forEach(al => out.push({ kind: "album", data: al }));
            if (a.songs.length)
                out.push({ kind: "header", data: "Songs" });
            a.songs.forEach((so, i) => out.push({ kind: "song", data: so, list: a.songs, index: i }));
        } else {
            Navidrome.albums.forEach(a => out.push({ kind: "album", data: a }));
        }
        return out;
    }

    onOpenChanged: {
        if (open && Navidrome.configured && Navidrome.albums.length === 0)
            Navidrome.loadAlbums(mode.current);
    }

    width: targetWidth
    height: targetHeight
    visible: width > 0 && height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    Background {
        anchors.fill: parent
    }

    // Content keeps its full size while the panel animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: Config.music.width
            height: Config.music.height
            spacing: Config.controlCentre.spacing
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            // Setup hint
            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 24
                visible: !Navidrome.configured
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: `Create ${Quickshell.shellPath("navidrome.json")} with:\n\n{\n  "url": "https://music.example.com",\n  "username": "you",\n  "password": "…"\n}\n\n("passwordCommand" works instead of "password".)`
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            // Now playing
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Config.controlCentre.padding
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                visible: Navidrome.configured
                implicitHeight: nowPlaying.implicitHeight + 24
                radius: Config.border.rounding - Config.controlCentre.padding / 2
                color: Config.colours.card

                ColumnLayout {
                    id: nowPlaying

                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Cover {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            source: Navidrome.coverUrl(Player.current?.coverArt ?? "", 160)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: Player.current?.title ?? "Nothing playing"
                                elide: Text.ElideRight
                                color: Player.current ? Config.colours.text : Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.size
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!Player.current
                                text: `${Player.current?.artist ?? ""} · ${Player.current?.album ?? ""}`
                                elide: Text.ElideRight
                                color: Config.colours.subtext
                                font.family: Config.font.family
                                font.pointSize: Config.font.small
                            }
                        }

                        Row {
                            spacing: 2

                            Control {
                                icon: "\u{F04AE}"
                                onClicked: Player.previous()
                            }

                            Control {
                                icon: Player.playing ? "\u{F03E4}" : "\u{F040A}"
                                primary: true
                                onClicked: Player.toggle()
                            }

                            Control {
                                icon: "\u{F04AD}"
                                onClicked: Player.next()
                            }
                        }
                    }

                    // Seek bar
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!Player.current
                        spacing: 8

                        Text {
                            text: root.time(Player.position)
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
                                    width: parent.width * (Player.duration > 0 ? Math.min(1, Player.position / Player.duration) : 0)
                                    height: parent.height
                                    radius: 2
                                    color: Config.colours.active
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => Player.seek(Player.duration * mouse.x / width)
                            }
                        }

                        Text {
                            text: root.time(Player.duration)
                            color: Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }

            // Search
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                visible: Navidrome.configured
                implicitHeight: 36
                radius: height / 2
                color: Config.colours.card

                Text {
                    id: searchIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0349}"
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                }

                TextInput {
                    id: search

                    anchors.left: searchIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: Config.colours.text
                    selectionColor: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    clip: true

                    onTextChanged: searchDelay.restart()
                    Keys.onEscapePressed: text = ""

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search artists, albums and songs"
                        color: Config.colours.muted
                        font: search.font
                    }

                    Timer {
                        id: searchDelay

                        interval: 300
                        onTriggered: Navidrome.search(search.text)
                    }
                }
            }

            // List header: back from an album or artist (with play-all), or the album list mode.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Config.controlCentre.padding + 6
                Layout.rightMargin: Config.controlCentre.padding + 6
                visible: Navidrome.configured && !Navidrome.results

                Text {
                    visible: !!Navidrome.album || !!Navidrome.artist
                    text: "\u{F0141}"
                    color: back.containsMouse ? Config.colours.text : Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size

                    MouseArea {
                        id: back

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // From an album opened on an artist's page, back to that artist.
                        onClicked: {
                            if (Navidrome.album)
                                Navidrome.album = null;
                            else
                                Navidrome.artist = null;
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Navidrome.album ? `${Navidrome.album.name} · ${Navidrome.album.artist}` : Navidrome.artist ? Navidrome.artist.name : "Albums"
                    elide: Text.ElideRight
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    font.bold: true
                }

                Row {
                    id: mode

                    property string current: "newest"

                    visible: !Navidrome.album && !Navidrome.artist
                    spacing: 12

                    Repeater {
                        model: [["newest", "New"], ["random", "Random"], ["frequent", "Most played"]]

                        Text {
                            required property var modelData

                            text: modelData[1]
                            color: mode.current === modelData[0] ? Config.colours.text : modeArea.containsMouse ? Config.colours.subtext : Config.colours.muted
                            font.family: Config.font.family
                            font.pointSize: Config.font.small

                            MouseArea {
                                id: modeArea

                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    mode.current = parent.modelData[0];
                                    Navidrome.loadAlbums(mode.current);
                                }
                            }
                        }
                    }
                }

                // Play the whole album, or everything by the artist.
                Control {
                    visible: !!Navidrome.album || !!Navidrome.artist
                    icon: "\u{F040A}"
                    primary: true
                    onClicked: {
                        if (Navidrome.album)
                            Player.play(Navidrome.album.songs, 0);
                        else
                            Navidrome.artistSongs(Navidrome.artist, songs => {
                                if (songs.length)
                                    Player.play(songs, 0);
                            });
                    }
                }
            }

            // Errors and empty states, in place of the list.
            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 24
                visible: Navidrome.configured && root.entries.length === 0
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Navidrome.error || (Navidrome.loading ? "Loading…" : Navidrome.results ? "No results" : Navidrome.artist ? "Nothing by this artist" : "No albums")
                color: Navidrome.error ? "#ff6b6b" : Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Config.controlCentre.padding
                Layout.rightMargin: Config.controlCentre.padding
                Layout.bottomMargin: Config.controlCentre.padding
                visible: Navidrome.configured && root.entries.length > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.entries

                delegate: Loader {
                    id: entry

                    required property var modelData

                    width: list.width
                    sourceComponent: ({ header, artist: artistRow, album: albumRow, song: songRow })[modelData.kind]

                    Component {
                        id: header

                        Text {
                            topPadding: 8
                            bottomPadding: 4
                            leftPadding: 6
                            text: entry.modelData.data
                            color: Config.colours.muted
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }

                    Component {
                        id: artistRow

                        MusicRow {
                            cover: Navidrome.coverUrl(entry.modelData.data.coverArt ?? "", 96)
                            title: entry.modelData.data.name
                            subtitle: entry.modelData.data.albumCount ? `${entry.modelData.data.albumCount} album${entry.modelData.data.albumCount === 1 ? "" : "s"}` : "Artist"
                            onClicked: root.openArtist(entry.modelData.data.id)
                        }
                    }

                    Component {
                        id: albumRow

                        MusicRow {
                            cover: Navidrome.coverUrl(entry.modelData.data.coverArt ?? "", 96)
                            title: entry.modelData.data.name
                            subtitle: entry.modelData.data.artist ?? ""
                            trailing: entry.modelData.data.year ? `${entry.modelData.data.year}` : ""
                            onClicked: root.openAlbum(entry.modelData.data.id)
                        }
                    }

                    Component {
                        id: songRow

                        MusicRow {
                            readonly property var song: entry.modelData.data

                            // Album tracks get numbers instead of covers.
                            // Outside an album (search, artist pages) songs show cover and album.
                            readonly property bool loose: !Navidrome.album || !!Navidrome.results

                            cover: loose ? Navidrome.coverUrl(song.coverArt ?? "", 96) : ""
                            title: loose ? song.title : `${song.track ?? entry.modelData.index + 1}. ${song.title}`
                            subtitle: loose ? `${song.artist ?? ""} · ${song.album ?? ""}` : (song.artist !== Navidrome.album?.artist ? song.artist ?? "" : "")
                            trailing: root.time(song.duration ?? 0)
                            active: Player.current?.id === song.id
                            onClicked: Player.play(entry.modelData.list, entry.modelData.index)
                        }
                    }
                }
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

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
