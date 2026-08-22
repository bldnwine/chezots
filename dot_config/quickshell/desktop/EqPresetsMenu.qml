import QtQuick

// Full-width Presets Bar placed below the APPLY row.
// Features a dropdown menu to select/delete presets, plus an inline text field to save new presets.
Item {
    id: presetsMenu
    required property var root

    property string activePreset: "Flat"
    property var presetList: ["Flat"]
    property bool menuOpen: false
    property string newPresetName: ""

    signal presetSelected(string name)
    signal saveRequested(string name)
    signal deleteRequested(string name)

    implicitWidth: 360
    implicitHeight: 28

    function cleanDisplayName(name) {
        if (!name) return "Flat";
        const single = String(name).split(/[\r\n]+/)[0].trim();
        return single.length > 24 ? single.slice(0, 24) + "…" : single;
    }

    Row {
        anchors.fill: parent
        spacing: 6

        // Dropdown Trigger Button
        Rectangle {
            id: triggerBtn
            width: 140
            height: parent.height
            radius: presetsMenu.root.cornerRadius
            color: triggerMouse.containsMouse || presetsMenu.menuOpen ? presetsMenu.root.rowHi : "transparent"
            border.color: presetsMenu.menuOpen ? presetsMenu.root.seal : presetsMenu.root.sep
            border.width: 1
            clip: true

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: "󰓃"
                    color: presetsMenu.root.seal
                    font.family: presetsMenu.root.mono
                    font.pixelSize: 10
                }

                Text {
                    width: parent.width - 32
                    text: presetsMenu.cleanDisplayName(presetsMenu.activePreset)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    clip: true
                    color: presetsMenu.root.ink
                    font.family: presetsMenu.root.mono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.letterSpacing: 1
                }

                Text {
                    text: presetsMenu.menuOpen ? "󰅃" : "󰅀"
                    color: presetsMenu.root.inkDeep
                    font.family: presetsMenu.root.mono
                    font.pixelSize: 10
                }
            }

            MouseArea {
                id: triggerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: presetsMenu.menuOpen = !presetsMenu.menuOpen
            }
        }

        // Inline New Preset Name Input
        Rectangle {
            width: parent.width - 140 - 6 - 50 - 6
            height: parent.height
            radius: presetsMenu.root.cornerRadius
            color: presetsMenu.root.rowHi
            border.color: nameInput.activeFocus ? presetsMenu.root.seal : presetsMenu.root.sep
            border.width: 1
            clip: true

            TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.margins: 6
                text: presetsMenu.newPresetName
                color: presetsMenu.root.ink
                font.family: presetsMenu.root.mono
                font.pixelSize: 10
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                maximumLength: 32
                onTextChanged: {
                    if (text.indexOf("\n") !== -1 || text.indexOf("\r") !== -1) {
                        text = text.replace(/[\r\n]+/g, " ").trim().slice(0, 32);
                    }
                    presetsMenu.newPresetName = text;
                }
                Keys.onReturnPressed: (e) => {
                    const clean = text.replace(/[\r\n]+/g, " ").trim().slice(0, 32);
                    if (clean.length > 0) {
                        presetsMenu.saveRequested(clean);
                        text = "";
                        presetsMenu.menuOpen = false;
                    }
                    e.accepted = true;
                }

                Text {
                    visible: nameInput.text.length === 0
                    anchors.fill: parent
                    text: "Preset name..."
                    color: presetsMenu.root.inkDeep
                    font.family: presetsMenu.root.mono
                    font.pixelSize: 9
                    verticalAlignment: Text.AlignVCenter
                    maximumLineCount: 1
                }
            }
        }

        // Save Button
        Rectangle {
            width: 50
            height: parent.height
            radius: presetsMenu.root.cornerRadius
            color: saveMouse.containsMouse ? presetsMenu.root.seal : presetsMenu.root.rowHi
            border.color: presetsMenu.root.sep
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "SAVE"
                color: saveMouse.containsMouse ? presetsMenu.root.bg : presetsMenu.root.ink
                font.family: presetsMenu.root.mono
                font.pixelSize: 9
                font.letterSpacing: 1
                font.weight: Font.Medium
            }

            MouseArea {
                id: saveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const clean = presetsMenu.newPresetName.replace(/[\r\n]+/g, " ").trim().slice(0, 32);
                    if (clean.length > 0) {
                        presetsMenu.saveRequested(clean);
                        presetsMenu.newPresetName = "";
                        presetsMenu.menuOpen = false;
                    }
                }
            }
        }
    }

    // Floating Dropdown Menu Card (above presets bar)
    Rectangle {
        id: menuCard
        visible: presetsMenu.menuOpen
        z: 100
        anchors.bottom: parent.top
        anchors.bottomMargin: 4
        anchors.left: parent.left
        width: 190
        height: Math.min(180, menuCol.implicitHeight + 16)
        radius: presetsMenu.root.cornerRadius
        color: presetsMenu.root.bg
        border.color: presetsMenu.root.seal
        border.width: 1
        clip: true

        Column {
            id: menuCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Text {
                text: "SAVED PRESETS"
                color: presetsMenu.root.inkDeep
                font.family: presetsMenu.root.mono
                font.pixelSize: 9
                font.letterSpacing: 1.5
                maximumLineCount: 1
            }

            // Scrollable presets list
            Flickable {
                width: parent.width
                height: Math.min(140, listCol.implicitHeight)
                contentWidth: width
                contentHeight: listCol.implicitHeight
                clip: true

                Column {
                    id: listCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: presetsMenu.presetList
                        delegate: Rectangle {
                            required property string modelData
                            required property int index

                            readonly property bool isCurrent: presetsMenu.activePreset === modelData
                            width: parent.width
                            height: 24
                            radius: presetsMenu.root.cornerRadius
                            color: isCurrent
                                   ? presetsMenu.root.rowSel
                                   : (itemMouse.containsMouse ? presetsMenu.root.rowHi : "transparent")
                            clip: true

                            Row {
                                anchors.left: parent.left
                                anchors.right: delBtn.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 6
                                anchors.rightMargin: 4
                                spacing: 6

                                Text {
                                    text: isCurrent ? "󰄬" : " "
                                    color: presetsMenu.root.seal
                                    font.family: presetsMenu.root.mono
                                    font.pixelSize: 10
                                }

                                Text {
                                    text: presetsMenu.cleanDisplayName(modelData)
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    clip: true
                                    width: parent.width - 20
                                    color: isCurrent ? presetsMenu.root.ink : presetsMenu.root.fg
                                    font.family: presetsMenu.root.mono
                                    font.pixelSize: 10
                                    font.weight: isCurrent ? Font.Medium : Font.Normal
                                }
                            }

                            // Delete preset button (only for custom presets)
                            Item {
                                id: delBtn
                                visible: modelData !== "Flat"
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: delMouse.containsMouse ? presetsMenu.root.seal : presetsMenu.root.inkDeep
                                    font.family: presetsMenu.root.mono
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: presetsMenu.deleteRequested(modelData)
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                anchors.rightMargin: modelData !== "Flat" ? 22 : 0
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    presetsMenu.presetSelected(modelData);
                                    presetsMenu.menuOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
