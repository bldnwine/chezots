"""EQ persistence/restart behavior; all hardware calls are mocked."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/pipewire-eq"
loader = importlib.machinery.SourceFileLoader("eq_helper", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
eq = importlib.util.module_from_spec(spec)
loader.exec_module(eq)


class EqualizerHelperTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="qs-eq-helper-")
        self.root = Path(self.temp.name)
        self.patches = [patch.object(eq, name, path) for name, path in {
            "STATE_DIR": self.root / "state", "PRESETS_FILE": self.root / "state/presets.json",
            "STATE_FILE": self.root / "state/state.json", "PW_CONF_DIR": self.root / "conf",
            "PW_EQ_CONF": self.root / "conf/eq.conf",
        }.items()]
        for p in self.patches:
            p.start()
        eq.ensure_dirs()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.temp.cleanup()

    def test_live_failure_never_restarts_pipewire(self):
        with patch.object(eq, "apply_live_controls", return_value=False), \
                patch.object(eq, "restart_pipewire") as restart:
            with self.assertRaisesRegex(RuntimeError, "press APPLY"):
                eq.cmd_apply([json.dumps({"preamp": -4})], allow_restart=False)
        restart.assert_not_called()
        self.assertEqual(eq.load_state()["preamp"], -4)
        self.assertFalse(eq.PW_EQ_CONF.exists())

    def test_successful_live_update_persists_without_restart(self):
        with patch.object(eq, "apply_live_controls", return_value=True), \
                patch.object(eq, "restart_pipewire") as restart, contextlib.redirect_stdout(io.StringIO()) as out:
            eq.cmd_apply([json.dumps({"preamp": -3})], allow_restart=False)
        restart.assert_not_called()
        self.assertEqual(json.loads(out.getvalue())["status"], "applied_live")
        self.assertTrue(eq.PW_EQ_CONF.read_text())
        self.assertEqual(eq.load_state()["preamp"], -3)

    def test_explicit_apply_can_initialize_but_reports_failure(self):
        with patch.object(eq, "apply_live_controls", return_value=False), \
                patch.object(eq, "restart_pipewire", return_value=True) as restart, \
                contextlib.redirect_stdout(io.StringIO()) as out:
            eq.cmd_apply([])
        restart.assert_called_once()
        self.assertEqual(json.loads(out.getvalue())["status"], "applied_restarted")
        with patch.object(eq, "apply_live_controls", return_value=False), \
                patch.object(eq, "restart_pipewire", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "not applied"):
                eq.cmd_apply([])

    def test_state_and_presets_are_replaced_atomically(self):
        real_replace = eq.os.replace
        observed = []

        def inspect_replace(source, target):
            observed.append(json.loads(Path(source).read_text()))
            real_replace(source, target)

        with patch.object(eq.os, "replace", side_effect=inspect_replace):
            eq.save_state({"activePreset": "Test", "preamp": -2})
            eq.save_presets({"Test": {"preamp": -2}})
        self.assertEqual(observed, [{"activePreset": "Test", "preamp": -2}, {"Test": {"preamp": -2}}])
        self.assertEqual(list(eq.STATE_DIR.glob(".*")), [])

    def test_failed_atomic_write_keeps_previous_state(self):
        eq.save_state({"preamp": -2})
        with patch.object(eq.os, "replace", side_effect=OSError("test failure")):
            with self.assertRaises(OSError):
                eq.save_state({"preamp": -9})
        self.assertEqual(eq.load_state()["preamp"], -2)
        self.assertEqual(list(eq.STATE_DIR.glob(".*")), [])

    def test_apply_does_not_hide_a_persistence_failure(self):
        eq.save_state({"preamp": -2})
        with patch.object(eq.os, "replace", side_effect=OSError("disk full")), \
                patch.object(eq, "apply_live_controls") as apply:
            with self.assertRaisesRegex(OSError, "disk full"):
                eq.cmd_apply([json.dumps({"preamp": -9})], allow_restart=False)
        apply.assert_not_called()

    def test_import_does_not_restart_pipewire(self):
        with patch.object(eq, "apply_live_controls", return_value=False), \
                patch.object(eq, "restart_pipewire") as restart:
            with self.assertRaisesRegex(RuntimeError, "press APPLY"):
                eq.cmd_import(["Preamp: -4 dB\nFilter 1: ON PK Fc 100 Hz Gain 2 dB Q 1"])
        restart.assert_not_called()
        self.assertEqual(eq.load_state()["preamp"], -4)

    def test_main_live_and_apply_have_different_restart_policies(self):
        for command, kwargs in (("live", {"allow_restart": False}), ("apply", {})):
            with patch.object(sys, "argv", [str(SCRIPT), command]), patch.object(eq, "cmd_apply") as apply:
                eq.main()
            apply.assert_called_once_with([], **kwargs)

    def test_external_cli_operations_share_the_file_lock(self):
        # Two independent invocations must not enter a mutation concurrently.
        code = '''import importlib.machinery,importlib.util,json,sys,time
from pathlib import Path
l=importlib.machinery.SourceFileLoader('eq',sys.argv[1]); s=importlib.util.spec_from_loader(l.name,l)
m=importlib.util.module_from_spec(s); l.exec_module(m)
m.STATE_DIR=Path(sys.argv[2]); m.PW_CONF_DIR=m.STATE_DIR/'conf'
def action():
 with open(m.STATE_DIR/'events','a') as f: f.write('start '+sys.argv[3]+'\\n')
 time.sleep(.12)
 with open(m.STATE_DIR/'events','a') as f: f.write('end '+sys.argv[3]+'\\n')
m.main=action; m.run()
'''
        children = [subprocess.Popen([sys.executable, "-B", "-c", code, str(SCRIPT), str(eq.STATE_DIR), str(i)]) for i in range(2)]
        for child in children:
            self.assertEqual(child.wait(timeout=5), 0)
        events = (eq.STATE_DIR / "events").read_text().splitlines()
        self.assertEqual([line.split()[0] for line in events], ["start", "end", "start", "end"])
        self.assertEqual(events[0].split()[1], events[1].split()[1])
        self.assertEqual(events[2].split()[1], events[3].split()[1])


if __name__ == "__main__":
    unittest.main()
