#!/usr/bin/env python3
"""Road map 6, spike C0 — the AssemblyAI client, the scrubber and the ledger.

Stdlib only, and three rules are structural rather than remembered:

* **The key never leaves `os.environ`.** `client_from_env` is the only reader
  and it never returns the string; it goes into one `authorization` header and
  into a `Scrubber`, which every printed or written string passes through.
  Its presence is printed as the word `present` and nothing else.
* **The key can only be paired with AssemblyAI.** `Client.__init__` takes
  exactly two pairs — the live base with a real key, or a loopback base with
  `SELFTEST_KEY` — and raises otherwise, without either key in the message.
  There is no base-URL environment variable to point the real key elsewhere,
  and `NoRedirect` means a 3xx is an ordinary `Reply` rather than a second
  request that carries the header to whatever `Location` said.
* **Money is reserved before it is spent.** `Ledger.reserve` runs before every
  upload and refuses at `BUDGET_DOLLARS`; the upload URL is written before the
  submit and the transcript id before the first poll, so a lost reply leaves a
  trail that `Client.find_own` can turn back into a DELETE. Nothing here
  deletes, truncates or moves the ledger — every write is a temp file in the
  same directory and an `os.replace`.
"""

import http.client
import json
import os
import time
import urllib.error
import urllib.request
from typing import NamedTuple

KEY_ENV = "RC_ASSEMBLYAI_KEY"
BASE_DEFAULT = "https://api.assemblyai.com"
USER_AGENT = "framejob-cloud-spike"
SELFTEST_KEY = "selftest-dummy"
LOOPBACK_PREFIX = "http://127.0.0.1:"
SPEECH_MODELS = ["universal-3-5-pro", "universal-2"]
RATE_PER_HOUR = 0.21
BUDGET_DOLLARS = 2.00


class LeakError(Exception):
    """A secret reached a string that was about to be printed or written."""


class BudgetError(Exception):
    """The next call would pass `BUDGET_DOLLARS`."""


class TransportError(Exception):
    """No HTTP answer at all — a dropped socket, a refused connection."""


class Scrubber:
    """Every string that leaves this spike goes through one of these.

    It holds the key and, as they arrive, the upload URLs — which are not
    secrets but are private URLs into the account, and road map 6 §3b says
    they live in `ledger.json` and nowhere else.
    """

    def __init__(self, secrets):
        self.secrets = [s for s in secrets if s]

    def add(self, secret):
        if secret and secret not in self.secrets:
            self.secrets.append(secret)

    def clean(self, text):
        out = text if isinstance(text, str) else str(text)
        for secret in self.secrets:
            out = out.replace(secret, "<scrubbed>")
        return out

    def assert_clean(self, text):
        out = text if isinstance(text, str) else str(text)
        for secret in self.secrets:
            if secret in out:
                raise LeakError("a secret reached a string about to be printed or written")


