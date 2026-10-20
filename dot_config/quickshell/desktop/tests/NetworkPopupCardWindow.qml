import QtQuick

Item {
    id: card
    required property var theme
    property bool revealed: false
    property real cardWidth: 460
    property real cardHeight: -1
    property string title: ""
    property string subtitle: ""
    property string footer: ""
    property string layerNamespace: ""
    property bool plain: false
    property bool escDismiss: true
    property real anchorGap: 8
    property string anchorEdge: ""
    property real anchorBarX: 0
    property real anchorBarY: 0
    signal dismiss()
    signal keyPressed(var event)
    default property alias bodyData: body.data
    width: theme.testPanelWidth
    height: theme.testPanelHeight
    focus: revealed
    property real panelWidth: 720
    property real panelHeight: 480
    function refocus() { forceActiveFocus(); }
    Item {
        id: body
        x: 16; y: 16
        width: card.cardWidth - 32
        height: card.cardHeight > 0 ? card.cardHeight - 32 : 400
        clip: false
    }
}
