#!/usr/bin/env python3
"""Read and set only a uniquely identified internal DRM backlight."""
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys


def device_for(output, sysfs):
    if not re.fullmatch(r'(?:eDP|LVDS|DSI)-[A-Za-z0-9-]+', output):
        raise ValueError('Brightness unavailable for this output')
    root = Path(sysfs)
    backlights = list((root / 'class/backlight').glob('*'))
    drm = list((root / 'class/drm').glob('card[0-9]*-' + output))
    if len(drm) != 1:
        raise ValueError('Internal display connector is unavailable or ambiguous')
    connector = drm[0].resolve(strict=True)
    matched = [p for p in backlights if connector in p.resolve(strict=True).parents]
    if len(matched) != 1:
        raise ValueError('No uniquely associated backlight for this display')
    return matched[0]


def read(device):
    maximum = int((device / 'max_brightness').read_text())
    current = int((device / 'brightness').read_text())
    if maximum <= 0 or not 0 <= current <= maximum:
        raise ValueError('Invalid backlight reading')
    return current * 100 / maximum


def execute(action, output, value, sysfs, brightnessctl):
    device = device_for(output, sysfs)
    current = read(device)
    previous = current
    if action != 'refresh':
        number = float(value)
        if not math.isfinite(number):
            raise ValueError('Invalid brightness value')
        target = max(1, min(100, round(number + current if action == 'step' else number)))
        process = subprocess.Popen([brightnessctl, '-q', '-d', device.name, 'set', str(target) + '%'],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=True)
        try:
            _, error = process.communicate(timeout=4)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
        if process.returncode:
            raise RuntimeError(error.strip() or 'Could not change brightness')
        current = read(device)
    result = {'ok': True, 'output': output, 'percentage': current}
    if action == 'dim':
        result['previousPercentage'] = previous
    return result


def main():
    # Service timeouts send SIGTERM, allowing the helper to reap its child.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        action, output, value = sys.argv[1:4]
        if action not in ('refresh', 'set', 'step', 'dim'):
            raise ValueError('Unknown brightness action')
        result = execute(action, output, value,
                         os.environ.get('QS_BRIGHTNESS_SYSFS', '/sys'),
                         os.environ.get('QS_BRIGHTNESSCTL', 'brightnessctl'))
        print(json.dumps(result))
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'ok': False, 'error': str(error) or 'Brightness command timed out'}))
        sys.exit(1)


if __name__ == '__main__':
    main()
