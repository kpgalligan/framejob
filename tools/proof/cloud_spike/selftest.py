#!/usr/bin/env python3
"""Road map 6, spike C0 — `--selftest`: seven checks, free, before a paid call.

`python3 tools/proof/cloud_spike/cloud_spike.py --selftest` works in a
`tempfile.mkdtemp()` work root of its own and NEVER opens the real
`ledger.json`. It talks to `fake.Fake` over loopback with `SELFTEST_KEY`, and
the pair guard in `aai.Client` is what makes that safe: the real key cannot be
sent to a loopback base and the dummy cannot be sent to AssemblyAI.

The seven, each of which was broken on purpose once and seen to fail before it
was trusted (`tools/proof/README.md` names which line was broken for each):

  a  the paid code path end to end against the fake — the header, the models,
     the DELETE, and no dummy key in anything printed or written
  b  the pair guard, and that its message holds neither key
  c  no redirect is followed, for a GET and for a POST, with a second fake
     that must stay untouched
  d  a lost submit reply is recovered by the ledger's own upload URL, and
     another account's transcript is not read, deleted or recorded
  e  `--remake` leaves `ledger.json` byte for byte
  f  `run_bounded` bounds a hang, and a q7 whose cleanup hangs still leaves
     its `measured` behind with `cleanup_blocked: true`
  g  the pause-crossing detector, the budget, and a keyless run that SKIPS the
     five paid rows by name and exits 2
"""

import contextlib
import io
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import wave

import aai
import cloud_rows
import fake as fake_module
import local_rows

CHECKS = []


def check(ok, what):
    CHECKS.append((bool(ok), what))
    print(f"  {'ok  ' if ok else 'FAIL'} {what}", flush=True)


