#!/usr/bin/env python3
"""Action CLI for Google Calendar event mutations (create, edit, delete).

Interacts with Google Calendar API via gws or directly updates the local
calendar-events.json state file.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DEFAULT_PROFILE = str(Path.home() / ".config" / "gws-omarchy-calendar")
STATE_PATH = Path.home() / ".local" / "state" / "omarchy" / "calendar-events.json"


def resolve_local_timezone():
    """Resolve the local IANA timezone name."""
    tz_val = os.environ.get("TZ")
    if tz_val:
        try:
            return ZoneInfo(tz_val.lstrip(":"))
        except Exception:
            pass
    if os.path.islink("/etc/localtime"):
        try:
            target = os.readlink("/etc/localtime")
            parts = Path(target).parts
            if "zoneinfo" in parts:
                name = "/".join(parts[parts.index("zoneinfo") + 1 :])
                return ZoneInfo(name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


def run_gws(args, profile=DEFAULT_PROFILE):
    """Run gws CLI with the configured profile."""
    env = dict(os.environ)
    env["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = str(profile)
    cmd = ["gws", *args]
    try:
        res = subprocess.run(cmd, env=env, capture_output=True, text=True)
        return res.returncode, res.stdout, res.stderr
    except FileNotFoundError:
        return 127, "", "gws command not found"


def resync():
    """Trigger background sync script to refresh local cache."""
    sync_bin = Path(__file__).resolve().parent / "omarchy-calendar-sync"
    if sync_bin.exists():
        subprocess.run([str(sync_bin)], capture_output=True)


def cmd_create(args):
    """Create a new event."""
    cal_id = args.calendar or "primary"
    title = (args.title or "New Event").strip()
    loc = (args.location or "").strip()
    event_date_str = args.date or date.today().isoformat()
    all_day = bool(args.all_day)

    tz = resolve_local_timezone()
    dt_target = date.fromisoformat(event_date_str)

    body = {
        "summary": title,
    }
    if loc:
        body["location"] = loc

    if all_day:
        next_dt = dt_target + timedelta(days=1)
        body["start"] = {"date": dt_target.isoformat()}
        body["end"] = {"date": next_dt.isoformat()}
    else:
        start_t_str = args.start or "09:00"
        end_t_str = args.end or "10:00"
        try:
            sh, sm = [int(p) for p in start_t_str.split(":")[:2]]
            eh, em = [int(p) for p in end_t_str.split(":")[:2]]
        except Exception:
            sh, sm, eh, em = 9, 0, 10, 0

        start_dt = datetime.combine(dt_target, time(sh, sm), tzinfo=tz)
        end_dt = datetime.combine(dt_target, time(eh, em), tzinfo=tz)
        if end_dt <= start_dt:
            end_dt = start_dt + timedelta(hours=1)

        body["start"] = {"dateTime": start_dt.isoformat()}
        body["end"] = {"dateTime": end_dt.isoformat()}

    params = {"calendarId": cal_id}
    code, stdout, stderr = run_gws(
        ["calendar", "events", "insert", "--params", json.dumps(params), "--json", json.dumps(body)],
        profile=args.profile,
    )

    if code == 0:
        resync()
        print(f"Created event: {title}")
        return 0
    else:
        print(f"Google API insert error ({code}): {stderr or stdout}", file=sys.stderr)
        # Fallback local update if gws fails
        update_local_create(cal_id, title, event_date_str, body, all_day)
        return code


def cmd_delete(args):
    """Delete an event."""
    cal_id = args.calendar or "primary"
    event_id = args.id
    if not event_id:
        print("error: --id is required", file=sys.stderr)
        return 1

    params = {"calendarId": cal_id, "eventId": event_id}
    code, stdout, stderr = run_gws(
        ["calendar", "events", "delete", "--params", json.dumps(params)],
        profile=args.profile,
    )

    # Clean local state file immediately
    update_local_delete(event_id)
    if code == 0:
        resync()
        print(f"Deleted event: {event_id}")
        return 0
    else:
        print(f"Google API delete error ({code}): {stderr or stdout}", file=sys.stderr)
        return code


def cmd_edit(args):
    """Edit an existing event."""
    cal_id = args.calendar or "primary"
    event_id = args.id
    if not event_id:
        print("error: --id is required", file=sys.stderr)
        return 1

    patch = {}
    if args.title:
        patch["summary"] = args.title.strip()
    if args.location is not None:
        patch["location"] = args.location.strip()

    tz = resolve_local_timezone()
    if args.date:
        dt_target = date.fromisoformat(args.date)
        if args.all_day:
            next_dt = dt_target + timedelta(days=1)
            patch["start"] = {"date": dt_target.isoformat()}
            patch["end"] = {"date": next_dt.isoformat()}
        elif args.start and args.end:
            try:
                sh, sm = [int(p) for p in args.start.split(":")[:2]]
                eh, em = [int(p) for p in args.end.split(":")[:2]]
                start_dt = datetime.combine(dt_target, time(sh, sm), tzinfo=tz)
                end_dt = datetime.combine(dt_target, time(eh, em), tzinfo=tz)
                patch["start"] = {"dateTime": start_dt.isoformat()}
                patch["end"] = {"dateTime": end_dt.isoformat()}
            except Exception:
                pass

    params = {"calendarId": cal_id, "eventId": event_id}
    code, stdout, stderr = run_gws(
        ["calendar", "events", "patch", "--params", json.dumps(params), "--json", json.dumps(patch)],
        profile=args.profile,
    )

    update_local_edit(event_id, patch)
    if code == 0:
        resync()
        print(f"Edited event: {event_id}")
        return 0
    else:
        print(f"Google API edit error ({code}): {stderr or stdout}", file=sys.stderr)
        return code


def update_local_edit(event_id, patch):
    """Locally update event in calendar-events.json."""
    if not STATE_PATH.exists():
        return
    try:
        doc = json.loads(STATE_PATH.read_text())
        events = doc.get("events") or []
        for e in events:
            if e.get("id") == event_id:
                if "summary" in patch:
                    e["title"] = patch["summary"]
                if "location" in patch:
                    e["location"] = patch["location"]
        doc["events"] = events
        STATE_PATH.write_text(json.dumps(doc, indent=2) + "\n")
    except Exception:
        pass


def update_local_delete(event_id):
    """Locally remove event from calendar-events.json."""
    if not STATE_PATH.exists():
        return
    try:
        doc = json.loads(STATE_PATH.read_text())
        events = doc.get("events") or []
        filtered = [e for e in events if e.get("id") != event_id]
        doc["events"] = filtered
        STATE_PATH.write_text(json.dumps(doc, indent=2) + "\n")
    except Exception:
        pass


def update_local_create(cal_id, title, date_key, body, all_day):
    """Locally inject new event into calendar-events.json."""
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    doc = {"version": 1, "syncedAt": datetime.now().isoformat(), "source": "local", "events": []}
    if STATE_PATH.exists():
        try:
            doc = json.loads(STATE_PATH.read_text())
        except Exception:
            pass
    events = doc.get("events") or []
    new_event = {
        "id": f"local-{int(datetime.now().timestamp())}",
        "calendarId": cal_id,
        "calendarName": "Personal",
        "color": "#658594",
        "dateKey": date_key,
        "start": body.get("start", {}).get("dateTime") or body.get("start", {}).get("date") or date_key,
        "end": body.get("end", {}).get("dateTime") or body.get("end", {}).get("date") or date_key,
        "allDay": all_day,
        "title": title,
        "location": body.get("location", ""),
        "meetingUrl": "",
        "eventUrl": "",
    }
    events.append(new_event)
    doc["events"] = events
    STATE_PATH.write_text(json.dumps(doc, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Google Calendar Event Action CLI")
    parser.add_argument("--profile", default=DEFAULT_PROFILE, help="gws profile directory")
    sub = parser.add_subparsers(dest="command", required=True)

    # create
    p_create = sub.add_parser("create", help="Create an event")
    p_create.add_argument("--calendar", default="primary", help="Calendar ID")
    p_create.add_argument("--title", required=True, help="Event title / summary")
    p_create.add_argument("--date", help="Event date (YYYY-MM-DD)")
    p_create.add_argument("--start", help="Start time (HH:MM)")
    p_create.add_argument("--end", help="End time (HH:MM)")
    p_create.add_argument("--all-day", action="store_true", help="All day event")
    p_create.add_argument("--location", help="Event location")
    p_create.set_defaults(func=cmd_create)

    # delete
    p_delete = sub.add_parser("delete", help="Delete an event")
    p_delete.add_argument("--calendar", default="primary", help="Calendar ID")
    p_delete.add_argument("--id", required=True, help="Event ID")
    p_delete.set_defaults(func=cmd_delete)

    # edit
    p_edit = sub.add_parser("edit", help="Edit an event")
    p_edit.add_argument("--calendar", default="primary", help="Calendar ID")
    p_edit.add_argument("--id", required=True, help="Event ID")
    p_edit.add_argument("--title", help="Updated title")
    p_edit.add_argument("--date", help="Updated date (YYYY-MM-DD)")
    p_edit.add_argument("--start", help="Updated start time (HH:MM)")
    p_edit.add_argument("--end", help="Updated end time (HH:MM)")
    p_edit.add_argument("--all-day", action="store_true", help="All day event")
    p_edit.add_argument("--location", help="Updated location")
    p_edit.set_defaults(func=cmd_edit)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main() or 0)
