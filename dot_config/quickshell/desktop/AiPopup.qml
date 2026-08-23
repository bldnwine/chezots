import QtQuick
import QtQuick.Layouts

CardWindow {
    id: aipopup
    required property var root

    theme: root
    plain: true
    revealed: root.aiVisible
    cardWidth: 440
    layerNamespace: "omarchy-ai"
    title: "GOOGLE ANTIGRAVITY"

    readonly property var ai: aipopup.root.aiService

    property int selectedSessionIndex: 0

    readonly property var currentSessions: (ai && ai.activeSessions && ai.activeSessions.length > 0)
        ? ai.activeSessions
        : (ai && ai.primarySession && ai.primarySession.conversationId ? [ai.primarySession] : [])

    readonly property var selectedSession: (currentSessions.length > 0)
        ? (currentSessions[Math.min(selectedSessionIndex, currentSessions.length - 1)] || null)
        : null

    subtitle: {
        if (!ai || !ai.agentRunning || currentSessions.length === 0) return "AGENT INACTIVE";
        if (selectedSession && selectedSession.currentModel) return selectedSession.currentModel.toUpperCase();
        return (ai.currentModel ? ai.currentModel.toUpperCase() : "AI AGENT");
    }

    footer: currentSessions.length > 1
        ? "TAB / 1-9 SWITCH SESSION  ·  R REFRESH  ·  ESC CLOSE"
        : "R REFRESH  ·  ESC CLOSE"

    anchorEdge: aipopup.root.barEdge
    anchorBarX: aipopup.root.popupAnchorX
    anchorBarY: aipopup.root.popupAnchorY

    function formatCountdown(resetsAt) {
        if (!resetsAt) return "";
        const ms = new Date(resetsAt).getTime();
        if (!isFinite(ms)) return "";
        const diff = ms - Date.now();
        if (diff <= 0) return "Refreshes now";
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);
        if (days > 0) return "Refreshes in " + days + "d " + (hours % 24) + "h";
        if (hours > 0) return "Refreshes in " + hours + "h " + (minutes % 60) + "m";
        return "Refreshes in " + Math.max(1, minutes) + "m";
    }

    onDismiss: aipopup.root.aiVisible = false

    onRevealedChanged: {
        if (aipopup.revealed) {
            aipopup.selectedSessionIndex = 0;
            if (ai) ai.refresh(true);
        }
    }

    headerRight: Component {
        Row {
            spacing: 8
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

            // Status indicator pill for currently selected session
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: aipopup.root.cornerRadius
                height: 20
                width: stateLabel.implicitWidth + 12

                readonly property string curState: (ai && ai.agentRunning && selectedSession) ? selectedSession.state : "idle"

                color: {
                    if (!ai || !ai.agentRunning || aipopup.currentSessions.length === 0)
                        return Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.08);
                    if (curState === "action_needed") return Qt.rgba(aipopup.root.warn.r, aipopup.root.warn.g, aipopup.root.warn.b, 0.15);
                    if (curState === "working") return Qt.rgba(aipopup.root.accent.r, aipopup.root.accent.g, aipopup.root.accent.b, 0.15);
                    return Qt.rgba(aipopup.root.seal.r, aipopup.root.seal.g, aipopup.root.seal.b, 0.12);
                }
                border.color: {
                    if (!ai || !ai.agentRunning || aipopup.currentSessions.length === 0) return aipopup.root.sep;
                    if (curState === "action_needed") return aipopup.root.warn;
                    if (curState === "working") return aipopup.root.accent;
                    return aipopup.root.seal;
                }

                Text {
                    id: stateLabel
                    anchors.centerIn: parent
                    text: {
                        if (!ai || !ai.agentRunning || aipopup.currentSessions.length === 0) return "INACTIVE";
                        const st = parent.curState;
                        if (st === "working") return "● WORKING";
                        if (st === "action_needed") return "! ACTION NEEDED";
                        if (st === "finished") return "✓ FINISHED";
                        return "IDLE";
                    }
                    color: {
                        if (!ai || !ai.agentRunning || aipopup.currentSessions.length === 0) return aipopup.root.inkDeep;
                        const st = parent.curState;
                        if (st === "action_needed") return aipopup.root.warn;
                        if (st === "working") return aipopup.root.accent;
                        return aipopup.root.seal;
                    }
                    font.family: aipopup.root.mono
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: 1
                }
            }

            // Refresh button
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 20
                radius: aipopup.root.cornerRadius
                color: refreshMouse.containsMouse ? Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.1) : "transparent"
                border.color: aipopup.root.sep

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: ai && ai.refreshing ? aipopup.root.accent : aipopup.root.ink
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (ai) ai.refresh(true)
                }
            }
        }
    }

    onKeyPressed: (event) => {
        const k = event.key;
        if (k === Qt.Key_Escape) {
            aipopup.root.aiVisible = false;
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_R) {
            if (ai) ai.refresh(true);
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Tab || k === Qt.Key_Right) {
            if (currentSessions.length > 1) {
                aipopup.selectedSessionIndex = (aipopup.selectedSessionIndex + 1) % currentSessions.length;
                event.accepted = true;
                return;
            }
        }
        if (k === Qt.Key_Backtab || k === Qt.Key_Left) {
            if (currentSessions.length > 1) {
                aipopup.selectedSessionIndex = (aipopup.selectedSessionIndex - 1 + currentSessions.length) % currentSessions.length;
                event.accepted = true;
                return;
            }
        }
        if (k >= Qt.Key_1 && k <= Qt.Key_9) {
            const idx = k - Qt.Key_1;
            if (idx < currentSessions.length) {
                aipopup.selectedSessionIndex = idx;
                event.accepted = true;
                return;
            }
        }
    }

    Column {
        id: contentCol
        width: parent.width
        spacing: 12

        // Inactive notice if no agent is running
        Rectangle {
            visible: !ai || !ai.agentRunning || currentSessions.length === 0
            width: parent.width
            implicitHeight: inactCol.implicitHeight + 16
            radius: aipopup.root.cornerRadius
            color: Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.03)
            border.color: aipopup.root.sep

            Column {
                id: inactCol
                anchors.centerIn: parent
                spacing: 3
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No active Antigravity session"
                    color: aipopup.root.ink
                    font.family: aipopup.root.mono
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Start agy in a terminal to track status & quotas"
                    color: aipopup.root.inkDeep
                    font.family: aipopup.root.mono
                    font.pixelSize: 9
                }
            }
        }

        // Session Tabs (shown when multiple agents are active)
        Row {
            visible: currentSessions.length > 1
            width: parent.width
            spacing: 6

            Repeater {
                model: currentSessions
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: aipopup.selectedSessionIndex === index
                    width: Math.min(140, (parent.width - (currentSessions.length - 1) * 6) / currentSessions.length)
                    height: 24
                    radius: aipopup.root.cornerRadius
                    color: isSelected
                        ? Qt.rgba(aipopup.root.accent.r, aipopup.root.accent.g, aipopup.root.accent.b, 0.18)
                        : (tabMouse.containsMouse ? Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.08) : Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.03))
                    border.color: isSelected ? aipopup.root.accent : aipopup.root.sep

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.state === "action_needed" ? "!" : (modelData.state === "finished" ? "✓" : "●")
                            color: modelData.state === "action_needed" ? aipopup.root.warn : (modelData.state === "working" ? aipopup.root.accent : aipopup.root.seal)
                            font.family: aipopup.root.mono
                            font.pixelSize: 8
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.workspaceName || ("Session " + (index + 1))
                            color: isSelected ? aipopup.root.ink : aipopup.root.inkDeep
                            font.family: aipopup.root.mono
                            font.pixelSize: 10
                            font.weight: isSelected ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 90)
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: aipopup.selectedSessionIndex = index
                    }
                }
            }
        }

        // Active Workspace / Session Card
        Rectangle {
            visible: !!(selectedSession && selectedSession.workspaceName)
            width: parent.width
            implicitHeight: wsCol.implicitHeight + 14
            radius: aipopup.root.cornerRadius
            color: Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.04)
            border.color: aipopup.root.sep

            Column {
                id: wsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 7
                spacing: 3

                Row {
                    width: parent.width
                    spacing: 6
                    Text {
                        text: "WORKSPACE"
                        color: aipopup.root.inkDeep
                        font.family: aipopup.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                    }
                    Text {
                        text: "·"
                        color: aipopup.root.inkDeep
                        font.pixelSize: 9
                    }
                    Text {
                        text: selectedSession ? selectedSession.workspaceName : ""
                        color: aipopup.root.accent
                        font.family: aipopup.root.mono
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }

                Text {
                    visible: !!(selectedSession && selectedSession.title)
                    width: parent.width
                    text: selectedSession ? selectedSession.title : ""
                    color: aipopup.root.ink
                    font.family: aipopup.root.mono
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }
        }

        // Section: Official Quotas & Rate Limits
        Repeater {
            model: (ai && ai.quotaGroups) ? ai.quotaGroups : []
            delegate: Column {
                required property var modelData
                width: parent.width
                spacing: 6

                // Group Header
                Column {
                    width: parent.width
                    spacing: 1

                    Text {
                        text: modelData.groupName.toUpperCase()
                        color: aipopup.root.ink
                        font.family: aipopup.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                    }
                    Text {
                        visible: !!modelData.description
                        text: modelData.description
                        color: aipopup.root.inkDeep
                        font.family: aipopup.root.mono
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                // Bucket Cards
                Repeater {
                    model: modelData.buckets
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        implicitHeight: bucketCol.implicitHeight + 12
                        radius: aipopup.root.cornerRadius
                        color: Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.03)
                        border.color: aipopup.root.sep

                        Column {
                            id: bucketCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 6
                            spacing: 4

                            // Title & Remaining Percentage
                            Item {
                                width: parent.width
                                height: Math.max(bucketTitle.implicitHeight, bucketPct.implicitHeight)

                                Text {
                                    id: bucketTitle
                                    anchors.left: parent.left
                                    anchors.right: bucketPct.left
                                    anchors.rightMargin: 6
                                    elide: Text.ElideRight
                                    text: modelData.displayName
                                    color: aipopup.root.ink
                                    font.family: aipopup.root.mono
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                Text {
                                    id: bucketPct
                                    anchors.right: parent.right
                                    text: modelData.remainingPercent.toFixed(2) + "%"
                                    color: modelData.remainingPercent < 20 ? aipopup.root.warn : aipopup.root.ink
                                    font.family: aipopup.root.mono
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }

                            // Quota Bar (shows remaining green portion like in CLI)
                            Rectangle {
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Qt.rgba(aipopup.root.ink.r, aipopup.root.ink.g, aipopup.root.ink.b, 0.12)
                                clip: true

                                readonly property real frac: Math.min(1.0, Math.max(0.0, Number(modelData.remainingFraction || 0)))

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * parent.frac
                                    radius: 3
                                    color: parent.frac < 0.20 ? aipopup.root.warn : "#87a987"
                                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                }
                            }

                            // Sub-label (Remaining description / Refreshes countdown)
                            Item {
                                width: parent.width
                                height: bucketSub.implicitHeight

                                Text {
                                    id: bucketSub
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    text: {
                                        if (modelData.remainingPercent >= 99.9) return "Quota available";
                                        const rem = Math.round(modelData.remainingPercent) + "% remaining";
                                        const cd = aipopup.formatCountdown(modelData.resetTime);
                                        return cd !== "" ? (rem + " · " + cd) : rem;
                                    }
                                    color: aipopup.root.inkDeep
                                    font.family: aipopup.root.mono
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
