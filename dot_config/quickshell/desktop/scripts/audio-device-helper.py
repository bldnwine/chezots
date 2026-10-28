#!/usr/bin/env python3
"""Switch Pulse devices without interpreting device-provided text as shell code."""
import json
import subprocess
import sys


def run(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Audio device command failed")
    return result.stdout


def switch(request, execute=run):
    kind = request.get("kind")
    name = request.get("name")
    port = request.get("port", "")
    if kind not in ("sink", "source") or not isinstance(name, str) or not name or "\x00" in name:
        raise ValueError("Invalid audio device")
    if not isinstance(port, str) or "\x00" in port:
        raise ValueError("Invalid audio port")
    execute(["pactl", "set-default-" + kind, name])
    if kind == "sink" and name == "effect_input.eq":
        return
    if port:
        execute(["pactl", "set-" + kind + "-port", name, port])
    if kind == "sink":
        streams = json.loads(execute(["pactl", "-f", "json", "list", "sink-inputs"]))
        if not isinstance(streams, list):
            raise ValueError("Invalid audio stream response")
        for stream in streams:
            if stream.get("properties", {}).get("node.name") == "effect_output.eq":
                index = stream.get("index")
                if not isinstance(index, int) or isinstance(index, bool) or index < 0:
                    raise ValueError("Invalid equalizer stream")
                execute(["pactl", "move-sink-input", str(index), name])
                break


if __name__ == "__main__":
    try:
        switch(json.loads(sys.argv[1]))
    except (ValueError, TypeError, KeyError, IndexError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
