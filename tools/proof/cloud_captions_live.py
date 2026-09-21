#!/usr/bin/env python3
"""Road map 6, C1 pipeline 5 — §5i's LIVE rows 20 and 21, against the REAL
AssemblyAI. Reached by `cloud_captions_proof.py --live` and by nothing else,
so a routine proof run cannot spend money:

    python3 tools/proof/cloud_captions_proof.py --live --port-base 4980

**The key** is read in one place, `cloud_spike/aai.py`'s `client_from_env`,
which never returns the string: it goes into one `authorization` header
inside `Client` and into a `Scrubber` every kept line passes through. Two
processes have it — the app under test, which INHERITS it (never an argument,
which `ps` would show), and this file's `Client`, for the read-backs the app
cannot do. Every leak check compares in process and prints a boolean.

**The money.** `work/cloudlive/ledger.json` is the spike's own append-only
ledger; a reservation is written BEFORE every billable call and the gate
refuses at $0.25 or at six transcriptions, counting an `extra` row for every
submit or id the APP made that the ledger had not accounted for. The fixture
is `say`'s eleven seconds — a fraction of a cent a run; the ceiling is there
for a loop that should not exist.

**The upload** is only `work/cloudprobe/fixtures/speech.aiff`, the synthetic
fixture the other proofs make. Nothing else on this machine is ever sent, and
`cleanup` deletes in a `finally` every transcript this run's own lines named.

The money half — the ledger, the line parsing, the deletions and the CONTROLs
— is `cloud_live_ledger.py`, imported here so that every name is reachable on
this module.
"""

import hashlib
import json
import math
import os
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "cloud_spike"))

from cloud_live_ledger import (                                            # noqa: E402,F401
    CEILING_DOLLARS, DELETED_TEXT, DELETED_URL, FOLDER, LEDGER, MAX_TRANSCRIPTIONS,
    PLANNED_SECONDS, Captured, Refused, account, cleanup, controls, erase, ids, leaks,
    normalise, read_json, reachable, refusal, requests_in, reserve, scrubbed, subsequence,
    submits, touches, uploads_ok, words_span)
from aai import KEY_ENV, Ledger, client_from_env                           # noqa: E402
from fixtures import truth_pauses                                          # noqa: E402

from cloud_captions_probe import SPEECH_TEXT, make_fixture, run_probe      # noqa: E402

# What a full run checks, and what a precondition SKIPS BY NAME. The run
# prints what it actually made beside it, so a drift shows.
LIVE_ROW_COUNT = 36


# --------------------------------------------------------------------------
# The dummy arm — R6-9 proved against nothing billable, before the real key


def dummy_arm(proof, client, binary, port, probe, ledger):
    """An instance with the DUMMY key and NO endpoint override: the credential
    must resolve to the environment's dummy (the store's folder is empty), the
    real service must refuse it, and nothing may be submitted. `probe` is
    taken for the symmetry of `run`'s two arms; this arm decodes nothing.

    An arm that does NOT hold ends the whole run before the real instance
    exists, so `close` has no instance to sweep with: this arm therefore
    closes its own reservation on its MEASURED outcome and deletes whatever
    its own captured lines named, here, before it returns.
    """
    print("\n20d. the dummy arm — R6-9's empty store, the environment's key, a real 401")
    rid = reserve(ledger, "20d", "dummy")
    with proof.Instance("L0", port, None, binary, key=proof.DUMMY, live=True) as instance:
        before = sorted(os.listdir(instance.secrets))
        session = proof.Session(instance, "live-dummy")
        media = session.media_of(make_fixture())
        session.add(media)
        since = instance.mark()
        text = session.error("transcribe", engine="assemblyai", place=False)
        lines = instance.client_lines(since)
        account(ledger, rid, "20d", lines)
        session.save()
        proof.check("20d: a dummy key resolved from the ENVIRONMENT (the store's folder is "
                    "empty) reaches the real service and is refused in the key's own "
                    "sentence",
                    text is not None and "AssemblyAI refused the API key — check it in "
                    "Reelcut ▸ Settings" in text,
                    scrubbed(getattr(proof, "live_scrubber", None), f"got {text!r}"))
        proof.check("20d: and the pty SAW the client's one line — `POST /v2/upload → 401`",
                    lines == ["POST /v2/upload → 401"], f"got {lines!r}")
        proof.check("20d: with ZERO `POST /v2/transcript` lines of any status and no id — "
                    "nothing billable was attempted",
                    submits(lines) == 0 and not ids(lines), f"got {lines!r}")
        proof.check("20d: no transcript cache and no marker in the package afterwards",
                    not os.path.exists(proof.cache_path(session, media))
                    and not os.path.exists(proof.cache_path(session, media, marker=True)),
                    f"got {sorted(os.listdir(os.path.join(session.path, 'cache')))!r}")
        after = sorted(os.listdir(instance.secrets))
        proof.check("20d: R6-9's secret folder is EMPTY before and after, so the person's "
                    "own store was never opened", before == [] and after == [],
                    f"got {before!r} then {after!r}")
        proof.check("20d: the pty reader did not fail", not instance.reader_failed)
    held = submits(lines) == 0 and text is not None
    if held:
        ledger.closed(rid, "no_transcript")
        wanted, branch = {"no_transcript"}, "no submit reached the wire, so the arm HELD"
    else:
        # `cleanup` closes this reservation itself, `deleted` or `unresolved`
        # — never `no_transcript`, which is what this check used to assert on
        # both branches (the reader review, road map 6 §10.13, H·6).
        cleanup(client, ledger, [rid], Captured(lines), None, 0)
        wanted = {"deleted", "unresolved"}
        branch = "a submit DID reach the wire, so `cleanup` ran over the captured lines"
    row = ledger.reservations()[rid]
    proof.check(f"20d: {branch}, and the ledger closed it "
                f"{' or '.join(sorted(wanted))}, billed nothing",
                row.get("outcome") in wanted and "billed" not in row, f"got {row!r}")
    return held


