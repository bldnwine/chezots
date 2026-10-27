import unittest
import os
import tempfile
import hashlib
import subprocess
from PIL import Image

class WallpaperTransformTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.script_path = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../scripts/wallpaper-transform.py")
        )

        # Create a test image with distinct quadrant colors
        # Top-left: Red, Top-right: Green, Bottom-left: Blue, Bottom-right: Yellow
        self.src_path = os.path.join(self.temp_dir.name, "source_wallpaper.png")
        img = Image.new("RGB", (200, 100))
        # Top-left (0..100, 0..50) = Red (255, 0, 0)
        # Top-right (100..200, 0..50) = Green (0, 255, 0)
        # Bottom-left (0..100, 50..100) = Blue (0, 0, 255)
        # Bottom-right (100..200, 50..100) = Yellow (255, 255, 0)
        for x in range(200):
            for y in range(100):
                if x < 100 and y < 50:
                    img.putpixel((x, y), (255, 0, 0))
                elif x >= 100 and y < 50:
                    img.putpixel((x, y), (0, 255, 0))
                elif x < 100 and y >= 50:
                    img.putpixel((x, y), (0, 0, 255))
                else:
                    img.putpixel((x, y), (255, 255, 0))
        img.save(self.src_path)

        with open(self.src_path, "rb") as f:
            self.src_hash = hashlib.sha256(f.read()).hexdigest()
        self.src_mtime = os.path.getmtime(self.src_path)

    def tearDown(self):
        self.temp_dir.cleanup()

    def assert_source_untouched(self):
        with open(self.src_path, "rb") as f:
            current_hash = hashlib.sha256(f.read()).hexdigest()
        self.assertEqual(current_hash, self.src_hash, "Source file was modified!")
        self.assertEqual(os.path.getmtime(self.src_path), self.src_mtime, "Source mtime changed!")

    def run_transform(self, args):
        cmd = ["python3", self.script_path, "--input", self.src_path] + args
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return res

    def test_full_frame_no_transform(self):
        out_path = os.path.join(self.temp_dir.name, "out1.png")
        res = self.run_transform(["--output", out_path, "--crop", "0,0,1,1"])
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(os.path.exists(out_path))

        with Image.open(out_path) as out:
            self.assertEqual(out.size, (200, 100))
            self.assertEqual(out.getpixel((10, 10)), (255, 0, 0))
            self.assertEqual(out.getpixel((150, 10)), (0, 255, 0))

        self.assert_source_untouched()

    def test_crop_quadrant(self):
        # Crop top-right (Green) quadrant: x=0.5, y=0.0, w=0.5, h=0.5
        out_path = os.path.join(self.temp_dir.name, "out_tr.png")
        res = self.run_transform(["--output", out_path, "--crop", "0.5,0.0,0.5,0.5"])
        self.assertEqual(res.returncode, 0, res.stderr)

        with Image.open(out_path) as out:
            self.assertEqual(out.size, (100, 50))
            # Every pixel should be Green
            self.assertEqual(out.getpixel((10, 10)), (0, 255, 0))
            self.assertEqual(out.getpixel((90, 40)), (0, 255, 0))

        self.assert_source_untouched()

    def test_rotation_90_cw(self):
        # 200x100 rotated 90° CW becomes 100x200
        # In original: Red (TL), Green (TR), Blue (BL), Yellow (BR)
        # Rotated 90 CW:
        # Top-left becomes Blue (0, 0, 255)
        # Top-right becomes Red (255, 0, 0)
        # Bottom-left becomes Yellow (255, 255, 0)
        # Bottom-right becomes Green (0, 255, 0)
        out_path = os.path.join(self.temp_dir.name, "out_rot90.png")
        res = self.run_transform(["--output", out_path, "--rotate", "90", "--crop", "0,0,1,1"])
        self.assertEqual(res.returncode, 0, res.stderr)

        with Image.open(out_path) as out:
            self.assertEqual(out.size, (100, 200))
            self.assertEqual(out.getpixel((20, 20)), (0, 0, 255))
            self.assertEqual(out.getpixel((80, 20)), (255, 0, 0))

        self.assert_source_untouched()

    def test_rotation_and_crop(self):
        # Rotate 90 CW and crop top-right (which is Red after rotation)
        out_path = os.path.join(self.temp_dir.name, "out_rot_crop.png")
        res = self.run_transform([
            "--output", out_path,
            "--rotate", "90",
            "--crop", "0.5,0.0,0.5,0.5"
        ])
        self.assertEqual(res.returncode, 0, res.stderr)

        with Image.open(out_path) as out:
            self.assertEqual(out.size, (50, 100))
            self.assertEqual(out.getpixel((10, 10)), (255, 0, 0))

        self.assert_source_untouched()

    def test_flip_horizontal(self):
        # Original: Red (TL), Green (TR)
        # Flipped H: Green (TL), Red (TR)
        out_path = os.path.join(self.temp_dir.name, "out_fliph.png")
        res = self.run_transform(["--output", out_path, "--flip-h", "--crop", "0,0,1,1"])
        self.assertEqual(res.returncode, 0, res.stderr)

        with Image.open(out_path) as out:
            self.assertEqual(out.getpixel((10, 10)), (0, 255, 0))
            self.assertEqual(out.getpixel((150, 10)), (255, 0, 0))

        self.assert_source_untouched()

    def test_clamping_out_of_bounds(self):
        # Negative x and excessive width should be safely clamped without crashing
        out_path = os.path.join(self.temp_dir.name, "out_clamp.png")
        res = self.run_transform(["--output", out_path, "--crop", "-0.5,-0.2,2.0,3.0"])
        self.assertEqual(res.returncode, 0, res.stderr)

        with Image.open(out_path) as out:
            self.assertEqual(out.size, (200, 100))

        self.assert_source_untouched()

    def test_auto_mkdir_output_dir(self):
        nested_out = os.path.join(self.temp_dir.name, "nested", "sub", "test.png")
        res = self.run_transform(["--output", nested_out, "--crop", "0,0,1,1"])
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(os.path.exists(nested_out))
        self.assert_source_untouched()

if __name__ == "__main__":
    unittest.main()
