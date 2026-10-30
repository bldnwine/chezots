"""Use production card geometry offscreen without a layer-shell window."""
from pathlib import Path


def write_card(root):
    source = Path(__file__).resolve().parents[1]
    qml = (source / "CardWindow.qml").read_text().replace("PanelWindow {", "Item {", 1)
    qml = qml.replace('    color: "transparent"\n', "", 1)
    # The geometry fixture is an Item, so it has no Wayland surface to grab.
    qml = qml.replace("    PopupFocusGrab { window: card }\n", "", 1)
    qml = qml.replace("    anchors { top: true; bottom: true; left: true; right: true }",
                      "    width: theme.testPanelWidth\n    height: theme.testPanelHeight", 1)
    qml = "\n".join(line for line in qml.splitlines()
                    if not line.strip().startswith(("exclusionMode:", "WlrLayershell.")))
    # Test-only accessors inspect the same geometry used by the live card.
    qml = qml.replace("    id: card", """    id: card
    readonly property real testBodyBottom: bodyContainer.y + bodyContainer.height
    readonly property real testFooterTop: footerLabel.y
    readonly property real testSurfaceHeight: surface.height
    readonly property real testBodyY: bodyContainer.y
""", 1)
    (root / "CardWindow.qml").write_text(qml)
