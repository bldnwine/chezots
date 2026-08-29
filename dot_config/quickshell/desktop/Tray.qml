import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Item {
    id: trayRoot
    required property var root

    readonly property bool isHorizontal: root.isHorizontal
    readonly property int primaryCount: root.trayPrimaryItems ? root.trayPrimaryItems.length : 0
    readonly property int overflowCount: root.trayOverflowItems ? root.trayOverflowItems.length : 0
    readonly property bool hasOverflow: root.trayHasOverflow
    readonly property bool hasItems: primaryCount > 0

    visible: hasItems

    Layout.alignment: isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth: isHorizontal ? implicitWidth : root.barHeight
    Layout.preferredHeight: isHorizontal ? root.barHeight : implicitHeight

    implicitWidth: isHorizontal ? (mainLayout.implicitWidth) : root.barHeight
    implicitHeight: isHorizontal ? root.barHeight : (mainLayout.implicitHeight)

    Row {
        id: mainLayout
        visible: trayRoot.isHorizontal
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // 1. Expandable overflow drawer (6th item onwards) to the left of the chevron
        Item {
            id: drawerContainerH
            visible: trayRoot.hasOverflow
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: root.barHeight
            implicitWidth: width
            width: (trayRoot.hasOverflow && root.trayExpanded) ? drawerRowH.implicitWidth : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Row {
                id: drawerRowH
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                spacing: 2

                Repeater {
                    model: root.trayOverflowItems || []
                    delegate: TrayItem {
                        root: trayRoot.root
                    }
                }
            }
        }

        // 2. Chevron toggle button (only visible when more than 5 items exist)
        Item {
            id: chevronBtnH
            visible: trayRoot.hasOverflow
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 16
            implicitHeight: root.barHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: root.cornerRadius
                color: chevronMouseH.containsMouse
                       ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Bloom { id: chevronBloomH; root: trayRoot.root }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: root.trayExpanded ? "›" : "‹"
                color: chevronMouseH.containsMouse ? root.seal : root.inkDeep
                font.family: root.mono
                font.pixelSize: 13
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Timer {
                id: chevronTipDelayH
                interval: 320
                onTriggered: {
                    const p = chevronBtnH.mapToItem(null, chevronBtnH.width / 2, chevronBtnH.height / 2);
                    root.showTooltip(root.trayExpanded ? "Collapse tray" : "Expand tray", p.x, p.y);
                }
            }

            MouseArea {
                id: chevronMouseH
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    chevronBloomH.fire(mouseX, mouseY);
                    chevronTipDelayH.restart();
                }
                onExited: {
                    chevronTipDelayH.stop();
                    root.hideTooltip("tray-chevron");
                }
                onClicked: function(mouse) {
                    chevronTipDelayH.stop();
                    root.hideTooltip("tray-chevron");
                    if (mouse.button === Qt.RightButton) {
                        root.openTrayManage(chevronBtnH);
                    } else {
                        root.trayExpanded = !root.trayExpanded;
                    }
                }
            }
        }

        // 3. Primary visible items (up to 5 items directly visible in bar)
        Row {
            id: visibleRowH
            visible: trayRoot.primaryCount > 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Repeater {
                model: root.trayPrimaryItems || []
                delegate: TrayItem {
                    root: trayRoot.root
                }
            }
        }
    }

    // Vertical bar orientation layout
    Column {
        id: mainLayoutV
        visible: !trayRoot.isHorizontal
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Item {
            id: drawerContainerV
            visible: trayRoot.hasOverflow
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.barHeight
            implicitHeight: height
            height: (trayRoot.hasOverflow && root.trayExpanded) ? drawerColV.implicitHeight : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Column {
                id: drawerColV
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 2

                Repeater {
                    model: root.trayOverflowItems || []
                    delegate: TrayItem {
                        root: trayRoot.root
                    }
                }
            }
        }

        Item {
            id: chevronBtnV
            visible: trayRoot.hasOverflow
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.barHeight
            implicitHeight: 16

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: root.cornerRadius
                color: chevronMouseV.containsMouse
                       ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Bloom { id: chevronBloomV; root: trayRoot.root }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: root.trayExpanded ? "ˇ" : "ˆ"
                color: chevronMouseV.containsMouse ? root.seal : root.inkDeep
                font.family: root.mono
                font.pixelSize: 13
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Timer {
                id: chevronTipDelayV
                interval: 320
                onTriggered: {
                    const p = chevronBtnV.mapToItem(null, chevronBtnV.width / 2, chevronBtnV.height / 2);
                    root.showTooltip(root.trayExpanded ? "Collapse tray" : "Expand tray", p.x, p.y);
                }
            }

            MouseArea {
                id: chevronMouseV
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    chevronBloomV.fire(mouseX, mouseY);
                    chevronTipDelayV.restart();
                }
                onExited: {
                    chevronTipDelayV.stop();
                    root.hideTooltip("tray-chevron");
                }
                onClicked: function(mouse) {
                    chevronTipDelayV.stop();
                    root.hideTooltip("tray-chevron");
                    if (mouse.button === Qt.RightButton) {
                        root.openTrayManage(chevronBtnV);
                    } else {
                        root.trayExpanded = !root.trayExpanded;
                    }
                }
            }
        }

        Column {
            id: visibleColV
            visible: trayRoot.primaryCount > 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Repeater {
                model: root.trayPrimaryItems || []
                delegate: TrayItem {
                    root: trayRoot.root
                }
            }
        }
    }

    component TrayItem: Item {
        id: trayItemRoot
        required property var root
        required property var modelData

        readonly property string itemTip: {
            if (!modelData) return "";
            return modelData.tooltipTitle || modelData.title || modelData.id || "Tray item";
        }

        implicitWidth: 20
        implicitHeight: root.barHeight

        Rectangle {
            anchors.centerIn: parent
            width: 18
            height: 18
            radius: root.cornerRadius
            color: itemMouseArea.containsMouse
                   ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                   : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Bloom { id: itemBloom; root: trayItemRoot.root }

        IconImage {
            id: itemIconImg
            anchors.centerIn: parent
            implicitSize: 14
            width: 14
            height: 14
            source: root.trayIconSource(trayItemRoot.modelData ? (trayItemRoot.modelData.icon || trayItemRoot.modelData.iconName) : "")
        }

        Timer {
            id: tipDelay
            interval: 320
            onTriggered: {
                if (!trayItemRoot.itemTip) return;
                const p = trayItemRoot.mapToItem(null, trayItemRoot.width / 2, trayItemRoot.height / 2);
                root.showTooltip(trayItemRoot.itemTip, p.x, p.y);
            }
        }

        MouseArea {
            id: itemMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor

            onEntered: {
                itemBloom.fire(mouseX, mouseY);
                if (trayItemRoot.itemTip) tipDelay.restart();
            }
            onExited: {
                tipDelay.stop();
                root.hideTooltip(trayItemRoot.itemTip);
            }
            onClicked: function(mouse) {
                tipDelay.stop();
                root.hideTooltip(trayItemRoot.itemTip);
                if (mouse.button === Qt.RightButton) {
                    root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse);
                } else if (mouse.button === Qt.MiddleButton) {
                    if (trayItemRoot.modelData && typeof trayItemRoot.modelData.secondaryActivate === "function") {
                        trayItemRoot.modelData.secondaryActivate();
                    }
                } else {
                    if (trayItemRoot.modelData) {
                        if (trayItemRoot.modelData.onlyMenu) {
                            root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse);
                        } else if (typeof trayItemRoot.modelData.activate === "function") {
                            trayItemRoot.modelData.activate();
                        }
                    }
                }
            }
            onWheel: function(wheel) {
                if (trayItemRoot.modelData && typeof trayItemRoot.modelData.scroll === "function") {
                    trayItemRoot.modelData.scroll(wheel.angleDelta.y, false);
                }
            }
        }
    }
}