# --------------------------------------------------------------------------
# Row 20 — the round trip


def race(client, instance, stop):
    """The provider's own bytes, kept IN MEMORY, in a race with the app's
    DELETE: it tails the captured lines for the first `GET
    /v2/transcript/<id>`, then GETs that id every quarter second for at most
    thirty, keeping the first `completed` body. The app usually wins — its
    DELETE follows its own last poll within a breath — and when it does, the
    one row this feeds is SKIPPED BY NAME.
    """
    deadline = time.monotonic() + 30
    target = None
    polls = 0
    while time.monotonic() < deadline and not stop.is_set():
        if target is None:
            found = ids(instance.client_lines())
            target = found[0] if found else None
        if target is not None:
            reply = client.get(target)
            polls += 1
            if (reply.status == 200 and isinstance(reply.json, dict)
                    and reply.json.get("status") == "completed"):
                print(f"  (the racing reader won with {polls} GETs of its own of the app's "
                      f"transcript)")
                return reply.body
        time.sleep(0.25)
    print(f"  (the racing reader made {polls} GETs and did not see `completed` first)")
    return None


def row_twenty(proof, instance, probe, ledger, client, aiff, state):
    """`state` is the caller's own dictionary, filled as the row goes, so a
    call that THROWS still leaves `close` the `since` and the cache path it
    needs to delete whatever the run made."""
    print("\n20. the fixture's round trip against api.assemblyai.com")
    state.update(since=instance.mark(), returned=False, ok=False, cache=None)
    rid = reserve(ledger, "20", "round-trip")
    out = os.path.join(proof.fresh("live-whole"), "whole.wav")
    answer, error, _ = run_probe(probe, "live-whole",
                                 {"mode": "extract", "op": "whole", "media": aiff,
                                  "name": "live", "out": out})
    frames = (answer or {}).get("frames")
    proof.check("20: the on-device extractor answers this fixture's frame count, which is "
                "what `audio_seconds` is read against",
                isinstance(frames, int) and frames > 0, error or str(answer))
    session = proof.Session(instance, "live20")
    media = session.media_of(aiff)
    session.add(media)
    state.update(cache=proof.cache_path(session, media), media=media, session=session)
    holder = {}
    stop = threading.Event()

    def racing():
        try:
            holder["body"] = race(client, instance, stop)
        except Exception:  # noqa: BLE001 — a race that threw is a SKIPPED row
            holder["body"] = None

    racer = threading.Thread(target=racing, daemon=True)
    racer.start()
    state["since"] = instance.mark()
    try:
        result = session.op("transcribe", engine="assemblyai", place=False)
    finally:
        stop.set()
        racer.join(timeout=35)
    state.update(returned=True, cues=result.get("cues"))
    lines = instance.client_lines(state["since"])
    seen = account(ledger, rid, "20", lines)

    posts = [row for row in requests_in(lines)
             if row[0] == "POST" and row[1] == "/v2/transcript"]
    counted = (uploads_ok(lines), len(posts), len(seen))
    proof.check("20: exactly one upload answered 200, exactly one `POST /v2/transcript` "
                "line of ANY status, and exactly one transcript id — the count the ledger "
                "is reserved against", counted == (1, 1, 1), f"got {counted!r} from {lines!r}")
    proof.check("20: and that submission answered 200",
                len(posts) == 1 and posts[0][2] == "200", f"got {posts!r}")
    if counted != (1, 1, 1):
        # A count that misses stops the money: `cleanup` deletes everything
        # `account` returned and no further live reservation is made.
        proof.check("20: the counts hold, so row 21 may reserve", False,
                    "an unaccounted submit or id — no further live call this run")
        return
    proof.check("20: the media is reported under `uploaded` with `cached` empty",
                result.get("uploaded") == [media] and result.get("cached") == [],
                f"got uploaded={result.get('uploaded')!r} cached={result.get('cached')!r}")

    raw = proof.read(state["cache"])
    header = read_json(state["cache"])
    words = header.get("words") or []
    model = [row.get("model") for row in result.get("speech_model_used") or []]
    proof.check("20: `speech_model_used` is `universal-3-5-pro` in the RESULT and in the "
                "cache header — the service's own answer, not the request",
                model == ["universal-3-5-pro"]
                and header.get("speech_model_used") == "universal-3-5-pro",
                f"got {model!r} / {header.get('speech_model_used')!r}")
    rounded = math.ceil((frames or 0) / 16000.0)
    proof.check(f"20: `audio_seconds` is the extract's duration ROUNDED UP — {frames} "
                f"frames at 16 kHz is {rounded} s — and equals the header's "
                f"`audio_duration`",
                result.get("audio_seconds") == rounded
                and header.get("audio_duration") == rounded,
                f"got {result.get('audio_seconds')!r} / {header.get('audio_duration')!r}")
    want = normalise(SPEECH_TEXT)
    got = normalise(" ".join(str(one.get("text", "")) for one in words))
    proof.check(f"20: the {len(words)} words hold the fixture's {len(want)} spoken tokens, "
                "in order", bool(words) and subsequence(want, got), f"got {got!r}")
    pauses = truth_pauses(out)
    touched = touches(words, pauses)
    proof.check(f"20: this host's WAV holds two pauses ({pauses}) and NO word touches one — "
                "no tolerance, as §3 q1 measured",
                len(pauses) == 2 and touched == [], f"got {pauses!r}, touching {touched!r}")
    deletes = [row for row in requests_in(lines) if row[0] == "DELETE"]
    proof.check("20: `remote_deleted` is true, and exactly one DELETE — of the one id this "
                "run made, answered 200",
                header.get("remote_deleted") is True and len(deletes) == 1
                and deletes[0][1] == f"/v2/transcript/{seen[0]}" and deletes[0][2] == "200"
                and header.get("transcript_id") == seen[0],
                f"got {deletes!r}, header id {header.get('transcript_id')!r}")
    sentinel = client.get(seen[0])
    body = sentinel.json if isinstance(sentinel.json, dict) else {}
    proof.check(f"20: and a GET afterwards answers 200 with q6's two sentences — "
                f"`{DELETED_URL}` and “{DELETED_TEXT}”",
                sentinel.status == 200 and body.get("audio_url") == DELETED_URL
                and body.get("text") == DELETED_TEXT,
                f"got {sentinel.status}, {str(body.get('audio_url'))[:60]!r}, "
                f"{str(body.get('text'))[:60]!r}")

    span = words_span(raw)
    served = holder.get("body")
    if served is None:
        proof.skip_rows(1, "the app's DELETE won the race with the reader's own GET, so "
                           "there is no `completed` body to compare the cache file's bytes "
                           "against (row 20's provider-bytes row)")
    else:
        proof.check("20: the cache file's `words` are the PROVIDER's bytes — the span "
                    "occurs contiguously in the body the racing GET kept, and decodes "
                    "equal to its `words`",
                    span in served and json.loads(span) == json.loads(served).get("words"),
                    f"span {span[:60]!r} of {len(span)} bytes, body {len(served)} bytes")
    ledger.billed(rid, header.get("audio_duration", rounded))
    state["ok"] = True


