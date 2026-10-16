#!/usr/bin/env python3
"""Fingerprint Locus theme discovery inputs without reading their contents."""

import hashlib
import json
import os
from pathlib import Path


def fingerprint(home, omarchy_path):
    records = []

    def record(path):
        try:
            stat = path.stat()
            stamp = (stat.st_dev, stat.st_ino, stat.st_mtime_ns,
                     stat.st_ctime_ns, stat.st_size)
        except FileNotFoundError:
            stamp = None
        records.append((str(path), stamp))

    def children(path):
        try:
            return sorted(p for p in path.iterdir() if not p.name.startswith("."))
        except FileNotFoundError:
            return []

    roots = [home / ".config/aether/themes",
             Path(omarchy_path or "/") / "themes",
             home / ".local/share/omarchy/themes",
             home / ".config/omarchy/themes"]
    for root in roots:
        record(root)
        for theme in children(root):
            if not theme.is_dir():
                continue
            for path in (theme, theme / "colors.toml", theme / "preview.png",
                         theme / "preview.jpg", theme / "backgrounds"):
                record(path)
            # Discovery selects the first supported background when there
            # is no preview. Include its metadata to catch in-place edits.
            background = next((p for p in children(theme / "backgrounds")
                               if p.suffix in (".png", ".jpg", ".jpeg", ".webp", ".avif")), None)
            if background is not None:
                record(background)

    blueprints = home / ".config/aether/blueprints"
    record(blueprints)
    for path in children(blueprints):
        if path.suffix == ".json":
            record(path)
    for path in (home / ".config/aether/theme/colors.toml",
                 home / ".config/omarchy/current/theme/colors.toml"):
        record(path)

    payload = json.dumps(records, ensure_ascii=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


if __name__ == "__main__":
    print(fingerprint(Path.home(), os.environ.get("OMARCHY_PATH", "")))
