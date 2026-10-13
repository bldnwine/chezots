#!/usr/bin/env python3
"""Apply Google Calendar mutations and cache only acknowledged results."""

import argparse
import json
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path

from omarchy_calendar_sync import config, contract, normalize
from omarchy_calendar_sync.cli import resolve_local_timezone
from omarchy_calendar_sync.gws import Gws, GwsError
from omarchy_calendar_sync.storage import cache_lock, write_atomic

STATE_PATH = contract.CONTRACT_PATH


def event_times(args, tz):
    if not args.date:
        raise ValueError("A date is required when changing event times")
    day = date.fromisoformat(args.date)
    if args.all_day:
        return {"start": {"date": day.isoformat()},
                "end": {"date": (day + timedelta(days=1)).isoformat()}}
    if not args.start or not args.end:
        raise ValueError("Both start and end times are required")
    start = datetime.combine(day, time.fromisoformat(args.start), tzinfo=tz)
    end = datetime.combine(day, time.fromisoformat(args.end), tzinfo=tz)
    if end < start:
        raise ValueError("End time must not be earlier than start time")
    return {"start": {"dateTime": start.isoformat()}, "end": {"dateTime": end.isoformat()}}


def perform(args, client, out_path=STATE_PATH, local_tz=None):
    """Serialize with sync, then update the cache after Google confirms success."""
    tz = local_tz or resolve_local_timezone()
    path = Path(out_path)
    with cache_lock(path):
        if path.exists():
            doc = json.loads(path.read_text())
            problems = contract.validate(doc)
            if problems:
                raise ValueError("Calendar cache is invalid; sync it before editing")
        else:
            doc = contract.build_document([], "1970-01-01T00:00:00+00:00", "local")

        calendars = client.calendars()
        requested = args.calendar or "primary"
        calendar = next((c for c in calendars if c["id"] == requested
                         or (requested == "primary" and c.get("primary"))), None)
        if calendar is None:
            raise ValueError("The selected calendar is not available")
        if calendar.get("accessRole") not in (None, "owner", "writer", "writerWithoutPrivateAccess"):
            raise ValueError("The selected calendar is read-only")
        cal_id = calendar["id"]
        event_id = getattr(args, "id", None)
        body = None
        if args.command != "delete":
            body = {}
            if args.title is not None:
                body["summary"] = args.title.strip()
            if args.location is not None:
                body["location"] = args.location.strip()
            if args.command == "create" or args.date or args.start or args.end or args.all_day:
                body.update(event_times(args, tz))
            if args.command == "create" and not body.get("summary"):
                raise ValueError("An event title is required")
            if not body:
                raise ValueError("No event changes were supplied")

        operation = {"create": "insert", "edit": "patch", "delete": "delete"}[args.command]
        result = client.mutate(operation, cal_id, event_id, body)
        rows = []
        if args.command != "delete":
            if not result.get("id") or not result.get("start") or not result.get("end"):
                raise GwsError("Google accepted the request but returned no event; sync to confirm its outcome")
            event_id = result["id"]
            rows = normalize.normalize_event(result, calendar, tz)
            if not rows:
                raise GwsError("Google accepted the request but its event could not be normalized; sync to confirm")

        doc["events"] = [e for e in doc["events"]
                         if not (e["calendarId"] == cal_id and e["id"] == event_id)] + rows
        doc["events"].sort(key=lambda e: (e["dateKey"], e["start"], e["title"]))
        if contract.validate(doc):
            raise ValueError("Refusing to write an invalid Calendar cache")
        write_atomic(path, doc)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Google Calendar event actions")
    parser.add_argument("--config", help="calendar-sync.json path")
    parser.add_argument("--profile", help="override the configured gws profile")
    parser.add_argument("--out", help="override the cache path")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "edit", "delete"):
        command = commands.add_parser(name)
        command.add_argument("--calendar", default="primary")
        if name != "create":
            command.add_argument("--id", required=True)
        if name != "delete":
            command.add_argument("--title", required=name == "create")
            command.add_argument("--date", required=name == "create")
            command.add_argument("--start")
            command.add_argument("--end")
            command.add_argument("--all-day", action="store_true")
            command.add_argument("--location")
    args = parser.parse_args(argv)
    try:
        cfg = config.load(args.config)
        client = Gws(args.profile or cfg["profile"], binary=cfg["gwsPath"])
        perform(args, client, args.out or STATE_PATH)
    except (GwsError, config.ConfigError, ValueError, OSError, TimeoutError) as error:
        print(f"Calendar action failed: {error}", file=sys.stderr)
        return 1
    print("Calendar event updated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