# --------------------------------------------------------------------------
# Row 21 — the second run, from the cache


def row_twenty_one(proof, instance, ledger, state):
    print("\n21. the second run — the cache, in under a second, with no upload at all")
    rid = reserve(ledger, "21", "cached")
    session = state["session"]
    before = hashlib.sha256(proof.read(state["cache"])).hexdigest()
    since = instance.mark()
    started = time.monotonic()
    result = session.op("transcribe", engine="assemblyai", place=False)
    elapsed = time.monotonic() - started
    lines = instance.client_lines(since)
    account(ledger, rid, "21", lines)
    after = hashlib.sha256(proof.read(state["cache"])).hexdigest()
    proof.check("21: the media is reported under `cached`, with `uploaded` empty",
                result.get("cached") == [state["media"]] and result.get("uploaded") == [],
                f"got cached={result.get('cached')!r} uploaded={result.get('uploaded')!r}")
    proof.check(f"21: and it answered in {elapsed:.2f} s, under the second §5i asks for",
                elapsed < 1.0, f"got {elapsed:.3f} s")
    proof.check("21: the cues are run 1's, cue for cue",
                result.get("cues") == state.get("cues"),
                f"got {len(result.get('cues') or [])} cues, {len(state.get('cues') or [])} "
                "before")
    proof.check("21: NO upload, measured as the client saying NOTHING — zero lines of any "
                "kind, so zero `POST /v2/upload` and zero `POST /v2/transcript`",
                lines == [], f"got {lines!r}")
    proof.check("21: and the cache file is byte for byte what run 1 wrote",
                before == after and bool(before), f"{before[:12]} → {after[:12]}")
    if lines == []:
        ledger.closed(rid, "no_upload")
    row = ledger.reservations()[rid]
    proof.check("21: the ledger closes this row `no_upload`, billed nothing",
                row.get("outcome") == "no_upload" and "billed" not in row, f"got {row!r}")


