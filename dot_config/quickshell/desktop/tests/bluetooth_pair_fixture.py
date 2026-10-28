#!/usr/bin/env python3
import json
import sys
import time

mode, marker = sys.argv[1:]
def emit(**message):
    print(json.dumps(message), flush=True)

emit(event='ready')
job = json.loads(sys.stdin.readline())
if mode == 'hang':
    time.sleep(10)
    sys.exit()
emit(event='prompt', id=7, path=job['path'], kind='passkey', code='', entered=0)
emit(event='prompt', id=6, path=job['path'], kind='pin', code='', entered=0)
command = json.loads(sys.stdin.readline())
if command['action'] == 'cancel':
    with open(marker, 'a', encoding='utf8') as output:
        output.write('cancel\n')
    emit(event='result', id=job['id'], path=job['path'], success=False, error='fixture canceled')
else:
    assert command['action'] == 'answer' and command['promptId'] == 7 and command['value'] == '42'
    emit(event='result', id=job['id'], path=job['path'], success=(mode == 'success'), error='fixture rejected')
