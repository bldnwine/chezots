"""Exercise the real Polkit card with a fake agent and offscreen panel."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-polkit-test-") as directory:
    root = Path(directory)
    qml = (source / "PolkitAgent.qml").read_text()
    hooks = '''
    property int testPanelWidth: 720
    property int testPanelHeight: 480
    readonly property real testCommandHeight: commandViewport.height
    readonly property real testContentHeight: commandViewport.contentHeight
    readonly property string testCommandText: commandText.text
    function testRowBottom() { return cardRow.mapToItem(card, 0, cardRow.height).y; }
    readonly property bool testInputVisible: passwordInput.visible
    readonly property string testInputText: passwordInput.text
    readonly property bool testInputMasked: passwordInput.echoMode === TextInput.Password
    function testScrollToEnd() { commandViewport.contentY = commandViewport.contentHeight - commandViewport.height; }
    readonly property real testScrollY: commandViewport.contentY
    readonly property var testFlow: fakeFlow
    function testSetInput(value) { passwordInput.text = value; }
'''
    qml = qml.replace('    id: root', '    id: root' + hooks, 1)
    start = qml.index('    PolkitAgent {\n        id: polkitAgent')
    end = qml.index('\n    Connections {', start)
    qml = qml[:start] + '''    QtObject {
        id: polkitAgent
        property bool isActive: true
        property var flow: fakeFlow
    }
    QtObject {
        id: fakeFlow
        property string message: ""
        property string actionId: ""
        property string inputPrompt: "Password:"
        property string supplementaryMessage: ""
        property bool isResponseRequired: true
        property bool responseVisible: false
        property bool failed: false
        property string submittedText: ""
        property bool cancelled: false
        signal authenticationFailed()
        signal authenticationSucceeded()
        signal authenticationRequestCancelled()
        function submit(value) { submittedText = value; }
        function cancelAuthenticationRequest() { cancelled = true; }
    }
''' + qml[end:]
    qml = qml.replace('    PanelWindow {\n        id: panel', '    Item {\n        id: panel', 1)
    qml = qml.replace('        anchors { top: true; bottom: true; left: true; right: true }\n        color: "transparent"\n        WlrLayershell.namespace: "omarchy-polkit"\n        WlrLayershell.layer: WlrLayer.Overlay\n        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive\n        exclusionMode: ExclusionMode.Ignore', '        width: root.testPanelWidth\n        height: root.testPanelHeight', 1)
    (root / "PolkitAgent.qml").write_text(qml)
    shutil.copy2(source / "PolkitModel.js", root / "PolkitModel.js")
    shutil.copy2(source / "PopupFocusStack.js", root / "PopupFocusStack.js")
    shutil.copy2(source / "tests/PolkitGeometryTest.qml", root / "shell.qml")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_NO_XDG_DESKTOP_PORTAL="1")
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)], env=env,
                            capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or "polkit geometry tests passed" not in output or "WARN scene:" in output or "TypeError" in output or "ReferenceError" in output:
        raise AssertionError(output)
print("polkit geometry tests passed")
