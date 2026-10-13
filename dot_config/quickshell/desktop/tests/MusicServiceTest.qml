import QtQuick
import Quickshell
import ".." as Desktop

ShellRoot {
    id: test
    function check(condition, message) { if (!condition) throw new Error(message); }

    QtObject {
        id: a
        property string dbusName: "org.mpris.MediaPlayer2.browser.a"
        property string identity: "Browser"
        property string trackTitle: "Song A"
        property string trackArtist: "Artist A"
        property bool isPlaying: true
    }
    QtObject {
        id: b
        property string dbusName: "org.mpris.MediaPlayer2.browser.b"
        property string identity: "Browser"
        property string trackTitle: "Song B"
        property string trackArtist: "Artist B"
        property bool isPlaying: true
    }
    QtObject {
        id: c
        property string dbusName: "org.mpris.MediaPlayer2.music"
        property string identity: "Music"
        property string trackTitle: "Song C"
        property string trackArtist: "Artist C"
        property bool isPlaying: false
    }
    QtObject {
        id: proxy
        property string dbusName: "org.mpris.MediaPlayer2.playerctld"
        property string identity: "playerctld"
        property string trackTitle: "Proxy song"
        property string trackArtist: ""
        property bool isPlaying: true
    }
    Desktop.MusicService { id: service; inputPlayers: [proxy, a, b, c, a] }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            test.check(service.players.length === 3, "proxy exclusion or D-Bus dedup failed");
            test.check(service.selectedPlayer === a, "startup should choose the first playing source");
            b.isPlaying = false;
            b.isPlaying = true;
            test.check(service.selectedPlayer === b, "most recent resume did not win");
            a.trackTitle = "Next song A";
            test.check(service.selectedPlayer === b, "metadata stole selection");
            service.selectPlayer(c);
            b.trackArtist = "Updated artist";
            b.isPlaying = false;
            test.check(service.selectedPlayer === c, "manual paused selection was not preserved");
            a.isPlaying = false;
            a.isPlaying = true;
            test.check(service.selectedPlayer === a, "new playback did not clear manual selection");
            test.check(service.title === a.trackTitle && service.artist === a.trackArtist && service.playing, "metadata bindings are stale");
            b.isPlaying = true;
            test.check(service.selectedPlayer === b, "second playing source did not win");
            b.isPlaying = false;
            test.check(service.selectedPlayer === a, "paused automatic source did not fall back to playing source");
            service.cycleSource(1);
            test.check(service.selectedPlayer === b, "scroll did not advance from current source");
            service.cycleSource(-1);
            test.check(service.selectedPlayer === a, "scroll backwards failed");
            service.cycleSource(-1);
            test.check(service.selectedPlayer === c, "scroll did not wrap using filtered list");
            service.inputPlayers = [c, b, proxy, a];
            test.check(service.selectedPlayer === c, "reordering changed manual source");
            a.isPlaying = false;
            a.trackTitle = "Changed while paused";
            test.check(service.selectedPlayer === c, "pause or metadata cleared manual source");
            service.inputPlayers = [b, a, proxy];
            test.check(service.selectedPlayer === b, "removed manual source did not choose titled fallback");
            b.trackTitle = "";
            test.check(service.selectedPlayer === a, "empty paused title did not choose titled fallback");
            service.inputPlayers = [c, a];
            c.isPlaying = true;
            test.check(service.selectedPlayer === c, "newly added source was not observed");
            service.inputPlayers = [a];
            test.check(service.selectedPlayer === a, "removed playing source left stale selection");
            service.inputPlayers = [];
            test.check(service.selectedPlayer === null && service.title === "" && !service.playing, "last player removal did not clear state");
            console.log("music service regression tests passed");
            Qt.quit();
        }
    }
}
