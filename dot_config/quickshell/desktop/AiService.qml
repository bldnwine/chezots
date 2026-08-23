import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool agentRunning: false
    property string agentState: "idle" // "working" | "finished" | "action_needed" | "idle"
    property int sessionCount: 0
    property var activeSessions: []
    property var primarySession: ({})

    property string currentModel: "Gemini 3.7 Flash"
    property string activeStatusText: "Inactive"
    property string conversationId: ""
    property string activeWorkspace: ""
    property string activeWorkspaceName: ""
    property string activeTitle: ""

    property var quotaGroups: []

    property bool ready: false
    property bool refreshing: false

    readonly property string scannerScript:
        Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/antigravity_usage_scanner.py"

    readonly property string statusText: {
        if (!root.agentRunning || root.sessionCount === 0) return "Antigravity CLI: Inactive";
        if (root.sessionCount > 1) {
            return "Antigravity: " + root.sessionCount + " Active Sessions (" + root.activeStatusText + ")";
        }
        return "Antigravity: " + root.activeStatusText + " (" + root.currentModel + ")";
    }

    readonly property string tipText: {
        if (!root.agentRunning || root.sessionCount === 0) return "Antigravity CLI\nInactive";
        if (root.sessionCount > 1) {
            let lines = ["Antigravity: " + root.sessionCount + " Active Sessions"];
            for (let i = 0; i < root.activeSessions.length; i++) {
                let s = root.activeSessions[i];
                let ws = s.workspaceName || "session";
                let st = s.state === "working" ? "Working" : (s.state === "action_needed" ? "Action Needed" : (s.state === "finished" ? "Finished" : "Idle"));
                lines.push("• " + ws + ": " + st);
            }
            return lines.join("\n");
        }
        let lines = ["Antigravity CLI: " + root.activeStatusText];
        if (root.currentModel) lines.push("Model: " + root.currentModel);
        if (root.activeWorkspaceName) lines.push("Workspace: " + root.activeWorkspaceName);
        return lines.join("\n");
    }

    function refresh(force) {
        if (scanProcess.running) return;
        root.refreshing = true;
        scanProcess.command = ["python3", root.scannerScript];
        scanProcess.running = true;
    }

    function applyData(jsonText) {
        try {
            const data = JSON.parse(jsonText || "{}");
            if (!data.ready) return;

            root.ready = true;
            root.agentRunning = data.agentRunning === true && Number(data.sessionCount || 0) > 0;
            root.agentState = root.agentRunning ? (data.agentState || "idle") : "idle";
            root.sessionCount = Number(data.sessionCount || 0);
            root.activeSessions = data.activeSessions || [];
            root.primarySession = data.primarySession || ({});

            if (root.agentRunning) {
                root.currentModel = data.currentModel || "Gemini 3.7 Flash";
                root.activeStatusText = data.activeStatusText || "Idle";
                root.conversationId = data.conversationId || "";
                root.activeWorkspace = data.activeWorkspace || "";
                root.activeWorkspaceName = data.activeWorkspaceName || "";
                root.activeTitle = data.activeTitle || "";
                root.quotaGroups = data.quotaGroups || [];
            } else {
                root.activeStatusText = "Inactive";
                root.conversationId = "";
                root.activeWorkspace = "";
                root.activeWorkspaceName = "";
                root.activeTitle = "";
                root.activeSessions = [];
            }
        } catch (e) {
            console.warn("AiService: parse error", e);
        }
    }

    Process {
        id: scanProcess
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyData(text)
        }
        onExited: root.refreshing = false
    }

    // Polling timer when active
    Timer {
        id: activePollTimer
        interval: 1500
        repeat: true
        running: root.agentRunning
        onTriggered: root.refresh(false)
    }

    // Polling timer when inactive (checks every 2.5s for newly opened sessions)
    Timer {
        id: idlePollTimer
        interval: 2500
        repeat: true
        running: !root.agentRunning
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    Component.onCompleted: root.refresh(true)
}
