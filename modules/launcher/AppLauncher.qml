import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.modules.controlcentre as CC
import qs.modules

// App launcher that grows out of the middle of the bar. Typing filters the apps; Enter or
// a click starts one, arrows (or Tab) move, Escape closes.
Item {
    id: root

    property bool open
    signal closed

    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay).sort((a, b) => a.name.localeCompare(b.name))

    // How well an app matches the query: higher is better, 0 is no match.
    function score(app: DesktopEntry, q: string): int {
        const name = app.name.toLowerCase();
        if (name === q)
            return 100;
        if (name.startsWith(q))
            return 90;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 80;
        if (name.includes(q))
            return 70;
        const extra = [app.genericName, app.id, ...app.keywords].join(" ").toLowerCase();
        if (extra.includes(q))
            return 50;
        if (app.comment.toLowerCase().includes(q))
            return 30;
        // Letters in order, e.g. "ffx" for Firefox.
        let i = 0;
        for (const c of name)
            if (c === q[i])
                i++;
        return i === q.length ? 10 : 0;
    }

    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        if (!q)
            return apps;
        return apps.map(a => ({ app: a, score: score(a, q) })).filter(m => m.score > 0).sort((a, b) => b.score - a.score).map(m => m.app);
    }

    function launch(app: DesktopEntry): void {
        if (!app)
            return;
        app.execute();
        root.closed();
    }

    readonly property int rowHeight: Config.launcher.row
    readonly property real targetWidth: open ? Config.launcher.width : Config.launcher.seed
    readonly property real targetHeight: open ? content.implicitHeight : 0

    onOpenChanged: {
        if (open) {
            search.text = "";
            list.currentIndex = 0;
            list.positionViewAtBeginning();
            search.forceActiveFocus();
        }
    }

    width: targetWidth
    height: targetHeight
    visible: height > 0

    Behavior on width {
        Anim {}
    }

    Behavior on height {
        Anim {}
    }

    CC.Background {
        anchors.fill: parent
    }

    // Content keeps its full width while the panel animates, so it doesn't reflow.
    Item {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.launcher.width - Config.launcher.padding * 2
            spacing: Config.launcher.padding
            opacity: root.open ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            Item {
                implicitHeight: 0
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: height / 2
                color: Config.colours.button

                Text {
                    id: searchIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0349}"
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.icon
                }

                TextInput {
                    id: search

                    anchors.left: searchIcon.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    color: Config.colours.text
                    selectionColor: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.size
                    clip: true

                    onTextChanged: list.currentIndex = 0
                    onAccepted: root.launch(root.shown[list.currentIndex])
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()
                    Keys.onEscapePressed: root.closed()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !search.text
                        text: "Search apps"
                        color: Config.colours.muted
                        font: search.font
                    }
                }
            }

            ListView {
                id: list

                SmoothScroll {
                    flickable: list
                }

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(count, Config.launcher.shown) * root.rowHeight + Math.max(0, Math.min(count, Config.launcher.shown) - 1) * spacing
                visible: count > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationWraps: true
                model: root.shown

                Behavior on Layout.preferredHeight {
                    Anim {}
                }

                delegate: Rectangle {
                    id: row

                    required property DesktopEntry modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem

                    width: list.width
                    height: root.rowHeight
                    radius: height / 2
                    color: current ? Config.colours.button : area.containsMouse ? Config.colours.buttonHover : "transparent"

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launch(row.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 14
                        spacing: 12

                        IconImage {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                            asynchronous: true
                        }

                        Text {
                            text: row.modelData.name
                            elide: Text.ElideRight
                            color: Config.colours.text
                            font.family: Config.font.family
                            font.pointSize: Config.font.size
                            Layout.maximumWidth: list.width * 0.55
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.genericName || row.modelData.comment
                            elide: Text.ElideRight
                            color: Config.colours.subtext
                            font.family: Config.font.family
                            font.pointSize: Config.font.small
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                visible: list.count === 0
                text: "No apps match"
                color: Config.colours.subtext
                font.family: Config.font.family
                font.pointSize: Config.font.small
            }

            Item {
                implicitHeight: 0
            }
        }
    }

    component Anim: NumberAnimation {
        duration: 250
        easing.type: Easing.OutCubic
    }
}
