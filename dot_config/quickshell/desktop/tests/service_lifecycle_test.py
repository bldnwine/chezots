"""Real Calendar/WARP QML lifecycles with private, non-networking commands."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='quickshell-services-test-') as directory:
    root = Path(directory)
    for name in ('CalendarService.qml','CalendarModel.js','WarpService.qml','WarpModel.js'):
        shutil.copy2(source/name, root/name)
    shutil.copy2(source/'tests/ServiceLifecycleTest.qml',root/'shell.qml')
    events = dict(version=1,syncedAt='2020-01-01T00:00:00Z',source='test',events=[
        dict(id='event',calendarId='one',dateKey='2026-10-12',title='Original',allDay=True,start='2026-10-12',end='2026-10-15'),
        dict(id='event',calendarId='two',dateKey='2026-10-12',title='Other',allDay=True,start='2026-10-12',end='2026-10-13')])
    (root/'events.json').write_text(json.dumps(events))
    (root/'action.py').write_text('''import json,os,sys,time
from pathlib import Path
with open(os.environ['QS_TEST_ACTION_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
time.sleep(.08)
print('fake Google denied the mutation',file=sys.stderr)
raise SystemExit(1)
''')
    (root/'sync.py').write_text('''import os,sys
with open(os.environ['QS_TEST_SYNC_LOG'],'a') as f: f.write('sync\\n')
print('fake sync failure',file=sys.stderr)
raise SystemExit(1)
''')
    sudo = root/'sudo'
    sudo.write_text('''#!/usr/bin/env python3
import json,os,sys,time
with open(os.environ['QS_TEST_DAEMON_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
time.sleep(5)
''')
    sudo.chmod(0o755)
    cli = root/'warp-cli'
    cli.write_text('''#!/usr/bin/env python3
import json,os,sys,time
args=[a for a in sys.argv[1:] if not a.startswith('--')]
with open(os.environ['QS_TEST_WARP_LOG'],'a') as f: f.write(json.dumps(args)+'\\n')
if args[:1] in (['mode'],['connect']): time.sleep(5)
result= {'status':'Disconnected'} if args[:1]==['status'] else {'settings':{'operation_mode':'warp'}} if args[:1]==['settings'] else {'registration':{'device_id':'known','account':{'account_type':'Free'}}} if args[:1]==['registration'] else {'stats':{'bytes_sent':10}}
print(json.dumps(result))
''')
    cli.chmod(0o755)
    clipboard=root/'wl-copy'
    clipboard.write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
Path(os.environ['QS_TEST_CLIPBOARD']).write_text(sys.stdin.read())
''')
    clipboard.chmod(0o755)
    env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1',
             PATH=str(root)+os.pathsep+os.environ['PATH'])
    for key, filename in dict(EVENTS='events.json',ACTION='action.py',SYNC='sync.py',WARP='warp-cli',
                              DAEMON_LOG='daemon.log',ACTION_LOG='actions.log',SYNC_LOG='sync.log',WARP_LOG='warp.log',CLIPBOARD='clipboard').items():
        env['QS_TEST_'+key]=str(root/filename)
    result=subprocess.run(['dbus-run-session','--','qs','-p',str(root)],env=env,capture_output=True,text=True,timeout=10)
    output=result.stdout+result.stderr
    if result.returncode or 'service lifecycle regression tests passed' not in output or 'WARN scene:' in output:
        print(output);raise SystemExit(1)
    assert (root/'sync.log').read_text().splitlines()==['sync']
    actions=[json.loads(line) for line in (root/'actions.log').read_text().splitlines()]
    assert len(actions)==2 and all(args[0]=='edit' for args in actions)
    assert '--date' not in actions[0] and '--all-day' not in actions[0]
    assert '--date' in actions[1] and '11:00' in actions[1]
    assert json.loads((root/'events.json').read_text())==events
    calls=[json.loads(line) for line in (root/'warp.log').read_text().splitlines()]
    assert not any('debug' in call or 'connectivity-check' in call for call in calls)
    daemon_calls=[json.loads(line) for line in (root/'daemon.log').read_text().splitlines()]
    assert daemon_calls==[['-n','/usr/bin/systemctl','start','warp-svc'],
                          ['-n','/usr/bin/systemctl','stop','warp-svc']]
    assert (root/'clipboard').read_text()=='literal $(printf injected) `printf injected` spaces'
    print('service lifecycle regression tests passed')
