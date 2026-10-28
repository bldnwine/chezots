#!/usr/bin/env python3
"""Atomically persist the display settings passed as literal JSON."""
import json
import os
from pathlib import Path
import sys
import tempfile


def write(path, raw):
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("Invalid display state")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        write(sys.argv[1], sys.argv[2])
    except (IndexError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
