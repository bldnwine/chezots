import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 1200; height: 1000; visible: true
        Item {
            id: test
            property int phase: 0
            function check(ok, message) { if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); } }
            function devices(count, name) {
                let list = [];
                for (let i = 0; i < count; ++i) list.push({id: name + i, name: name + i, port: "p", portLabel: "", isActive: false});
                return list;
            }
            function streams(count) {
                let list = [];
                for (let i = 0; i < count; ++i) list.push({id:i, name:"app" + i, description:"app", ready:true, properties:{"application.name":"App", "media.name":"Track"}, audio:{channels:[1], volume:0.5, muted:false}});
                return list;
            }
            function checkGeometry(expected) {
                test.check(Math.abs(popup.testSurfaceHeight - expected) < 1, "card height changed");
                test.check(popup.testBodyBottom <= popup.testFooterTop + 1, "body overlaps footer");
                test.check(popup.testFooterBottomInSurface <= popup.testSurfaceHeight + 1, "footer extends past card");
                // Deck is mapped to the card; the card body geometry is relative to bodyCol.
                test.check(popup.testDeckBottom <= popup.testActualBodyBottom + 1, "deck extends past body");
                test.check(popup.testScrollHeight >= 0, "negative deck height");
            }
            QtObject {
                id: fakeRoot
                property int testPanelWidth: 1200
                property int testPanelHeight: 1000
                property real barOffset: 30
                property string barEdge: "top"
                property real popupAnchorX: 400
                property real popupAnchorY: 0
                property bool audioVisible: true
                property var audioSinks: []
                property var audioSources: []
                property var testStreams: []
                property string audioDeviceError: ""
                property int audioVol: 50
                property bool audioMuted: false
                property int audioInputVol: 50
                property bool audioInputMuted: false
                property string audioSinkDesc: ""
                property string mono: "monospace"
                property color bg: "black"
                property color fg: "white"
                property color ink: "white"
                property color inkDeep: "gray"
                property color seal: "blue"
                property color sep: "gray"
                property color rowSel: "#333333"
                property color rowHi: "#222222"
                property color warn: "red"
                property real cornerRadius: 4
                function setAudioVolume(v) {}
                function setInputVolume(v) {}
                function toggleAudioMute() {}
                function toggleInputMute() {}
                function setDefaultSink(id, port) {}
                function setDefaultSource(id, port) {}
                function run(command) {}
            }
            AudioPopup { id: popup; root: fakeRoot }
            Timer {
                interval: 120; repeat: true; running: true
                onTriggered: {
                    switch (test.phase++) {
                    case 0:
                        test.checkGeometry(760);
                        fakeRoot.audioSinks = test.devices(16, "sink");
                        fakeRoot.audioSources = test.devices(16, "source");
                        fakeRoot.testStreams = test.streams(6);
                        fakeRoot.audioDeviceError = "A device error that wraps over multiple lines to exercise layout stability";
                        break;
                    case 1:
                        test.checkGeometry(760);
                        popup.selectKbd(popup.kbdRows.length - 1);
                        break;
                    case 2:
                        test.check(popup.testScrollY > 0 && popup.testSelectionVisible(), "keyboard selection was not scrolled into view");
                        popup.eqExpanded = true;
                        break;
                    case 3:
                        test.checkGeometry(760);
                        test.check(popup.testSelectionVisible(), "selection not visible after expanding EQ");
                        fakeRoot.testPanelHeight = 450;
                        break;
                    case 4:
                        test.checkGeometry(404);
                        test.check(popup.testSelectionVisible(), "selection not visible after panel resize");
                        fakeRoot.audioSinks = [];
                        fakeRoot.audioSources = [];
                        fakeRoot.testStreams = [];
                        fakeRoot.audioDeviceError = "";
                        popup.eqExpanded = false;
                        break;
                    case 5:
                        test.checkGeometry(404);
                        test.check(popup.testScrollY === 0, "scroll not clamped on removal");
                        console.log("audio popup regression tests passed");
                        Qt.exit(0);
                    }
                }
            }
        }
    }
}