class Reply(NamedTuple):
    """An answer, whatever its status. A 3xx and a 401 are both Reply."""

    status: int
    body: bytes
    json: object
    seconds: float


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Stock urllib copies every header but the two content ones across a
    redirect, for a GET and for a 301/302/303 POST — the `authorization`
    header with it. Nothing here follows one."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, base, key, scrubber):
        live = base == BASE_DEFAULT and key != SELFTEST_KEY
        loopback = base.startswith(LOOPBACK_PREFIX) and key == SELFTEST_KEY
        if not key or not (live or loopback):
            raise ValueError(
                "a client is the live base with a real key, or a loopback base with the "
                "selftest dummy; this pair is neither")
        self.base = base.rstrip("/")
        self.key = key
        self.scrubber = scrubber
        self.opener = urllib.request.build_opener(NoRedirect)

    def _request(self, method, path, data=None, headers=None, length=None, timeout=120):
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("authorization", self.key)
        request.add_header("user-agent", USER_AGENT)
        if length is not None:
            request.add_header("content-length", str(length))
        for name, value in (headers or {}).items():
            request.add_header(name, value)
        started = time.monotonic()
        try:
            with self.opener.open(request, timeout=timeout) as answer:
                status, body = answer.status, answer.read()
        except urllib.error.HTTPError as error:
            status, body = error.code, error.read()
            error.close()
        except (urllib.error.URLError, http.client.HTTPException, OSError) as error:
            raise TransportError(
                self.scrubber.clean(f"{type(error).__name__}: {error}")) from None
        seconds = time.monotonic() - started
        try:
            parsed = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            parsed = None
        return Reply(status, body, parsed, seconds)

    def upload(self, path):
        size = os.path.getsize(path)
        with open(path, "rb") as body:
            return self._request("POST", "/v2/upload", data=body, length=size, timeout=1800,
                                 headers={"content-type": "application/octet-stream"})

    def submit(self, audio_url, **options):
        payload = {"audio_url": audio_url}
        models = options.pop("speech_models", SPEECH_MODELS)
        if models is not None:
            payload["speech_models"] = models
        payload.update(options)
        return self._request("POST", "/v2/transcript",
                             data=json.dumps(payload).encode("utf-8"),
                             headers={"content-type": "application/json"})

    def get(self, transcript_id):
        return self._request("GET", f"/v2/transcript/{transcript_id}")

    def delete(self, transcript_id):
        return self._request("DELETE", f"/v2/transcript/{transcript_id}")

    def wait(self, transcript_id, interval, ceiling):
        """Polls to a terminal status, the ceiling, or a status that is not 200."""
        started = time.monotonic()
        polls = 0
        while True:
            reply = self.get(transcript_id)
            polls += 1
            status = (reply.json or {}).get("status") if isinstance(reply.json, dict) else None
            elapsed = time.monotonic() - started
            if reply.status != 200 or status in ("completed", "error") or elapsed >= ceiling:
                return reply, polls, elapsed
            time.sleep(interval)

    def find_own(self, audio_urls, own_id=None):
        """ONE page of the transcript list, and the only list call there is.

        It exists to find transcripts THIS SPIKE created whose id was lost
        with a reply — matched by an upload URL the ledger recorded. The body
        is parsed and dropped inside this method: no id, URL, status, date or
        count of anybody else's transcript leaves it.

        `own_id` is q1's measurement of whether that recovery can work at
        all: it leaves `last_own_entry` describing THIS SPIKE'S OWN entry and
        nothing else — is it in the page yet, does it carry an `audio_url`,
        and is that URL the one we uploaded to.
        """
        reply = self._request("GET", "/v2/transcript?limit=200")
        self.last_own_entry = {"present": False}
        if reply.status != 200 or not isinstance(reply.json, dict):
            return reply.status, []
        found = []
        for entry in reply.json.get("transcripts") or []:
            if not isinstance(entry, dict):
                continue
            if own_id is not None and entry.get("id") == own_id:
                self.last_own_entry = {
                    "present": True,
                    "has_audio_url_field": "audio_url" in entry,
                    "audio_url_matches_the_upload": entry.get("audio_url") in audio_urls,
                    "fields": sorted(entry.keys()),
                    "status": entry.get("status"),
                }
            if entry.get("audio_url") in audio_urls and isinstance(entry.get("id"), str):
                found.append(entry["id"])
        return reply.status, found


def client_from_env():
    """The key's one reader. No key is not an error: the caller SKIPS BY NAME."""
    key = os.environ.get(KEY_ENV)
    scrubber = Scrubber([key] if key else [])
    if not key:
        return None, scrubber
    return Client(BASE_DEFAULT, key, scrubber), scrubber


