import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'scripts/brightness_helper.py'


class BrightnessHelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        sysfs = self.root / 'sys'
        self.connector = sysfs / 'devices/card1/card1-eDP-1'
        self.device = self.connector / 'intel_backlight'
        self.device.mkdir(parents=True)
        (self.device / 'brightness').write_text('30')
        (self.device / 'max_brightness').write_text('100')
        (sysfs / 'class/drm').mkdir(parents=True)
        (sysfs / 'class/backlight').mkdir(parents=True)
        (sysfs / 'class/drm/card1-eDP-1').symlink_to(self.connector)
        (sysfs / 'class/backlight/intel_backlight').symlink_to(self.device)
        ctl = self.root / 'brightnessctl'
        ctl.write_text('#!/usr/bin/python3\nimport os, pathlib, sys\n'
                       'pathlib.Path(os.environ["LOG"]).write_text(repr(sys.argv[1:]))\n'
                       'pathlib.Path(os.environ["DEVICE"]).joinpath("brightness").write_text(sys.argv[-1][:-1])\n')
        ctl.chmod(0o755)
        self.env = dict(os.environ, QS_BRIGHTNESS_SYSFS=str(sysfs), QS_BRIGHTNESSCTL=str(ctl),
                        LOG=str(self.root / 'log'), DEVICE=str(self.device))

    def call(self, action, output='eDP-1', value='0'):
        p = subprocess.run(['python3', str(HELPER), action, output, value], env=self.env,
                           capture_output=True, text=True, timeout=5)
        return p.returncode, json.loads(p.stdout)

    def test_seed_step_and_real_result(self):
        self.assertEqual(self.call('step', value='5'), (0, {'ok': True, 'output': 'eDP-1', 'percentage': 35.0}))
        self.assertEqual((self.root / 'log').read_text(), "['-q', '-d', 'intel_backlight', 'set', '35%']")
        (self.device / 'brightness').write_text('60')
        self.assertEqual(self.call('step', value='-5')[1]['percentage'], 55)
        result = self.call('dim', value='30')[1]
        self.assertEqual(result['previousPercentage'], 55)
        self.assertEqual(result['percentage'], 30)

    def test_external_and_unknown_never_write(self):
        for output in ('HDMI-A-1', 'DP-1', 'eDP-2', 'eDP-1;bad'):
            self.assertNotEqual(self.call('set', output, '70')[0], 0)
        self.assertFalse((self.root / 'log').exists())

    def test_ambiguity_and_failed_write(self):
        other = self.connector / 'another'
        other.mkdir()
        (self.root / 'sys/class/backlight/another').symlink_to(other)
        self.assertNotEqual(self.call('set', value='70')[0], 0)
        (self.root / 'sys/class/backlight/another').unlink()
        self.env['QS_BRIGHTNESSCTL'] = '/bin/false'
        self.assertNotEqual(self.call('set', value='70')[0], 0)
        self.assertEqual((self.device / 'brightness').read_text(), '30')

    def test_termination_reaps_writer(self):
        ctl = Path(self.env['QS_BRIGHTNESSCTL'])
        ctl.write_text('#!/usr/bin/python3\nimport os, pathlib, time\n'
                       'pathlib.Path(os.environ["LOG"]).write_text(str(os.getpid()))\n'
                       'time.sleep(30)\n')
        process = subprocess.Popen(['python3', str(HELPER), 'set', 'eDP-1', '70'], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            for _ in range(100):
                if (self.root / 'log').exists():
                    break
                time.sleep(.01)
            writer_pid = int((self.root / 'log').read_text())
            process.terminate()
            process.communicate(timeout=3)
            with self.assertRaises(ProcessLookupError):
                os.kill(writer_pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
