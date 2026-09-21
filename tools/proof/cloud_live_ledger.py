#!/usr/bin/env python3
"""Road map 6, C1 pipeline 5 — the money, the client lines and the CONTROLs.

The half of the live rows that has no instance in it: what the app's own
`AssemblyAI: ` lines say it did, what the ledger then owes, how a transcript
is deleted and proved gone, and the pure checks the rows are written on.
`cloud_captions_live.py` imports every name here, so the whole interface is
reachable on that module; this file exists because the two halves together
pass the 400-line cap for a new file.

**Nothing here ever names the key.** `Scrubber` holds it (filled by
`aai.client_from_env`, the key's one reader) and `leaks` compares in process
and answers a boolean.

**Nothing here lists the account.** Every id it acts on came from a line the
app printed in this run or from the cache file this run wrote.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "cloud_spike"))

from aai import RATE_PER_HOUR, Scrubber                                    # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "work", "cloudlive", "ledger.json")
FOLDER = os.path.dirname(LEDGER)

CEILING_DOLLARS = 0.25
MAX_TRANSCRIPTIONS = 6
PLANNED_SECONDS = 11

# `AssemblyAI: ` is already off (`Instance.client_lines`); what is left is
# `<method> <path> → <status>`, which a retry line and a failed-poll line —
# the only other things `note` prints — do not match.
REQUEST = re.compile(r"^(GET|POST|DELETE|PUT|PATCH|\?) (\S+) → (\S+)$")
DELETED_URL = "http://deleted_by_user"
DELETED_TEXT = "Deleted by user."


class Refused(Exception):
    """The gate said no BEFORE a billable call was made."""


def requests_in(lines):
    out = []
    for line in lines:
        found = REQUEST.match(line.strip())
        if found:
            out.append((found.group(1), found.group(2), found.group(3)))
    return out


def submits(lines):
    """`POST /v2/transcript` lines whose status is not 4xx.

    A 200, a 5xx, `error` and `?` may EACH have made a transcript — what was
    lost is the reply, not the work — so each is counted and each costs a
    reservation. Only a 4xx is certainly nothing.
    """
    return len([1 for method, path, status in requests_in(lines)
                if method == "POST" and path == "/v2/transcript"
                and not (status.isdigit() and 400 <= int(status) < 500)])


def uploads_ok(lines):
    return len([1 for method, path, status in requests_in(lines)
                if method == "POST" and path == "/v2/upload" and status == "200"])


def ids(lines):
    """Distinct transcript ids, in the order they were first seen."""
    found = []
    for method, path, _ in requests_in(lines):
        if method in ("GET", "DELETE") and path.startswith("/v2/transcript/"):
            one = path.split("/v2/transcript/", 1)[1].strip("/")
            if one and one not in found:
                found.append(one)
    return found


def refusal(ledger):
    """Why the next billable call may not be made, or None.

    The count is of reservations whose outcome is not `no_transcript` or
    `no_upload` — so open rows, `deleted` rows, `unresolved` rows and every
    `extra` row `account` wrote all count against the six.
    """
    dollars = (ledger.total_seconds() + PLANNED_SECONDS) / 3600.0 * RATE_PER_HOUR
    if dollars > CEILING_DOLLARS:
        return (f"the next call would reach ${dollars:.4f}, past the "
                f"${CEILING_DOLLARS:.2f} ceiling")
    counted = [row for row in ledger.reservations().values()
               if row.get("outcome") not in ("no_transcript", "no_upload")]
    if len(counted) >= MAX_TRANSCRIPTIONS:
        return (f"{len(counted)} reservations already count against the "
                f"{MAX_TRANSCRIPTIONS}-transcription ceiling")
    return None


def reserve(ledger, row, label):
    why = refusal(ledger)
    if why:
        raise Refused(why)
    return ledger.reserve(row, label, PLANNED_SECONDS)


def account(ledger, rid, row, lines):
    """Makes the ledger say what the APP did, not what the rows expected.

    The first id is the reservation's own. Every FURTHER id, and every submit
    beyond the ids seen, gets a reservation of its own written straight
    through `Ledger.reserve` — a record of a fact rather than an
    authorisation, so it bypasses the gate and is COUNTED by it. Never
    `billed`, so `total_seconds()` charges it the planned seconds. An `extra`
    with no id is closed `unresolved` at once: a submit whose id never
    surfaced is for a person to resolve, and this file will not go looking
    for it on the account.
    """
    seen = ids(lines)
    for index, one in enumerate(seen):
        if index == 0:
            ledger.created(rid, one)
            continue
        ledger.created(ledger.reserve(row, "extra", PLANNED_SECONDS), one)
    for _ in range(max(0, submits(lines) - len(seen))):
        ledger.closed(ledger.reserve(row, "extra", PLANNED_SECONDS), "unresolved")
    return seen


def erase(client, one):
    """DELETE, then C0's q6 sentinel GET. True only when it is gone."""
    client.delete(one)
    reply = client.get(one)
    body = reply.json if isinstance(reply.json, dict) else {}
    return (reply.status == 200 and body.get("audio_url") == DELETED_URL
            and body.get("text") == DELETED_TEXT)


