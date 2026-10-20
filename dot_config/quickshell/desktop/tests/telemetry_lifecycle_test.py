"""Exercise real asynchronous FileViews with private fixtures and no desktop UI."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


SOURCE = Path(__file__).resolve().parents[1]


def cpu(values):
    return "cpu " + " ".join(map(str, values)) + "\ncpu0 1 2 3\n"


def network(rows):
    return (
        "Inter-| Receive | Transmit\n"
        " face | bytes packets errs drop fifo frame compressed multicast | bytes packets errs drop fifo colls carrier compressed\n"
        + "\n".join(f" {name}: {rx} 0 0 0 0 0 0 0 {tx} 0 0 0 0 0 0 0" for name, rx, tx in rows)
        + "\n"
    )


with tempfile.TemporaryDirectory(prefix="quickshell-telemetry-test-") as directory:
    root = Path(directory)
    for name in ("TelemetryService.qml", "TelemetryModel.js"):
        shutil.copy2(SOURCE / name, root / name)
    shutil.copy2(SOURCE / "tests/TelemetryTest.qml", root / "shell.qml")
    stat = root / "stat"
    memory = root / "meminfo"
    net = root / "netdev"
    first = [100, 20, 30, 500, 10, 5, 15, 0, 1000, 1000]
    second = [140, 20, 50, 540, 10, 5, 15, 0, 2000, 2000]
    stat.write_text(cpu(first))
    memory.write_text("MemTotal: 1000 kB\nMemAvailable: 250 kB\n")
    net.write_text(network([("lo", 90000000, 90000000), ("eth0", 100, 200)]))
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1",
               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(root / "cache"),
               QS_TEST_STAT=str(stat), QS_TEST_MEMORY=str(memory), QS_TEST_NETWORK=str(net))
    log_path = root / "test.log"
    with log_path.open("w+") as log:
        process = subprocess.Popen(["dbus-run-session", "--", "qs", "-p", str(root)],
                                   env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)

        def call(method, *args):
            result = subprocess.run(["qs", "-p", str(root), "ipc", "call", "audit", method, *map(str, args)],
                                    env=env, capture_output=True, text=True, timeout=5)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            return json.loads(result.stdout) if method == "status" else None

        def wait(predicate, timeout=5):
            deadline = time.monotonic() + timeout
            last = None
            while time.monotonic() < deadline:
                try:
                    last = call("status")
                except (RuntimeError, json.JSONDecodeError):
                    if process.poll() is not None:
                        raise RuntimeError("test shell exited")
                    time.sleep(0.02)
                    continue
                if predicate(last):
                    return last
                time.sleep(0.02)
            raise AssertionError(f"timed out, last status: {last}")

        def sample_net(rows):
            net.write_text(network(rows))
            call("sampleNetwork")
            return wait(lambda s: not s["netBusy"])

        try:
            initial = wait(lambda s: s["phase"] == "idle")
            assert initial["window"] == 2000
            started = time.monotonic()
            call("request")
            wait(lambda s: s["phase"] == "window")
            # Repeated manual refreshes must not restart the two-second window.
            call("request")
            assert call("status")["cpu"] == 0
            stat.write_text(cpu(second))
            state = wait(lambda s: s["phase"] == "idle" and s["cpu"] == 60)
            assert time.monotonic() - started >= 1.9
            assert state["memory"] == 75
            assert 0 <= state["liveCpu"] <= 100 and state["liveMemory"] > 0 and state["liveBytes"] >= 0

            # Hiding the last system consumer cancels a pending CPU window.
            call("system", "true")
            wait(lambda s: s["phase"] == "window")
            call("system", "false")
            stat.write_text(cpu([300, 20, 100, 540, 10, 5, 15, 0]))
            time.sleep(2.1)
            state = call("status")
            assert (state["phase"], state["cpu"], state["memory"]) == ("idle", 60, 75)

            # Explicit popup requests still work while periodic polling is disabled.
            stat.write_text(cpu(first))
            memory.write_text("corrupt\n")
            call("request")
            wait(lambda s: s["phase"] == "window")
            stat.write_text(cpu(second))
            wait(lambda s: s["phase"] == "idle")
            state = call("status")
            assert (state["cpu"], state["memory"]) == (60, 75), "failed memory reads must retain the complete sample"
            memory.write_text("MemTotal: 1000 kB\nMemAvailable: 500 kB\n")
            stat.write_text(cpu(first))
            call("request")
            wait(lambda s: s["phase"] == "window")
            stat.write_text(cpu(second))
            wait(lambda s: s["phase"] == "idle" and s["memory"] == 50)

            # Rapid hide/show must start a fresh measurement window.
            call("system", "true")
            wait(lambda s: s["phase"] == "window")
            call("system", "false")
            stat.write_text(cpu(first))
            call("system", "true")
            wait(lambda s: s["phase"] == "window")
            stat.write_text(cpu(second))
            wait(lambda s: s["phase"] == "idle" and s["cpu"] == 60)
            call("system", "false")

            stat.unlink()
            call("request")
            state = wait(lambda s: s["phase"] == "idle" and not s["statBusy"])
            assert (state["cpu"], state["memory"]) == (60, 50)

            call("network", "true")
            state = wait(lambda s: s["bytes"] == 300 and s["armed"])
            assert state["bursts"] == 0
            exact = 100 + 1572864
            assert sample_net([("eth0", exact, 200)])["bursts"] == 0
            state = sample_net([("eth0", exact + 2000000, 200)])
            assert state["bursts"] == 1 and not state["armed"]
            assert sample_net([("eth0", exact + 4000000, 200)])["bursts"] == 1
            wait(lambda s: s["armed"])
            # Resetting one counter must reseed even if another grew greatly.
            assert sample_net([("eth0", 1, 9000000)])["bursts"] == 1
            assert sample_net([("eth0", 2000001, 9000000)])["bursts"] == 2
            wait(lambda s: s["armed"])
            assert sample_net([("eth0", 2000001, 9000000), ("tun0", 90000000, 90000000)])["bursts"] == 2

            net.unlink()
            call("sampleNetwork")
            wait(lambda s: not s["netBusy"])
            assert sample_net([("eth0", 900000000, 900000000)])["bursts"] == 2

            call("network", "false")
            assert call("status")["bytes"] == -1
            net.write_text(network([("eth0", 999000000, 999000000)]))
            call("network", "true")
            state = wait(lambda s: s["armed"] and s["bytes"] == 1998000000)
            assert state["bursts"] == 2, "hidden activity must not produce a resume burst"

            call("quit")
            assert process.wait(timeout=5) == 0
            log.flush()
            output = log_path.read_text()
            assert "WARN scene:" not in output and "ReferenceError" not in output and "TypeError" not in output, output
            print("telemetry FileView, sampling window, cancellation, failure, cooldown, and resume tests passed")
        except BaseException:
            log.flush()
            print(log_path.read_text())
            raise
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
