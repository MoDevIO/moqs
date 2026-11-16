pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.config

Singleton {
    id: root

    // Newest first.
    property list<Notif> list: []
    readonly property list<Notif> popups: list.filter(n => n.popup)

    // Popup timers pause while the pointer is over them.
    property bool paused: false

    function clear(): void {
        for (const n of list.slice())
            n.notification.dismiss();
    }

    function hidePopups(): void {
        for (const n of list)
            n.popup = false;
    }

    NotificationServer {
        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;
            root.list = [notifComp.createObject(root, {
                    notification: notif
                }), ...root.list];
        }
    }

    Component {
        id: notifComp

        Notif {}
    }

    component Notif: QtObject {
        id: notif

        required property Notification notification
        readonly property date time: new Date()
        property bool popup: true

        readonly property Timer timer: Timer {
            running: notif.popup && !root.paused && notif.notification.urgency !== NotificationUrgency.Critical
            interval: notif.notification.expireTimeout > 0 ? notif.notification.expireTimeout : Config.notifs.timeout
            onTriggered: {
                notif.popup = false;
                // Transient notifications don't stay in the centre.
                if (notif.notification.transient)
                    notif.notification.expire();
            }
        }

        readonly property Connections conn: Connections {
            target: notif.notification

            function onClosed(): void {
                root.list = root.list.filter(n => n !== notif);
                notif.destroy();
            }
        }
    }
}
