import QtQuick
import QtQuick.Effects
import Quickshell

// Card delegate for an individual notification.
Item {
    id: cardRoot

    required property var root
    required property int index

    required property string key
    required property string app
    required property string appIcon
    required property string summary
    required property string body
    required property string image
    required property string preview
    required property string file
    required property string glyph
    required property double timestamp
    required property int urgency
    required property bool unread

    property double now: 0
    property bool showBody: true
    property bool showPreview: true
    property bool selected: false

    signal clicked()
    signal removeRequested()

    readonly property bool hovered: rowMouse.containsMouse || dismissMouse.containsMouse
    readonly property string iconSource: {
        if (image !== "" && image.indexOf("image://") !== 0) return resolveIcon(image);
        if (appIcon !== "") return resolveIcon(appIcon);
        if (app !== "") return resolveIcon(app.toLowerCase());
        return "";
    }
    readonly property bool hasIcon: iconSource !== "" && iconImage.status !== Image.Error
    readonly property string initial: app !== "" ? app.charAt(0).toUpperCase() : "?"
    readonly property bool hasPreview: showPreview && preview !== "" && previewImage.status !== Image.Error

    readonly property string cleanSummary: String(summary || "")
        .replace(/<img[^>]*>/gi, "")
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
        .trim()

    readonly property string cleanBody: String(body || "")
        .replace(/<img[^>]*>/gi, "")
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
        .trim()

    readonly property string when: {
        var age = Math.max(0, now - timestamp);
        if (age < 60000) return "now";
        if (age < 3600000) return Math.round(age / 60000) + "m ago";
        return Qt.formatDateTime(new Date(timestamp), "HH:mm");
    }

    function resolveIcon(icon) {
        var value = String(icon || "");
        if (value === "") return "";
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value;
        if (value.charAt(0) === "/") return "file://" + value;
        return Quickshell.iconPath(value, true);
    }

    implicitHeight: bgRect.implicitHeight
    width: parent ? parent.width : 400

    Rectangle {
        id: bgRect
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: contentCol.implicitHeight + 20
        radius: cardRoot.root.cornerRadius
        color: cardRoot.selected || cardRoot.hovered ? cardRoot.root.rowSel : cardRoot.root.rowHi
        border.color: cardRoot.selected ? cardRoot.root.seal : cardRoot.root.sep
        border.width: cardRoot.selected ? 2 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        // Critical urgency bar along leading edge
        Rectangle {
            visible: cardRoot.urgency === 2
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 4
            width: 3
            radius: 1.5
            color: cardRoot.root.seal
        }

        // Unread indicator dot along leading edge
        Rectangle {
            visible: cardRoot.unread && cardRoot.urgency !== 2
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 2.5
            color: cardRoot.root.accent
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) cardRoot.removeRequested();
                else cardRoot.clicked();
            }
        }

        // Avatar / App Icon
        Item {
            id: avatar
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 10
            width: 32
            height: 32

            Rectangle {
                anchors.fill: parent
                radius: cardRoot.root.cornerRadius
                visible: !cardRoot.hasIcon
                color: cardRoot.root.bg
                border.color: cardRoot.root.sep
                border.width: 1
            }

            Text {
                visible: !cardRoot.hasIcon && cardRoot.glyph === ""
                anchors.centerIn: parent
                text: cardRoot.initial
                font.family: cardRoot.root.mono
                font.pixelSize: 13
                font.bold: true
                color: cardRoot.root.ink
            }

            Text {
                visible: !cardRoot.hasIcon && cardRoot.glyph !== ""
                anchors.centerIn: parent
                text: cardRoot.glyph
                font.family: cardRoot.root.mono
                font.pixelSize: 15
                color: cardRoot.root.seal
            }

            Image {
                id: iconImage
                anchors.fill: parent
                visible: cardRoot.hasIcon
                source: cardRoot.iconSource
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
        }

        // Content Column
        Column {
            id: contentCol
            anchors.left: avatar.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 10
            spacing: 2

            // Top row: App Name + Relative Time / Dismiss Button
            Item {
                width: parent.width
                height: 18

                Text {
                    anchors.left: parent.left
                    anchors.right: timeSlot.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: cardRoot.app.length > 0 ? cardRoot.app.toUpperCase() : "NOTIFICATION"
                    font.family: cardRoot.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                    color: cardRoot.root.inkDeep
                    elide: Text.ElideRight
                }

                Item {
                    id: timeSlot
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: cardRoot.hovered ? dismissBtn.width : timeLabel.implicitWidth
                    height: parent.height

                    Text {
                        id: timeLabel
                        visible: !cardRoot.hovered
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: cardRoot.when
                        font.family: cardRoot.root.mono
                        font.pixelSize: 9
                        color: cardRoot.root.inkDeep
                    }

                    Rectangle {
                        id: dismissBtn
                        visible: cardRoot.hovered
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 9
                        color: dismissMouse.containsMouse ? cardRoot.root.rowHi : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: cardRoot.root.mono
                            font.pixelSize: 10
                            color: dismissMouse.containsMouse ? cardRoot.root.seal : cardRoot.root.inkDeep
                        }

                        MouseArea {
                            id: dismissMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cardRoot.removeRequested()
                        }
                    }
                }
            }

            // Summary
            Text {
                width: parent.width
                visible: cardRoot.cleanSummary.length > 0
                text: cardRoot.cleanSummary
                font.family: cardRoot.root.mono
                font.pixelSize: 12
                font.weight: Font.Medium
                color: cardRoot.root.ink
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Body
            Text {
                width: parent.width
                visible: cardRoot.showBody && cardRoot.cleanBody.length > 0
                text: cardRoot.cleanBody
                font.family: cardRoot.root.mono
                font.pixelSize: 11
                color: cardRoot.root.inkDeep
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }

            // Preview Image
            Item {
                width: parent.width
                height: cardRoot.hasPreview ? Math.min(width * 9 / 16, 96) + 4 : 0
                visible: cardRoot.hasPreview

                Image {
                    id: previewImage
                    anchors.fill: parent
                    anchors.topMargin: 4
                    source: cardRoot.showPreview ? cardRoot.preview : ""
                    sourceSize.width: Math.round(width * 2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: previewMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                Rectangle {
                    id: previewMask
                    anchors.fill: previewImage
                    radius: cardRoot.root.cornerRadius
                    color: "black"
                    visible: false
                    layer.enabled: true
                    layer.smooth: true
                }
            }
        }
    }
}
