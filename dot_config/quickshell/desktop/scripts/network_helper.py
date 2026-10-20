#!/usr/bin/env python3
"""Single-request, bounded iwd helper. No shell is involved."""
import ctypes
import json
import os
import re
import select
import signal
import subprocess
import sys
import time

IWCTL = os.environ.get("NETWORK_HELPER_IWCTL", "iwctl")
IP = os.environ.get("NETWORK_HELPER_IP", "ip")
PING = os.environ.get("NETWORK_HELPER_PING", "ping")
PROC_NET_DEV = os.environ.get("NETWORK_HELPER_PROC_NET_DEV", "/proc/net/dev")
SCALE = max(.001, float(os.environ.get("NETWORK_HELPER_DEADLINE_SCALE", "1")))
_cancelled = False
_deadline = None

# Adopt orphaned subprocess descendants so that killed grandchildren can be
# waited for rather than left as zombies under an unrelated init process.
try:
    ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)  # PR_SET_CHILD_SUBREAPER
except (AttributeError, OSError):
    pass


class Failure(Exception):
    def __init__(self, kind, message, detail=""):
        self.kind = kind
        self.detail = detail
        super().__init__(message)


def _kill_group(pid):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except ProcessLookupError:
            break
        except OSError:
            pass
        if sig == signal.SIGTERM:
            time.sleep(.08)


def _proc_children():
    """Return the process table's parent links (Linux is required by iwd)."""
    children = {}
    try:
        entries = os.listdir("/proc")
    except OSError:
        return children
    for entry in entries:
        if not entry.isdigit():
            continue
        try:
            with open("/proc/" + entry + "/stat", encoding="ascii") as stream:
                stat = stream.read()
            fields = stat[stat.rfind(")") + 2:].split()
            children.setdefault(int(fields[1]), set()).add(int(entry))
        except (OSError, ValueError, IndexError):
            continue
    return children


def _owned_tree(root, remembered):
    links = _proc_children()
    # As a subreaper, direct children also include command descendants which
    # already escaped their original parent and were reparented here.
    todo = [root, *links.get(os.getpid(), ())]
    todo = [pid for pid in todo if pid != os.getpid()]
    found = set(remembered) | set(todo)
    while todo:
        parent = todo.pop()
        for child in links.get(parent, ()):
            if child not in found:
                found.add(child)
                todo.append(child)
    return found


def _cleanup(proc):
    # Ordinary iwctl/ip/ping exits need no process-table scan or sleep.
    # Subreaper children include descendants whose original parent exited.
    try:
        with open(f"/proc/self/task/{os.getpid()}/children", encoding="ascii") as stream:
            adopted = {int(pid) for pid in stream.read().split()}
    except OSError:
        adopted = set()
    if proc.poll() is None or adopted - {proc.pid}:
        owned = _owned_tree(proc.pid, adopted)
        for pid in owned:
            try:
                os.kill(pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
        # A bounded grace period, then kill and reap even escaped descendants.
        end = time.monotonic() + .35
        while True:
            for pid in tuple(owned):
                try:
                    child, _ = os.waitpid(pid, os.WNOHANG)
                    if child:
                        owned.discard(pid)
                except ChildProcessError:
                    if not os.path.exists(f"/proc/{pid}"):
                        owned.discard(pid)
            proc.poll()
            if not owned or time.monotonic() >= end:
                break
            time.sleep(.01)
        owned = _owned_tree(proc.pid, owned)
        for pid in owned:
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        try:
            proc.wait(timeout=.1)
        except subprocess.TimeoutExpired:
            _kill_group(proc.pid)
            proc.wait(timeout=.1)
        # Descendants may take a scheduler tick to die and be adopted.
        end = time.monotonic() + .15
        while time.monotonic() < end:
            try:
                child, _ = os.waitpid(-1, os.WNOHANG)
                if child == 0:
                    time.sleep(.005)
                else:
                    continue
            except ChildProcessError:
                break
    for stream in (proc.stdout, proc.stderr):
        if stream and not stream.closed:
            stream.close()


def _signal(signum, frame):
    global _cancelled
    _cancelled = True


signal.signal(signal.SIGTERM, _signal)
signal.signal(signal.SIGINT, _signal)


def _remaining():
    if _cancelled:
        raise Failure("cancelled", "Operation cancelled")
    if _deadline is not None:
        left = _deadline - time.monotonic()
        if left <= 0:
            raise Failure("timeout", "Network operation timed out")
        return left
    return 3600


def run(argv, timeout=3, command="Network command"):
    timeout = min(timeout, _remaining())
    try:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, start_new_session=True,
                                env=dict(os.environ, LC_ALL="C"))
    except FileNotFoundError:
        raise Failure("unavailable", command + " is unavailable")
    except OSError:
        raise Failure("unavailable", command + " could not be started")
    try:
        end = time.monotonic() + timeout
        while True:
            _remaining()
            try:
                out, err = proc.communicate(timeout=min(.1, max(.001, end - time.monotonic())))
                break
            except subprocess.TimeoutExpired:
                if time.monotonic() >= end:
                    raise Failure("timeout", command + " timed out")
        if _cancelled:
            raise Failure("cancelled", "Operation cancelled")
        if proc.returncode:
            blob = out + "\n" + err
            if re.search(r"authentication (?:failed|rejected)|invalid passphrase", blob, re.I):
                raise Failure("auth", "Authentication was rejected")
            raise Failure("command", command + " failed", blob + "\nexit status " + str(proc.returncode))
        return out
    finally:
        _cleanup(proc)


