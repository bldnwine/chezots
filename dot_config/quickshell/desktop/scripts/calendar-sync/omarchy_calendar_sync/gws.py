"""Adapter around the gws CLI.

The only module in this package that touches a subprocess. Everything it
returns is plain data, so the rest of the sync is testable without Google.
"""

import json
import os
import re
import subprocess

MINIMUM_VERSION = (0, 13, 2)
FALLBACK_COLOR = "#9e9e9e"
MAX_PAGES = 50

_VERSION = re.compile(r"(\d+)\.(\d+)\.(\d+)")


class GwsError(Exception):
    """Base class for every failure this adapter reports."""


class GwsMissing(GwsError):
    """The gws binary is not on PATH."""


class GwsTooOld(GwsError):
    """The installed gws predates the output shape this sync relies on."""


class GwsAuthError(GwsError):
    """Credentials are absent, expired, or lack the calendar scope."""


class GwsApiError(GwsError):
    """Google returned an error, or gws returned something unparseable."""


def _subprocess_runner(argv, env):
    completed = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=25)
    return completed.returncode, completed.stdout, completed.stderr


class Gws:
    def __init__(self, profile, runner=None, binary="gws"):
        self.profile = str(profile)
        self.binary = str(binary or "gws")
        self._runner = runner or _subprocess_runner
        self._version = None

    def _run(self, args):
        env = dict(os.environ)
        env["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = self.profile
        try:
            code, stdout, stderr = self._runner([self.binary, *args], env)
        except FileNotFoundError as error:
            raise GwsMissing(
                f"{self.binary} is not installed or not on PATH. "
                "A systemd user service does not inherit your shell PATH, so set "
                "gwsPath to an absolute path in calendar-sync.json."
            ) from error
        except subprocess.TimeoutExpired as error:
            raise GwsApiError("gws request timed out after 25 seconds") from error
        return code, stdout, stderr

    def version(self):
        if self._version is not None:
            return self._version
        code, stdout, stderr = self._run(["--version"])
        if code != 0:
            raise GwsApiError(f"cannot read gws version: {(stderr or stdout).strip()[:200]}")
        match = _VERSION.search(stdout)
        if not match:
            raise GwsApiError(f"cannot parse gws version from {stdout!r}")
        self._version = tuple(int(part) for part in match.groups())
        return self._version

    def check(self):
        found = self.version()
        if found < MINIMUM_VERSION:
            wanted = ".".join(str(p) for p in MINIMUM_VERSION)
            have = ".".join(str(p) for p in found)
            raise GwsTooOld(f"gws {wanted} or newer is required, found {have}")

    def calendars(self):
        items = self._pages(["calendar", "calendarList", "list"], {"maxResults": 250})
        calendars = [
            {
                "id": item["id"],
                "name": item.get("summary") or item["id"],
                "color": item.get("backgroundColor") or FALLBACK_COLOR,
                "primary": item.get("primary") is True,
                "accessRole": item.get("accessRole"),
            }
            for item in items
        ]
        return sorted(calendars, key=lambda calendar: calendar["name"])

    def events(self, calendar_id, time_min, time_max):
        return self._pages(["calendar", "events", "list"], {
            "calendarId": calendar_id, "singleEvents": True, "orderBy": "startTime",
            "timeMin": time_min, "timeMax": time_max, "maxResults": 250,
        })

    def _pages(self, command, params):
        items = []
        page_token = None
        for _ in range(MAX_PAGES):
            params = dict(params)
            if page_token:
                params["pageToken"] = page_token
            payload = self._json(
                [*command, "--params", json.dumps(params)]
            )
            if not isinstance(payload.get("items", []), list) or ("items" not in payload and "kind" not in payload):
                raise GwsApiError("gws returned an invalid list response")
            items.extend(payload.get("items", []))
            page_token = payload.get("nextPageToken")
            if not page_token:
                return items
        raise GwsApiError(
            f"gws {' '.join(command)} did not finish paginating within {MAX_PAGES} pages"
        )

    def mutate(self, operation, calendar_id, event_id=None, body=None):
        params = {"calendarId": calendar_id}
        if event_id:
            params["eventId"] = event_id
        args = ["calendar", "events", operation, "--params", json.dumps(params)]
        if body is not None:
            args.extend(["--json", json.dumps(body)])
        return self._json(args, allow_empty=operation == "delete")

    def _json(self, args, allow_empty=False):
        """Run gws and parse stdout.

        stderr carries keyring noise on success, so it is never parsed as
        data. On a nonzero exit code, stdout may not even be JSON, so stderr
        is quoted in the raised error instead since that is the only place
        useful diagnostic detail can come from.
        """
        exit_code, stdout, stderr = self._run(args)

        if allow_empty and exit_code == 0 and not stdout.strip():
            return {}

        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError as error:
            if exit_code != 0:
                raise GwsApiError(f"gws exited with code {exit_code}: {(stderr or stdout).strip()[:200]}") from error
            raise GwsApiError(f"gws returned unparseable output: {error}") from error

        if isinstance(payload, dict) and "error" in payload:
            error = payload["error"]
            if not isinstance(error, dict):
                raise GwsApiError(str(error))
            error_code = error.get("code")
            if error_code is None:
                error_code = "unknown"
            message = error.get("message", "unknown error")
            if error_code in (401, 403):
                raise GwsAuthError(f"{error_code}: {message}")
            raise GwsApiError(f"{error_code}: {message}")

        if exit_code != 0:
            raise GwsApiError(f"gws exited with code {exit_code}: {(stderr or stdout).strip()[:200]}")
        if not isinstance(payload, dict):
            raise GwsApiError("gws response is not an object")

        return payload