# --------------------------------------------------------------------------
# Closing — the instance down, the transcripts gone, the sweep, the ledger


def close(proof, instance, client, ledger, state):
    """The order that cannot miss a line: when the MCP call did not RETURN,
    the reader is joined FIRST, so no in-flight `GET` line is lost and read as
    `unresolved`."""
    if instance is None:
        return
    stopped = False
    if not state.get("returned"):
        instance.parity()
        instance.stop()
        stopped = True
    cleanup(client, ledger, ledger.open_rows(), instance, state.get("cache"),
            state.get("since", 0))
    if not stopped:
        instance.parity()
        instance.stop()


def sweep(proof, instance, ledger, scrubber, state):
    paths = [FOLDER, proof.logs.get("L0", "")]
    if instance is not None:
        paths += [instance.log, instance.secrets]
    if state.get("session") is not None:
        paths.append(state["session"].path)
    found = leaks(scrubber, [one for one in paths if one], proof.transcript_of_the_run)
    leaked = bool(instance is not None and instance.leaked)
    proof.check("20: the key is in NOTHING this run wrote — not a captured line, not an "
                "MCP answer or refusal, not the package, not the secret folder, not the "
                f"ledger, not either instance's /tmp log (leaked {leaked}, found {found})",
                not found and not leaked)
    if instance is not None:
        proof.check("20: the pty reader ran to the end without failing",
                    not instance.reader_failed)
    owed = sorted(set(ledger.open_rows() + ledger.unresolved()))
    proof.check(f"L: the ledger closes with nothing owed — no open and no `unresolved` "
                f"reservation — at ${ledger.dollars():.4f} over "
                f"{ledger.total_seconds():.0f} planned seconds", not owed, f"owed {owed!r}")


def run(proof, binary, port_base, probe):
    """The live rows, in the one order that spends nothing it need not."""
    at = proof.passed + proof.failed
    controls(proof)
    client, scrubber = client_from_env()
    proof.live_scrubber = scrubber
    os.makedirs(FOLDER, exist_ok=True)
    ledger = Ledger(LEDGER, scrubber)

    def left():
        return max(0, LIVE_ROW_COUNT - (proof.passed + proof.failed - at))

    if client is None:
        proof.skip_rows(left(), f"{KEY_ENV} is absent (the word, and never the value)")
        return
    if not reachable("api.assemblyai.com", 443, 5):
        proof.skip_rows(left(), "no TCP connect to api.assemblyai.com:443 in 5 s")
        return
    if make_fixture() is None:
        proof.skip_rows(left(), "`say` is not on this host, and the synthetic fixture is "
                                "the ONLY file these rows may upload")
        return
    owed = sorted(set(ledger.open_rows() + ledger.unresolved()))
    if owed:
        proof.check("L: the ledger opens with nothing owed by an earlier run", False,
                    f"owed {owed!r} — a person closes these before any live call")
        proof.skip_rows(left(), "the ledger holds an owed reservation from an earlier run")
        return
    why = refusal(ledger)
    if why:
        proof.skip_rows(left(), f"the ledger gate refuses the next call: {why}")
        return

    instance = None
    state = {"since": 0, "returned": True, "session": None}
    try:
        if not dummy_arm(proof, client, binary, port_base + 3, probe, ledger):
            proof.skip_rows(left(), "the dummy arm did not hold (R6-9): a submit reached "
                                    "the wire under the dummy folder, so `cleanup` ran and "
                                    "the key WAS used \u2014 to delete what that submit made, "
                                    "and for nothing else")
            return
        instance = proof.Instance("L1", port_base + 4, None, binary, key=proof.INHERIT,
                                  live=True)
        row_twenty(proof, instance, probe, ledger, client, make_fixture(), state)
        if state.get("ok"):
            row_twenty_one(proof, instance, ledger, state)
    finally:
        close(proof, instance, client, ledger, state)
        sweep(proof, instance, ledger, scrubber, state)
        print(f"\n  the live rows made {proof.passed + proof.failed - at} checks "
              f"(LIVE_ROW_COUNT says {LIVE_ROW_COUNT})")
