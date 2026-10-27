import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: editor
    anchors.fill: parent
    visible: active

    required property var root
    required property var wallpaperWindow

    property bool active: false
    property var target: null

    // Transformation state
    property int currentRotation: 0 // 0, 90, 180, 270
    property bool flipH: false
    property bool flipV: false

    // Normalized crop rectangle [0.0 - 1.0] relative to rotated frame
    property real cropNormX: 0.0
    property real cropNormY: 0.0
    property real cropNormW: 1.0
    property real cropNormH: 1.0

    // Preset: "screen", "16:9", "16:10", "21:9", "4:3", "1:1", "free"
    property string aspectPreset: "screen"
    property bool isApplying: false

    // Image source pixel metrics
    readonly property real srcW: (previewImg.sourceSize.width > 0) ? previewImg.sourceSize.width : 1920
    readonly property real srcH: (previewImg.sourceSize.height > 0) ? previewImg.sourceSize.height : 1080
    readonly property real orientedW: (currentRotation % 180 === 0) ? srcW : srcH
    readonly property real orientedH: (currentRotation % 180 === 0) ? srcH : srcW
    readonly property real orientedAspect: orientedW / orientedH

    // Screen aspect ratio
    readonly property real screenAspect: (Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : (16.0 / 9.0)

    function open(entry) {
        target = entry;
        currentRotation = 0;
        flipH = false;
        flipV = false;
        aspectPreset = "screen";
        active = true;
        isApplying = false;

        // Give image time to load/decode sourceSize
        Qt.callLater(() => {
            applyAspectPreset("screen");
            editorCard.forceActiveFocus();
        });
    }

    function close() {
        active = false;
        target = null;
        isApplying = false;
        wallpaperWindow.onEditorClosed();
    }

    function rotateClockwise() {
        currentRotation = (currentRotation + 90) % 360;
        Qt.callLater(() => applyAspectPreset(aspectPreset));
    }

    function rotateCounterClockwise() {
        currentRotation = (currentRotation + 270) % 360;
        Qt.callLater(() => applyAspectPreset(aspectPreset));
    }

    function toggleFlipH() {
        flipH = !flipH;
    }

    function toggleFlipV() {
        flipV = !flipV;
    }

    function resetAll() {
        currentRotation = 0;
        flipH = false;
        flipV = false;
        aspectPreset = "free";
        cropNormX = 0.0;
        cropNormY = 0.0;
        cropNormW = 1.0;
        cropNormH = 1.0;
    }

    function applyAspectPreset(preset) {
        aspectPreset = preset;
        if (preset === "free") return;

        let targetRatio = 16.0 / 9.0;
        if (preset === "screen") {
            targetRatio = screenAspect;
        } else if (preset === "16:9") {
            targetRatio = 16.0 / 9.0;
        } else if (preset === "16:10") {
            targetRatio = 16.0 / 10.0;
        } else if (preset === "21:9") {
            targetRatio = 21.0 / 9.0;
        } else if (preset === "4:3") {
            targetRatio = 4.0 / 3.0;
        } else if (preset === "1:1") {
            targetRatio = 1.0;
        }

        // Fit largest rectangle of targetRatio into orientedW x orientedH
        let maxW, maxH;
        if (orientedAspect > targetRatio) {
            maxH = orientedH;
            maxW = maxH * targetRatio;
        } else {
            maxW = orientedW;
            maxH = maxW / targetRatio;
        }

        cropNormW = Math.max(0.01, Math.min(1.0, maxW / orientedW));
        cropNormH = Math.max(0.01, Math.min(1.0, maxH / orientedH));
        cropNormX = Math.max(0.0, (1.0 - cropNormW) / 2.0);
        cropNormY = Math.max(0.0, (1.0 - cropNormH) / 2.0);
    }

    function applyWallpaper() {
        if (!target || !target.path || isApplying) return;
        isApplying = true;

        const baseStem = target.name ? target.name.replace(/\.[^/.]+$/, "").replace(/[^a-zA-Z0-9._-]/g, "_") : "wallpaper";
        const ts = Date.now();
        const customFileName = "custom_" + baseStem + "_" + ts + ".png";
        const destPath = Quickshell.env("HOME") + "/.local/state/quickshell-desktop/custom-wallpapers/" + customFileName;

        transformProc.destPath = destPath;
        transformProc.command = [
            "python3",
            Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/wallpaper-transform.py",
            "--input", target.path,
            "--output", destPath,
            "--rotate", String(currentRotation),
            flipH ? "--flip-h" : "",
            flipV ? "--flip-v" : "",
            "--crop", cropNormX.toFixed(4) + "," + cropNormY.toFixed(4) + "," + cropNormW.toFixed(4) + "," + cropNormH.toFixed(4)
        ].filter(arg => arg.length > 0);

        transformProc.running = false;
        transformProc.running = true;
    }

    Process {
        id: transformProc
        property string destPath: ""
        stdout: StdioCollector { id: transformStdout }
        stderr: StdioCollector { id: transformStderr }
        onExited: function(exitCode) {
            editor.isApplying = false;
            if (exitCode === 0) {
                console.log("[WallpaperEditor] Applying transformed wallpaper:", transformProc.destPath);
                wallpaperWindow.applyCustomWallpaper(transformProc.destPath, editor.target);
                editor.close();
            } else {
                console.warn("wallpaper transform error:", transformStderr.text);
                wallpaperWindow.showToast("󰅚 TRANSFORM FAILED");
            }
        }
    }

    // Semi-transparent backdrop scrim (clicking outside dismisses editor)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.72)

        MouseArea {
            anchors.fill: parent
            onClicked: editor.close()
        }
    }

    // Main Modal Card
    Rectangle {
        id: editorCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 1160)
        height: Math.min(parent.height - 60, 700)
        radius: root.cornerRadius
        color: root.bg
        border.color: root.sep
        border.width: 1
        clip: true

        // Prevent outside click handler from catching inside clicks
        MouseArea {
            anchors.fill: parent
            onClicked: editorCard.forceActiveFocus()
        }

        focus: true
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                editor.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                editor.applyWallpaper();
                event.accepted = true;
            } else if (event.key === Qt.Key_R && !(event.modifiers & Qt.ControlModifier)) {
                editor.rotateClockwise();
                event.accepted = true;
            } else if (event.key === Qt.Key_H) {
                editor.toggleFlipH();
                event.accepted = true;
            } else if (event.key === Qt.Key_V) {
                editor.toggleFlipV();
                event.accepted = true;
            }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            // 1. Header Bar
            Rectangle {
                width: parent.width
                height: 48
                color: Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.35)
                border.color: root.sep
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        text: "󰆐"
                        color: root.seal
                        font.family: root.mono
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "CROP & ROTATE WALLPAPER"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 1
                        height: 14
                        color: root.sep
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: (editor.target ? editor.target.name : "") + "  (" + Math.round(editor.srcW) + "×" + Math.round(editor.srcH) + ")"
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Close Button (✕)
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: root.cornerRadius > 0 ? 14 : 0
                    color: closeMouse.containsMouse ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15) : "transparent"
                    border.color: closeMouse.containsMouse ? root.seal : "transparent"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeMouse.containsMouse ? root.seal : root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editor.close()
                    }
                }
            }

            // 2. Middle Area (Canvas + Controls Panel)
            Item {
                width: parent.width
                height: parent.height - 48 - 56

                Row {
                    anchors.fill: parent
                    spacing: 0

                    // Left: Interactive Preview & Crop Canvas
                    Item {
                        id: canvasArea
                        width: parent.width - 270
                        height: parent.height
                        clip: true

                        // Subtle dark workspace background
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.28)
                        }

                        readonly property real availW: Math.max(100, width - 40)
                        readonly property real availH: Math.max(100, height - 40)
                        readonly property real frameW: (availW / availH > editor.orientedAspect) ? (availH * editor.orientedAspect) : availW
                        readonly property real frameH: (availW / availH > editor.orientedAspect) ? availH : (availW / editor.orientedAspect)

                        // Sized oriented image container
                        Item {
                            id: contentFrame
                            width: canvasArea.frameW
                            height: canvasArea.frameH
                            anchors.centerIn: parent

                            // Rotated & Flipped Image
                            Image {
                                id: previewImg
                                width: (editor.currentRotation % 180 === 0) ? contentFrame.width : contentFrame.height
                                height: (editor.currentRotation % 180 === 0) ? contentFrame.height : contentFrame.width
                                anchors.centerIn: parent
                                source: (editor.active && editor.target) ? ("file://" + editor.target.path) : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                rotation: editor.currentRotation
                                transform: Scale {
                                    xScale: editor.flipH ? -1 : 1
                                    yScale: editor.flipV ? -1 : 1
                                    origin.x: previewImg.width / 2
                                    origin.y: previewImg.height / 2
                                }
                                onStatusChanged: {
                                    if (status === Image.Ready) {
                                        editor.applyAspectPreset(editor.aspectPreset);
                                    }
                                }
                            }

                            // Dimmed Shroud outside the crop box
                            Item {
                                anchors.fill: parent

                                // Top shroud
                                Rectangle {
                                    x: 0
                                    y: 0
                                    width: parent.width
                                    height: Math.max(0, cropBox.y)
                                    color: Qt.rgba(0, 0, 0, 0.58)
                                }
                                // Bottom shroud
                                Rectangle {
                                    x: 0
                                    y: cropBox.y + cropBox.height
                                    width: parent.width
                                    height: Math.max(0, parent.height - (cropBox.y + cropBox.height))
                                    color: Qt.rgba(0, 0, 0, 0.58)
                                }
                                // Left shroud
                                Rectangle {
                                    x: 0
                                    y: cropBox.y
                                    width: Math.max(0, cropBox.x)
                                    height: cropBox.height
                                    color: Qt.rgba(0, 0, 0, 0.58)
                                }
                                // Right shroud
                                Rectangle {
                                    x: cropBox.x + cropBox.width
                                    y: cropBox.y
                                    width: Math.max(0, parent.width - (cropBox.x + cropBox.width))
                                    height: cropBox.height
                                    color: Qt.rgba(0, 0, 0, 0.58)
                                }
                            }

                            // Interactive Crop Box
                            Item {
                                id: cropBox
                                x: editor.cropNormX * contentFrame.width
                                y: editor.cropNormY * contentFrame.height
                                width: editor.cropNormW * contentFrame.width
                                height: editor.cropNormH * contentFrame.height

                                // Highlight border
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: root.seal
                                    border.width: 2
                                }

                                // Rule of thirds grid lines
                                Item {
                                    anchors.fill: parent
                                    opacity: 0.35

                                    Rectangle { x: parent.width / 3; y: 0; width: 1; height: parent.height; color: "white" }
                                    Rectangle { x: 2 * parent.width / 3; y: 0; width: 1; height: parent.height; color: "white" }
                                    Rectangle { x: 0; y: parent.height / 3; width: parent.width; height: 1; color: "white" }
                                    Rectangle { x: 0; y: 2 * parent.height / 3; width: parent.width; height: 1; color: "white" }
                                }

                                // Move Drag Area
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.SizeAllCursor
                                    property real startX: 0
                                    property real startY: 0
                                    property real initialNormX: 0
                                    property real initialNormY: 0

                                    onPressed: (mouse) => {
                                        startX = mouse.x;
                                        startY = mouse.y;
                                        initialNormX = editor.cropNormX;
                                        initialNormY = editor.cropNormY;
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return;
                                        const dx = (mouse.x - startX) / contentFrame.width;
                                        const dy = (mouse.y - startY) / contentFrame.height;
                                        editor.cropNormX = Math.max(0.0, Math.min(1.0 - editor.cropNormW, initialNormX + dx));
                                        editor.cropNormY = Math.max(0.0, Math.min(1.0 - editor.cropNormH, initialNormY + dy));
                                    }
                                }

                                // Corner Handles
                                // Top-Left Handle
                                Rectangle {
                                    x: -6; y: -6; width: 12; height: 12
                                    color: root.seal; border.color: root.paper; border.width: 1
                                    radius: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.SizeFDiagCursor
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property real initX: 0
                                        property real initY: 0
                                        property real initW: 0
                                        property real initH: 0

                                        onPressed: (mouse) => {
                                            startGlobalX = mouse.x;
                                            startGlobalY = mouse.y;
                                            initX = editor.cropNormX;
                                            initY = editor.cropNormY;
                                            initW = editor.cropNormW;
                                            initH = editor.cropNormH;
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!pressed) return;
                                            const dx = (mouse.x - startGlobalX) / contentFrame.width;
                                            let newX = Math.max(0.0, Math.min(initX + initW - 0.05, initX + dx));
                                            let newW = initW - (newX - initX);

                                            if (editor.aspectPreset !== "free") {
                                                const ratio = (editor.aspectPreset === "screen") ? editor.screenAspect :
                                                    (editor.aspectPreset === "16:9" ? 16/9 :
                                                    (editor.aspectPreset === "16:10" ? 16/10 :
                                                    (editor.aspectPreset === "21:9" ? 21/9 :
                                                    (editor.aspectPreset === "4:3" ? 4/3 : 1.0))));
                                                let targetNormH = (newW * editor.orientedW) / (ratio * editor.orientedH);
                                                let newY = (initY + initH) - targetNormH;
                                                if (newY >= 0.0) {
                                                    editor.cropNormX = newX;
                                                    editor.cropNormW = newW;
                                                    editor.cropNormY = newY;
                                                    editor.cropNormH = targetNormH;
                                                }
                                            } else {
                                                const dy = (mouse.y - startGlobalY) / contentFrame.height;
                                                let newY = Math.max(0.0, Math.min(initY + initH - 0.05, initY + dy));
                                                let newH = initH - (newY - initY);
                                                editor.cropNormX = newX;
                                                editor.cropNormW = newW;
                                                editor.cropNormY = newY;
                                                editor.cropNormH = newH;
                                            }
                                        }
                                    }
                                }

                                // Top-Right Handle
                                Rectangle {
                                    x: parent.width - 6; y: -6; width: 12; height: 12
                                    color: root.seal; border.color: root.paper; border.width: 1
                                    radius: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.SizeBDiagCursor
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property real initY: 0
                                        property real initW: 0
                                        property real initH: 0

                                        onPressed: (mouse) => {
                                            startGlobalX = mouse.x;
                                            startGlobalY = mouse.y;
                                            initY = editor.cropNormY;
                                            initW = editor.cropNormW;
                                            initH = editor.cropNormH;
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!pressed) return;
                                            const dx = (mouse.x - startGlobalX) / contentFrame.width;
                                            let newW = Math.max(0.05, Math.min(1.0 - editor.cropNormX, initW + dx));

                                            if (editor.aspectPreset !== "free") {
                                                const ratio = (editor.aspectPreset === "screen") ? editor.screenAspect :
                                                    (editor.aspectPreset === "16:9" ? 16/9 :
                                                    (editor.aspectPreset === "16:10" ? 16/10 :
                                                    (editor.aspectPreset === "21:9" ? 21/9 :
                                                    (editor.aspectPreset === "4:3" ? 4/3 : 1.0))));
                                                let targetNormH = (newW * editor.orientedW) / (ratio * editor.orientedH);
                                                let newY = (initY + initH) - targetNormH;
                                                if (newY >= 0.0) {
                                                    editor.cropNormW = newW;
                                                    editor.cropNormY = newY;
                                                    editor.cropNormH = targetNormH;
                                                }
                                            } else {
                                                const dy = (mouse.y - startGlobalY) / contentFrame.height;
                                                let newY = Math.max(0.0, Math.min(initY + initH - 0.05, initY + dy));
                                                let newH = initH - (newY - initY);
                                                editor.cropNormW = newW;
                                                editor.cropNormY = newY;
                                                editor.cropNormH = newH;
                                            }
                                        }
                                    }
                                }

                                // Bottom-Left Handle
                                Rectangle {
                                    x: -6; y: parent.height - 6; width: 12; height: 12
                                    color: root.seal; border.color: root.paper; border.width: 1
                                    radius: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.SizeBDiagCursor
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property real initX: 0
                                        property real initW: 0
                                        property real initH: 0

                                        onPressed: (mouse) => {
                                            startGlobalX = mouse.x;
                                            startGlobalY = mouse.y;
                                            initX = editor.cropNormX;
                                            initW = editor.cropNormW;
                                            initH = editor.cropNormH;
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!pressed) return;
                                            const dx = (mouse.x - startGlobalX) / contentFrame.width;
                                            let newX = Math.max(0.0, Math.min(initX + initW - 0.05, initX + dx));
                                            let newW = initW - (newX - initX);

                                            if (editor.aspectPreset !== "free") {
                                                const ratio = (editor.aspectPreset === "screen") ? editor.screenAspect :
                                                    (editor.aspectPreset === "16:9" ? 16/9 :
                                                    (editor.aspectPreset === "16:10" ? 16/10 :
                                                    (editor.aspectPreset === "21:9" ? 21/9 :
                                                    (editor.aspectPreset === "4:3" ? 4/3 : 1.0))));
                                                let targetNormH = (newW * editor.orientedW) / (ratio * editor.orientedH);
                                                if (editor.cropNormY + targetNormH <= 1.0) {
                                                    editor.cropNormX = newX;
                                                    editor.cropNormW = newW;
                                                    editor.cropNormH = targetNormH;
                                                }
                                            } else {
                                                const dy = (mouse.y - startGlobalY) / contentFrame.height;
                                                let newH = Math.max(0.05, Math.min(1.0 - editor.cropNormY, initH + dy));
                                                editor.cropNormX = newX;
                                                editor.cropNormW = newW;
                                                editor.cropNormH = newH;
                                            }
                                        }
                                    }
                                }

                                // Bottom-Right Handle
                                Rectangle {
                                    x: parent.width - 6; y: parent.height - 6; width: 12; height: 12
                                    color: root.seal; border.color: root.paper; border.width: 1
                                    radius: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.SizeFDiagCursor
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property real initW: 0
                                        property real initH: 0

                                        onPressed: (mouse) => {
                                            startGlobalX = mouse.x;
                                            startGlobalY = mouse.y;
                                            initW = editor.cropNormW;
                                            initH = editor.cropNormH;
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!pressed) return;
                                            const dx = (mouse.x - startGlobalX) / contentFrame.width;
                                            let newW = Math.max(0.05, Math.min(1.0 - editor.cropNormX, initW + dx));

                                            if (editor.aspectPreset !== "free") {
                                                const ratio = (editor.aspectPreset === "screen") ? editor.screenAspect :
                                                    (editor.aspectPreset === "16:9" ? 16/9 :
                                                    (editor.aspectPreset === "16:10" ? 16/10 :
                                                    (editor.aspectPreset === "21:9" ? 21/9 :
                                                    (editor.aspectPreset === "4:3" ? 4/3 : 1.0))));
                                                let targetNormH = (newW * editor.orientedW) / (ratio * editor.orientedH);
                                                if (editor.cropNormY + targetNormH <= 1.0) {
                                                    editor.cropNormW = newW;
                                                    editor.cropNormH = targetNormH;
                                                }
                                            } else {
                                                const dy = (mouse.y - startGlobalY) / contentFrame.height;
                                                let newH = Math.max(0.05, Math.min(1.0 - editor.cropNormY, initH + dy));
                                                editor.cropNormW = newW;
                                                editor.cropNormH = newH;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Vertical Separator
                    Rectangle {
                        width: 1
                        height: parent.height
                        color: root.sep
                    }

                    // Right: Tooling & Controls Sidebar
                    Rectangle {
                        width: 269
                        height: parent.height
                        color: Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.20)

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16

                            // Section: Rotation & Orientation
                            Column {
                                width: parent.width
                                spacing: 8

                                Text {
                                    text: "ORIENTATION"
                                    color: root.inkDeep
                                    font.family: root.mono
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.5
                                    font.weight: Font.Bold
                                }

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    // Rotate -90° (CCW)
                                    Rectangle {
                                        width: (parent.width - 8) / 2
                                        height: 32
                                        radius: root.cornerRadius
                                        color: rotCcwMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10) : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04)
                                        border.color: root.sep
                                        border.width: 1

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "󰑋"; color: root.ink; font.family: root.mono; font.pixelSize: 13 }
                                            Text { text: "-90°"; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                                        }
                                        MouseArea {
                                            id: rotCcwMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: editor.rotateCounterClockwise()
                                        }
                                    }

                                    // Rotate +90° (CW)
                                    Rectangle {
                                        width: (parent.width - 8) / 2
                                        height: 32
                                        radius: root.cornerRadius
                                        color: rotCwMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10) : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04)
                                        border.color: root.sep
                                        border.width: 1

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "󰑊"; color: root.ink; font.family: root.mono; font.pixelSize: 13 }
                                            Text { text: "+90°"; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                                        }
                                        MouseArea {
                                            id: rotCwMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: editor.rotateClockwise()
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    // Flip Horizontal
                                    Rectangle {
                                        width: (parent.width - 8) / 2
                                        height: 30
                                        radius: root.cornerRadius
                                        color: editor.flipH ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15) : (flipHMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04))
                                        border.color: editor.flipH ? root.seal : root.sep
                                        border.width: 1

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "󰹑"; color: editor.flipH ? root.seal : root.ink; font.family: root.mono; font.pixelSize: 12 }
                                            Text { text: "Flip H"; color: editor.flipH ? root.seal : root.ink; font.family: root.mono; font.pixelSize: 10 }
                                        }
                                        MouseArea {
                                            id: flipHMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: editor.toggleFlipH()
                                        }
                                    }

                                    // Flip Vertical
                                    Rectangle {
                                        width: (parent.width - 8) / 2
                                        height: 30
                                        radius: root.cornerRadius
                                        color: editor.flipV ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15) : (flipVMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04))
                                        border.color: editor.flipV ? root.seal : root.sep
                                        border.width: 1

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text { text: "󰹒"; color: editor.flipV ? root.seal : root.ink; font.family: root.mono; font.pixelSize: 12 }
                                            Text { text: "Flip V"; color: editor.flipV ? root.seal : root.ink; font.family: root.mono; font.pixelSize: 10 }
                                        }
                                        MouseArea {
                                            id: flipVMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: editor.toggleFlipV()
                                        }
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: root.sep }

                            // Section: Aspect Ratio Presets
                            Column {
                                width: parent.width
                                spacing: 8

                                Text {
                                    text: "ASPECT RATIO"
                                    color: root.inkDeep
                                    font.family: root.mono
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.5
                                    font.weight: Font.Bold
                                }

                                Grid {
                                    width: parent.width
                                    columns: 2
                                    spacing: 6

                                    Repeater {
                                        model: [
                                            { label: "󰍹 Screen", key: "screen" },
                                            { label: "16 : 9",   key: "16:9" },
                                            { label: "16 : 10",  key: "16:10" },
                                            { label: "21 : 9",   key: "21:9" },
                                            { label: "4 : 3",    key: "4:3" },
                                            { label: "1 : 1",    key: "1:1" },
                                            { label: "󰄾 Free",   key: "free" }
                                        ]

                                        delegate: Rectangle {
                                            width: (index === 6) ? (editorCard.width > 0 ? (269 - 32) : 100) : ((269 - 32 - 6) / 2)
                                            height: 28
                                            radius: root.cornerRadius
                                            readonly property bool isSelected: editor.aspectPreset === modelData.key
                                            color: isSelected ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15) : (btnMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.03))
                                            border.color: isSelected ? root.seal : root.sep
                                            border.width: isSelected ? 1.5 : 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: isSelected ? root.seal : root.ink
                                                font.family: root.mono
                                                font.pixelSize: 10
                                                font.weight: isSelected ? Font.Bold : Font.Normal
                                            }

                                            MouseArea {
                                                id: btnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: editor.applyAspectPreset(modelData.key)
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: root.sep }

                            // Crop Selection Live Metrics
                            Column {
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: "CROP RESOLUTION"
                                    color: root.inkDeep
                                    font.family: root.mono
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.5
                                    font.weight: Font.Bold
                                }

                                Text {
                                    text: Math.round(editor.cropNormW * editor.orientedW) + " × " + Math.round(editor.cropNormH * editor.orientedH) + " px"
                                    color: root.ink
                                    font.family: root.mono
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Text {
                                    text: "Rotation: " + editor.currentRotation + "°" + (editor.flipH ? " · FlipH" : "") + (editor.flipV ? " · FlipV" : "")
                                    color: root.inkDeep
                                    font.family: root.mono
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }

            // 3. Footer Action Bar
            Rectangle {
                width: parent.width
                height: 56
                color: Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.35)
                border.color: root.sep
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    // Reset Button
                    Rectangle {
                        width: 90
                        height: 32
                        radius: root.cornerRadius
                        color: resetMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"
                        border.color: root.sep
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰑐"; color: root.inkDeep; font.family: root.mono; font.pixelSize: 12 }
                            Text { text: "Reset"; color: root.inkDeep; font.family: root.mono; font.pixelSize: 11 }
                        }

                        MouseArea {
                            id: resetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editor.resetAll()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Drag box to move · Drag corners to resize"
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                        opacity: 0.75
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    // Cancel Button
                    Rectangle {
                        width: 84
                        height: 32
                        radius: root.cornerRadius
                        color: cancelMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"
                        border.color: root.sep
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editor.close()
                        }
                    }

                    // Apply Button
                    Rectangle {
                        width: 140
                        height: 32
                        radius: root.cornerRadius
                        color: editor.isApplying ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.5) : (applyMouse.containsMouse ? Qt.lighter(root.seal, 1.1) : root.seal)

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: editor.isApplying ? "󰑐" : "󰄬"
                                color: root.paper
                                font.family: root.mono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }

                            Text {
                                text: editor.isApplying ? "Applying..." : "Apply Wallpaper"
                                color: root.paper
                                font.family: root.mono
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: applyMouse
                            anchors.fill: parent
                            hoverEnabled: !editor.isApplying
                            cursorShape: editor.isApplying ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: editor.applyWallpaper()
                        }
                    }
                }
            }
        }
    }
}
