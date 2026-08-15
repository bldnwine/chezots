import QtQuick
import Quickshell.Services.Mpris
import Quickshell
import Quickshell.Io

// Media popup — MPRIS player controls, track metadata, player source switcher,
// progress seek slider, and transport controls. Backed by Navbar's Mpris
// players probe.
CardWindow {
    id: mediaPopup
    required property var root

    theme: root
    plain: true
    revealed: root.mediaVisible
    cardWidth: 390
    layerNamespace: "omarchy-media"

    anchorEdge: mediaPopup.root.barEdge
    anchorBarX: mediaPopup.root.popupAnchorX
    anchorBarY: mediaPopup.root.popupAnchorY

    onDismiss: mediaPopup.root.mediaVisible = false

    onKeyPressed: (event) => {
        const k = event.key;
        if (k === Qt.Key_Space || k === Qt.Key_K) {
            mediaPopup.root.musicToggle();
            event.accepted = true;
        } else if (k === Qt.Key_Left || k === Qt.Key_H) {
            mediaPopup.root.run("playerctl position 5-");
            event.accepted = true;
        } else if (k === Qt.Key_Right || k === Qt.Key_L) {
            mediaPopup.root.run("playerctl position 5+");
            event.accepted = true;
        } else if (k === Qt.Key_B) {
            mediaPopup.root.musicPrev();
            event.accepted = true;
        } else if (k === Qt.Key_N) {
            mediaPopup.root.musicNext();
            event.accepted = true;
        } else if (k === Qt.Key_Up) {
            mediaPopup.root.musicPrevSource();
            event.accepted = true;
        } else if (k === Qt.Key_Down) {
            mediaPopup.root.musicNextSource();
            event.accepted = true;
        }
    }

    property var activePlayer: mediaPopup.root.musicPlayer
    property var playerList: mediaPopup.root.mprisPlayers
    property real latchedLength: 0

    readonly property bool isBrowserPlayer: {
        if (!activePlayer) return false;
        const dbus = (activePlayer.dbusName || "").toLowerCase();
        return dbus.indexOf("firefox") >= 0 || dbus.indexOf("zen") >= 0 || dbus.indexOf("chromium") >= 0 || dbus.indexOf("chrome") >= 0;
    }

    function syncBrowserLength() {
        if (!isBrowserPlayer || !activePlayer || len > 0 || seekArmed || seekRunner.running) return;
        const pfx = "org.mpris.MediaPlayer2.";
        const raw = activePlayer.dbusName || "";
        const pname = raw.indexOf(pfx) === 0 ? raw.slice(pfx.length) : raw;
        seekRunner.command = ["playerctl", "-p", pname, "metadata", "mpris:length"];
        seekRunner.running = false;
        seekRunner.running = true;
    }

    // ---- Seek state (matched to mediahero.qml) ----
    readonly property real posn: activePlayer ? activePlayer.position : 0
    readonly property bool lengthKnown: activePlayer
        ? (!!activePlayer.lengthSupported && activePlayer.length > 0)
        : false
    readonly property real len: {
        if (!activePlayer) return 0;
        if (lengthKnown) return activePlayer.length;
        if (latchedLength > 0) return latchedLength;
        return 0;
    }
    readonly property real liveFrac: len > 0 ? Math.max(0, Math.min(1, posn / len)) : 0
    property bool seekArmed: false
    property bool seekSent: false
    property real seekFrac: 0
    readonly property real shownFrac: seekArmed ? seekFrac : liveFrac

    function onScrub(frac) {
        mediaPopup.seekFrac = Math.max(0, Math.min(1, frac));
        mediaPopup.seekArmed = true;
        mediaPopup.seekSent = false;
        seekDebounce.restart();
    }

    // Position poll — drives the progress bar while playing
    Timer {
        interval: 500; repeat: true
        running: mediaPopup.revealed && mediaPopup.activePlayer !== null
                 && mediaPopup.activePlayer.isPlaying
        onTriggered: {
            mediaPopup.activePlayer.positionChanged();
            if (mediaPopup.len <= 0) mediaPopup.syncBrowserLength();
            if (mediaPopup.seekSent && mediaPopup.len > 0
                && Math.abs(mediaPopup.posn - mediaPopup.seekFrac * mediaPopup.len) < 1.5) {
                mediaPopup.seekArmed = false;
                mediaPopup.seekSent = false;
                seekIgnore.stop();
            }
        }
    }

    Process {
        id: seekRunner
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                const us = parseInt(txt, 10);
                if (!isNaN(us) && us > 0 && us < 86400000000000) {
                    const sec = Math.round(us / 1000000);
                    if (sec > 0) mediaPopup.latchedLength = sec;
                }
            }
        }
    }

    // Debounce: waits 300ms after last scrub movement, then seeks
    Timer {
        id: seekDebounce; interval: 300
        onTriggered: {
            if (mediaPopup.activePlayer && mediaPopup.len > 0) {
                const target = Math.round(mediaPopup.seekFrac * mediaPopup.len);
                const dbus = (mediaPopup.activePlayer.dbusName || "").toLowerCase();
                const isBrowser = dbus.indexOf("firefox") >= 0 || dbus.indexOf("zen") >= 0;
                if (isBrowser) {
                    const pfx = "org.mpris.MediaPlayer2.";
                    const raw = mediaPopup.activePlayer.dbusName || "";
                    const pname = raw.indexOf(pfx) === 0 ? raw.slice(pfx.length) : raw;
                    seekRunner.command = ["playerctl", "-p", pname, "position", String(target)];
                    seekRunner.running = false;
                    seekRunner.running = true;
                } else {
                    mediaPopup.activePlayer.position = target;
                }
                mediaPopup.seekSent = true;
                seekIgnore.restart();
            } else {
                mediaPopup.seekArmed = false;
            }
        }
    }

    // Fallback disarm — if position never converges, give up after 3s
    Timer {
        id: seekIgnore; interval: 3000
        onTriggered: { mediaPopup.seekArmed = false; mediaPopup.seekSent = false; }
    }

    Connections {
        target: mediaPopup.activePlayer
        function onLengthChanged() {
            if (mediaPopup.lengthKnown) mediaPopup.latchedLength = mediaPopup.activePlayer.length;
        }
        function onLengthSupportedChanged() {
            if (mediaPopup.lengthKnown) mediaPopup.latchedLength = mediaPopup.activePlayer.length;
            else if (mediaPopup.len <= 0) mediaPopup.syncBrowserLength();
        }
        function onTrackTitleChanged() {
            seekDebounce.stop();
            seekIgnore.stop();
            mediaPopup.seekArmed = false;
            mediaPopup.seekSent = false;
            mediaPopup.latchedLength = mediaPopup.lengthKnown ? mediaPopup.activePlayer.length : 0;
            if (mediaPopup.latchedLength <= 0) mediaPopup.syncBrowserLength();
        }
    }

    onRevealedChanged: if (revealed && len <= 0) syncBrowserLength();
    onActivePlayerChanged: {
        seekDebounce.stop();
        seekIgnore.stop();
        mediaPopup.seekArmed = false;
        mediaPopup.seekSent = false;
        mediaPopup.latchedLength = activePlayer && activePlayer.lengthSupported
            && activePlayer.length > 0 ? activePlayer.length : 0;
        if (mediaPopup.latchedLength <= 0) syncBrowserLength();
    }

    function formatTime(seconds) {
        if (!seconds || seconds <= 0 || isNaN(seconds)) return "00:00";
        const sec = Math.floor(seconds);
        const m = Math.floor(sec / 60);
        const s = sec % 60;
        const padS = s < 10 ? "0" + s : "" + s;
        if (m < 60) {
            const padM = m < 10 ? "0" + m : "" + m;
            return padM + ":" + padS;
        }
        const h = Math.floor(m / 60);
        const remM = m % 60;
        const padRM = remM < 10 ? "0" + remM : "" + remM;
        return h + ":" + padRM + ":" + padS;
    }

    Column {
        id: col
        width: parent.width
        spacing: 12

        // Player source switcher chips row
        Row {
            width: parent.width
            spacing: 6
            visible: mediaPopup.playerList.length > 0

            Repeater {
                model: mediaPopup.playerList
                delegate: QuickButton {
                    required property var modelData
                    required property int index
                    root: mediaPopup.root
                    label: (modelData.identity || modelData.desktopEntry || ("Player " + (index + 1))).toUpperCase()
                    selected: mediaPopup.activePlayer === modelData
                    onClicked: mediaPopup.root.selectMusicPlayer(modelData)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.sep
            visible: mediaPopup.playerList.length > 0
        }

        // Track metadata
        Column {
            width: parent.width
            spacing: 4

            Text {
                width: parent.width
                text: mediaPopup.root.musicTitle ? mediaPopup.root.musicTitle : "No Active Media"
                color: root.fg
                font.family: root.mono
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: mediaPopup.root.musicArtist ? mediaPopup.root.musicArtist : (mediaPopup.activePlayer ? (mediaPopup.activePlayer.identity || "Unknown Artist") : "Select a player")
                color: root.ink
                font.family: root.mono
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: mediaPopup.activePlayer && mediaPopup.activePlayer.trackAlbum ? mediaPopup.activePlayer.trackAlbum : ""
                color: root.inkDeep
                font.family: root.mono
                font.pixelSize: 10
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }

        // Progress & Time bar
        Column {
            width: parent.width
            spacing: 4
            visible: mediaPopup.activePlayer !== null

            Row {
                width: parent.width
                Item {
                    width: parent.width / 2
                    height: 14
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: mediaPopup.len > 0
                            ? mediaPopup.formatTime(mediaPopup.shownFrac * mediaPopup.len)
                            : mediaPopup.formatTime(mediaPopup.posn)
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                    }
                }
                Item {
                    width: parent.width / 2
                    height: 14
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: mediaPopup.len > 0 ? mediaPopup.formatTime(mediaPopup.len) : (mediaPopup.root.musicTitle ? "--:--" : "LIVE")
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                    }
                }
            }

            // Seek slider bar container with a 24px touch target
            Item {
                width: parent.width
                height: 24
                visible: mediaPopup.activePlayer !== null

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)

                    Rectangle {
                        width: parent.width * mediaPopup.shownFrac
                        height: parent.height
                        radius: parent.radius
                        color: root.seal
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    enabled: mediaPopup.activePlayer !== null
                             && mediaPopup.len > 0
                             && mediaPopup.activePlayer.canSeek
                    onPressed: mouse => mediaPopup.onScrub(mouse.x / width)
                    onPositionChanged: mouse => { if (pressed) mediaPopup.onScrub(mouse.x / width) }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: root.sep }

        // Playback transport buttons row
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            QuickButton {
                root: mediaPopup.root
                label: "⏮ PREV"
                onClicked: mediaPopup.root.musicPrev()
            }

            QuickButton {
                root: mediaPopup.root
                label: mediaPopup.root.musicPlaying ? "⏸ PAUSE" : "▶ PLAY"
                selected: true
                onClicked: mediaPopup.root.musicToggle()
            }

            QuickButton {
                root: mediaPopup.root
                label: "NEXT ⏭"
                onClicked: mediaPopup.root.musicNext()
            }
        }
    }
}
