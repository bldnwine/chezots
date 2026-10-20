import QtQuick
import Quickshell

ShellRoot {
    id: test
    property int phase: 0
    property double testStarted: Date.now()
    property bool connectFinished: false
    property bool connectOk: true
    property int stageTicks: 0
    function helper(mode) { return ["python3", Quickshell.env("QS_TEST_NETWORK_HELPER"), mode || ""]; }
    function check(ok, message) {
        if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); }
    }
    NetworkService {
        id: service
        helperCommand: ["python3", Quickshell.env("QS_TEST_NETWORK_HELPER")]
        actionTimeoutMs: 250
        scanTimeoutMs: 1000
        stateTimeoutMs: 1000
        detailsTimeoutMs: 500
        cleanupGraceMs: 100
    }
    NetworkService {
        id: missing
        helperCommand: ["qs-network-helper-that-does-not-exist"]
        actionTimeoutMs: 250
    }
    Connections { target: service
        function onWifiConnectResult(ssid, ok) { test.connectFinished=true; test.connectOk=ok; }
    }
    Timer {
        interval: 30; repeat: true; running: true
        onTriggered: {
            switch (test.phase) {
            case 0:
                service.viewVisible=true;
                test.phase=1;
                break;
            case 1:
                if (service.networks.length) {
                    service.requestScan();
                    test.check(service.wifiConnect("timeout-fixture","not-logged-secret"), "action was not accepted");
                    test.check(service.busy, "busy did not set before process start");
                    test.check(!service.request("connect",{ssid:"two"}), "connect overlapped");
                    test.check(!service.request("disconnect",{}), "disconnect overlapped");
                    test.check(!service.request("radio",{enabled:false}), "radio overlapped");
                    test.check(!service.request("forget",{ssid:"x"}), "forget overlapped");
                    test.check(!service.request("autoconnect",{ssid:"x"}), "autoconnect overlapped");
                    service.viewVisible=false;
                    test.phase=2;
                }
                break;
            case 2:
                if (test.connectFinished) {
                    test.check(!test.connectOk && service.wifiErrorKind==="timeout", "timeout did not report/release action");
                    test.check(!service.busy && service.wifiActionText==="", "timeout left stale busy text");
                    test.check(!service.pingSamples.length, "closed details retained samples");
                    test.phase=3;
                }
                break;
            case 3:
                missing.beginMutation("disconnect",{});
                test.phase=4;
                break;
            case 4:
                if (!missing.busy && missing.wifiError) {
                    test.check(missing.wifiErrorKind==="unavailable", "failed launch was not classified");
                    service.viewVisible=true;
                    service.applyDetails({iface:"a",ip:"1",gateway:"g",rx_bytes:100,tx_bytes:200,sample_time:1,internet_ping_ms:10});
                    service.applyDetails({iface:"b",ip:"1",gateway:"g",rx_bytes:100,tx_bytes:200,sample_time:2,internet_ping_ms:null});
                    test.check(service.downloadRate===0 && service.pingSamples.length===1, "route identity did not reset rates/pings");
                    test.check(service.packetLoss===100, "packet loss was not sampled across rolling window");
                    service.viewVisible=false;
                    test.connectFinished=false;
                    service.actionTimeoutMs=1500;
                    test.check(service.wifiConnect("slow-fixture", "not-logged-secret"), "closed connect rejected");
                    test.phase=5;
                }
                break;
            case 5:
                if (test.connectFinished) {
                    test.check(test.connectOk && !service.busy, "closing cancelled a valid connect: " + service.wifiError + " " + service.wifiErrorKind);
                    test.check(!service.viewVisible && !service.scanning, "closed action enabled polling");
                    service.helperCommand=test.helper("late-scan");
                    service.viewVisible=true;
                    test.stageTicks=0;
                    test.phase=6;
                }
                break;
            case 6:
                if (++test.stageTicks >= 2) {
                    service.helperCommand=test.helper();
                    test.connectFinished=false;
                    service.wifiConnect("slow-fixture", "");
                    test.phase=7;
                }
                break;
            case 7:
                if (test.connectFinished && !service.scanning) {
                    test.check(test.connectOk && service.networks[0].ssid==="fixture", "cancelled scan clobbered action state");
                    service.helperCommand=test.helper("malformed");
                    service.requestScan("popup");
                    test.phase=8;
                }
                break;
            case 8:
                if (!service.scanning && service.wifiError) {
                    test.check(service.networks.length===1 && service.wifiErrorKind==="malformed", "malformed read erased cached list or hid error");
                    service.helperCommand=test.helper("hang-scan");
                    service.scanTimeoutMs=150;
                    service.requestScan("popup");
                    test.phase=9;
                }
                break;
            case 9:
                if (!service.scanning && service.wifiErrorKind==="timeout") {
                    service.viewVisible=false;
                    service.helperCommand=test.helper();
                    test.check(service.requestScan(), "external scan was rejected while popup hidden");
                    test.phase=10;
                }
                break;
            case 10:
                if (!service.scanning) {
                    test.check(service.wifiError==="" && service.networks.length===1, "successful retry did not clear read error");
                    service.helperCommand=test.helper("bad-details");
                    service.viewVisible=true;
                    test.phase=11;
                }
                break;
            case 11:
                if (service.netDetailsError) {
                    test.check(service.info.iface!=="bad", "malformed route details were applied");
                    service.copyText('literal $(printf injected) `printf injected` $HOME');
                    service.viewVisible=false;
                    test.stageTicks=0;
                    test.phase=12;
                }
                break;
            case 12:
                if (++test.stageTicks>=60) {
                    test.check(!service.scanning && !service.pingSamples.length, "closed popup retained active polling state");
                    console.log("network service lifecycle QML tests passed");
                    Qt.quit();
                    test.phase=13;
                }
                break;
            }
            if (test.phase > 0 && test.phase < 13 && Date.now()-test.testStarted > 9000) throw new Error("network lifecycle phase timed out: "+test.phase);
        }
    }
}
