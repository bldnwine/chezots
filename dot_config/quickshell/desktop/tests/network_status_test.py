#!/usr/bin/env python3
import importlib.util
import pathlib
import subprocess
import unittest
from unittest.mock import patch

path = pathlib.Path(__file__).resolve().parents[1] / 'scripts/network_status.py'
spec = importlib.util.spec_from_file_location('network_status', path)
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


class StatusTests(unittest.TestCase):
    def test_snapshot_preserves_independent_ethernet_wifi_and_vpn(self):
        with patch.object(status, 'interfaces', return_value=['enp1s0', 'proton0', 'wlan0']), \
             patch.object(status, 'has_ipv4', return_value=True), \
             patch.object(status, 'wifi_status', return_value=(True, 72, 'a|b: c')):
            self.assertEqual(status.snapshot(), {'eth': True, 'vpn': 'proton0', 'wifi': True,
                                                  'signal': 72, 'ssid': 'a|b: c'})

    def test_ipv4_is_required_and_links_only_skips_iw(self):
        with patch.object(status, 'interfaces', return_value=['eth0', 'proton1']), \
             patch.object(status, 'has_ipv4', return_value=False), \
             patch.object(status, 'wifi_status') as wifi:
            self.assertEqual(status.snapshot(False)['eth'], False)
            wifi.assert_not_called()

    def test_iw_signal_and_ssid_parsing(self):
        result = subprocess.CompletedProcess([], 0, 'Connected to xx\n\tSSID: a|b: c\n\tsignal: -64 dBm\n', '')
        with patch.object(status.os.path, 'exists', return_value=True), \
             patch.object(status.subprocess, 'run', return_value=result) as run:
            self.assertEqual(status.wifi_status(['wlan0']), (True, 72, 'a|b: c'))
            self.assertEqual(run.call_args.args[0], ['iw', 'dev', 'wlan0', 'link'])
            self.assertLessEqual(run.call_args.kwargs['timeout'], 1)

    def test_timed_out_iw_does_not_block_other_interfaces(self):
        ok = subprocess.CompletedProcess([], 0, '\tsignal: -110 dBm\n\tSSID: other\n', '')
        with patch.object(status.os.path, 'exists', return_value=True), \
             patch.object(status.subprocess, 'run', side_effect=[subprocess.TimeoutExpired('iw', 1), ok]):
            self.assertEqual(status.wifi_status(['wlan0', 'wlan1']), (True, 0, 'other'))


if __name__ == '__main__':
    unittest.main()