def iw(args, timeout=3, passphrase=None, action="Wi-Fi command"):
    argv = [IWCTL, "--dont-ask"]
    if passphrase:
        argv += ["--passphrase", passphrase]
    argv += ["--"] + args
    return run(argv, timeout, action)


def _clean(s):
    return re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", s)


def _device_rows(text):
    lines = [_clean(x).strip() for x in text.splitlines() if _clean(x).strip()]
    header_i = next((i for i, s in enumerate(lines) if re.search(r"\bName\b", s) and re.search(r"\bPowered\b", s)), -1)
    devices = []
    if header_i < 0 and lines:
        raise Failure("command", "Could not parse Wi-Fi devices")
    if header_i >= 0:
        headers = re.split(r"\s{2,}", lines[header_i])
        for line in lines[header_i + 1:]:
            cols = re.split(r"\s{2,}", line)
            if len(cols) >= len(headers):
                row = dict(zip(headers, cols))
                if row.get("Name") and row.get("Mode", "station").lower() == "station":
                    devices.append(row)
    return devices


def _devices():
    return _device_rows(iw(["device", "list"], action="Reading Wi-Fi devices"))


def _radio(devices):
    # device list already includes Powered; avoid another CLI per snapshot.
    states = [row.get("Powered", "").lower() for row in devices]
    if any(state not in ("on", "off") for state in states):
        raise Failure("command", "Could not read Wi-Fi radio state")
    return any(state == "on" for state in states)


def _known():
    text = _clean(iw(["known-networks", "list"], action="Reading saved Wi-Fi networks"))
    lines = [line.rstrip() for line in text.splitlines()]
    header = next((i for i, s in enumerate(lines) if re.search(r"\bName\b", s) and re.search(r"\bSecurity\b", s)), -1)
    result = set()
    if header < 0:
        if any(x.strip() for x in lines):
            raise Failure("command", "Could not parse saved Wi-Fi networks")
        return result
    security_col = lines[header].find("Security")
    for line in lines[header + 1:]:
        if not line.strip() or re.fullmatch(r"[\s+|\-=]+", line):
            continue
        name = line[:security_col].strip()
        if name:
            result.add(name)
    return result


def _parse_networks(text, known):
    lines = [_clean(s).rstrip() for s in text.splitlines()]
    header = next((i for i, s in enumerate(lines) if "Network name" in s and "Security" in s and "Signal" in s), -1)
    if header < 0:
        raise Failure("command", "Could not parse scanned Wi-Fi networks")
    security_col = lines[header].find("Security")
    signal_col = lines[header].find("Signal")
    if security_col < 0 or signal_col <= security_col:
        raise Failure("command", "Could not parse scanned Wi-Fi networks")
    rows = []
    for line in lines[header + 1:]:
        if not line.strip() or re.fullmatch(r"[\s+|\-=]+", line):
            continue
        prefix = line[:security_col]
        active = bool(re.match(r"^\s*>\s", prefix))
        ssid = prefix.strip()
        if active:
            ssid = ssid[1:].strip()
        m = re.match(r"^\s*(open|psk|8021x|802\.1x|wep|unknown)\s*$", line[security_col:signal_col], re.I)
        if not m:
            continue
        match = re.search(r"(-?\d+(?:\.\d+)?)(?:\s*dBm)?\s*$", line[signal_col:], re.I)
        if not match or not ssid:
            continue
        dbm = float(match.group(1))
        if abs(dbm) > 200:
            dbm /= 100.0
        signal = max(0, min(100, round((dbm + 100) * 2)))
        rows.append({"ssid": ssid, "signal": signal, "security": m.group(1),
                     "inUse": active, "known": ssid in known})
    rows.sort(key=lambda n: (not n["inUse"], -n["signal"]))
    return rows