def cleanup(client, ledger, rids, instance, cache_file, since):
    """Every transcript this run's OWN lines named, deleted and proved gone.

    It acts on the SET of ids in the lines captured since the row began plus
    the one in the cache file — row 20's id met again under row 21 is a repeat
    DELETE, a 200 by q6, and is not recorded twice. A reservation closes
    `deleted` only when the sentinel passes for every id it owns, and
    `unresolved` — a FAIL, named for the person — when one does not.
    """
    if not rids:
        return
    rows = ledger.reservations()
    pool = list(ids(instance.client_lines(since)))
    cached = (read_json(cache_file) or {}).get("transcript_id")
    if cached and cached not in pool:
        pool.append(cached)
    owned = {rid: [one for one in [rows.get(rid, {}).get("transcript_id")] if one]
             for rid in rids}
    taken = {one for mine in owned.values() for one in mine}
    owned[rids[0]].extend([one for one in pool if one not in taken])
    verdict = {one: erase(client, one) for mine in owned.values() for one in set(mine)}
    for rid in rids:
        mine = owned[rid]
        if not mine:
            ledger.closed(rid, "no_transcript")
        else:
            ledger.closed(rid, "deleted" if all(verdict.get(one) for one in mine)
                          else "unresolved")


class Captured(object):
    """A stopped instance's own lines, for `cleanup`.

    `cleanup` asks an instance what its client printed since a mark; an arm
    whose rows are cleaned up AFTER its instance came down (the dummy arm,
    which returns through a `with` block) hands the lines its pty captured
    while that instance was still up, and this stands in for it.
    """

    def __init__(self, lines):
        self.lines = list(lines)

    def client_lines(self, since=0):
        return self.lines


def scrubbed(scrubber, detail):
    """A `detail` built from app text or from an exception, cleaned before
    anything can print it — the live rows' Constraints. A `scrubber` of None
    (no live key in this process) leaves the text alone.
    """
    return scrubber.clean(detail) if scrubber is not None else detail


def read_json(path):
    if not path:
        return {}
    try:
        with open(path, "rb") as handle:
            return json.loads(handle.read() or b"{}")
    except (OSError, ValueError):
        return {}


def normalise(text):
    """Tokens: `[[slnc N]]` out, punctuation out, lower case, `5` is `five`."""
    body = re.sub(r"\[\[slnc \d+\]\]", " ", text).lower()
    body = re.sub(r"[^a-z0-9 ]+", " ", body)
    return ["five" if piece == "5" else piece for piece in body.split()]


def subsequence(want, got):
    """Every token of `want`, in order, somewhere in `got`."""
    rest = iter(got)
    return all(any(token == one for one in rest) for token in want)


