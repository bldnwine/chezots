"""Device and port strings remain literal; EQ switching retains its ordering."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("audio_device_helper", Path(__file__).resolve().parents[1] / "scripts/audio-device-helper.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class Switching(unittest.TestCase):
    def execute(self, request, streams='[]', fail_at=None):
        calls = []
        def run(args):
            calls.append(args)
            if len(calls) == fail_at:
                raise RuntimeError("fixture failure")
            return streams if args[1:3] == ["-f", "json"] else ""
        helper.switch(request, run)
        return calls

    def test_literal_source_and_port(self):
        name, port = 'source"; $(touch /tmp/forbidden) `id`', 'port"$HOME;'
        self.assertEqual(self.execute(dict(kind="source", name=name, port=port)), [
            ["pactl", "set-default-source", name], ["pactl", "set-source-port", name, port]])

    def test_physical_sink_and_eq_order(self):
        calls = self.execute(dict(kind="sink", name="physical", port="headphones"),
                             '[{"index": 7, "properties": {"node.name": "effect_output.eq"}}]')
        self.assertEqual(calls, [["pactl", "set-default-sink", "physical"],
            ["pactl", "set-sink-port", "physical", "headphones"],
            ["pactl", "-f", "json", "list", "sink-inputs"],
            ["pactl", "move-sink-input", "7", "physical"]])

    def test_eq_virtual_sink_needs_no_rerouting(self):
        self.assertEqual(self.execute(dict(kind="sink", name="effect_input.eq", port="ignored")),
                         [["pactl", "set-default-sink", "effect_input.eq"]])

    def test_no_eq_and_no_port(self):
        self.assertEqual(len(self.execute(dict(kind="sink", name="physical"))), 2)

    def test_failure_stops_sequence(self):
        with self.assertRaisesRegex(RuntimeError, "fixture failure"):
            self.execute(dict(kind="sink", name="physical", port="headphones"), fail_at=1)

    def test_invalid_requests(self):
        for request in (dict(kind="other", name="x"), dict(kind="sink", name=""),
                        dict(kind="source", name="x", port=None)):
            with self.assertRaises(ValueError):
                self.execute(request)

    def test_invalid_eq_index(self):
        with self.assertRaises(ValueError):
            self.execute(dict(kind="sink", name="x"), '[{"index":"7;id","properties":{"node.name":"effect_output.eq"}}]')


if __name__ == "__main__":
    unittest.main()
