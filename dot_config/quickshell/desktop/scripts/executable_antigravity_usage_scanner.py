#!/usr/bin/env python3
"""
High-performance usage scanner and status monitor for Google Antigravity CLI (agy).
Queries the live Antigravity Language Server for official real-time quota buckets
and tracks active agent sessions bound directly to running OS processes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any


def default_base_dir() -> Path:
    return Path(os.environ.get("ANTIGRAVITY_DATA_DIR") or os.path.expanduser("~/.gemini/antigravity-cli"))


def sanitize_plain_text(val: Any, max_len: int = 250) -> str:
    if val is None:
        return ""
    text = str(val)
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len]


def get_live_agy_processes() -> dict[int, str]:
    """Find all running agy process PIDs and their bound conversation IDs via open FDs."""
    live_pids: dict[int, str] = {}
    for cmd_path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            with open(cmd_path, "rb") as f:
                raw = f.read().decode("utf-8", errors="replace").replace("\x00", " ").strip()
                parts = raw.split()
                if parts and (parts[0] == "agy" or parts[0].endswith("/agy")):
                    pid = int(cmd_path.split("/")[2])
                    live_pids[pid] = ""
                    # Check open FDs for conversation UUID lock / db
                    for fd in glob.glob(f"/proc/{pid}/fd/*"):
                        try:
                            target = os.readlink(fd)
                            m = re.search(r"/(?:presence|conversations)/([a-f0-9-]{36})\.(?:lock|db)", target)
                            if m:
                                live_pids[pid] = m.group(1)
                                break
                        except Exception:
                            pass
        except Exception:
            pass
    return live_pids


def get_live_quota(live_pids: list[int]) -> list[dict[str, Any]]:
    """Query live Antigravity Language Server for official quota groups and buckets."""
    if not live_pids:
        return []

    agy_inodes = set()
    for pid in live_pids:
        for fd in glob.glob(f"/proc/{pid}/fd/*"):
            try:
                target = os.readlink(fd)
                if target.startswith("socket:["):
                    agy_inodes.add(int(target[8:-1]))
            except Exception:
                pass

    ports = []
    if agy_inodes:
        try:
            with open("/proc/net/tcp", "r") as f:
                for line in f.readlines()[1:]:
                    parts = line.strip().split()
                    if len(parts) >= 10 and parts[3] == "0A" and int(parts[9]) in agy_inodes:
                        ports.append(int(parts[1].split(":")[1], 16))
        except Exception:
            pass

    for port in ports:
        url = f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
        try:
            req = urllib.request.Request(url, data=b"{}", headers={"Content-Type": "application/json", "Connect-Protocol-Version": "1"})
            with urllib.request.urlopen(req, timeout=0.4) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                groups = data.get("response", {}).get("groups", [])
                formatted = []
                for g in groups:
                    g_name = g.get("displayName") or "Models"
                    desc = g.get("description") or ""
                    buckets = []
                    for b in g.get("buckets", []):
                        rem_frac = float(b.get("remainingFraction", 1.0))
                        rem_pct = max(0.0, min(100.0, round(rem_frac * 100.0, 2)))
                        buckets.append({
                            "bucketId": b.get("bucketId", ""),
                            "displayName": b.get("displayName", "Limit"),
                            "description": b.get("description", ""),
                            "window": b.get("window", ""),
                            "remainingFraction": rem_frac,
                            "remainingPercent": rem_pct,
                            "usedFraction": round(1.0 - rem_frac, 4),
                            "usedPercent": round(100.0 - rem_pct, 2),
                            "resetTime": b.get("resetTime", "")
                        })
                    formatted.append({
                        "groupName": g_name,
                        "description": desc,
                        "buckets": buckets
                    })
                return formatted
        except Exception:
            pass
    return []


def fast_read_last_steps(transcript_path: Path, max_bytes: int = 8192) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = []
    if not transcript_path.exists():
        return steps
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - max_bytes), os.SEEK_SET)
            chunk = f.read().decode("utf-8", errors="replace")
            for line in chunk.strip().splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    steps.append(json.loads(line))
                except Exception:
                    continue
    except Exception:
        pass
    return steps


def infer_agent_state(last_steps: list[dict[str, Any]]) -> tuple[str, str, str]:
    if not last_steps:
        return "idle", "Gemini 3.7 Flash", "Idle"

    latest_model = "Gemini 3.7 Flash"
    for step in reversed(last_steps):
        content = step.get("content") or ""
        if "Model Selection" in content:
            match = re.search(r"Model Selection` from .*? to (.+?)\.\s*(?:No need|$)", content)
            if match:
                m = sanitize_plain_text(match.group(1).strip().replace("`", ""), 80)
                if m and len(m) < 60 and not m.lower().startswith("comment"):
                    latest_model = m
                    break

    last_step = last_steps[-1]
    step_type = last_step.get("type", "")
    tool_calls = last_step.get("tool_calls", [])

    if step_type == "USER_INPUT":
        return "working", latest_model, "Thinking…"

    if step_type == "PLANNER_RESPONSE":
        if tool_calls:
            for tc in tool_calls:
                fn_name = ""
                if isinstance(tc, dict):
                    fn_name = tc.get("function", {}).get("name") or tc.get("name") or ""
                if fn_name == "ask_question":
                    return "action_needed", latest_model, "Action Needed"
            return "working", latest_model, "Executing Tools…"
        else:
            return "finished", latest_model, "Task Finished"

    if step_type == "GENERIC":
        return "working", latest_model, "Processing…"

    return "idle", latest_model, "Idle"


def get_conversation_metadata(conv_id: str, base_dir: Path) -> tuple[str, str, str]:
    ws_path = ""
    ws_name = ""
    title = ""
    
    hist_file = base_dir / "history.jsonl"
    if hist_file.exists():
        try:
            with open(hist_file, "r", encoding="utf-8", errors="replace") as f:
                for line in reversed(f.readlines()[-40:]):
                    try:
                        data = json.loads(line)
                        if data.get("conversationId") == conv_id:
                            ws_path = data.get("workspace") or ""
                            title = data.get("display") or ""
                            if ws_path:
                                break
                    except Exception:
                        continue
        except Exception:
            pass

    if ws_path:
        clean_path = ws_path.replace("file://", "")
        ws_name = Path(clean_path).name or clean_path
    return ws_path, ws_name, title


def scan(base_dir: Path) -> dict[str, Any]:
    live_procs = get_live_agy_processes()
    running = len(live_procs) > 0
    brain_dir = base_dir / "brain"

    sessions: list[dict[str, Any]] = []

    if running:
        seen_convs = set()
        for pid, conv_id in live_procs.items():
            if not conv_id or conv_id in seen_convs:
                continue
            seen_convs.add(conv_id)

            transcript_path = brain_dir / conv_id / ".system_generated" / "logs" / "transcript.jsonl"
            last_steps = fast_read_last_steps(transcript_path) if transcript_path.exists() else []
            state, model, status_text = infer_agent_state(last_steps)
            ws_path, ws_name, title = get_conversation_metadata(conv_id, base_dir)

            sessions.append({
                "pid": pid,
                "conversationId": conv_id,
                "workspace": ws_path,
                "workspaceName": ws_name or f"PID {pid}",
                "title": title or f"Session {conv_id[:8]}",
                "state": state,
                "currentModel": model,
                "activeStatusText": status_text
            })

    # Sort sessions so working/action_needed are prioritized
    state_rank = {"action_needed": 0, "working": 1, "finished": 2, "idle": 3}
    sessions.sort(key=lambda s: state_rank.get(s["state"], 4))

    # Primary session
    primary_session = sessions[0] if sessions else {
        "conversationId": "",
        "workspace": "",
        "workspaceName": "",
        "title": "",
        "state": "idle",
        "currentModel": "Gemini 3.7 Flash",
        "activeStatusText": "Inactive" if not running else "Idle"
    }

    # Derive overall bar state
    overall_state = "idle"
    if running:
        if any(s["state"] == "action_needed" for s in sessions):
            overall_state = "action_needed"
        elif any(s["state"] == "working" for s in sessions):
            overall_state = "working"
        elif any(s["state"] == "finished" for s in sessions):
            overall_state = "finished"
        else:
            overall_state = primary_session["state"]

    # Official quota groups from running agy language server
    quota_groups = get_live_quota(list(live_procs.keys())) if running else []

    return {
        "schemaVersion": 4,
        "ready": True,
        "agentRunning": running,
        "agentState": overall_state if running else "idle",
        "sessionCount": len(sessions),
        "activeSessions": sessions,
        "primarySession": primary_session if running else {},
        "currentModel": primary_session.get("currentModel", "Gemini 3.7 Flash"),
        "activeStatusText": primary_session.get("activeStatusText", "Inactive" if not running else "Idle"),
        "conversationId": primary_session.get("conversationId", ""),
        "activeWorkspace": primary_session.get("workspace", ""),
        "activeWorkspaceName": primary_session.get("workspaceName", ""),
        "activeTitle": primary_session.get("title", ""),
        "quotaGroups": quota_groups,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat()
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Antigravity Usage & Status Scanner")
    parser.add_argument("path", nargs="?", default=None, help="Base path for antigravity-cli")
    parser.add_argument("--fast", action="store_true", help="Ignored, unified scan")
    parser.add_argument("--json", action="store_true", default=True, help="Emit JSON output")
    args = parser.parse_args()

    base_dir = Path(os.path.expanduser(args.path)) if args.path else default_base_dir()
    result = scan(base_dir)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
