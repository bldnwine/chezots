"""Exercise the real watcher against isolated state and a controllable event stream."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/notification-center"


class WatchBatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="notification-batch-")
        self.root = Path(self.temp.name)
        self.src = self.root / "src"
        self.src.mkdir()
        self.store = self.root / "store"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.fifo = self.root / "events"
        os.mkfifo(self.fifo)
        (self.bin / "inotifywait").write_text('#!/bin/sh\nexec cat "$FAKE_EVENTS"\n')
        (self.bin / "jq").write_text('#!/bin/sh\ncase "$*" in *"select(.timestamp >= \\$cutoff)"*) echo prune >> "$PRUNE_LOG";; esac\nexec /usr/bin/jq "$@"\n')
        for path in self.bin.iterdir():
            path.chmod(0o755)
        self.log = self.root / "prunes"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        NC_STORE=str(self.store), NC_SRC_DIR=str(self.src),
                        NC_SRC_HISTORY=str(self.src / "history"), NC_MAX_ITEMS="3",
                        FAKE_EVENTS=str(self.fifo), PRUNE_LOG=str(self.log))
        self.proc = subprocess.Popen([str(SCRIPT), "watch"], env=self.env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.events = open(self.fifo, "w")
        self.announced = []
        def collect():
            for line in self.proc.stdout:
                self.announced.append(line)
        self.reader = threading.Thread(target=collect, daemon=True)
        self.reader.start()

    def tearDown(self):
        self.events.close()
        try:
            self.proc.wait(timeout=5)
        finally:
            if self.proc.poll() is None:
                self.proc.kill()
                self.proc.wait()
            self.proc.stdout.close()
            self.proc.stderr.close()
            self.temp.cleanup()

    def emit(self, n, **extra):
        stamp = int(time.time() * 1000)
        key = f"{stamp}-{n}"
        path = self.src / (key + ".json")
        path.write_text(json.dumps(dict(key=key, app="batch", summary=str(n), body="",
                                        timestamp=stamp, **extra)))
        self.events.write(str(path) + "\n")
        self.events.flush()
        return key

    def wait_for(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.02)
        self.fail("timed out waiting for watcher")

    def entries(self):
        path = self.store / "archive.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text().splitlines() if line]

    def prunes(self):
        return len(self.log.read_text().splitlines()) if self.log.exists() else 0

    def test_burst_announces_immediately_and_prunes_once_on_idle(self):
        self.wait_for(lambda: (self.store / "screenshot-sources").is_dir())
        source = self.store / "screenshot-sources" / "queued.png"
        source.write_bytes(b"queued")
        os.utime(source, (time.time() - 7200, time.time() - 7200))
        (self.src / "queued.json").write_text(json.dumps(dict(screenshotPath=str(source), screenshotTemporary=True)))
        for i in range(6):
            self.emit(i)
        self.wait_for(lambda: len(self.announced) == 6)
        self.wait_for(lambda: self.prunes() >= 1 and len(self.entries()) == 3)
        self.assertEqual(self.prunes(), 1)
        self.assertEqual([x["summary"] for x in self.entries()], ["3", "4", "5"])
        self.assertTrue(source.exists(), "pruning must keep sources referenced by pending input")

    def test_continuous_events_do_not_extend_deadline(self):
        self.emit(0)
        self.wait_for(lambda: len(self.announced) == 1)
        start = time.monotonic()
        for i in range(1, 9):
            time.sleep(.18)
            self.emit(i)
        self.assertGreaterEqual(self.prunes(), 1, "prune must run during sustained arrivals")
        self.assertLess(time.monotonic() - start, 2.5)
        self.wait_for(lambda: len(self.announced) == 9)
        self.wait_for(lambda: len(self.entries()) == 3)

    def test_termination_flushes_pending_batch(self):
        self.emit(1)
        self.wait_for(lambda: len(self.announced) == 1)
        self.proc.terminate()
        self.proc.wait(timeout=5)
        self.assertEqual(self.prunes(), 1)
        self.assertEqual([x["summary"] for x in self.entries()], ["1"])

    def test_partial_event_survives_deadline_and_eof_discards_incomplete(self):
        self.emit(1)
        self.wait_for(lambda: len(self.announced) == 1)
        stamp = int(time.time() * 1000)
        key = f"{stamp}-chunked"
        path = self.src / (key + ".json")
        path.write_text(json.dumps(dict(key=key, app="batch", summary="chunked", body="", timestamp=stamp)))
        event = str(path)
        split = len(event) // 2
        self.events.write(event[:split])
        self.events.flush()
        self.wait_for(lambda: self.prunes() == 1)
        self.events.write(event[split:] + "\n")
        self.events.flush()
        self.wait_for(lambda: len(self.announced) == 2)
        self.assertTrue(any(x["key"] == key for x in self.entries()))
        self.events.write(str(self.src / "incomplete.json"))
        self.events.flush()
        self.events.close()
        self.proc.wait(timeout=5)
        self.assertEqual(len(self.announced), 2)

    def test_remove_clear_and_eof_flush_preserve_pending_screenshot(self):
        self.wait_for(lambda: (self.store / "screenshot-sources").is_dir())
        source = self.store / "screenshot-sources" / "pending.png"
        source.write_bytes(b"pending")
        key = self.emit(1, screenshotPath=str(source), screenshotTemporary=True)
        self.wait_for(lambda: len(self.announced) == 1)
        subprocess.run([str(SCRIPT), "remove", key], env=self.env, check=True, stdout=subprocess.DEVNULL)
        self.emit(2)
        self.wait_for(lambda: len(self.announced) == 2)
        subprocess.run([str(SCRIPT), "clear"], env=self.env, check=True, stdout=subprocess.DEVNULL)
        self.emit(3)
        self.wait_for(lambda: len(self.announced) == 3)
        self.events.close()
        self.proc.wait(timeout=5)
        self.assertEqual([x["summary"] for x in self.entries()], ["3"])
        self.assertGreaterEqual(self.prunes(), 1)
        # A new pending source is retained during restart recovery.
        source.write_bytes(b"pending")
        stamp = int(time.time() * 1000) + 10
        path = self.src / f"{stamp}-recovery.json"
        path.write_text(json.dumps(dict(key=path.stem, app="recover", summary="recover", body="",
                                        timestamp=stamp, screenshotPath=str(source), screenshotTemporary=True)))
        subprocess.run([str(SCRIPT), "sync"], env=self.env, check=True, stdout=subprocess.DEVNULL)
        self.assertTrue(source.exists())
        self.assertTrue(any(x["key"] == path.stem for x in self.entries()))


if __name__ == "__main__":
    unittest.main()