class Ledger:
    """Append-only, on disk, so a crashed run still knows what it owes.

    `reserve → uploaded → created → billed → closed`, each event stamped with
    `time.time()`. No method here deletes or truncates the file, and neither
    does `--remake` or `--selftest`.
    """

    def __init__(self, path, scrubber=None):
        self.path = str(path)
        self.scrubber = scrubber or Scrubber([])
        try:
            with open(self.path) as handle:
                self.events = json.load(handle)["events"]
        except (OSError, ValueError, KeyError, TypeError):
            self.events = []

    def _append(self, event):
        event["at"] = time.time()
        self.events.append(event)
        text = json.dumps({"events": self.events}, indent=2, sort_keys=True)
        self.scrubber.assert_clean(text)
        folder = os.path.dirname(self.path) or "."
        os.makedirs(folder, exist_ok=True)
        temp = os.path.join(folder, f".{os.path.basename(self.path)}.{os.getpid()}.tmp")
        with open(temp, "w") as handle:
            handle.write(text)
        os.replace(temp, self.path)

    def reservations(self):
        rows = {}
        for event in self.events:
            rid = event.get("rid")
            kind = event.get("kind")
            if kind == "reserve":
                rows[rid] = {"rid": rid, "row": event["row"], "label": event["label"],
                             "planned": event["planned"], "at": event["at"]}
            elif rid in rows:
                row = rows[rid]
                if kind == "uploaded":
                    row["upload_url"] = event["upload_url"]
                    row["bytes"] = event["bytes"]
                    row["uploaded_at"] = event["at"]
                elif kind == "created":
                    row["transcript_id"] = event["transcript_id"]
                elif kind == "billed":
                    row["billed"] = event["audio_duration"]
                elif kind == "closed":
                    row["outcome"] = event["outcome"]
                    row["status"] = event.get("status")
        return rows

    def reserve(self, row, label, planned_seconds):
        planned = float(planned_seconds)
        dollars = (self.total_seconds() + planned) / 3600.0 * RATE_PER_HOUR
        if dollars > BUDGET_DOLLARS:
            raise BudgetError(
                f"the next call would reach ${dollars:.2f}, past the ${BUDGET_DOLLARS:.2f} budget")
        taken = len([e for e in self.events if e.get("kind") == "reserve"]) + 1
        rid = f"{row}-{label}-{taken}"
        self._append({"kind": "reserve", "rid": rid, "row": row, "label": label,
                      "planned": planned})
        return rid

    def uploaded(self, rid, upload_url, size):
        self._append({"kind": "uploaded", "rid": rid, "upload_url": upload_url, "bytes": size})

    def created(self, rid, transcript_id):
        self._append({"kind": "created", "rid": rid, "transcript_id": transcript_id})

    def billed(self, rid, audio_duration):
        self._append({"kind": "billed", "rid": rid, "audio_duration": audio_duration})

    def closed(self, rid, outcome, status=None):
        self._append({"kind": "closed", "rid": rid, "outcome": outcome, "status": status})

    def undeleted(self):
        return [(r["rid"], r["transcript_id"]) for r in self.reservations().values()
                if "transcript_id" in r and "outcome" not in r]

    def lost(self):
        return [(r["rid"], r["upload_url"], r["uploaded_at"]) for r in self.reservations().values()
                if "upload_url" in r and "transcript_id" not in r and "outcome" not in r]

    def unsent(self):
        return [r["rid"] for r in self.reservations().values()
                if "upload_url" not in r and "outcome" not in r]

    def open_rows(self):
        return [r["rid"] for r in self.reservations().values() if "outcome" not in r]

    def unresolved(self):
        return [r["rid"] for r in self.reservations().values() if r.get("outcome") == "unresolved"]

    def ran(self, row):
        return any(r["row"] == row for r in self.reservations().values())

    def total_seconds(self):
        total = 0.0
        for row in self.reservations().values():
            total += float(row.get("billed", row["planned"]))
        return total

    def dollars(self):
        return self.total_seconds() / 3600.0 * RATE_PER_HOUR
