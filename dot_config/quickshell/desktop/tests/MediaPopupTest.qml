import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 720; height: 480; visible: true
        Item {
            id: test
            property int phase: 0
            property var players: []
            function check(ok, message) {
                if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); }
            }
            function player(name) { return playerComponent.createObject(test, {identity: name}); }
            Component {
                id: playerComponent
                QtObject {
                    property string identity: ""
                    property real position: 0
                    property bool lengthSupported: true
                    property real length: 100
                    property bool isPlaying: false
                    property bool canSeek: false
                    property string dbusName: ""
                    property string trackAlbum: ""
                    property string trackTitle: ""
                }
            }
            QtObject {
                id: fakeRoot
                property bool mediaVisible: true
                property var mprisPlayers: test.players
                property var musicPlayer: null
                property string musicTitle: "Title"
                property string musicArtist: "Artist"
                property bool musicPlaying: false
                property string barEdge: ""
                property real popupAnchorX: 0
                property real popupAnchorY: 0
                property int testPanelWidth: 720
                property int testPanelHeight: 480
                property string mono: "monospace"
                property color fg: "white"
                property color ink: "white"
                property color inkDeep: "gray"
                property color seal: "blue"
                property color sep: "gray"
                property real cornerRadius: 4
                function selectMusicPlayer(player) { musicPlayer = player; }
                function musicToggle() {}
                function musicPrev() {}
                function musicNext() {}
                function musicPrevSource() {}
                function musicNextSource() {}
                function runCommand(a, b) {}
            }
            MediaPopup { id: popup; root: fakeRoot }
            Timer {
                interval: 100; repeat: true; running: true
                onTriggered: {
                    switch (test.phase++) {
                    case 0:
                        test.players = [test.player("one"), test.player("two"), test.player("three"), test.player("four"), test.player("five"), test.player("six")];
                        fakeRoot.musicPlayer = test.players[5];
                        break;
                    case 1:
                        test.check(popup.testClipped && popup.testScrollbarVisible, "overflow must be clipped and scrollable");
                        test.check(popup.testX > 0 && popup.testItem(5).x + popup.testItem(5).width <= popup.testX + popup.testWidth + 1, "selected player is not visible");
                        popup.testClick(0);
                        break;
                    case 2:
                        test.check(fakeRoot.musicPlayer === test.players[0] && popup.testX === 0 && popup.testItem(0).selected, "button selection did not reveal first player");
                        popup.testWheel(-120);
                        test.check(popup.testX > 0 && popup.testMetadataX === 0, "wheel did not scroll only player strip");
                        test.players = [test.players[0]];
                        break;
                    case 3:
                        test.check(popup.testX === 0 && !popup.testScrollbarVisible, "removal did not clamp scroll");
                        test.players = [test.player("A very long player identity that exceeds the entire available width and remains reachable by scrolling")];
                        fakeRoot.musicPlayer = test.players[0];
                        break;
                    case 4:
                        test.check(popup.testContentWidth > popup.testWidth && popup.testX === 0, "long selected label must start visible");
                        popup.testWheel(-10000);
                        test.check(Math.abs(popup.testX - (popup.testContentWidth - popup.testWidth)) < 1, "long label end is unreachable");
                        popup.cardWidth = 250;
                        break;
                    case 5:
                        test.check(popup.testX === 0, "viewport change did not reveal selected player");
                        console.log("media popup regression tests passed");
                        Qt.exit(0);
                    }
                }
            }
        }
    }
}
