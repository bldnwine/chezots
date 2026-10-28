"""Real QML with private buses, isolated state and fake hardware/agent."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='quickshell-adoption-') as directory:
    root = Path(directory)
    runtime = root/'runtime'
    runtime.mkdir(mode=0o700)
    for name in ('BarSettings.qml','BarSettingsModel.js','BluetoothService.qml','BatteryService.qml'):
        shutil.copy2(source/name,root/name)
    agent=root/'agent'
    agent.write_text('#!/bin/sh\necho "fixture connection refused" >&2\nexit 1\n')
    agent.chmod(0o755)
    state=root/'state'
    state.mkdir()
    (state/'bar-edge').write_text('left')
    (state/'bar-height').write_text('32')
    (state/'bar-template').write_text('desk')
    (state/'bar-templates.json').write_text(json.dumps({'desk':{'height':28}}))
    def run(harness, mode=''):
        (root/'shell.qml').write_text((source/'tests'/harness).read_text())
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1',
                 XDG_RUNTIME_DIR=str(runtime), QS_TEST_STATE=str(state), QS_TEST_MODE=mode, QS_TEST_AGENT=str(agent))
        result=subprocess.run(['dbus-run-session','--','qs','-p',str(root)],env=env,capture_output=True,text=True,timeout=10)
        output=result.stdout+result.stderr
        if result.returncode or 'lifecycle tests passed' not in output or 'WARN scene:' in output:
            raise AssertionError(output)
    run('BarSettingsTest.qml','migration')
    saved=json.loads((state/'bar.json').read_text())
    assert saved['settings']['height']==37 and saved['settings']['air']==19
    assert saved['selectedTemplate']=='newdesk'
    assert (state/'bar-edge').read_text()=='left'
    run('BarSettingsTest.qml','restart')
    run('BarSettingsTest.qml','shutdown')
    assert json.loads((state/'bar.json').read_text())['settings']['air']==23
    run('BarSettingsTest.qml','savefail')
    assert json.loads((state/'bar.json').read_text())['settings']['air']==23
    (state/'bar.json').write_text('{broken')
    run('BarSettingsTest.qml','corrupt')
    assert (state/'bar.json').read_text()=='{broken'
    run('HardwareServicesTest.qml')
    popup=(source/'BluetoothPopup.qml').read_text().replace('    id: btpopup',
        '    id: btpopup\n    property alias testPairCode: pairCode.text\n    readonly property real testScrollY: deviceScroll.contentY\n    readonly property real testScrollHeight: deviceScroll.height',1)
    (root/'BluetoothPopup.qml').write_text(popup)
    card=(source/'tests/NetworkPopupCardWindow.qml').read_text().replace('    id: card',
        '    id: card\n    property var screen: ({height: 480})',1)
    (root/'CardWindow.qml').write_text(card)
    shutil.copy2(source/'QuickButton.qml',root/'QuickButton.qml')
    run('BluetoothPopupTest.qml')
print('adoption lifecycle tests passed')
