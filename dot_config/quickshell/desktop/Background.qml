import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Palette.js" as Palette

Item {
    id: root

    required property var theme

    readonly property string home: Quickshell.env("HOME")
    readonly property string backgroundLink: home + "/.config/omarchy/current/background"

    property string currentBackground: ""
    property string displayedBackground: ""
    property string incomingBackground: ""
    property string oldBackground: ""
    property bool finishingTransition: false
    property int backgroundVersion: 0
    property int revealStartedVersion: -1
    property int pendingThemeVersion: -1
    property string pendingColorsRaw: ""
    property real revealProgress: 1

    function imageUrl(path) {
        if (!path) return "";
        var p = String(path).trim();
        if (!p) return "";
        return p.startsWith("file://") ? p : ("file://" + encodeURI(p));
    }

    function refreshBackground() {
        readlinkProc.running = false;
        readlinkProc.running = true;
    }

    function setBackground(path, instant) {
        transitionBackground("", path, path, instant, false);
    }

    function transitionBackground(fromPath, path, finalPath, instant, force) {
        path = String(path || "").trim();
        finalPath = String(finalPath || path).trim();
        fromPath = String(fromPath || "").trim();
        if (!path || (!force && finalPath === currentBackground)) return;
        currentBackground = finalPath;
        backgroundVersion += 1;
        revealStartedVersion = -1;

        revealAnimation.stop();
        finishingTransition = false;

        if (instant || !displayedBackground) {
            oldBackground = "";
            incomingBackground = "";
            displayedBackground = path;
            revealProgress = 1;
            return;
        }

        oldBackground = fromPath || displayedBackground;
        incomingBackground = path;
        revealProgress = 0;
    }

    function setPendingTheme(colorsB64) {
        if (!colorsB64) return;
        try {
            pendingColorsRaw = Qt.atob(colorsB64);
        } catch (e) {
            console.warn("background: failed to decode theme base64", e);
            return;
        }
        pendingThemeVersion = backgroundVersion;
        pendingThemeFallbackTimer.restart();
    }

    function applyPendingTheme() {
        if (pendingThemeVersion < 0) return;
        pendingThemeFallbackTimer.stop();
        if (pendingColorsRaw && root.theme) {
            var parsed = Palette.parseAll(pendingColorsRaw);
            Palette.apply(root.theme, Palette.mapKeys(parsed));
        }
        pendingThemeVersion = -1;
        pendingColorsRaw = "";
    }

    function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
        transitionBackground(fromPath, path, finalPath, false, true);
        setPendingTheme(colorsB64);
        if (!incomingBackground || revealProgress >= 1) applyPendingTheme();
    }

    function startReveal(panel) {
        if (!incomingBackground) return;
        panel.maskReady = true;
        if (revealStartedVersion === backgroundVersion) return;
        revealStartedVersion = backgroundVersion;
        applyPendingTheme();
        revealAnimation.restart();
    }

    Process {
        id: readlinkProc
        command: ["sh", "-c", "readlink -f \"$HOME/.config/omarchy/current/background\" 2>/dev/null || ls -1 \"$HOME/.config/aether/theme/backgrounds\"/* 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var found = String(this.text || "").trim();
                if (found) root.setBackground(found, false);
            }
        }
    }

    IpcHandler {
        target: "background"

        function refresh() {
            root.refreshBackground();
        }

        function set(path: string) {
            root.setBackground(path, false);
        }

        function setInstant(path: string) {
            root.setBackground(path, true);
        }

        function transition(fromPath: string, path: string) {
            root.transitionBackground(fromPath, path, path, false, false);
        }

        function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string) {
            root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64);
        }
    }

    Timer {
        id: pendingThemeFallbackTimer
        interval: 300
        repeat: false
        onTriggered: root.applyPendingTheme()
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "revealProgress"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.incomingBackground) {
                root.displayedBackground = root.currentBackground || root.incomingBackground;
                root.finishingTransition = true;
            }
            root.revealProgress = 1;
        }
    }

    Component.onCompleted: refreshBackground()

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            visible: true
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            updatesEnabled: true

            property bool maskReady: false

            function maybeStartReveal() {
                if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return;
                if (incomingFrame.status !== Image.Ready) return;
                Qt.callLater(function() {
                    if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return;
                    if (incomingFrame.status !== Image.Ready) return;
                    root.startReveal(panel);
                });
            }

            WlrLayershell.namespace: "omarchy-background"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            Image {
                id: base
                anchors.fill: parent
                source: root.displayedBackground ? root.imageUrl(root.displayedBackground) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                onStatusChanged: {
                    if (status === Image.Ready && root.finishingTransition) {
                        root.incomingBackground = "";
                        root.oldBackground = "";
                        root.finishingTransition = false;
                    }
                }
            }

            Image {
                id: oldFrame
                anchors.fill: parent
                source: root.oldBackground ? root.imageUrl(root.oldBackground) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
                visible: root.oldBackground !== "" && root.revealProgress < 1
                onStatusChanged: panel.maybeStartReveal()
            }

            Item {
                id: incomingLayer
                anchors.fill: parent
                visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
                layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: revealMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.02
                }

                Image {
                    id: incomingFrame
                    anchors.fill: parent
                    source: root.incomingBackground ? root.imageUrl(root.incomingBackground) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    mipmap: true
                    onStatusChanged: panel.maybeStartReveal()
                }
            }

            Item {
                id: revealMask
                anchors.fill: parent
                visible: false
                layer.enabled: true

                readonly property real slant: -0.18
                readonly property real centerTop: width / 2 - slant * height / 2
                readonly property real centerBottom: width / 2 + slant * height / 2
                readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
                readonly property real spread: reach * root.revealProgress

                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "white"
                        strokeColor: "transparent"
                        startX: revealMask.centerTop - revealMask.spread; startY: 0
                        PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
                        PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
                        PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
                        PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
                    }
                }
            }

            Connections {
                target: root
                function onIncomingBackgroundChanged() {
                    panel.maskReady = false;
                    panel.maybeStartReveal();
                }
            }
        }
    }
}
