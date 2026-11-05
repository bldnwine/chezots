"""Exercise bulk retention and temporary screenshot ownership with isolated state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

script = Path(__file__).resolve().parents[1] / 'scripts/notification-center'
with tempfile.TemporaryDirectory(prefix='notification-prune-') as directory:
    root = Path(directory)
    store, source = root / 'store', root / 'incoming'
    store.mkdir()
    source.mkdir()
    managed = store / 'screenshot-sources'
    managed.mkdir()
    images = store / 'images'
    images.mkdir()
    now = int(time.time() * 1000)
    shared = managed / 'shared.png'
    pending = managed / 'pending.png'
    discarded = managed / 'discarded.png'
    for path in (shared, pending, discarded):
        path.write_bytes(b'image')
    (source / 'pending.json').write_text(json.dumps({'screenshotTemporary': True, 'screenshotPath': str(pending)}))
    entries = [{'key': str(i), 'timestamp': 1, 'screenshotTemporary': True,
                'screenshotPath': str(discarded)} for i in range(1000)]
    duplicate = managed / 'duplicate.png'
    duplicate.write_bytes(b'image')
    entries += [dict(key='current', timestamp=1, screenshotTemporary=True, screenshotPath=str(duplicate)),
                dict(key='old-shared', timestamp=1, screenshotTemporary=True, screenshotPath=str(shared)),
                dict(key='old-pending', timestamp=1, screenshotTemporary=True, screenshotPath=str(pending)),
                dict(key='current', timestamp=now, screenshotTemporary=True, screenshotPath=str(shared))]
    archive = store / 'archive.jsonl'
    archive.write_text(''.join(json.dumps(entry) + '\n' for entry in entries))
    (images / '0-image').write_bytes(b'image')
    (images / 'current-image').write_bytes(b'image')
    env = dict(os.environ, NC_STORE=str(store), NC_SRC_DIR=str(source), NC_SRC_HISTORY=str(source / 'history'))
    start = time.monotonic()
    subprocess.run([str(script), 'prune'], env=env, check=True, capture_output=True, timeout=10)
    elapsed = time.monotonic() - start
    assert [json.loads(line)['key'] for line in archive.read_text().splitlines()] == ['current']
    assert shared.exists() and pending.exists() and duplicate.exists() and not discarded.exists()
    assert (images / 'current-image').exists()
    assert not (images / '0-image').exists()
    before = archive.stat()
    subprocess.run([str(script), 'prune'], env=env, check=True, capture_output=True, timeout=10)
    after = archive.stat()
    assert (before.st_ino, before.st_mtime_ns) == (after.st_ino, after.st_mtime_ns)
    print(f'notification prune regression passed; 1002 expired records in {elapsed:.3f}s')
