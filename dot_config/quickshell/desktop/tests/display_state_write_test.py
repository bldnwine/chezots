"""Atomic state writes preserve old data on invalid input and treat text literally."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('writer', Path(__file__).resolve().parents[1] / 'scripts/display-state-write.py')
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)

class StateWrite(unittest.TestCase):
    def test_literal_paths_and_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'state "$HOME"' / 'display.json'
            data = {'brightnessByOutput': {'eDP-1': 42}, 'literal': '`id` $(touch nope) "quoted"\nnew line'}
            writer.write(path, json.dumps(data))
            self.assertEqual(json.loads(path.read_text()), data)
            before = path.read_bytes()
            for invalid in ('{broken', '[]'):
                with self.assertRaises(ValueError):
                    writer.write(path, invalid)
                self.assertEqual(path.read_bytes(), before)
            writer.write(path, json.dumps({'brightnessByOutput': {'eDP-1': 55}}))
            self.assertEqual(json.loads(path.read_text())['brightnessByOutput']['eDP-1'], 55)
            self.assertEqual(list(path.parent.iterdir()), [path])

if __name__ == '__main__':
    unittest.main()
