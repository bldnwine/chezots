"""Use production card geometry offscreen without a layer-shell window."""
from pathlib import Path
import shutil


def write_card(root):
    source = Path(__file__).resolve().parents[1]
    shutil.copy2(source / "SurfaceEffects.qml", root / "SurfaceEffects.qml")
    qml = (source / "CardWindow.qml").read_text().replace("PanelWindow {", "Item {", 1)
    qml = qml.replace('    color: "transparent"\n', "", 1)
    # The geometry fixture is an Item, so it has no Wayland surface to grab.
    qml = qml.replace("    PopupFocusGrab { window: card }\n", "", 1)
    qml = qml.replace("    anchors { top: true; bottom: true; left: true; right: true }",
                      "    width: theme.testPanelWidth\n    height: theme.testPanelHeight", 1)
    qml = "\n".join(line for line in qml.splitlines()
                    if not line.strip().startswith(("exclusionMode:", "WlrLayershell.", "BackgroundEffect.")))
    # Test-only accessors inspect the same geometry used by the live card.
    qml = qml.replace("    id: card", """    id: card
    readonly property real testBodyBottom: bodyViewport.y + bodyViewport.height
    readonly property real testFooterTop: footerLabel.y
    readonly property real testSurfaceHeight: surface.height
    readonly property real testBodyY: bodyViewport.y
    readonly property real testSurfaceWidth: surface.width
    readonly property real testSurfaceX: surface.x
    readonly property real testSurfaceY: surface.y
    readonly property real testFooterBottom: footerLabel.y + footerLabel.height
""", 1)
    (root / "CardWindow.qml").write_text(qml)