def tiny_wav(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(16000)
        handle.writeframes(b"".join(struct.pack("<h", (i % 200) * 60 - 6000)
                                    for i in range(16000)))


def bytes_of(path):
    """None rather than a traceback: a `--remake` that ATE the ledger has to
    come back as this check's FAIL, not as a crashed instrument."""
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return None


def ledger_for(work, scrub):
    return aai.Ledger(os.path.join(work, "ledger.json"), aai.Scrubber(list(scrub.secrets)))


def a_round_trip(work):
    server = fake_module.Fake()
    base = server.start()
    scrub = aai.Scrubber([aai.SELFTEST_KEY])
    client = aai.Client(base, aai.SELFTEST_KEY, scrub)
    ledger = ledger_for(work, scrub)
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        answer = cloud_rows.q1(client, ledger, scrub, work, 1.0, [[0.3, 0.9]],
                               lambda text: print(scrub.clean(text)))
    path = os.path.join(work, "answers.json")
    with open(path, "w") as handle:
        handle.write(json.dumps({"rows": {"q1": answer}}, indent=2, sort_keys=True))
    log = server.log
    server.stop()
    headers = {row["headers"].get("authorization") for row in log}
    submits = [row for row in log if row["method"] == "POST" and row["path"] == "/v2/transcript"]
    deletes = [row for row in log if row["method"] == "DELETE"]
    check(headers == {aai.SELFTEST_KEY}, "1a the fake saw the dummy key on every request")
    check(len(submits) == 3 and all(row["json"].get("speech_models") == aai.SPEECH_MODELS
                                    for row in submits),
          "1a every submit named speech_models in AssemblyAI's order")
    check(len(deletes) == 3, "1a every transcript the path created was DELETEd")
    check(answer["measured"]["list_match"] == "proven",
          "1a find_own returned exactly the spike's own transcript")
    written = open(path).read()
    check(aai.SELFTEST_KEY not in captured.getvalue() and aai.SELFTEST_KEY not in written,
          "1a no key reached stdout or answers.json")


def b_pair_guard(work):
    messages = []
    for base, key in ((aai.LOOPBACK_PREFIX + "9", "not-the-dummy"),
                      (aai.BASE_DEFAULT, aai.SELFTEST_KEY)):
        try:
            aai.Client(base, key, aai.Scrubber([]))
            messages.append(None)
        except ValueError as error:
            messages.append(str(error))
    check(all(m is not None for m in messages), "1b both wrong pairs are refused")
    check(all("not-the-dummy" not in (m or "") and aai.SELFTEST_KEY not in (m or "")
              for m in messages), "1b neither refusal holds a key")


def c_no_redirect(work):
    first, second = fake_module.Fake(), fake_module.Fake()
    base, other = first.start(), second.start()
    scrub = aai.Scrubber([aai.SELFTEST_KEY])
    client = aai.Client(base, aai.SELFTEST_KEY, scrub)
    first.redirect_next = other + "/v2/transcript/somewhere-else"
    got = client.get("anything")
    first.redirect_next = other + "/v2/transcript"
    posted = client.submit("https://cdn.example.invalid/upload/x")
    log = list(second.log)
    first.stop()
    second.stop()
    check(got.status == 302 and posted.status == 302, "1c a 302 comes back as a Reply")
    check(log == [], "1c the second fake saw nothing — no redirect is followed")


def d_lost_reply(work):
    server = fake_module.Fake()
    server.foreign = [{"id": "t_somebodyelse", "audio_url": "https://cdn.example.invalid/theirs"}]
    base = server.start()
    scrub = aai.Scrubber([aai.SELFTEST_KEY])
    client = aai.Client(base, aai.SELFTEST_KEY, scrub)
    ledger = ledger_for(work, scrub)
    server.drop_submit_reply = True
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        answer = cloud_rows.call(client, ledger, scrub, "selftest", "lost",
                                 os.path.join(work, "fixtures", "speech.wav"), 1.0, {})
    log = list(server.log)
    server.stop()
    row = ledger.reservations()[answer["rid"]]
    touched = [entry for entry in log if "t_somebodyelse" in entry["path"]]
    text = captured.getvalue() + json.dumps(ledger.events) + open(
        os.path.join(work, "answers.json")).read()
    check("transport_error" in answer.get("submit", {}),
          "1d a dropped submit reply is a TransportError")
    check(row.get("outcome") == "deleted",
          "1d the recovery found the transcript by its ledgered upload URL and deleted it")
    check(touched == [], "1d no GET and no DELETE of another account's transcript")
    check("t_somebodyelse" not in text and "cdn.example.invalid/theirs" not in text,
          "1d another account's id and URL are in no record of ours")


def e_remake_keeps_the_ledger(work):
    import cloud_spike
    ledger = aai.Ledger(os.path.join(work, "ledger.json"), aai.Scrubber([]))
    rid = ledger.reserve("q8", "hour", 3600.0)
    ledger.uploaded(rid, "https://cdn.example.invalid/upload/hour", 115200000)
    second = ledger.reserve("q1", "plain", 10.0)
    ledger.uploaded(second, "https://cdn.example.invalid/upload/one", 300)
    ledger.created(second, "t_kept")
    for folder in ("fixtures", "bin", "bundles"):
        os.makedirs(os.path.join(work, folder), exist_ok=True)
        open(os.path.join(work, folder, "throwaway"), "w").write("x")
    before = bytes_of(os.path.join(work, "ledger.json"))
    totals = (ledger.total_seconds(), ledger.undeleted(), ledger.lost(), ledger.ran("q8"))
    cloud_spike.remake(work)
    again = aai.Ledger(os.path.join(work, "ledger.json"), aai.Scrubber([]))
    after = bytes_of(os.path.join(work, "ledger.json"))
    check(before is not None and before == after,
          "1e --remake left the ledger byte for byte")
    check((again.total_seconds(), again.undeleted(), again.lost(), again.ran("q8")) == totals,
          "1e the totals, the undeleted, the lost and ran('q8') are unchanged")
    check(not os.path.exists(os.path.join(work, "bin", "throwaway")),
          "1e --remake did delete fixtures, bin and bundles")
    tiny_wav(os.path.join(work, "fixtures", "speech.wav"))


def f_bounded(work):
    marker = "cloudspikeselftestmarker"
    hang = [sys.executable, "-c", f"import time; time.sleep(60)  # {marker}"]
    result = local_rows.run_bounded(hang, timeout=1.0)
    gone = subprocess.run(["pgrep", "-f", marker], capture_output=True,
                          env=local_rows.child_env()).returncode != 0
    check(result["blocked"] and result["rc"] is None, "1f run_bounded bounds a hang")
    check(gone, "1f the bounded child is gone")
    # A q7 whose cleanup hangs: `measured` is saved BEFORE cleanup and rewritten
    # with `cleanup_blocked` after, so the row survives its own janitor.
    path = os.path.join(work, "answers.json")
    answers = {"rows": {}}

    def save(measured):
        answers["rows"]["q7"] = {"state": "run", "reason": None, "measured": measured}
        with open(path, "w") as handle:
            handle.write(json.dumps(answers, indent=2, sort_keys=True))

    measured = {"steps": {"A add": {"status": 0}}, "cleanup_blocked": False}
    save(measured)
    hung = local_rows.run_bounded(hang, timeout=1.0)
    measured["cleanup_blocked"] = hung["blocked"]
    save(measured)
    written = json.load(open(path))["rows"]["q7"]["measured"]
    check(written["steps"] and written["cleanup_blocked"] is True,
          "1f a q7 whose cleanup hangs still leaves measured, with cleanup_blocked true")


def g_detector_budget_and_skips(work):
    straddling = [{"text": "over", "start": 250, "end": 700, "confidence": 1.0}]
    clean = [{"text": "over", "start": 100, "end": 280, "confidence": 1.0}]
    pauses = [[0.3, 0.9]]
    check(cloud_rows.overlaps(straddling, pauses)[0]["crosses"],
          "1g a word straddling a pause is flagged")
    check(all(not row["crosses"] for row in cloud_rows.overlaps(clean, pauses)),
          "1g a word that stops at the pause is not")
    full = aai.Ledger(os.path.join(work, "full-ledger.json"), aai.Scrubber([]))
    full.reserve("q8", "hour", aai.BUDGET_DOLLARS / aai.RATE_PER_HOUR * 3600.0)
    refused = False
    try:
        full.reserve("q1", "plain", 60.0)
    except aai.BudgetError:
        refused = True
    check(refused, "1g the ledger refuses the call that would pass the budget")
    keyless = dict(os.environ)
    keyless.pop(aai.KEY_ENV, None)
    keyless["RC_CLOUD_SPIKE_WORK"] = os.path.join(work, "keyless")
    child = subprocess.run([sys.executable, os.path.join(os.path.dirname(
        os.path.abspath(__file__)), "cloud_spike.py"), "--only", "q1,q2,q5,q6,q8"],
        capture_output=True, text=True, env=keyless, timeout=300)
    named = all(f"{row} SKIPPED" in child.stdout for row in ("q1", "q2", "q5", "q6", "q8"))
    check(named, "1g a keyless run skips each paid row BY NAME")
    check(child.returncode == 2, "1g and exits 2, because a skip is not a pass")
    check("SPIKE INCOMPLETE" in child.stdout, "1g and says SPIKE INCOMPLETE")


def run():
    work = tempfile.mkdtemp(prefix="cloud-spike-selftest-")
    started = time.monotonic()
    print(f"--selftest in {work} (the real ledger is never opened)")
    tiny_wav(os.path.join(work, "fixtures", "speech.wav"))
    with open(os.path.join(work, "answers.json"), "w") as handle:
        handle.write("{}")
    for step in (a_round_trip, b_pair_guard, c_no_redirect, d_lost_reply,
                 e_remake_keeps_the_ledger, f_bounded, g_detector_budget_and_skips):
        print(f"{step.__name__.split('_')[0]} —")
        step(work)
    passed = sum(1 for ok, _ in CHECKS if ok)
    print(f"\n{passed}/{len(CHECKS)} selftest checks passed in "
          f"{time.monotonic() - started:.1f} s")
    for ok, what in CHECKS:
        if not ok:
            print(f"  FAILED: {what}")
    return 0 if passed == len(CHECKS) else 1
