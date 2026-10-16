"""Theme fingerprint and real QML cache lifecycle checks using temporary data."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("theme_fingerprint", SOURCE / "scripts/theme-fingerprint.py")
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)


class ThemeCacheTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="quickshell-themes-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.omarchy = self.root / "omarchy"

    def write(self, relative, text):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def fingerprint(self):
        return scanner.fingerprint(self.home, str(self.omarchy))

    def test_fingerprint_tracks_discovery_changes(self):
        previous = self.fingerprint()
        for relative in [".config/aether/blueprints/test.json",
                         ".config/aether/themes/test/colors.toml",
                         ".local/share/omarchy/themes/test/preview.png",
                         ".config/omarchy/themes/test/backgrounds/first.jpg",
                         ".config/aether/theme/colors.toml",
                         ".config/omarchy/current/theme/colors.toml"]:
            path = self.write(relative, "initial")
            changed = self.fingerprint()
            self.assertNotEqual(previous, changed, relative)
            self.assertEqual(changed, self.fingerprint(), "reads must not invalidate the fingerprint")
            path.write_text("updated contents")
            updated = self.fingerprint()
            self.assertNotEqual(changed, updated, relative)
            path.unlink()
            previous = self.fingerprint()
            self.assertNotEqual(updated, previous, relative)
        colors = self.omarchy / "themes/custom/colors.toml"
        colors.parent.mkdir(parents=True)
        colors.write_text("custom")
        self.assertNotEqual(previous, self.fingerprint(), "custom OMARCHY_PATH must be included")

    @unittest.skipUnless(shutil.which("qs") and shutil.which("dbus-run-session"), "requires Quickshell and D-Bus")
    def test_qml_cache_reuses_refreshes_and_survives_failed_or_cancelled_scans(self):
        config = self.root / "config"
        (config / "scripts").mkdir(parents=True)
        for name in ["Themes.qml", "Data.js", "Palette.js"]:
            shutil.copy2(SOURCE / name, config / name)
        shutil.copy2(SOURCE / "scripts/theme-fingerprint.py", config / "scripts/theme-fingerprint.py")
        shutil.copy2(SOURCE / "tests/ThemeCacheTest.qml", config / "shell.qml")
        first = 'background = "#111111"\nforeground = "#eeeeee"\n'
        second = 'background = "#222222"\nforeground = "#dddddd"\n'
        self.write(".config/aether/themes/first/colors.toml", first)
        self.write(".config/aether/themes/second/colors.toml", second)
        current = self.write(".config/aether/theme/colors.toml", first)
        control = self.root / "control"
        control.write_text("")
        scan_log = self.root / "scans"
        shim = self.root / "sh"
        shim.write_text('''#!/usr/bin/env python3
import os,sys,time
from pathlib import Path
with open(os.environ['QS_TEST_SCANS'],'a') as log: log.write('scan\\n')
mode=Path(os.environ['QS_TEST_CONTROL']).read_text()
if mode == 'fail':
    print('incomplete output')
    raise SystemExit(1)
if mode == 'slow': time.sleep(.6)
os.execv('/bin/sh',['sh']+sys.argv[1:])
''')
        shim.chmod(0o755)
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, HOME=str(self.home), OMARCHY_PATH=str(self.omarchy),
                   XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1",
                   PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                   QS_TEST_SCANS=str(scan_log), QS_TEST_CONTROL=str(control))
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        with (self.root / "output").open("w+") as output:
            process = subprocess.Popen(["dbus-run-session", "--", "qs", "-p", str(config)],
                                       env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            def call(method):
                result = subprocess.run(["qs", "-p", str(config), "ipc", "--any-display", "call", "audit", method],
                                        env=env, capture_output=True, text=True, timeout=3)
                if result.returncode:
                    raise RuntimeError(result.stdout + result.stderr)
                return json.loads(result.stdout) if method == "status" else None

            def wait(predicate):
                deadline = time.monotonic() + 4
                last_error = ""
                while time.monotonic() < deadline:
                    try:
                        state = call("status")
                        if predicate(state):
                            return state
                    except (RuntimeError, json.JSONDecodeError) as error:
                        last_error = str(error)
                    time.sleep(.03)
                self.fail("QML cache did not reach expected state: " + last_error)

            def scans():
                return len(scan_log.read_text().splitlines()) if scan_log.exists() else 0

            try:
                wait(lambda state: not state["running"])
                call("open")
                original = wait(lambda state: state["loaded"] and not state["running"])["items"]
                self.assertEqual(scans(), 1)
                self.assertEqual(next(it["title"] for it in original if it["isActive"]), "first")
                call("close")
                call("open")
                self.assertEqual(call("status")["items"], original, "warm rows should be immediately available")
                wait(lambda state: not state["running"])
                self.assertEqual(scans(), 1, "unchanged sources should not run discovery again")

                current.write_text(second)
                call("refresh")
                wait(lambda state: not state["running"] and any(it["title"] == "second" and it["isActive"] for it in state["items"]))
                self.assertEqual(scans(), 2)
                blueprint = self.write(".config/aether/blueprints/new.json", '{"palette":{"colors":["#000000"]}}')
                call("refresh")
                updated = wait(lambda state: not state["running"] and len(state["items"]) == 3)["items"]
                self.assertEqual(scans(), 3)

                blueprint.unlink()
                control.write_text("fail")
                call("refresh")
                wait(lambda state: not state["running"] and scans() == 4)
                self.assertEqual(call("status")["items"], updated, "failed scans must retain complete cached results")
                control.write_text("")
                call("refresh")
                cached = wait(lambda state: not state["running"] and len(state["items"]) == 2)["items"]
                self.assertEqual(scans(), 5, "a failed scan must remain eligible for retry")

                current.write_text(first)
                control.write_text("slow")
                call("refresh")
                wait(lambda state: state["running"] and scans() == 6)
                call("close")
                time.sleep(.7)
                state = call("status")
                self.assertFalse(state["running"])
                self.assertEqual(state["items"], cached)
                self.assertEqual(scans(), 6, "closed views must not scan")
                control.write_text("")
                call("open")
                wait(lambda state: not state["running"] and any(it["title"] == "first" and it["isActive"] for it in state["items"]))
                self.assertEqual(scans(), 7, "cancelled scans must not mark the cache fresh")
                call("quit")
                process.wait(timeout=3)
                self.assertEqual(process.returncode, 0)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=3)
                output.seek(0)
                logs = output.read()
                if "WARN scene:" in logs:
                    self.fail(logs)


if __name__ == "__main__":
    unittest.main()