def touches(words, pauses):
    """Every word × pause overlap over 0 ms, as (text, ms) pairs."""
    out = []
    for one in words:
        for start, end in pauses:
            overlap = min(float(one["end"]), end * 1000.0) - max(
                float(one["start"]), start * 1000.0)
            if overlap > 0:
                out.append((one.get("text"), round(overlap)))
    return out


def words_span(raw):
    """Row 4's cut: the `words` array's own bytes, as they were served."""
    at = raw.find(b'"words":')
    return raw[at + len(b'"words":'):-1] if at >= 0 else b""


def leaks(scrubber, paths, texts):
    """True when a secret reached one of these strings or files.

    It prints NOTHING and returns nothing but the boolean; a path may be a
    file or a folder, and an unreadable file is skipped rather than raised on.
    """
    for text in texts:
        body = text if isinstance(text, str) else str(text)
        if any(secret in body for secret in scrubber.secrets):
            return True
    for path in paths:
        targets = []
        if os.path.isdir(path):
            for base, _, names in os.walk(path):
                targets += [os.path.join(base, name) for name in names]
        elif os.path.exists(path):
            targets.append(path)
        for one in targets:
            try:
                with open(one, "rb") as handle:
                    body = handle.read()
            except OSError:
                continue
            if any(secret.encode("utf-8") in body for secret in scrubber.secrets):
                return True
    return False


def controls(proof):
    """The CONTROLs for everything above: free, and run whatever the host
    answers, so a live row that passes is a row whose instrument was seen to
    fail on purpose in the same process."""
    canned = ["POST /v2/upload → 200", "POST /v2/upload → 500",
              "POST /v2/transcript → 200", "POST /v2/transcript → 500",
              "POST /v2/transcript → 401", "GET /v2/transcript/abc → 200",
              "GET /v2/transcript/abc → 200", "DELETE /v2/transcript/def → 200",
              "retry 1 of upload after server"]
    proof.check("C: CONTROL — `submits` counts the 200 and the 5xx and not the 401",
                submits(canned) == 2, f"got {submits(canned)}")
    proof.check("C: CONTROL — `uploads_ok` counts only the upload that answered 200",
                uploads_ok(canned) == 1, f"got {uploads_ok(canned)}")
    proof.check("C: CONTROL — `ids` answers the two distinct ids, in order",
                ids(canned) == ["abc", "def"], f"got {ids(canned)!r}")

    word = {"text": "straddle", "start": 2600, "end": 2900}
    touched = touches([word], [[2.72, 4.29]])
    proof.check("C: CONTROL — the pause check REPORTS a touch for a synthetic word that "
                "straddles a known pause",
                touched == [("straddle", 180)], f"got {touched!r}")

    want = normalise("the quick brown fox")
    proof.check("C: CONTROL — the sentence check FAILS on a shuffled list and holds on the "
                "list itself",
                not subsequence(want, ["fox", "the", "quick", "brown"])
                and subsequence(want, ["the", "a", "quick", "brown", "b", "fox"]),
                f"want {want!r}")

    body = b'{"id":"x","words":[{"text":"a","start":1,"end":2}],"status":"completed"}'
    span = words_span(b'{"words":[{"text":"a","start":1,"end":2}]}')
    again = json.dumps(json.loads(span)).encode("utf-8")
    proof.check("C: CONTROL — the served bytes occur in the body while a RE-SERIALISATION "
                "of the same words does not",
                span in body and again not in body, f"got {span!r} / {again!r}")

    dummy = f"control-dummy-{os.getpid()}"
    os.makedirs(os.path.join(FOLDER, "controls"), exist_ok=True)
    seeded = os.path.join(FOLDER, "controls", "seeded.txt")
    with open(seeded, "w") as handle:
        handle.write("before " + dummy + " after\n")
    flagged = (leaks(Scrubber([dummy]), [], [f"x {dummy} y"]),
               leaks(Scrubber([dummy]), [seeded], []))
    os.remove(seeded)
    proof.check("C: CONTROL — `leaks` flags a registered dummy in a STRING and in a FILE, "
                "and the file is taken away again",
                flagged == (True, True) and not os.path.exists(seeded), f"got {flagged!r}")
