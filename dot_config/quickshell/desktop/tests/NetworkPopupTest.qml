import QtQuick
import Quickshell

ShellRoot {
    Window {
      id: testWindow
      width: 720
      height: 480
      visible: true
      Item {
    id: test
    width: 720
    height: 480
    property int phase: 0
    property var nets: []
    property var captured: []
    property var rootModel: null
    function check(ok, message) {
        if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); }
    }
    function makeNets(count) {
        const list = [];
        for (let i = 0; i < count; ++i)
            list.push({ssid: "Network " + i, security: "WPA2-PSK", known: true, inUse: false, signal: 80-i});
        return list;
    }
    QtObject {
        id: fakeRoot
        property bool networkVisible: true
        property bool wifiRadioOn: true
        property var wifiNetworks: test.nets
        property bool wifiBusy: false
        property bool wifiScanning: false
        property string wifiActionText: ""
        property string wifiError: ""
        property string wifiErrorKind: ""
        property string netDetailsError: ""
        property string netKind: "wifi"
        property string wifiSsid: ""
        property int wifiSignal: 0
        property real barOffset: 0
        property int testPanelWidth: 720
        property int testPanelHeight: 480
        property real popupAnchorX: 320
        property real popupAnchorY: 20
        property string barEdge: ""
        property string mono: "monospace"
        property color bg: "#111111"
        property color fg: "#eeeeee"
        property color ink: "#eeeeee"
        property color inkDeep: "#aaaaaa"
        property color warn: "#ff5555"
        property color seal: "#55aaff"
        property color sep: "#555555"
        property color rowHi: "#222222"
        property color rowSel: "#333333"
        property real cornerRadius: 4
        property string icoRefresh: "R"
        property var netInfo: ({iface:"", rx_bytes:0, tx_bytes:0, ip:"", gateway:""})
        signal wifiConnectResult(string ssid, bool ok)
        function wifiConnect(ssid, password) { test.captured.push({ssid:ssid, password:password || ""}); }
        function toggleWifiRadio() {}
        function refreshWifi() {}
        function disconnectWifi() {}
        function wifiToggleAutoConnect(ssid) {}
        function forgetWifi(ssid) {}
        function copyNetworkText(text) { test.captured.push({copy:text}); }
        function wifiBarsGlyph(signal) { return "|||"; }
        function fmtPing(v) { return "—"; }
        function fmtLoss(v) { return "—"; }
        function fmtRate(v) { return "—"; }
        function fmtBytes(v) { return "—"; }
    }
    Loader {
        id: popupLoader
        active: true
        sourceComponent: Component {
            NetworkPopup { root: fakeRoot }
        }
    }
    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            const p = popupLoader.item;
            if (!p && test.phase !== 7) return;
            switch (test.phase++) {
            case 0:
                test.nets = test.makeNets(14);
                p.kbdIndex = 13;
                break;
            case 1:
                test.check(p.visibleNets.length === 14, "all networks should be retained");
                test.check(p.testScrollY > 0, "keyboard selection did not scroll list");
                test.check(p.cardHeight <= 550 && p.cardWidth <= 390, "popup card was not capped");
                fakeRoot.testPanelWidth = 300;
                fakeRoot.testPanelHeight = 300;
                test.check(p.cardWidth <= 284 && p.cardHeight <= 284 && p.cardHeight > 0,
                           "small-screen card exceeds available panel area");
                test.check(p.testScrollHeight > 0, "small-screen controls are unreachable");
                fakeRoot.testPanelWidth = 720;
                fakeRoot.testPanelHeight = 480;
                p.kbdIndex = 2;
                p._activateAt(2);
                test.check(p.passphraseSsid === "", "known PSK prompted before attempting saved credential");
                fakeRoot.wifiError = "Authentication failed";
                fakeRoot.wifiErrorKind = "auth";
                fakeRoot.wifiBusy = true;
                fakeRoot.wifiActionText = "Connecting to network…";
                p.statusText = "Old error";
                test.check(p.testStatusText === "Connecting to network…", "busy action text lost priority");
                fakeRoot.wifiBusy = false;
                p.statusText = "";
                fakeRoot.wifiConnectResult("Network 0", false);
                p._onWifiResult("Network 0", false);
                test.check(p.passphraseSsid === "" && p.retrySsid === "Network 0", "auth failure should offer explicit retry");
                fakeRoot.wifiErrorKind = "command";
                fakeRoot.wifiError = "Command failed";
                p._onWifiResult("Network 0", false);
                test.check(p.passphraseSsid === "" && p.retrySsid === "Network 0", "command failure should offer explicit retry");
                fakeRoot.wifiErrorKind = "auth";
                fakeRoot.wifiError = "Authentication failed";
                p._activateAt(p.kbdMax - 1);
                test.check(p.passphraseSsid === "Network 0", "retry activation did not open editor");
                break;
            case 2:
                test.check(p.testInputFocused, "passphrase field did not receive focus");
                test.check(p.testScrollY === 0, "editor did not scroll into view from the network list");
                p.testSetInput("literal secret");
                test.nets = test.makeNets(14);
                test.check(p.passphraseText === "literal secret", "model update lost typed secret");
                p._submitPassphrase();
                test.check(p.passphraseSsid === "" && p.testInputText === "", "submit did not clear hidden input");
                test.check(test.captured[test.captured.length-1].password === "literal secret", "password argument changed");
                test.check(p.retrySsid === "Network 0", "password retry not retained pending result");
                p._onWifiResult("Network 0", false);
                test.check(p.passphraseSsid === "" && p.retrySsid === "Network 0", "failed password attempt reopened editor automatically");
                fakeRoot.wifiErrorKind = "timeout";
                p._onWifiResult("Network 0", false);
                test.check(p.retrySsid === "", "timeout incorrectly offered password retry");
                p._activateAt(2);
                test.check(p.passphraseSsid === "", "saved network should not reopen editor");
                test.nets = [{ssid:"New",security:"WPA2-PSK",known:false,inUse:false,signal:80},
                             {ssid:"Enterprise",security:"8021x",known:false,inUse:false,signal:60}];
                break;
            case 3:
                p._activateAt(2);
                test.check(p.passphraseSsid === "New", "unknown PSK did not prompt immediately");
                p._cancelPassphrase();
                p._activateAt(3);
                test.check(p.passphraseSsid === "", "8021x should not prompt for PSK");
                p.kbdIndex = 3;
                p.kbdSsid = "Enterprise";
                test.nets = [{ssid:"New",security:"WPA2-PSK",known:false,inUse:false,signal:80}];
                test.check(p.kbdIndex < p.kbdMax && p.kbdSsid !== "Enterprise", "selection removal was not rehomed");
                fakeRoot.wifiErrorKind = "unavailable";
                p._onWifiResult("New", false);
                test.check(p.retrySsid === "", "unavailable error offered retry");
                test.captured = [];
                p._copy("literal $(echo x) `echo y`");
                test.check(test.captured[0].copy === "literal $(echo x) `echo y`", "clipboard text was modified");
                p._activateAt(2);
                test.check(p.testInputFocused, "unknown-PSK editor did not focus");
                p._cancelPassphrase();
                test.check(fakeRoot.networkVisible && !p.testInputFocused, "Esc cancel should retain popup and release editor focus");
                fakeRoot.networkVisible = false;
                break;
            case 4:
                test.check(p.kbdIndex === 0 && p.kbdSsid === "" && p.passphraseText === "" && p.testInputText === "", "close did not clear transient state");
                fakeRoot.networkVisible = true;
                test.check(!!popupLoader.item, "retained popup disappeared before Loader unload");
                break;
            case 5:
                fakeRoot.networkVisible = false;
                break;
            case 6:
                popupLoader.active = false;
                break;
            case 7:
                popupLoader.active = true;
                fakeRoot.networkVisible = true;
                break;
            case 8:
                test.check(!!popupLoader.item, "popup failed to reopen after Loader unload");
                fakeRoot.testPanelWidth = 300;
                fakeRoot.testPanelHeight = 300;
                test.nets = test.makeNets(14);
                p.kbdIndex = 13;
                break;
            case 9:
                test.check(p.testSelectionVisible(), "selected row is clipped on short screen");
                p.kbdIndex = 2;
                break;
            case 10:
                test.check(p.testSelectionVisible(), "first row is clipped after scrolling back");
                console.log("network popup regression tests passed");
                Qt.quit();
                break;
            }
        }
    }
}
      }
    }
