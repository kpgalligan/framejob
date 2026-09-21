#!/usr/bin/env python3
"""Road map 6, C1 pipeline 5, the fix pass — `dummy_arm`'s FAILURE branch,
driven with stubs.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_live_selftest.py

**It makes no request and spends nothing.** The client, the instance, the
session and the proof module are all stubs; the LEDGER is the real
`aai.Ledger` on a temporary file (never `work/cloudlive/ledger.json`), so what
is measured is the accounting the live rows would do.

Why it exists: 05-review's finding 4. When the dummy arm fails because a
submit got through, `cloud_captions_live.run` returns before the real
instance exists, so `close` has no instance to sweep with — the arm has to
close its OWN reservation on its measured outcome and delete what its own
captured lines named, before it returns. The rows below fail on the tree
without that fix (a `no_transcript` close and no DELETE) and hold with it.

The stub instance REFUSES to answer `client_lines` once it has been stopped,
so a fix that reached for the down instance's pty instead of the lines
captured while it was up is a failure here too.
"""

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "cloud_spike"))

import cloud_captions_live as live                                         # noqa: E402
from aai import Ledger, Scrubber                                           # noqa: E402

SECRET = "selftest-not-a-real-key"
FOUND_ID = "selftest-transcript-id"

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


class StubReply(object):
    def __init__(self, status, body):
        self.status = status
        self.json = body
        self.body = json.dumps(body).encode("utf-8")


class StubClient(object):
    """Answers C0's q6 sentinel for anything it is asked to delete."""

    def __init__(self):
        self.deleted = []
        self.got = []

    def delete(self, one):
        self.deleted.append(one)
        return StubReply(200, {"id": one})

    def get(self, one):
        self.got.append(one)
        return StubReply(200, {"id": one, "audio_url": live.DELETED_URL,
                               "text": live.DELETED_TEXT})


class StubInstance(object):
    def __init__(self, lines, secrets):
        self.lines = list(lines)
        self.secrets = secrets
        self.reader_failed = False
        self.stopped = False
        self.log = os.path.join(secrets, "..", "stub.log")

    def mark(self):
        return 0

    def client_lines(self, since=0):
        if self.stopped:
            raise AssertionError("client_lines asked of a STOPPED instance")
        return self.lines

    def parity(self):
        pass

    def stop(self):
        self.stopped = True

    def __enter__(self):
        return self

    def __exit__(self, *rest):
        self.stopped = True
        return False


class StubSession(object):
    def __init__(self, path, refusal):
        self.path = path
        self.refusal = refusal

    def media_of(self, path):
        return "media0"

    def add(self, media, **rest):
        pass

    def error(self, op, **rest):
        return self.refusal

    def save(self):
        pass


class StubProof(object):
    """Only what `dummy_arm` touches."""

    DUMMY = "proof-key"

    def __init__(self, folder, lines, refusal):
        self.folder = folder
        self.secrets = os.path.join(folder, "secrets")
        os.makedirs(self.secrets, exist_ok=True)
        self.instance = StubInstance(lines, self.secrets)
        self.session = StubSession(os.path.join(folder, "package"), refusal)
        os.makedirs(os.path.join(self.session.path, "cache"), exist_ok=True)
        self.live_scrubber = Scrubber([SECRET])
        self.rows = []

    def Instance(self, name, port, endpoint, binary, key=None, live=False):
        return self.instance

    def Session(self, instance, name):
        return self.session

    def check(self, name, ok, detail=""):
        self.rows.append((name, bool(ok), detail))

    def cache_path(self, session, media, marker=False):
        return os.path.join(session.path, "cache", f"{media}.json")


def arm(folder, lines, refusal):
    """One `dummy_arm` call over stubs, with its own ledger file."""
    proof = StubProof(folder, lines, refusal)
    client = StubClient()
    ledger = Ledger(os.path.join(folder, "ledger.json"), Scrubber([SECRET]))
    live.make_fixture = lambda: os.path.join(folder, "fixture.aiff")
    held = live.dummy_arm(proof, client, "/nonexistent/binary", 4989, None, ledger)
    rows = ledger.reservations()
    rid = sorted(rows)[0]
    return proof, client, ledger, held, rows[rid]


def main():
    folder = tempfile.mkdtemp(prefix="cloud-live-selftest-")
    try:
        print("\nA. the dummy arm FAILED — a submit got through and an id was seen")
        submitted = ["POST /v2/upload → 200", "POST /v2/transcript → 200",
                     f"GET /v2/transcript/{FOUND_ID} → 200"]
        proof, client, ledger, held, row = arm(
            os.path.join(folder, "a"), submitted,
            "AssemblyAI refused the API key — check it in Reelcut ▸ Settings")
        check("A: the arm answers FALSE, so the run stops before the real key is used",
              held is False, f"got {held!r}")
        check(f"A: the id the app's own lines named was DELETED — exactly one DELETE, of "
              f"`{FOUND_ID}`", client.deleted == [FOUND_ID], f"got {client.deleted!r}")
        check("A: and q6's sentinel GET was made for it, so the deletion is PROVED",
              client.got == [FOUND_ID], f"got {client.got!r}")
        check("A: the reservation closes on its MEASURED outcome — `deleted`, not "
              "`no_transcript` — and is not billed",
              row.get("outcome") == "deleted" and "billed" not in row, f"got {row!r}")
        check("A: the ledger owes nothing when the arm returns — no open and no "
              "`unresolved` reservation",
              ledger.open_rows() == [] and ledger.unresolved() == [],
              f"open {ledger.open_rows()!r}, unresolved {ledger.unresolved()!r}")

        print("\nB. CONTROL — the dummy arm HELD, the 401 and nothing else")
        proof, client, ledger, held, row = arm(
            os.path.join(folder, "b"), ["POST /v2/upload → 401"],
            "AssemblyAI refused the API key — check it in Reelcut ▸ Settings")
        check("B: CONTROL — the arm answers TRUE and nothing is deleted, because nothing "
              "was made", held is True and client.deleted == [] and client.got == [],
              f"got {held!r}, {client.deleted!r}, {client.got!r}")
        check("B: CONTROL — the reservation still closes `no_transcript`, billed nothing",
              row.get("outcome") == "no_transcript" and "billed" not in row, f"got {row!r}")
        check("B: CONTROL — and the ledger owes nothing",
              ledger.open_rows() == [] and ledger.unresolved() == [],
              f"open {ledger.open_rows()!r}, unresolved {ledger.unresolved()!r}")

        print("\nC. CONTROL — the arm's own checks were made, and its refusal detail is "
              "SCRUBBED")
        proof, client, ledger, held, row = arm(
            os.path.join(folder, "c"), ["POST /v2/upload → 401"],
            f"refused: {SECRET} — check it in Reelcut ▸ Settings")
        details = " ".join(detail for _, _, detail in proof.rows)
        check(f"C: CONTROL — the arm made its {len(proof.rows)} checks and no detail it "
              "built from the app's text holds the registered secret",
              len(proof.rows) == 7 and SECRET not in details and "<scrubbed>" in details,
              f"got {len(proof.rows)} rows, {details[:120]!r}")
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
