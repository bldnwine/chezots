import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

CardWindow {
    id: popup
    required property var root

    theme: root
    plain: true
    revealed: root.notificationCenterVisible
    cardWidth: 460
    cardHeight: 560
    layerNamespace: "omarchy-notifications"
    title: "NOTIFICATIONS"
    subtitle: {
        var total = (service && service.entries) ? service.entries.length : 0;
        if (total === 0) return "NO NOTIFICATIONS";
        var unreadCount = service ? service.unread : 0;
        var s = total === 1 ? "1 NOTIFICATION" : total + " NOTIFICATIONS";
        if (unreadCount > 0) s += " · " + unreadCount + " UNREAD";
        if (popup.filterText.length > 0) s += " · “" + popup.filterText + "”";
        return s;
    }
    footer: "↵ OPEN · / SEARCH · DEL REMOVE · SHIFT+DEL CLEAR"
    escDismiss: false

    Component.onCompleted: popup.rebuild()

    anchorEdge: popup.root.barEdge
    anchorBarX: popup.root.popupAnchorX
    anchorBarY: popup.root.popupAnchorY

    readonly property var service: root.notificationCenterService
    readonly property string focusScript: Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/hyprland-focus-app"

    property string filterText: ""
    property bool searching: false
    property int selectedIndex: 0
    property double now: Date.now()
    property double readMark: 0
    property bool clearArmed: false

    ListModel { id: rows }

    function dayOf(timestamp) {
        var when = new Date(timestamp);
        var today = new Date();
        var midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        if (timestamp >= midnight) return "TODAY";
        if (timestamp >= midnight - 86400000) return "YESTERDAY";
        if (timestamp >= midnight - 6 * 86400000) return Qt.formatDateTime(when, "dddd").toUpperCase();
        if (when.getFullYear() === today.getFullYear()) return Qt.formatDateTime(when, "d MMMM").toUpperCase();
        return Qt.formatDateTime(when, "d MMMM yyyy").toUpperCase();
    }

    function matches(entry) {
        if (!popup.filterText) return true;
        var needle = popup.filterText.toLowerCase();
        return String(entry.app || "").toLowerCase().indexOf(needle) >= 0
            || String(entry.summary || "").toLowerCase().indexOf(needle) >= 0
            || String(entry.body || "").toLowerCase().indexOf(needle) >= 0;
    }

    function rebuild() {
        rows.clear();
        if (!service) return;
        var list = service.entries;
        for (var i = 0; i < list.length; i++) {
            var e = list[i];
            if (matches(e)) {
                var ts = Number(e.timestamp || 0);
                rows.append({
                    key: String(e.key || ""),
                    app: String(e.app || ""),
                    appIcon: String(e.appIcon || ""),
                    summary: String(e.summary || ""),
                    body: String(e.body || ""),
                    image: String(e.image || ""),
                    preview: String(e.preview || ""),
                    file: String(e.file || ""),
                    glyph: String(e.glyph || ""),
                    urgency: Number(e.urgency || 1),
                    timestamp: ts,
                    day: dayOf(ts),
                    unread: ts > popup.readMark
                });
            }
        }
        if (rows.count === 0) popup.selectedIndex = 0;
        else if (popup.selectedIndex >= rows.count) popup.selectedIndex = rows.count - 1;
        else if (popup.selectedIndex < 0) popup.selectedIndex = 0;
    }

    function startSearch() {
        popup.searching = true;
        Qt.callLater(() => searchInput.forceActiveFocus());
    }

    function endSearch() {
        popup.searching = false;
        popup.filterText = "";
        popup.rebuild();
        popup.refocus();
    }

    function select(delta) {
        if (rows.count === 0) return;
        popup.selectedIndex = Math.max(0, Math.min(rows.count - 1, popup.selectedIndex + delta));
        notifListView.positionViewAtIndex(popup.selectedIndex, ListView.Contain);
    }

    function extractUrl(text) {
        if (!text) return "";
        var match = String(text).match(/https?:\/\/[^\s"'<>]+/i);
        if (match) return match[0];
        return "";
    }

    function extractFilePath(text) {
        if (!text) return "";
        var clean = String(text).trim();
        if (clean.indexOf("file://") === 0) return clean;
        if (clean.indexOf("/") === 0 && (clean.indexOf(".png") > 0 || clean.indexOf(".jpg") > 0 || clean.indexOf(".jpeg") > 0 || clean.indexOf(".webp") > 0 || clean.indexOf(".gif") > 0 || clean.indexOf(".pdf") > 0 || clean.indexOf(".mp4") > 0 || clean.indexOf(".txt") > 0 || clean.indexOf(".md") > 0)) {
            return clean;
        }
        return "";
    }

    function activate(index) {
        if (index < 0 || index >= rows.count) return;
        var item = rows.get(index);
        if (!item) return;

        var key = item.key;
        var summary = item.summary;
        var body = item.body;
        var file = item.file;
        var app = item.app;

        var handled = false;

        // 1. Invoke live D-Bus notification action (tells browser/app to open the page/site)
        if (root.invokeNotification && root.invokeNotification(key)) {
            handled = true;
        }

        // 2. Check for URL in summary or body
        if (!handled) {
            var url = extractUrl(summary) || extractUrl(body);
            if (url) {
                Quickshell.execDetached(["xdg-open", url]);
                handled = true;
            }
        }

        // 3. Check for image / file attachment or path in body
        if (!handled) {
            var fileTarget = file || extractFilePath(body) || extractFilePath(summary);
            if (fileTarget && fileTarget.length > 0) {
                Quickshell.execDetached(["xdg-open", fileTarget]);
                handled = true;
            }
        }

        // 4. Focus app window in Hyprland
        if (!handled && app && /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$/.test(app)) {
            Quickshell.execDetached([popup.focusScript, app]);
            handled = true;
        }

        // Dismiss and remove the notification upon activation
        popup.removeIndex(index);
        root.notificationCenterVisible = false;
    }

    function removeIndex(index) {
        if (index < 0 || index >= rows.count) return;
        var item = rows.get(index);
        if (!item) return;
        var key = item.key;
        if (popup.root && popup.root.removeNotification) {
            popup.root.removeNotification(key);
        } else if (service) {
            service.remove(key);
        }
    }

    function clearAll() {
        if (popup.root && popup.root.clearAllNotifications) {
            popup.root.clearAllNotifications();
        } else if (service) {
            service.clearAll();
        }
        popup.clearArmed = false;
        popup.selectedIndex = 0;
    }

    headerRight: Component {
        Row {
            spacing: 6

            // Search Toggle Button
            Rectangle {
                width: 26
                height: 26
                radius: popup.root.cornerRadius
                color: popup.searching || searchBtnMouse.containsMouse ? popup.root.rowHi : "transparent"
                border.color: popup.searching ? popup.root.seal : "transparent"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰍉"
                    font.family: popup.root.mono
                    font.pixelSize: 13
                    color: popup.searching ? popup.root.seal : popup.root.ink
                }

                MouseArea {
                    id: searchBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.searching ? popup.endSearch() : popup.startSearch()
                }
            }

            // DND Toggle Button
            Rectangle {
                width: 26
                height: 26
                radius: popup.root.cornerRadius
                color: popup.root.doNotDisturb || dndBtnMouse.containsMouse ? popup.root.rowHi : "transparent"
                border.color: popup.root.doNotDisturb ? popup.root.seal : "transparent"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: popup.root.doNotDisturb ? "󰂛" : "󰂚"
                    font.family: popup.root.mono
                    font.pixelSize: 13
                    color: popup.root.doNotDisturb ? popup.root.seal : popup.root.ink
                }

                MouseArea {
                    id: dndBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.root.toggleDnd()
                }
            }

            // Clear Button (with 2-step confirmation)
            Rectangle {
                width: clearBtnText.implicitWidth + 12
                height: 26
                radius: popup.root.cornerRadius
                color: popup.clearArmed || clearBtnMouse.containsMouse ? popup.root.rowHi : "transparent"
                border.color: popup.clearArmed ? popup.root.seal : popup.root.sep
                border.width: 1

                Text {
                    id: clearBtnText
                    anchors.centerIn: parent
                    text: popup.clearArmed ? "SURE?" : "CLEAR"
                    font.family: popup.root.mono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.letterSpacing: 1
                    color: popup.clearArmed ? popup.root.seal : popup.root.inkDeep
                }

                MouseArea {
                    id: clearBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (popup.clearArmed) {
                            disarmTimer.stop();
                            popup.clearAll();
                        } else {
                            popup.clearArmed = true;
                            disarmTimer.restart();
                        }
                    }
                }
            }

            Timer {
                id: disarmTimer
                interval: 4000
                onTriggered: popup.clearArmed = false
            }
        }
    }

    Connections {
        target: popup.service
        function onEntryAdded(entry) {
            if (popup.revealed && popup.service) popup.service.markSeen();
            popup.rebuild();
        }
        function onEntriesReset() {
            popup.rebuild();
        }
    }

    Timer {
        interval: 30000
        running: popup.revealed
        repeat: true
        onTriggered: popup.now = Date.now()
    }

    onRevealedChanged: {
        if (popup.revealed) {
            popup.now = Date.now();
            popup.clearArmed = false;
            if (popup.service) {
                popup.readMark = popup.service.lastSeen;
                popup.service.load();
                popup.service.markSeen();
            }
            popup.rebuild();
            popup.refocus();
        } else {
            popup.searching = false;
            popup.filterText = "";
        }
    }

    onKeyPressed: (event) => {
        const k = event.key;

        if (k === Qt.Key_Escape) {
            if (popup.searching) {
                popup.endSearch();
            } else {
                root.notificationCenterVisible = false;
            }
            event.accepted = true;
            return;
        }

        if (k === Qt.Key_Slash && !popup.searching) {
            popup.startSearch();
            event.accepted = true;
            return;
        }

        if (popup.searching) {
            if (k === Qt.Key_Down) {
                popup.select(1);
                event.accepted = true;
            } else if (k === Qt.Key_Up) {
                popup.select(-1);
                event.accepted = true;
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                popup.activate(popup.selectedIndex);
                event.accepted = true;
            }
            return;
        }

        if (k === Qt.Key_Up || k === Qt.Key_Left) {
            popup.select(-1);
            event.accepted = true;
        } else if (k === Qt.Key_Down || k === Qt.Key_Right) {
            popup.select(1);
            event.accepted = true;
        } else if (k === Qt.Key_PageUp) {
            popup.select(-4);
            event.accepted = true;
        } else if (k === Qt.Key_PageDown) {
            popup.select(4);
            event.accepted = true;
        } else if (k === Qt.Key_Home) {
            popup.selectedIndex = 0;
            notifListView.positionViewAtBeginning();
            event.accepted = true;
        } else if (k === Qt.Key_End) {
            popup.selectedIndex = Math.max(0, rows.count - 1);
            notifListView.positionViewAtEnd();
            event.accepted = true;
        } else if (k === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) popup.clearAll();
            else popup.removeIndex(popup.selectedIndex);
            event.accepted = true;
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            popup.activate(popup.selectedIndex);
            event.accepted = true;
        }
    }

    onDismiss: root.notificationCenterVisible = false

    Item {
        width: parent.width
        implicitHeight: 440
        height: 440

        Column {
            anchors.fill: parent
            spacing: 8

            // Search Bar Input
            Rectangle {
                visible: popup.searching
                width: parent.width
                height: 32
                radius: popup.root.cornerRadius
                color: popup.root.rowHi
                border.color: popup.root.seal
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        font.family: popup.root.mono
                        font.pixelSize: 12
                        color: popup.root.seal
                    }

                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24
                        text: popup.filterText
                        color: popup.root.ink
                        font.family: popup.root.mono
                        font.pixelSize: 11
                        selectByMouse: true
                        onTextChanged: {
                            popup.filterText = text;
                            popup.rebuild();
                        }
                    }
                }
            }

            // Notification List
            ListView {
                id: notifListView
                width: parent.width
                height: parent.height - (popup.searching ? 40 : 0)
                model: rows
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                visible: rows.count > 0

                section.property: "day"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    id: sectionHeader
                    required property string section
                    width: notifListView.width
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        text: sectionHeader.section
                        font.family: popup.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                        color: popup.root.inkDeep
                    }
                }

                delegate: NotificationCard {
                    root: popup.root
                    now: popup.now
                    selected: index === popup.selectedIndex

                    onClicked: {
                        popup.selectedIndex = index;
                        popup.activate(index);
                    }
                    onRemoveRequested: popup.removeIndex(index)
                }
            }

            // Empty State
            Item {
                width: parent.width
                height: parent.height
                visible: rows.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "󰂚"
                        font.family: popup.root.mono
                        font.pixelSize: 42
                        color: popup.root.rowSel
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Text {
                        text: popup.filterText.length > 0
                            ? "No notifications match “" + popup.filterText + "”"
                            : "No notifications kept yet"
                        font.family: popup.root.mono
                        font.pixelSize: 11
                        color: popup.root.inkDeep
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }
                }
            }
        }
    }
}
