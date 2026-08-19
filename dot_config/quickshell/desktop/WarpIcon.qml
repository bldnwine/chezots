import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property real iconSize: 14
  property color color: "#c5c9c5"
  property color badgeColor: "#c4746e"
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Cloudflare's mark rendered natively as a cloud silhouette with trailing speed lines.
  // Drawn from vector curves so it stays crisp at any size.
  Shape {
    id: cloud
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeWidth: 0

      startX: root.width * 0.20
      startY: root.height * 0.72

      PathLine { x: root.width * 0.86; y: root.height * 0.72 }
      PathCubic {
        x: root.width * 0.86; y: root.height * 0.44
        control1X: root.width * 1.00; control1Y: root.height * 0.70
        control2X: root.width * 1.00; control2Y: root.height * 0.46
      }
      PathCubic {
        x: root.width * 0.63; y: root.height * 0.40
        control1X: root.width * 0.80; control1Y: root.height * 0.40
        control2X: root.width * 0.72; control2Y: root.height * 0.38
      }
      PathCubic {
        x: root.width * 0.24; y: root.height * 0.50
        control1X: root.width * 0.52; control1Y: root.height * 0.14
        control2X: root.width * 0.26; control2Y: root.height * 0.20
      }
      PathCubic {
        x: root.width * 0.20; y: root.height * 0.72
        control1X: root.width * 0.06; control1Y: root.height * 0.54
        control2X: root.width * 0.04; control2Y: root.height * 0.70
      }
    }
  }

  // Speed lines: WARP tunnel movement indication
  Column {
    anchors.left: parent.left
    anchors.leftMargin: -root.iconSize * 0.06
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.iconSize * 0.06
    spacing: Math.max(1, root.iconSize * 0.11)
    opacity: root.crossed ? 0.0 : 0.55
    visible: opacity > 0

    Rectangle {
      width: root.iconSize * 0.20
      height: Math.max(1, root.iconSize * 0.08)
      radius: height / 2
      color: root.color
    }

    Rectangle {
      width: root.iconSize * 0.13
      height: Math.max(1, root.iconSize * 0.08)
      radius: height / 2
      color: root.color
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  Rectangle {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    border.color: "#181616"
    border.width: 1

    Text {
      anchors.centerIn: parent
      text: "!"
      color: "#181616"
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