def _state(devices=None):
    if devices is None:
        devices = _devices()
    radio_on = _radio(devices)
    if not radio_on:
        return {"radioOn": False, "networks": []}, devices
    known = _known()
    result = []
    for row in devices:
        result.extend(_parse_networks(iw(["station", row["Name"], "get-networks", "rssi-dbms"], action="Reading Wi-Fi networks"), known))
    result.sort(key=lambda n: (not n["inUse"], -n["signal"]))
    return {"radioOn": True, "networks": result}, devices


def _route():
    try:
        text = run([IP, "-j", "-4", "route", "get", "1.1.1.1"], 2, "Reading IPv4 route")
    except Failure as exc:
        if exc.kind == "command" and re.search(r"network is unreachable|no route to host|network is down", exc.detail, re.I):
            return None
        raise
    try:
        routes = json.loads(text)
    except ValueError:
        raise Failure("command", "IPv4 route returned malformed data")
    if not isinstance(routes, list):
        raise Failure("command", "IPv4 route returned malformed data")
    if not routes:
        return None
    route = routes[0]
    if not isinstance(route, dict) or not isinstance(route.get("dev"), str) or not route.get("dev"):
        raise Failure("command", "IPv4 route is missing its interface")
    src = route.get("prefsrc", route.get("src", ""))
    gw = route.get("gateway", "")
    if not isinstance(src, str) or not isinstance(gw, str):
        raise Failure("command", "IPv4 route returned malformed fields")
    return route["dev"], src, gw


def _counter(iface):
    try:
        with open(PROC_NET_DEV, encoding="ascii") as f:
            for line in f:
                if ":" in line:
                    name, value = line.split(":", 1)
                    if name.strip() == iface:
                        fields = value.split()
                        return int(fields[0]), int(fields[8])
    except (OSError, ValueError, IndexError):
        raise Failure("unavailable", "Could not read interface byte counters")
    raise Failure("unavailable", "No byte counters for routed interface")


def _details():
    route = _route()
    if route is None:
        sample = time.monotonic()
        return {"info": {"iface": "", "ip": "", "gateway": "", "rx_bytes": 0, "tx_bytes": 0,
                         "sample_time": sample, "internet_ping_ms": None}}
    iface, addr, gateway = route
    rx, tx = _counter(iface)
    sample = time.monotonic()
    latency = None
    try:
        out = run([PING, "-n", "-c", "1", "-W", "1", "-w", "1", "-I", iface, "1.1.1.1"], 1.5, "Checking internet connectivity")
        match = re.search(r"time[=<]([\d.]+)\s*ms", out)
        if match:
            latency = float(match.group(1))
    except Failure as exc:
        if exc.kind == "timeout":
            return {"info": {"iface": iface, "ip": addr, "gateway": gateway,
                             "rx_bytes": rx, "tx_bytes": tx, "sample_time": sample,
                             "internet_ping_ms": None}}
        if (exc.kind != "command" or not re.search(r"exit status 1\s*$", exc.detail)
                or not re.search(r"100% packet loss|0 received|Destination Host Unreachable|Network is unreachable", exc.detail, re.I)):
            raise
    return {"info": {"iface": iface, "ip": addr, "gateway": gateway, "rx_bytes": rx, "tx_bytes": tx,
                     "sample_time": sample, "internet_ping_ms": latency}}


def _wait_scan(dev):
    while True:
        _remaining()
        out = iw(["station", dev, "show"], action="Waiting for Wi-Fi scan")
        state = re.search(r"(?im)^\s*Scanning\s+(yes|no|on|off)\s*$", _clean(out))
        if not state:
            raise Failure("command", "Could not read Wi-Fi scan state")
        scanning = state.group(1).lower() in ("yes", "on")
        if not scanning:
            return
        time.sleep(min(.3, _remaining()))


