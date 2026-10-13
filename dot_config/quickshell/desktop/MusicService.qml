import QtQuick
import QtQml.Models

// Event-driven selection. D-Bus names identify sources; display names need
// not be unique (for example, two browser windows).
Item {
    id: root
    visible: false

    property var inputPlayers: []
    property var players: {
        const seen = {};
        return root.inputPlayers.filter(function(player) {
            if (!player || !player.dbusName) return false;
            const name = player.dbusName;
            if (/playerctld/i.test(name) || /playerctld/i.test(player.identity || "")) return false;
            if (seen[name]) return false;
            seen[name] = true;
            return true;
        });
    }
    property var selectedPlayer: null
    readonly property string title: selectedPlayer ? selectedPlayer.trackTitle || "" : ""
    readonly property string artist: selectedPlayer ? selectedPlayer.trackArtist || "" : ""
    readonly property bool playing: selectedPlayer ? Boolean(selectedPlayer.isPlaying) : false

    property string _manualName: ""
    property var _known: ({})
    property int _sequence: 0
    property bool _initialized: false

    function reconcile(initial) {
        const next = {};
        for (const player of root.players) {
            const name = player.dbusName;
            const previous = root._known[name];
            let started = previous ? previous.started : 0;
            if (!initial && player.isPlaying && (!previous || previous.player !== player || !previous.playing)) {
                started = ++root._sequence;
                if (name !== root._manualName) root._manualName = "";
            }
            next[name] = { player: player, playing: Boolean(player.isPlaying), started: started };
        }
        root._known = next;
        if (root._manualName && !next[root._manualName]) root._manualName = "";

        let best = root._manualName ? next[root._manualName].player : null;
        if (!best) {
            // Keep the current source on a tie, including startup where
            // playback history is unknown. Genuine starts break the tie.
            if (root.selectedPlayer && root.players.indexOf(root.selectedPlayer) !== -1 && root.selectedPlayer.isPlaying)
                best = root.selectedPlayer;
            for (const player of root.players) {
                if (player.isPlaying && (!best || next[player.dbusName].started > next[best.dbusName].started)) best = player;
            }
        }
        if (!best && root.selectedPlayer && root.players.indexOf(root.selectedPlayer) !== -1 && root.selectedPlayer.trackTitle)
            best = root.selectedPlayer;
        if (!best) {
            for (const player of root.players) {
                if (player.trackTitle && (!best || next[player.dbusName].started > next[best.dbusName].started)) best = player;
            }
        }
        root.selectedPlayer = best;
    }

    function selectPlayer(player) {
        if (root.players.indexOf(player) === -1) return;
        root._manualName = player.dbusName;
        root.selectedPlayer = player;
    }

    function cycleSource(delta) {
        if (!root.players.length) return;
        const index = root.players.indexOf(root.selectedPlayer);
        const next = index < 0 ? (delta > 0 ? 0 : root.players.length - 1)
            : (index + delta + root.players.length) % root.players.length;
        root.selectPlayer(root.players[next]);
    }

    onPlayersChanged: if (root._initialized) root.reconcile(false)
    Component.onCompleted: {
        root.reconcile(true);
        root._initialized = true;
    }

    Instantiator {
        model: root.players
        delegate: Item {
            required property var modelData
            Connections {
                target: modelData
                function onIsPlayingChanged() { root.reconcile(false); }
                function onTrackTitleChanged() { root.reconcile(false); }
                function onTrackArtistChanged() { root.reconcile(false); }
            }
        }
    }
}
