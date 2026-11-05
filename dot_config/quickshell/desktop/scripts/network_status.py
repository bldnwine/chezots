#!/usr/bin/env python3
"""Publish link changes and bounded Wi-Fi signal samples as JSON lines."""
import argparse
import fcntl
import json
import os
import re
import select
import socket
import struct
import subprocess
import time

SYS_NET = '/sys/class/net'


def interfaces():
    try:
        return sorted(os.listdir(SYS_NET))
    except OSError:
        return []


def has_ipv4(name):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            fcntl.ioctl(sock.fileno(), 0x8915, struct.pack('256s', os.fsencode(name)[:15]))
        return True
    except OSError:
        return False


def wifi_status(names):
    deadline = time.monotonic() + 2.0
    for name in names:
        if not (os.path.exists(os.path.join(SYS_NET, name, 'wireless')) or
                os.path.exists(os.path.join(SYS_NET, name, 'phy80211'))):
            continue
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            result = subprocess.run(['iw', 'dev', name, 'link'], capture_output=True,
                                    text=True, errors='replace', timeout=min(1.0, remaining), check=False)
        except (OSError, subprocess.TimeoutExpired):
            continue
        signal = re.search(r'^\s*signal:\s*(-?\d+)', result.stdout, re.MULTILINE)
        if signal:
            ssid = re.search(r'^\s*SSID: (.*)$', result.stdout, re.MULTILINE)
            return True, max(0, min(100, 2 * (int(signal.group(1)) + 100))), ssid.group(1) if ssid else ''
    return False, 0, ''


def snapshot(wifi=True):
    names = interfaces()
    active, signal, ssid = wifi_status(names) if wifi else (False, 0, '')
    return {'eth': any((n.startswith('en') or n.startswith('eth')) and has_ipv4(n) for n in names),
            'vpn': next((n for n in names if n.startswith('proton')), ''),
            'wifi': active, 'signal': signal, 'ssid': ssid}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--links-only', action='store_true')
    args = parser.parse_args()
    # Link and IPv4-address multicast notifications. Restricted environments
    # can deny netlink; fall back to sampling within this same resident process.
    monitor = None
    try:
        monitor = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
        monitor.bind((0, 1 | 0x10))
    except OSError:
        if monitor is not None:
            monitor.close()
        monitor = None
    previous = None
    while True:
        started = time.monotonic()
        state = snapshot(not args.links_only)
        if state != previous:
            print(json.dumps(state, ensure_ascii=True), flush=True)
            previous = state
        period = 5.0 if args.links_only else 3.0
        timeout = max(0, period - (time.monotonic() - started))
        if monitor is None:
            time.sleep(timeout)
            continue
        ready, _, _ = select.select([monitor], [], [], None if args.links_only else timeout)
        if ready:
            monitor.recv(65536)
            # Coalesce notifications emitted together by the kernel.
            while select.select([monitor], [], [], 0)[0]:
                monitor.recv(65536)


if __name__ == '__main__':
    main()
