"""Regression checks for memory safety and bounded scanner I/O."""
import ctypes
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load_script(filename):
    spec = importlib.util.spec_from_file_location(filename.replace(".", "_"), SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


wallpapers = load_script("wallpaper-scan.py")
ai = load_script("antigravity_usage_scanner.py")


class PerformanceHelpersTest(unittest.TestCase):
    def test_statx_writes_stay_inside_allocation(self):
        self.assertEqual(ctypes.sizeof(wallpapers.struct_statx), 256)
        if wallpapers.libc is None or not hasattr(wallpapers.libc, "statx"):
            self.skipTest("statx unavailable")

        class Guarded(ctypes.Structure):
            _fields_ = [("value", wallpapers.struct_statx), ("guard", ctypes.c_ubyte * 128)]

        buffer = Guarded()
        buffer.guard[:] = [0xAB] * 128
        with tempfile.NamedTemporaryFile() as file:
            file.write(b"wallpaper test")
            file.flush()
            code = wallpapers.libc.statx(-100, file.name.encode(), 0, wallpapers.FLAGS, ctypes.byref(buffer.value))
            self.assertEqual(code, 0)
            self.assertEqual(buffer.value.stx_size, 14)
        self.assertEqual(bytes(buffer.guard), bytes([0xAB]) * 128)

    def test_scan_deduplicates_symlinks_and_handles_stat_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "image.png").write_bytes(b"image")
            (root / "alias.jpg").symlink_to(root / "image.png")
            (root / "ignored.txt").write_text("ignored")
            for libc in (wallpapers.libc, None):
                with patch.object(wallpapers, "DIRS", [directory]), patch.object(wallpapers, "libc", libc):
                    result = wallpapers.scan()
                self.assertEqual(len(result), 1)
                self.assertEqual(result[0]["size"], 5)

    def test_history_tail_reads_only_last_lines(self):
        lines = [json.dumps({"conversationId": str(i), "workspace": "/work/日本語", "display": "title"}, ensure_ascii=False) for i in range(50000)]
        stream = io.BytesIO(("\n".join(lines) + "\n").encode())
        sizes = []
        read = stream.read
        stream.read = lambda size: (sizes.append(size), read(size))[1]
        with patch("builtins.open", return_value=stream):
            self.assertEqual(ai.read_history_tail(Path("unused")), lines[-40:])
        self.assertLess(sum(sizes), 256 * 1024)
        self.assertNotIn(-1, sizes)

    def test_oversized_corrupt_history_is_bounded(self):
        stream = io.BytesIO(b"x" * 1024 * 1024)
        with patch("builtins.open", return_value=stream):
            self.assertEqual(ai.read_history_tail(Path("unused")), [])

    def test_missing_and_unterminated_history(self):
        with patch("builtins.open", side_effect=FileNotFoundError):
            self.assertEqual(ai.read_history_tail(Path("unused")), [])
        with patch("builtins.open", return_value=io.BytesIO(b"one\ntwo")):
            self.assertEqual(ai.read_history_tail(Path("unused")), ["one", "two"])

    def test_multiple_sessions_share_history_read_and_skip_quota(self):
        lines = ["bad json", json.dumps({"conversationId": "a", "workspace": "/work/a", "display": "A"}),
                 json.dumps({"conversationId": "b", "workspace": "/work/b", "display": "B"})]
        with patch.object(ai, "get_live_agy_processes", return_value={1: "a", 2: "b"}), \
             patch.object(ai, "read_history_tail", return_value=lines) as history, \
             patch.object(ai, "get_live_quota") as quota:
            result = ai.scan(Path("/nonexistent"), include_quota=False)
        history.assert_called_once()
        quota.assert_not_called()
        self.assertNotIn("quotaGroups", result)
        self.assertEqual([s["workspaceName"] for s in result["activeSessions"]], ["a", "b"])


if __name__ == "__main__":
    unittest.main()
