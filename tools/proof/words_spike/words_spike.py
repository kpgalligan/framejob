#!/usr/bin/env python3
"""Road map 8, spike W0 — the runner: seven rows, one ledger, one budget.

    python3 tools/proof/words_spike/words_spike.py [--only q1,q4,…] [--remake]
            [--leakcheck PATH …]

Order, cheapest first: q4 and q5 (local, no key, no network), then q6's fetch
and registry reading, then q3 and q1 (local, the Speech framework), then q7
(the scratch tree and its builds) with q6's picture half behind it, and last
q2, the only row that spends money. A row that needs `RC_ASSEMBLYAI_KEY` and
finds none is SKIPPED BY NAME and the run exits 2 — a skip is not a pass.

Exit 0 means every requested row ran and no reservation is open or
`unresolved`; exit 2 names what is owed under `SPIKE INCOMPLETE`; exit 1 is an
instrument that failed — a probe that would not build, a control that did not
hold, a face that resolved to the system fallback.

`--remake` deletes and rebuilds `fixtures/`, `bin/`, the per-row folders and
the scratch tree, and NOTHING else: `answers.json` and `ledger.json` sit
beside them and are never rebuilt, because the ledger is the only record of
what was spent and what is owed.

**This spike carries its own `--leakcheck`.** `cloud_spike.py`'s reads
`work/cloud_spike/ledger.json` and exempts only that path
(`cloud_spike.py:43-47, 290-300`), so calling it from here would check the
wrong ledger's URLs and report this one's as a leak. Nothing in
`cloud_spike/` is edited.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.normpath(os.path.join(HERE, ".."))
CLOUD = os.path.join(PROOF, "cloud_spike")
sys.path.insert(0, HERE)
for folder in (PROOF, CLOUD):
    if folder not in sys.path:
        sys.path.append(folder)

import aai                                                           # noqa: E402
import cloud_rows                                                    # noqa: E402
import local_rows                                                    # noqa: E402
import scratch_rows                                                  # noqa: E402
import speech_rows                                                   # noqa: E402
import text_rows                                                     # noqa: E402
from fixtures import Fixtures                                        # noqa: E402
import cloud_live_ledger                                             # noqa: E402

ROWS = ["q1", "q2", "q3", "q4", "q5", "q6", "q7"]
PAID = {"q2"}
ORDER = ["q4", "q5", "q6", "q3", "q1", "q7", "q2"]
NEEDS_FIXTURES = {"q1", "q2"}


def work_root():
    named = os.environ.get("RC_WORDS_SPIKE_WORK")
    if named:
        return os.path.abspath(named)
    return os.path.normpath(os.path.join(HERE, "..", "work", "words_spike"))


def remake(work):
    """Fixtures, binaries, per-row folders and the scratch tree only. The
    ledger is never touched."""
    for folder in ("fixtures", "bin", "bundles", "q4", "q5", "q6", "q7", "scratch"):
        shutil.rmtree(os.path.join(str(work), folder), ignore_errors=True)


def host_facts():
    def shell(command):
        try:
            return subprocess.run(command, capture_output=True, text=True,
                                  env=local_rows.child_env()).stdout.strip()
        except OSError:
            return ""
    return {
        "macos": shell(["sw_vers", "-productVersion"]),
        "build": shell(["sw_vers", "-buildVersion"]),
        "hardware": shell(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "xcode": " ".join(shell(["xcodebuild", "-version"]).split()),
        "swiftc": " ".join(shell(["xcrun", "swiftc", "--version"]).split()[:4]),
        "rustc": shell(["rustc", "--version"]),
        "ffmpeg": shell(["ffmpeg", "-version"]).splitlines()[:1],
        "python": sys.version.split()[0],
    }


# ---- The run ---------------------------------------------------------------

def spend_from(ledger):
    calls = []
    for row in sorted(ledger.reservations().values(), key=lambda r: r["at"]):
        calls.append({"row": row["row"], "label": row["label"],
                      "uploaded": row["label"] + ".wav",
                      "bytes": row.get("bytes"), "audio_duration": row.get("billed"),
                      "outcome": row.get("outcome", "OPEN")})
    return {"calls": calls, "total_seconds": round(ledger.total_seconds(), 1),
            "dollars": round(ledger.dollars(), 4)}


def write_answers(path, answers, scrub, ledger):
    answers["spend"] = spend_from(ledger)
    # Each row's `measured` ALSO at the top level under its own name. `rows`
    # is the record — state, reason and measurement together, `cloud_spike`'s
    # shape — and this is the short path a one-line check reads, so
    # `answers["q5"]["raster"]` is the same object as
    # `answers["rows"]["q5"]["measured"]["raster"]`.
    for row in ROWS:
        if row in answers["rows"]:
            answers[row] = answers["rows"][row].get("measured") or {}
    text = json.dumps(answers, indent=2, sort_keys=True)
    scrub.assert_clean(text)
    with open(path, "w") as handle:
        handle.write(text)


def settle(client, ledger, scrub, say):
    """The first and last act of every run that has a key: what this spike
    created and did not delete, deleted."""
    counts = {}
    for rid, transcript_id in ledger.undeleted():
        answer = cloud_rows.record_delete(ledger, rid, client.delete(transcript_id))
        counts[answer] = counts.get(answer, 0) + 1
    for rid in ledger.unsent():
        ledger.closed(rid, "upload_only")
        counts["upload_only"] = counts.get("upload_only", 0) + 1
    for rid, url, _ in ledger.lost():
        status, ids = client.find_own({url})
        if ids:
            # Closed `deleted` only when every DELETE answered 2xx; else left
            # in `lost()` for the next settle (#170).
            answer = cloud_rows.delete_found(client, ledger, rid, ids)
            counts[answer] = counts.get(answer, 0) + 1
        else:
            ledger.closed(rid, "unresolved", status)
            counts["unresolved"] = counts.get("unresolved", 0) + 1
    say("settled: " + (", ".join(f"{k} {v}" for k, v in sorted(counts.items()))
                       or "nothing open"))
    return counts


def carry(answers, previous, wanted):
    rows = (previous or {}).get("rows") or {}
    dates = ((previous or {}).get("carriedForward") or {}).get("dates") or {}
    carried = {}
    for row in ROWS:
        if row not in wanted and row in rows:
            answers["rows"][row] = rows[row]
            carried[row] = dates.get(row, previous.get("date"))
    if carried:
        answers["carriedForward"] = {"rows": sorted(carried), "dates": carried}


def scratch_binary(work):
    """q7's binary from a previous invocation, for a `--only q6` that has no
    q7 beside it."""
    path = os.path.join(
        scratch_rows.scratch_root(work), "w0-tree", "build", "Build", "Products",
        "Release", "Frame Job.app", "Contents", "MacOS", "Frame Job")
    return path if os.path.exists(path) else None


def run(arguments):
    work = work_root()
    os.makedirs(work, exist_ok=True)
    if arguments.remake:
        remake(work)
    client, scrub = aai.client_from_env()
    ledger = cloud_live_ledger.spike_ledger(os.path.join(work, "ledger.json"),
                                            aai.Scrubber(list(scrub.secrets)),
                                            client is not None, "words_spike")

    def say(text):
        print(scrub.clean(str(text)), flush=True)

    wanted = [q for q in ORDER if q in (arguments.only or ROWS)]
    started = time.strftime("%Y-%m-%d")
    answers_path = os.path.join(work, "answers.json")
    try:
        with open(answers_path) as handle:
            previous = json.load(handle)
    except (OSError, ValueError):
        previous = {}
    answers = {"date": started, "host": host_facts(), "rows": {}, "notes": [],
               "fixtures": {}}
    say(f"W0 word-captions spike — {started} — "
        f"key {'present' if client else 'absent'}")
    say(f"host: {json.dumps(answers['host'], sort_keys=True)}")
    if client:
        settle(client, ledger, scrub, say)

    fixtures = Fixtures(work, say)
    built = False
    for row in wanted:
        say(f"\n{row} —")
        if row in PAID and client is None:
            answers["rows"][row] = {"state": "skipped", "measured": {},
                                    "reason": f"{aai.KEY_ENV} is not set"}
            say(f"  {row} SKIPPED — {aai.KEY_ENV} is not set")
            continue
        try:
            if row in NEEDS_FIXTURES and not built:
                fixtures.build()
                built = True
                answers["fixtures"] = {
                    "seconds": fixtures.seconds, "truth_pauses": fixtures.pauses,
                    "ten": fixtures.ten, "isolated_words": fixtures.isolated,
                    "notes": fixtures.notes}
            answers["rows"][row] = one_row(row, work, fixtures, client, ledger, scrub, say,
                                           answers)
        except aai.BudgetError as error:
            answers["rows"][row] = {"state": "not_run", "measured": {},
                                    "reason": scrub.clean(str(error))}
            say(f"  {row} NOT RUN — {scrub.clean(str(error))}")
        except (aai.TransportError, RuntimeError, OSError, ValueError) as error:
            answers["rows"][row] = {
                "state": "not_run", "measured": {},
                "reason": scrub.clean(f"{type(error).__name__}: {error}")}
            say(f"  {row} NOT RUN — {scrub.clean(str(error))}")
        answers["notes"] = fixtures.notes
        write_answers(answers_path, answers, scrub, ledger)

    # q6's PICTURE half rides behind q7, because the app it drives is the one
    # q7's scratch copy built. A `--only q6` finds the binary a previous q7
    # left, or records the half as not run and says why.
    if "q6" in wanted and (answers["rows"].get("q6") or {}).get("state") in ("run", "failed"):
        binary = ((answers["rows"].get("q7") or {}).get("measured") or {}).get("binary") \
            or scratch_binary(work)
        picture = scratch_rows.q6_picture(work, binary, say)
        answers["rows"]["q6"]["measured"]["picture"] = picture
        if picture["state"] != "run" and answers["rows"]["q6"]["state"] == "run":
            answers["rows"]["q6"]["state"] = picture["state"]
            answers["rows"]["q6"]["reason"] = "the picture half: " + (picture["reason"] or "")
        write_answers(answers_path, answers, scrub, ledger)

    if client:
        settle(client, ledger, scrub, say)
    carry(answers, previous, wanted)
    write_answers(answers_path, answers, scrub, ledger)
    return summary(answers, ledger, say, answers_path)


def one_row(row, work, fixtures, client, ledger, scrub, say, answers):
    if row == "q4":
        return text_rows.q4(work, say)
    if row == "q5":
        return text_rows.q5(work, say)
    if row == "q6":
        return text_rows.q6_registration(work, say)
    if row == "q3":
        return speech_rows.q3(work, say)
    if row == "q1":
        return speech_rows.q1(work, fixtures, say)
    if row == "q7":
        return scratch_rows.q7(work, say)
    return speech_rows.q2(work, fixtures, client, ledger, scrub, say)


def summary(answers, ledger, say, path):
    say("")
    owed = []
    broken = []
    for row in ROWS:
        state = (answers["rows"].get(row) or {}).get("state", "not_run")
        reason = (answers["rows"].get(row) or {}).get("reason")
        say(f"  {row}: {state}" + (f" — {reason}" if reason else ""))
        if state == "failed":
            broken.append(f"{row} failed: {reason or 'no reason recorded'}")
        elif state != "run":
            owed.append(f"{row} {state}: {reason or 'no reason recorded'}")
    for rid in ledger.open_rows():
        owed.append(f"reservation {rid} is still open")
    for rid in ledger.unresolved():
        owed.append(f"reservation {rid} is unresolved")
    spend = answers["spend"]
    say(f"spend: {len(spend['calls'])} calls, {spend['total_seconds']} s of audio, "
        f"${spend['dollars']:.4f} of the ${aai.BUDGET_DOLLARS:.2f} budget")
    say(f"answers in {path}")
    if owed or broken:
        say("SPIKE INCOMPLETE")
        for line in broken + owed:
            say(f"  owed: {line}")
        return 1 if broken else 2
    say("every row ran; every reservation is closed")
    return 0


# ---- --leakcheck -----------------------------------------------------------

def leakcheck(paths):
    """In process, names only: never the secret, never the URL, never a line.

    `cloud_spike.py:290-320`'s shape over THIS spike's ledger, which is also
    the one path exempted — the upload URLs live there and nowhere else.
    """
    ledger_path = os.path.join(work_root(), "ledger.json")
    secrets = []
    key = os.environ.get(aai.KEY_ENV)
    if key:
        secrets.append(key)
    try:
        with open(ledger_path) as handle:
            for event in json.load(handle)["events"]:
                if event.get("upload_url"):
                    secrets.append(event["upload_url"])
    except (OSError, ValueError, KeyError, TypeError):
        pass
    found = []
    for root in paths:
        walked = [root] if os.path.isfile(root) else [
            os.path.join(folder, name)
            for folder, _, names in os.walk(root) for name in names]
        for name in walked:
            if os.path.abspath(name) == os.path.abspath(ledger_path):
                continue
            try:
                with open(name, "rb") as handle:
                    blob = handle.read()
            except OSError:
                continue
            if any(secret.encode("utf-8") in blob for secret in secrets):
                found.append(name)
    print(f"leakcheck: {len(secrets)} secrets, {len(paths)} roots")
    if found:
        for name in found:
            print(f"  LEAK {name}")
        return 1
    print("clean")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--only", help="rows to run, e.g. q4,q5")
    parser.add_argument("--remake", action="store_true")
    parser.add_argument("--leakcheck", nargs="+")
    arguments = parser.parse_args()
    if arguments.leakcheck:
        return leakcheck(arguments.leakcheck)
    if arguments.only:
        arguments.only = [q.strip() for q in arguments.only.split(",") if q.strip()]
        unknown = [q for q in arguments.only if q not in ROWS]
        if unknown:
            print(f"unknown rows: {unknown}")
            return 1
    return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
