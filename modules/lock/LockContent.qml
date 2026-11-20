import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.modules.controlcentre as CC

// What the lock screen shows: the time, the password field, and below a few things from the
// dashboard (weather, the next lesson, what's due) and the music playing, with its controls.
// Typing anywhere goes to the password field.
Item {
    id: root

    readonly property bool failed: Lock.state === "failed"
    readonly property bool checking: Lock.state === "checking"

    // The lesson running now or next, today or on the next school day.
    readonly property var nextLesson: {
        const now = WebUntis.today * 10000 + WebUntis.time;
        return WebUntis.lessons.find(l => !l.cancelled && l.date * 10000 + l.end > now) ?? null;
    }
    readonly property var dueSoon: WebUntis.homework.filter(h => !h.done && h.due && h.due <= WebUntis.addDays(WebUntis.today, 1))
    readonly property var nextExam: WebUntis.exams[0] ?? null

    // Comes up gently once the surface is there.
    opacity: 0
    Component.onCompleted: {
        opacity = 1;
        field.focusField();
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: Lock

        function onStateChanged(): void {
            if (Lock.state === "failed")
                field.fail();
        }
    }

    // A click anywhere puts the focus back in the password field.
    MouseArea {
        anchors.fill: parent
        onClicked: field.focusField()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.1
        spacing: 34

        Clock {
            Layout.alignment: Qt.AlignHCenter
        }

        PasswordField {
            id: field

            Layout.alignment: Qt.AlignHCenter
            checking: root.checking
            failed: root.failed
            message: root.failed ? Lock.message : ""
            onSubmitted: text => Lock.unlock(text)
            onEdited: Lock.state = "idle"
        }
    }

    // Dashboard bits and music, at the bottom.
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        spacing: Config.dashboard.spacing

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Config.dashboard.spacing

            Tile {
                visible: Weather.configured && Weather.current !== null
                icon: Weather.current ? Weather.icon(Weather.current.code, Weather.current.day) : ""
                title: Weather.current ? Weather.degrees(Weather.current.temp) : ""
                detail: Weather.current ? Weather.describe(Weather.current.code) : ""
            }

            Tile {
                readonly property var l: root.nextLesson
                readonly property bool now: l !== null && l.date === WebUntis.today && WebUntis.time >= l.start

                visible: WebUntis.configured && l !== null
                icon: "\u{F1180}"
                title: l ? l.subject : ""
                detail: !l ? "" : now ? `Now, until ${WebUntis.clock(l.end)}` : `${l.date === WebUntis.today ? "" : WebUntis.dayName(l.date) + " "}${WebUntis.clock(l.start)}${l.rooms ? " · " + l.rooms : ""}`
            }

            Tile {
                visible: WebUntis.configured && (root.dueSoon.length > 0 || root.nextExam !== null)
                icon: root.dueSoon.length ? "\u{F05DA}" : "\u{F18FA}"
                title: root.dueSoon.length ? `${root.dueSoon.length} due ${root.dueSoon.some(h => h.due <= WebUntis.today) ? "today" : "tomorrow"}` : root.nextExam ? `${root.nextExam.subject} exam` : ""
                detail: root.dueSoon.length ? root.dueSoon.map(h => h.subject).filter((s, i, a) => s && a.indexOf(s) === i).join(", ") : root.nextExam ? WebUntis.countdown(root.nextExam.date) : ""
            }
        }

        CC.NowPlaying {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 420
        }
    }

    // A small card: icon, a main line and a grey one below.
    component Tile: Rectangle {
        id: tile

        property string icon
        property string title
        property string detail

        implicitWidth: 230
        implicitHeight: 64
        radius: Config.border.rounding - Config.dashboard.padding / 2
        color: Config.colours.card

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Text {
                text: tile.icon
                color: Config.colours.text
                font.family: Config.font.family
                font.pointSize: Config.font.icon + 4
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    elide: Text.ElideRight
                    color: Config.colours.text
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: tile.detail
                    elide: Text.ElideRight
                    color: Config.colours.subtext
                    font.family: Config.font.family
                    font.pointSize: Config.font.small
                }
            }
        }
    }
}
