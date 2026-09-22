import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: wallpaperWindow
    required property var root

    visible: root.wallpapersVisible || reveal > 0.001
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-wallpapers"
    WlrLayershell.keyboardFocus: root.wallpapersVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real reveal: root.wallpapersVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    // State
    property var allWallpapers: []
    property var filteredWallpapers: []
    property int selectedIndex: 0
    property string currentWallpaperPath: ""
    property string currentWallpaperName: ""
    property string appliedToast: ""

    // Search Mode State
    property bool searchActive: false
    property string query: ""

    // Favorites State
    readonly property string favoritesStatePath: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/wallpaper-favorites.json"
    property var favoritesList: []
    property var favoritesMap: ({})
    property bool favOnlyMode: false

    function toggleFavorite(entry) {
        if (!entry || !entry.path) return;
        const p = entry.path;
        const nextList = [];
        let found = false;

        for (let i = 0; i < favoritesList.length; i++) {
            if (favoritesList[i] === p) {
                found = true;
            } else {
                nextList.push(favoritesList[i]);
            }
        }

        if (!found) {
            nextList.push(p);
            appliedToast = "󰓎 FAVORITED: " + entry.name;
        } else {
            appliedToast = "UNFAVORITED: " + entry.name;
        }
        toastTimer.restart();

        favoritesList = nextList;
        const map = {};
        for (let i = 0; i < nextList.length; i++) {
            map[nextList[i]] = true;
        }
        favoritesMap = map;
        saveFavorites();

        if (favOnlyMode) {
            rebuildList();
        }
    }

    function toggleFavoritesCategory() {
        favOnlyMode = !favOnlyMode;
        appliedToast = favOnlyMode ? "CATEGORY: FAVORITES ONLY" : "CATEGORY: ALL WALLPAPERS";
        toastTimer.restart();
        selectedIndex = 0;
        rebuildList();
        focusCurrentWallpaper();
        Qt.callLater(() => {
            if (carousel && filteredWallpapers.length > 0) {
                carousel.positionViewAtIndex(selectedIndex, selectedIndex === 0 ? ListView.Beginning : ListView.Center);
            }
        });
    }

    function saveFavorites() {
        const payload = JSON.stringify(favoritesList);
        favSaveProc.command = ["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "sh", favoritesStatePath, payload];
        favSaveProc.running = false;
        favSaveProc.running = true;
    }

    // Sorting State (aligned with Yazi):
    // Uppercase = reverse / descending (newest / largest / Z-A)
    // Lowercase = normal / ascending (oldest / smallest / A-Z)
    // 'M' (modified desc, newest first), 'm' (modified asc, oldest first)
    // 'B' (birth desc, newest first),    'b' (birth asc, oldest first)
    // 'a' (name asc, A-Z),               'A' (name desc, Z-A)
    // 'S' (size desc, largest first),    's' (size asc, smallest first)
    // 'r' (random shuffle)
    property string sortMode: "M"
    property bool pendingSortPrefix: false

    function sortLabel() {
        switch (sortMode) {
            case "M": return "MODIFIED (NEWEST) ↓";
            case "m": return "MODIFIED (OLDEST) ↑";
            case "B": return "BIRTH (NEWEST) ↓";
            case "b": return "BIRTH (OLDEST) ↑";
            case "a": return "NAME (A → Z)";
            case "A": return "NAME (Z → A)";
            case "S": return "SIZE (LARGEST) ↓";
            case "s": return "SIZE (SMALLEST) ↑";
            case "r": return "RANDOM";
            default:  return "MODIFIED (NEWEST) ↓";
        }
    }

    function sortToast(mode) {
        switch (mode) {
            case "M": return "SORT: MODIFIED (LATEST FIRST)";
            case "m": return "SORT: MODIFIED (OLDEST FIRST)";
            case "B": return "SORT: BIRTH (NEWEST FIRST)";
            case "b": return "SORT: BIRTH (OLDEST FIRST)";
            case "a": return "SORT: NAME (A → Z)";
            case "A": return "SORT: NAME (Z → A)";
            case "S": return "SORT: SIZE (LARGEST FIRST)";
            case "s": return "SORT: SIZE (SMALLEST FIRST)";
            case "r": return "SORT: RANDOM SHUFFLE";
            default:  return "SORT: " + mode.toUpperCase();
        }
    }

    function formatSize(bytes) {
        if (!bytes || bytes <= 0) return "";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
        return Math.round(bytes / 1024) + " KB";
    }

    function refresh() {
        currentBgProc.running = false;
        currentBgProc.running = true;
        scanProc.running = false;
        scanProc.running = true;
    }

    function applyWallpaper(entry) {
        if (!entry || !entry.path) return;
        currentWallpaperPath = entry.path;
        currentWallpaperName = entry.name;
        Quickshell.execDetached(["omarchy-theme-bg-set", entry.path]);
        appliedToast = "APPLIED: " + entry.name;
        toastTimer.restart();
    }

    function focusCurrentWallpaper() {
        if (!currentWallpaperPath || filteredWallpapers.length === 0) return;
        for (let i = 0; i < filteredWallpapers.length; i++) {
            if (filteredWallpapers[i].path === currentWallpaperPath) {
                selectedIndex = i;
                Qt.callLater(() => {
                    if (carousel) carousel.positionViewAtIndex(i, ListView.Center);
                });
                return;
            }
        }
    }

    function rebuildList() {
        const q = query.trim().toLowerCase();
        let list = allWallpapers.slice();

        if (favOnlyMode) {
            list = list.filter(item => !!favoritesMap[item.path]);
        }

        if (q.length > 0) {
            list = list.filter(item => item.name.toLowerCase().includes(q));
        }

        const natCompare = (a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });

        switch (sortMode) {
            case "M":
                list.sort((a, b) => (b.mtime - a.mtime) || natCompare(a.name, b.name));
                break;
            case "m":
                list.sort((a, b) => (a.mtime - b.mtime) || natCompare(a.name, b.name));
                break;
            case "B":
                list.sort((a, b) => ((b.btime || b.mtime) - (a.btime || a.mtime)) || natCompare(a.name, b.name));
                break;
            case "b":
                list.sort((a, b) => ((a.btime || a.mtime) - (b.btime || b.mtime)) || natCompare(a.name, b.name));
                break;
            case "a":
                list.sort((a, b) => natCompare(a.name, b.name));
                break;
            case "A":
                list.sort((a, b) => natCompare(b.name, a.name));
                break;
            case "S":
                list.sort((a, b) => (b.size - a.size) || natCompare(a.name, b.name));
                break;
            case "s":
                list.sort((a, b) => (a.size - b.size) || natCompare(a.name, b.name));
                break;
            case "r":
                // Fisher-Yates
                for (let i = list.length - 1; i > 0; i--) {
                    const j = Math.floor(Math.random() * (i + 1));
                    const tmp = list[i];
                    list[i] = list[j];
                    list[j] = tmp;
                }
                break;
        }

        filteredWallpapers = list;
        if (selectedIndex >= list.length) {
            selectedIndex = Math.max(0, list.length - 1);
        }
        if (list.length > 0 && selectedIndex < 0) {
            selectedIndex = 0;
        }
    }

    function setSort(mode) {
        sortMode = mode;
        pendingSortPrefix = false;
        appliedToast = sortToast(mode);
        toastTimer.restart();
        selectedIndex = 0;
        rebuildList();
        Qt.callLater(() => {
            if (carousel && filteredWallpapers.length > 0) {
                carousel.positionViewAtIndex(0, ListView.Beginning);
            }
        });
    }

    function moveSelection(delta) {
        if (filteredWallpapers.length === 0) return;
        let next = selectedIndex + delta;
        if (next < 0) next = 0;
        if (next >= filteredWallpapers.length) next = filteredWallpapers.length - 1;
        selectedIndex = next;
        carousel.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    // Probes
    Process {
        id: scanProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/wallpaper-scan.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text || "[]");
                    wallpaperWindow.allWallpapers = data;
                    wallpaperWindow.rebuildList();
                    wallpaperWindow.focusCurrentWallpaper();
                } catch(e) {
                    console.warn("wallpaper scan parse error:", e);
                }
            }
        }
    }

    Process {
        id: currentBgProc
        command: ["sh", "-c", "readlink -f \"$HOME/.config/omarchy/current/background\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = (this.text || "").trim();
                if (p) {
                    wallpaperWindow.currentWallpaperPath = p;
                    wallpaperWindow.currentWallpaperName = p.substring(p.lastIndexOf("/") + 1);
                    wallpaperWindow.focusCurrentWallpaper();
                }
            }
        }
    }

    FileView {
        id: favFileView
        path: wallpaperWindow.favoritesStatePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(favFileView.text() || "[]");
                wallpaperWindow.favoritesList = Array.isArray(data) ? data : [];
                const map = {};
                for (let i = 0; i < wallpaperWindow.favoritesList.length; i++) {
                    map[wallpaperWindow.favoritesList[i]] = true;
                }
                wallpaperWindow.favoritesMap = map;
                if (wallpaperWindow.favOnlyMode) {
                    wallpaperWindow.rebuildList();
                }
            } catch (_) {}
        }
        onFileChanged: reload()
    }

    Process {
        id: favSaveProc
        running: false
        command: ["true"]
    }

    Timer {
        id: toastTimer
        interval: 1800
        repeat: false
        onTriggered: wallpaperWindow.appliedToast = ""
    }

    Connections {
        target: root
        function onWallpapersVisibleChanged() {
            if (root.wallpapersVisible) {
                wallpaperWindow.currentBgProc.running = false;
                wallpaperWindow.currentBgProc.running = true;
                if (wallpaperWindow.allWallpapers.length === 0) {
                    wallpaperWindow.scanProc.running = false;
                    wallpaperWindow.scanProc.running = true;
                } else {
                    wallpaperWindow.rebuildList();
                    wallpaperWindow.focusCurrentWallpaper();
                }
                wallpaperWindow.searchActive = false;
                wallpaperWindow.query = "";
                wallpaperWindow.pendingSortPrefix = false;
                Qt.callLater(() => surface.forceActiveFocus());
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => surface.forceActiveFocus());
        }
    }

    Component.onCompleted: {
        if (root.pendingWallpaperSort) {
            sortMode = root.pendingWallpaperSort;
            root.pendingWallpaperSort = "";
        }
        refresh();
        Qt.callLater(() => surface.forceActiveFocus());
    }

    // Dimmed backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45 * wallpaperWindow.reveal)
    }

    // Dismiss on outside tap
    MouseArea {
        anchors.fill: parent
        onClicked: root.wallpapersVisible = false
    }

    // Main Shelf Card anchored to bottom of screen
    Rectangle {
        id: surface
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.barEdge === "bottom" ? (root.barOffset + 14) : 18
        width: Math.min(parent.width - 40, 1380)
        height: wallpaperWindow.searchActive ? 304 : 260
        Behavior on height {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        color: root.bg
        border.color: root.sep
        border.width: 1
        radius: root.cornerRadius
        clip: true

        transform: Translate {
            y: (1 - wallpaperWindow.reveal) * 50
        }
        opacity: wallpaperWindow.reveal

        // Absorb clicks so background dismissal isn't triggered and keep active focus
        MouseArea {
            anchors.fill: parent
            onClicked: surface.forceActiveFocus()
        }

        focus: true
        Keys.onPressed: function(event) {
            const k = event.key;

            // Global Ctrl shortcuts: Ctrl+S to star, Ctrl+F for favorites category
            if (event.modifiers & Qt.ControlModifier) {
                if (k === Qt.Key_S) {
                    const entry = wallpaperWindow.filteredWallpapers[wallpaperWindow.selectedIndex];
                    if (entry) wallpaperWindow.toggleFavorite(entry);
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_F) {
                    wallpaperWindow.toggleFavoritesCategory();
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_R) {
                    wallpaperWindow.refresh();
                    event.accepted = true;
                    return;
                }
            }

            // Handle pending sort mode sequence after ','
            if (wallpaperWindow.pendingSortPrefix) {
                wallpaperWindow.pendingSortPrefix = false;
                const isShift = (event.modifiers & Qt.ShiftModifier) || event.text === "M" || event.text === "B" || event.text === "A" || event.text === "S";
                if (k === Qt.Key_M) {
                    wallpaperWindow.setSort(isShift ? "M" : "m");
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_B) {
                    wallpaperWindow.setSort(isShift ? "B" : "b");
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_A) {
                    wallpaperWindow.setSort(isShift ? "A" : "a");
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_S) {
                    wallpaperWindow.setSort(isShift ? "S" : "s");
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_R) {
                    wallpaperWindow.setSort("r");
                    event.accepted = true;
                    return;
                }
                // Any other key cancels pending sort
            }

            // Search Mode Key Handling
            if (wallpaperWindow.searchActive) {
                if (k === Qt.Key_Escape) {
                    if (wallpaperWindow.query.length > 0) {
                        wallpaperWindow.query = "";
                        wallpaperWindow.selectedIndex = 0;
                        wallpaperWindow.rebuildList();
                        Qt.callLater(() => {
                            if (carousel && wallpaperWindow.filteredWallpapers.length > 0) {
                                carousel.positionViewAtIndex(0, ListView.Beginning);
                            }
                        });
                    } else {
                        wallpaperWindow.searchActive = false;
                    }
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    const entry = wallpaperWindow.filteredWallpapers[wallpaperWindow.selectedIndex];
                    if (entry) wallpaperWindow.applyWallpaper(entry);
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_Down) {
                    wallpaperWindow.searchActive = false;
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_Backspace) {
                    if (wallpaperWindow.query.length > 0) {
                        wallpaperWindow.query = wallpaperWindow.query.substring(0, wallpaperWindow.query.length - 1);
                        wallpaperWindow.selectedIndex = 0;
                        wallpaperWindow.rebuildList();
                        Qt.callLater(() => {
                            if (carousel && wallpaperWindow.filteredWallpapers.length > 0) {
                                carousel.positionViewAtIndex(0, ListView.Beginning);
                            }
                        });
                    }
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_Left) {
                    wallpaperWindow.moveSelection(-1);
                    event.accepted = true;
                    return;
                } else if (k === Qt.Key_Right) {
                    wallpaperWindow.moveSelection(1);
                    event.accepted = true;
                    return;
                } else if (event.text && event.text.length === 1) {
                    const ch = event.text;
                    if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) {
                        wallpaperWindow.query += ch;
                        wallpaperWindow.selectedIndex = 0;
                        wallpaperWindow.rebuildList();
                        Qt.callLater(() => {
                            if (carousel && wallpaperWindow.filteredWallpapers.length > 0) {
                                carousel.positionViewAtIndex(0, ListView.Beginning);
                            }
                        });
                        event.accepted = true;
                        return;
                    }
                }
                return;
            }

            // Normal Navigation Mode Key Handling
            if (k === Qt.Key_Escape || k === Qt.Key_Q) {
                root.wallpapersVisible = false;
                event.accepted = true;
                return;
            } else if (k === Qt.Key_Slash) {
                wallpaperWindow.searchActive = true;
                event.accepted = true;
                return;
            } else if (k === Qt.Key_Comma) {
                wallpaperWindow.pendingSortPrefix = true;
                event.accepted = true;
                return;
            } else if (k === Qt.Key_M) {
                const isShift = (event.modifiers & Qt.ShiftModifier) || event.text === "M";
                wallpaperWindow.setSort(isShift ? "M" : "m");
                event.accepted = true;
                return;
            } else if (k === Qt.Key_B) {
                const isShift = (event.modifiers & Qt.ShiftModifier) || event.text === "B";
                wallpaperWindow.setSort(isShift ? "B" : "b");
                event.accepted = true;
                return;
            } else if (k === Qt.Key_A) {
                const isShift = (event.modifiers & Qt.ShiftModifier) || event.text === "A";
                wallpaperWindow.setSort(isShift ? "A" : "a");
                event.accepted = true;
                return;
            } else if (k === Qt.Key_S && !(event.modifiers & Qt.ControlModifier)) {
                const isShift = (event.modifiers & Qt.ShiftModifier) || event.text === "S";
                wallpaperWindow.setSort(isShift ? "S" : "s");
                event.accepted = true;
                return;
            } else if (k === Qt.Key_R && !(event.modifiers & Qt.ControlModifier)) {
                wallpaperWindow.setSort("r");
                event.accepted = true;
                return;
            } else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backtab) {
                wallpaperWindow.moveSelection(-1);
                event.accepted = true;
                return;
            } else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Tab) {
                wallpaperWindow.moveSelection(1);
                event.accepted = true;
                return;
            } else if (k === Qt.Key_Home) {
                wallpaperWindow.selectedIndex = 0;
                carousel.positionViewAtIndex(0, ListView.Beginning);
                event.accepted = true;
                return;
            } else if (k === Qt.Key_End) {
                wallpaperWindow.selectedIndex = Math.max(0, wallpaperWindow.filteredWallpapers.length - 1);
                carousel.positionViewAtIndex(wallpaperWindow.selectedIndex, ListView.End);
                event.accepted = true;
                return;
            } else if (k === Qt.Key_PageUp) {
                wallpaperWindow.moveSelection(-4);
                event.accepted = true;
                return;
            } else if (k === Qt.Key_PageDown) {
                wallpaperWindow.moveSelection(4);
                event.accepted = true;
                return;
            } else if (k === Qt.Key_F5 || (k === Qt.Key_R && (event.modifiers & Qt.ControlModifier))) {
                wallpaperWindow.refresh();
                event.accepted = true;
                return;
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                const entry = wallpaperWindow.filteredWallpapers[wallpaperWindow.selectedIndex];
                if (entry) wallpaperWindow.applyWallpaper(entry);
                event.accepted = true;
                return;
            }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            // Search Row (only appears when search mode is invoked via /)
            Item {
                id: searchRow
                width: parent.width
                height: wallpaperWindow.searchActive ? 42 : 0
                visible: height > 0
                clip: true

                Behavior on height {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    id: searchPill
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 320
                    height: 32
                    radius: root.cornerRadius > 0 ? 16 : 0
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                    border.color: root.seal
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰍉"
                            color: root.seal
                            font.family: root.mono
                            font.pixelSize: 14
                        }

                        Text {
                            id: searchInputText
                            anchors.verticalCenter: parent.verticalCenter
                            width: searchPill.width - 66
                            text: wallpaperWindow.query.length > 0 ? wallpaperWindow.query : "Search wallpapers..."
                            color: wallpaperWindow.query.length > 0 ? root.ink : root.inkDeep
                            opacity: wallpaperWindow.query.length > 0 ? 1.0 : 0.5
                            font.family: root.mono
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        // Blinking Caret
                        Rectangle {
                            width: 2
                            height: 14
                            color: root.seal
                            anchors.verticalCenter: parent.verticalCenter
                            visible: wallpaperWindow.searchActive
                            SequentialAnimation on opacity {
                                running: wallpaperWindow.searchActive
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.2; duration: 550; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.2; to: 1; duration: 550; easing.type: Easing.InOutSine }
                            }
                        }

                        // Clear button
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: wallpaperWindow.query.length > 0
                            text: "✕"
                            color: root.inkDeep
                            font.family: root.mono
                            font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    wallpaperWindow.query = "";
                                    wallpaperWindow.rebuildList();
                                }
                            }
                        }
                    }
                }

                // Filter count on right of search row
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: wallpaperWindow.favOnlyMode
                          ? (wallpaperWindow.filteredWallpapers.length + " / " + wallpaperWindow.favoritesList.length + " FAVORITES")
                          : (wallpaperWindow.filteredWallpapers.length + " / " + wallpaperWindow.allWallpapers.length + " WALLPAPERS")
                    color: wallpaperWindow.favOnlyMode ? root.seal : root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.sep
                visible: searchRow.visible
            }

            // Main Carousel Area
            Item {
                width: parent.width
                height: 232

                Text {
                    anchors.centerIn: parent
                    visible: wallpaperWindow.filteredWallpapers.length === 0
                    text: wallpaperWindow.allWallpapers.length === 0
                          ? "Scanning wallpapers..."
                          : (wallpaperWindow.favOnlyMode
                             ? "No favorite wallpapers yet (Ctrl+S to star)"
                             : "No matching wallpapers")
                    color: root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 12
                    font.letterSpacing: 2
                }

                ListView {
                    id: carousel
                    anchors.fill: parent
                    anchors.margins: 10
                    orientation: ListView.Horizontal
                    spacing: 12
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    model: wallpaperWindow.filteredWallpapers
                    currentIndex: wallpaperWindow.selectedIndex

                    preferredHighlightBegin: 20
                    preferredHighlightEnd: width - 20
                    highlightRangeMode: ListView.ApplyRange

                    delegate: Item {
                        id: cardItem
                        required property int index
                        required property var modelData

                        readonly property bool isSelected: wallpaperWindow.selectedIndex === index
                        readonly property bool isActive: modelData && modelData.path === wallpaperWindow.currentWallpaperPath

                        // Compute responsive width: ~4.2 cards visible across the carousel
                        width: Math.max(260, Math.min(340, (carousel.width - 4 * 12) / 4.2))
                        height: carousel.height

                        Rectangle {
                            id: cardBg
                            anchors.fill: parent
                            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, cardItem.isSelected ? 0.08 : 0.04)
                            border.color: cardItem.isSelected ? root.seal : (cardMouse.containsMouse ? root.ink : root.sep)
                            border.width: cardItem.isSelected ? 2 : 1
                            radius: root.cornerRadius
                            antialiasing: true

                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            // Wallpaper Image (optimized thumbnail decode)
                            Image {
                                anchors.fill: parent
                                anchors.margins: cardItem.isSelected ? 2 : 1
                                source: wallpaperWindow.visible ? ("file://" + modelData.path) : ""
                                sourceSize.width: 360
                                sourceSize.height: 202
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                clip: true
                                opacity: cardItem.isSelected || cardMouse.containsMouse ? 1.0 : 0.88
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            // Favorite Badge (Star icon)
                            Rectangle {
                                id: favBadge
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                height: 20
                                width: 22
                                radius: root.cornerRadius > 0 ? 10 : 0
                                color: isFavorited ? root.seal : Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.75)
                                border.color: isFavorited ? root.seal : root.sep
                                border.width: 1
                                visible: isFavorited || cardMouse.containsMouse

                                readonly property bool isFavorited: !!wallpaperWindow.favoritesMap[modelData.path]

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰓎"
                                    color: favBadge.isFavorited ? root.paper : root.inkDeep
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wallpaperWindow.toggleFavorite(modelData);
                                        surface.forceActiveFocus();
                                    }
                                }
                            }

                            // Active Wallpaper Badge
                            Rectangle {
                                visible: cardItem.isActive
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                height: 20
                                width: activeBadgeRow.width + 12
                                radius: root.cornerRadius > 0 ? 10 : 0
                                color: root.seal

                                Row {
                                    id: activeBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "󰄬"
                                        color: root.paper
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        text: "ACTIVE"
                                        color: root.paper
                                        font.family: root.mono
                                        font.pixelSize: 9
                                        font.letterSpacing: 1
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            // Bottom Wallpaper Name Scrim
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 38
                                color: Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.88)
                                border.color: root.sep
                                border.width: 1

                                Column {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: modelData.name
                                        color: cardItem.isSelected ? root.seal : root.ink
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Row {
                                        spacing: 8
                                        Text {
                                            text: wallpaperWindow.formatSize(modelData.size)
                                            color: root.inkDeep
                                            font.family: root.mono
                                            font.pixelSize: 9
                                        }
                                        Text {
                                            visible: !!wallpaperWindow.favoritesMap[modelData.path]
                                            text: "󰓎 FAV"
                                            color: root.seal
                                            font.family: root.mono
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wallpaperWindow.selectedIndex = cardItem.index;
                                surface.forceActiveFocus();
                            }
                            onDoubleClicked: {
                                wallpaperWindow.selectedIndex = cardItem.index;
                                wallpaperWindow.applyWallpaper(cardItem.modelData);
                                surface.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.sep
            }

            // Footer Tooltip / Shortcut Hints Row
            Item {
                width: parent.width
                height: 28

                // Leftmost corner: sorting indicator and favorites category toggle
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Sort indicator letter
                    Item {
                        width: sortLetter.implicitWidth + 8
                        height: parent.height

                        Text {
                            id: sortLetter
                            anchors.centerIn: parent
                            text: wallpaperWindow.pendingSortPrefix ? "," : wallpaperWindow.sortMode
                            color: root.seal
                            font.family: root.mono
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const sorts = ["M", "m", "B", "b", "a", "A", "S", "s", "r"];
                                const idx = sorts.indexOf(wallpaperWindow.sortMode);
                                wallpaperWindow.setSort(sorts[(idx + 1) % sorts.length]);
                                surface.forceActiveFocus();
                            }
                        }
                    }

                    // Favs category indicator icon
                    Item {
                        width: favCatIcon.implicitWidth + 8
                        height: parent.height

                        Text {
                            id: favCatIcon
                            anchors.centerIn: parent
                            text: "󰓎"
                            color: wallpaperWindow.favOnlyMode ? root.seal : root.inkDeep
                            opacity: wallpaperWindow.favOnlyMode ? 1.0 : 0.35
                            font.family: root.mono
                            font.pixelSize: 12
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wallpaperWindow.toggleFavoritesCategory();
                                surface.forceActiveFocus();
                            }
                        }
                    }
                }

                // Center / Tooltip hints
                Text {
                    anchors.centerIn: parent
                    text: wallpaperWindow.appliedToast.length > 0
                          ? wallpaperWindow.appliedToast
                          : (wallpaperWindow.pendingSortPrefix
                             ? "SORT: (M/m)odified · (B/b)irth · (a/A)lphabetical · (S/s)ize · (r)andom"
                             : "h/l: Navigate  ·  M/m: Mod  ·  B/b: Birth  ·  a/A: Name  ·  S/s: Size  ·  ^S: Star  ·  ^F: " + (wallpaperWindow.favOnlyMode ? "All" : "Favs") + "  ·  /: Search  ·  ↵: Apply")
                    color: wallpaperWindow.appliedToast.length > 0 || wallpaperWindow.pendingSortPrefix ? root.seal : root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    opacity: wallpaperWindow.appliedToast.length > 0 || wallpaperWindow.pendingSortPrefix ? 1.0 : 0.75
                    Behavior on color { ColorAnimation { duration: 140 } }
                }

                // Rightmost corner: wallpaper count (clickable to toggle favorites category)
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: wallpaperWindow.favOnlyMode
                          ? ("󰓎 " + wallpaperWindow.filteredWallpapers.length + " FAVORITES")
                          : (wallpaperWindow.favoritesList.length > 0
                             ? (wallpaperWindow.filteredWallpapers.length + " WALLPAPERS (󰓎 " + wallpaperWindow.favoritesList.length + ")")
                             : (wallpaperWindow.filteredWallpapers.length + " WALLPAPERS"))
                    color: wallpaperWindow.favOnlyMode ? root.seal : root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    opacity: wallpaperWindow.favOnlyMode ? 1.0 : 0.6

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wallpaperWindow.toggleFavoritesCategory();
                            surface.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }
}
