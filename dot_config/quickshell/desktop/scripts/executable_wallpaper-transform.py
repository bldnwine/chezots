#!/usr/bin/env python3
"""
Non-destructive wallpaper transformation helper for Quickshell.
Crops, rotates, and flips images using Pillow without modifying original files.
"""

import os
import sys
import argparse
import glob
from PIL import Image, ImageOps

def parse_args():
    parser = argparse.ArgumentParser(description="Transform wallpaper non-destructively.")
    parser.add_argument("--input", required=True, help="Path to source wallpaper image")
    parser.add_argument("--output", required=True, help="Destination path for transformed image")
    parser.add_argument("--rotate", type=int, default=0, choices=[0, 90, 180, 270],
                        help="Clockwise rotation in degrees (0, 90, 180, 270)")
    parser.add_argument("--flip-h", action="store_true", help="Flip horizontally")
    parser.add_argument("--flip-v", action="store_true", help="Flip vertically")
    parser.add_argument("--crop", default="0,0,1,1",
                        help="Normalized crop rectangle: norm_x,norm_y,norm_w,norm_h (all 0.0-1.0)")
    parser.add_argument("--max-cached", type=int, default=25,
                        help="Maximum custom wallpaper files to retain in destination directory")
    return parser.parse_args()

def prune_cache(out_dir, max_files):
    try:
        files = glob.glob(os.path.join(out_dir, "custom_*.*"))
        if len(files) > max_files:
            files.sort(key=lambda p: os.path.getmtime(p))
            to_remove = files[:len(files) - max_files]
            for f in to_remove:
                try:
                    os.remove(f)
                except OSError:
                    pass
    except Exception:
        pass

def main():
    args = parse_args()
    input_path = os.path.abspath(os.path.expanduser(args.input))
    output_path = os.path.abspath(os.path.expanduser(args.output))

    if not os.path.isfile(input_path):
        sys.stderr.write(f"Error: input file does not exist: {input_path}\n")
        sys.exit(1)

    try:
        crop_parts = [float(x.strip()) for x in args.crop.split(",")]
        if len(crop_parts) != 4:
            raise ValueError("Expected 4 comma-separated values")
        norm_x, norm_y, norm_w, norm_h = crop_parts
    except Exception as e:
        sys.stderr.write(f"Error parsing --crop values: {e}\n")
        sys.exit(1)

    # 1. Open original image in read-only mode
    try:
        with Image.open(input_path) as src:
            # 2. Normalize EXIF orientation if present
            img = ImageOps.exif_transpose(src)
            if img is None:
                img = src.copy()
            else:
                img = img.copy()
    except Exception as e:
        sys.stderr.write(f"Error opening image {input_path}: {e}\n")
        sys.exit(1)

    # 3. Apply rotation (user visual orientation matches rotated frame)
    # Pillow's ROTATE_270 rotates 90 degrees clockwise.
    if args.rotate == 90:
        img = img.transpose(Image.Transpose.ROTATE_270)
    elif args.rotate == 180:
        img = img.transpose(Image.Transpose.ROTATE_180)
    elif args.rotate == 270:
        img = img.transpose(Image.Transpose.ROTATE_90)

    # 4. Apply flips
    if args.flip_h:
        img = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if args.flip_v:
        img = img.transpose(Image.Transpose.FLIP_TOP_BOTTOM)

    cur_w, cur_h = img.size

    # 5. Normalize and clamp crop coordinates
    norm_x = max(0.0, min(1.0, norm_x))
    norm_y = max(0.0, min(1.0, norm_y))
    norm_w = max(0.001, min(1.0 - norm_x, norm_w))
    norm_h = max(0.001, min(1.0 - norm_y, norm_h))

    x0 = int(round(norm_x * cur_w))
    y0 = int(round(norm_y * cur_h))
    x1 = int(round((norm_x + norm_w) * cur_w))
    y1 = int(round((norm_y + norm_h) * cur_h))

    # Strict bounds clamp
    x0 = max(0, min(cur_w - 1, x0))
    y0 = max(0, min(cur_h - 1, y0))
    x1 = max(x0 + 1, min(cur_w, x1))
    y1 = max(y0 + 1, min(cur_h, y1))

    # 6. Perform crop
    cropped = img.crop((x0, y0, x1, y1))

    # 7. Ensure output directory exists
    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    # 8. Save output with high quality
    ext = os.path.splitext(output_path)[1].lower()
    save_kwargs = {}
    if ext in [".jpg", ".jpeg"]:
        if cropped.mode in ("RGBA", "P"):
            cropped = cropped.convert("RGB")
        save_kwargs["quality"] = 96
        save_kwargs["subsampling"] = 0
    elif ext == ".png":
        save_kwargs["compress_level"] = 1  # Fast PNG compression for responsiveness
    elif ext == ".webp":
        save_kwargs["quality"] = 96

    try:
        cropped.save(output_path, **save_kwargs)
    except Exception as e:
        sys.stderr.write(f"Error saving image to {output_path}: {e}\n")
        sys.exit(1)

    # 9. Clean up cache if exceeded
    if out_dir and args.max_cached > 0:
        prune_cache(out_dir, args.max_cached)

    print(output_path)
    sys.exit(0)

if __name__ == "__main__":
    main()
