import QtQuick
import Quickshell

ShellRoot {
    Window {
        width: 720
        height: 480
        visible: true
        QtObject {
            id: theme
            property string mono: "monospace"
            property color indigo: "#8888ff"
            property color bg: "#111111"
            property color ink: "#eeeeee"
            property color sep: "#555555"
            property color seal: "#ff5555"
            property color paper: "#000000"
            property color rowHi: "#222222"
            property int cornerRadius: 4
        }
        PolkitAgent { id: agent; theme: theme }
        Timer {
            property int phase: 0
            interval: 100
            repeat: true
            running: true
            function check(ok, message) {
                if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); }
            }
            onTriggered: {
                switch (phase++) {
                case 0:
                    agent.syncFromFlow();
                    check(agent.cardHeight === 52 && agent.cardWidth === 380, "empty command geometry");
                    agent.extractedCommand = "echo ok";
                    break;
                case 1:
                    check(agent.commandHeight >= 30 && agent.commandHeight < 180, "short command geometry");
                    agent.extractedCommand = "<b>literal</b>\n" + "x".repeat(1000) + "\nlast line";
                    break;
                case 2:
                    check(agent.testCommandText === agent.extractedCommand, "command text changed");
                    check(agent.commandHeight === 180 && agent.testContentHeight > agent.testCommandHeight, "long command must scroll");
                    check(agent.testRowBottom() === agent.cardHeight && agent.testInputVisible, "authentication row is clipped");
                    check(agent.testInputMasked, "password masking changed");
                    agent.testScrollToEnd();
                    check(agent.testScrollY > 0, "command cannot scroll to end");
                    agent.testPanelWidth = 220;
                    agent.testPanelHeight = 150;
                    break;
                case 3:
                    check(agent.cardWidth === 188 && agent.cardHeight <= 118, "card exceeds small panel margins");
                    check(agent.testContentHeight > agent.testCommandHeight && agent.testRowBottom() === agent.cardHeight, "small panel clips authentication row");
                    agent.testSetInput("secret");
                    agent.submitResponse();
                    check(agent.testFlow.submittedText === "secret" && agent.testInputText === "" && agent.submitted, "submission changed");
                    agent.triggerFailureFeedback();
                    check(agent.errorFlash && !agent.submitted && agent.testInputText === "", "failure feedback changed");
                    agent.errorFlash = false;
                    agent.testFlow.isResponseRequired = false;
                    agent.testFlow.inputPrompt = "Swipe fingerprint";
                    agent.syncFromFlow();
                    break;
                case 4:
                    check(agent.fingerprintWaiting && !agent.testInputVisible, "fingerprint waiting changed");
                    agent.extractedCommand = "echo next";
                    check(agent.testScrollY === 0, "new request retained old command scroll");
                    agent.cancelRequest();
                    check(agent.testFlow.cancelled && agent.closing, "cancellation changed");
                    console.log("polkit geometry tests passed");
                    Qt.quit();
                }
            }
        }
    }
}