def handle(req):
    global _deadline
    op = req.get("op")
    budget = {"connect": 30, "scan": 15, "state": 10, "details": 4}.get(op, 10) * SCALE
    _deadline = time.monotonic() + budget
    if op == "details":
        return _details()
    if op in ("state", "scan"):
        devices = _devices()[:1]
        if not devices:
            if op == "scan":
                raise Failure("unavailable", "No Wi-Fi station device is available")
            return {"radioOn": False, "networks": []}
        radio_on = _radio(devices)
        if not radio_on:
            if op == "scan":
                return {"radioOn": False, "networks": []}
            return {"radioOn": False, "networks": []}
        if op == "scan":
            iw(["station", devices[0]["Name"], "scan"], action="Starting Wi-Fi scan")
            _wait_scan(devices[0]["Name"])
        result, _ = _state(devices)
        return result
    ssid = req.get("ssid", "")
    if op in ("connect", "forget", "autoconnect") and (not isinstance(ssid, str) or not ssid):
        raise Failure("malformed", "A network name is required")
    if op == "disconnect":
        devices = _devices()
        if not devices:
            raise Failure("unavailable", "No Wi-Fi station device is available")
        iw(["station", devices[0]["Name"], "disconnect"], 10, action="Disconnecting from Wi-Fi")
        return {}
    if op == "connect":
        devices = _devices()
        if not devices:
            raise Failure("unavailable", "No Wi-Fi station device is available")
        password = req.get("passphrase")
        if password is not None and not isinstance(password, str):
            raise Failure("malformed", "Passphrase must be text")
        iw(["station", devices[0]["Name"], "connect", ssid], 30, password, "Connecting to Wi-Fi")
        return {"ssid": ssid}
    if op == "radio":
        if not isinstance(req.get("enabled"), bool):
            raise Failure("malformed", "enabled must be boolean")
        devices = _devices()
        if not devices:
            raise Failure("unavailable", "No Wi-Fi device is available")
        iw(["device", devices[0]["Name"], "set-property", "Powered", "on" if req["enabled"] else "off"], 10, action="Changing Wi-Fi radio state")
        return {"enabled": req["enabled"]}
    if op == "forget":
        iw(["known-networks", ssid, "forget"], 10, action="Forgetting saved Wi-Fi network")
        return {"ssid": ssid}
    if op == "autoconnect":
        enabled = req.get("enabled")
        if enabled is None:
            text = iw(["known-networks", ssid, "show"], action="Reading auto-connect setting")
            match = re.search(r"(?im)^\s*\*?\s*AutoConnect\s+(yes|no)\s*$", _clean(text))
            if not match:
                raise Failure("command", "Could not read auto-connect setting")
            enabled = match.group(1).lower() != "yes"
        elif not isinstance(enabled, bool):
            raise Failure("malformed", "enabled must be boolean")
        iw(["known-networks", ssid, "set-property", "AutoConnect", "yes" if enabled else "no"], 10, action="Changing auto-connect setting")
        return {"ssid": ssid, "enabled": enabled}
    raise Failure("malformed", "Unknown network operation")


def _read_request():
    fd = sys.stdin.fileno()
    deadline = time.monotonic() + 2 * SCALE
    data = bytearray()
    while True:
        left = deadline - time.monotonic()
        if left <= 0:
            raise Failure("timeout", "Timed out reading request")
        ready, _, _ = select.select([fd], [], [], left)
        if not ready:
            raise Failure("timeout", "Timed out reading request")
        chunk = os.read(fd, min(4096, 65537 - len(data)))
        if not chunk:
            break
        data.extend(chunk)
        if len(data) > 65536:
            raise Failure("malformed", "Request exceeds size limit")
        if b"\n" in chunk:
            data = data[:data.index(b"\n")]
            break
    if not data:
        raise Failure("malformed", "Request is empty")
    try:
        req = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise Failure("malformed", "Request is not valid JSON")
    if not isinstance(req, dict):
        raise Failure("malformed", "Request must be an object")
    return req


def main():
    try:
        result = handle(_read_request())
        response = {"ok": True, "error": "", "errorKind": ""}
        response.update(result)
    except Failure as exc:
        response = {"ok": False, "error": str(exc), "errorKind": exc.kind}
    except Exception:
        response = {"ok": False, "error": "Network operation failed", "errorKind": "command"}
    sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
