#!/usr/bin/env python3
"""Road map 6, spike C0 — the runner: eight rows, one ledger, one budget.

    python3 tools/proof/cloud_spike/cloud_spike.py [--only q1,q3,…] [--remake]
            [--allow-q8-rerun] [--selftest] [--leakcheck PATH …]

Order, cheapest first: the selftest (free, no key, loopback only), then q3,
q4 and q7 (local), then q1, q6, q5, q2 and q8 (paid, in that order). A row
that needs `RC_ASSEMBLYAI_KEY` and finds none is SKIPPED BY NAME and the run
exits 2 — a skip is not a pass. Exit 0 means every requested row ran and no
reservation is open or `unresolved`; exit 1 is an instrument failure.

`--remake` deletes and rebuilds `fixtures/`, `bin/` and `bundles/` and NOTHING
else: `answers.json` and `ledger.json` sit beside them and are never rebuilt,
because the ledger is the only record of what was spent and what is owed.

`RC_CLOUD_SPIKE_WORK` names a WORK DIRECTORY (never a URL, never a base) and
exists so `--selftest` and its child run can work in a `mkdtemp` of their own.
The key itself has no such override: `aai.client_from_env` reads
`RC_ASSEMBLYAI_KEY` and always pairs it with `aai.BASE_DEFAULT`.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aai                                                          # noqa: E402
import cloud_rows                                                   # noqa: E402
import local_rows                                                   # noqa: E402
from fixtures import Fixtures                                       # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROWS = ["q1", "q2", "q3", "q4", "q5", "q6", "q7", "q8"]
PAID = {"q1", "q2", "q5", "q6", "q8"}
ORDER = ["q3", "q4", "q7", "q1", "q6", "q5", "q2", "q8"]


def work_root():
    named = os.environ.get("RC_CLOUD_SPIKE_WORK")
    if named:
        return os.path.abspath(named)
    return os.path.normpath(os.path.join(HERE, "..", "work", "cloud_spike"))


def remake(work):
    """Fixtures, binaries and bundles only. The ledger is never touched."""
    for folder in ("fixtures", "bin", "bundles"):
        shutil.rmtree(os.path.join(str(work), folder), ignore_errors=True)


def host_facts():
    def shell(command):
        try:
            return subprocess.run(command, capture_output=True, text=True,
                                  env=local_rows.child_env()).stdout.strip()
        except OSError:
            return ""
    interface = ""
    for line in shell(["route", "-n", "get", "default"]).splitlines():
        if "interface:" in line:
            interface = line.split(":", 1)[1].strip()
    kind = ""
    ports = shell(["networksetup", "-listallhardwareports"]).splitlines()
    for index, line in enumerate(ports):
        if line.strip() == f"Device: {interface}" and index > 0:
            kind = ports[index - 1].replace("Hardware Port:", "").strip()
    return {
        "macos": shell(["sw_vers", "-productVersion"]),
        "xcode": " ".join(shell(["xcodebuild", "-version"]).split()),
        "swiftc": " ".join(shell(["xcrun", "swiftc", "--version"]).split()[:4]),
        "python": sys.version.split()[0],
        # The KIND of the default route's interface — never its name, its
        # address, its SSID or the host's.
        "default_interface_kind": kind or "unknown",
    }


# ---- The run ---------------------------------------------------------------

def uploaded_name(row, label):
    if row == "q8":
        return "hour.wav"
    if row == "q2" and label.startswith("m4a"):
        return label.replace("m4a_", "speech_aac_") + ".m4a"
    if row == "q2" and label == "flac":
        return "speech.flac"
    return "speech.wav"


def spend_from(ledger):
    calls = []
    for row in sorted(ledger.reservations().values(), key=lambda r: r["at"]):
        calls.append({"row": row["row"], "label": row["label"],
                      "uploaded": uploaded_name(row["row"], row["label"]),
                      "bytes": row.get("bytes"), "audio_duration": row.get("billed"),
                      "outcome": row.get("outcome", "OPEN")})
    return {"calls": calls, "total_seconds": round(ledger.total_seconds(), 1),
            "dollars": round(ledger.dollars(), 4)}


def run(arguments):
    work = work_root()
    os.makedirs(work, exist_ok=True)
    if arguments.remake:
        remake(work)
    client, scrub = aai.client_from_env()
    ledger = aai.Ledger(os.path.join(work, "ledger.json"), aai.Scrubber(list(scrub.secrets)))

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
    answers = {"date": started, "host": host_facts(), "rows": {},
               "truth_pauses": [], "notes": []}
    say(f"C0 cloud spike — {started} — key {'present' if client else 'absent'}")
    say(f"host: {json.dumps(answers['host'], sort_keys=True)}")
    list_match = ((previous.get("rows", {}).get("q1", {}).get("measured") or {})
                  .get("list_match", "absent"))
    if client:
        cloud_rows.settle(client, ledger, scrub, list_match, say)

    fixtures = Fixtures(work, HERE, say)
    also_carried = {}

    def save(measured):
        answers["rows"]["q7"] = {"state": "run", "reason": None, "measured": measured}
        write_answers(answers_path, answers, scrub, ledger)

    for row in wanted:
        say(f"\n{row} —")
        if row in PAID and client is None:
            answers["rows"][row] = {"state": "skipped", "measured": {},
                                    "reason": f"{aai.KEY_ENV} is not set"}
            say(f"  {row} SKIPPED — {aai.KEY_ENV} is not set")
            continue
        if row == "q8" and ledger.ran("q8") and not arguments.allow_q8_rerun:
            # An hour of audio is not bought twice by accident. A q8 that
            # already ran is CARRIED FORWARD with the date it was measured —
            # it ran, so the run is not incomplete for it; a q8 that never
            # answered is a skip, and the run is.
            before = (previous.get("rows") or {}).get("q8") or {}
            when = (((previous.get("carriedForward") or {}).get("dates") or {})
                    .get("q8", previous.get("date")))
            if before.get("state") == "run":
                answers["rows"][row] = dict(before)
                answers["rows"][row]["reason"] = (
                    f"carried forward from {when}: the ledger has already spent an hour "
                    "on q8 (--allow-q8-rerun to repeat it)")
                also_carried[row] = when
                say(f"  q8 CARRIED FORWARD from {when} — the ledger has already spent its hour")
            else:
                answers["rows"][row] = {
                    "state": "skipped", "measured": {},
                    "reason": "q8 has run in this ledger; --allow-q8-rerun to repeat"}
                say("  q8 SKIPPED — it has run in this ledger (--allow-q8-rerun to repeat)")
            continue
        try:
            answers["rows"][row] = one_row(row, fixtures, client, ledger, scrub, say, save)
        except aai.BudgetError as error:
            answers["rows"][row] = {"state": "not_run", "measured": {},
                                    "reason": scrub.clean(str(error))}
            say(f"  {row} NOT RUN — {scrub.clean(str(error))}")
        except (aai.TransportError, RuntimeError, OSError) as error:
            answers["rows"][row] = {"state": "not_run", "measured": {},
                                    "reason": scrub.clean(f"{type(error).__name__}: {error}")}
            say(f"  {row} NOT RUN — {scrub.clean(str(error))}")
        answers["truth_pauses"] = fixtures.pauses or answers["truth_pauses"]
        answers["notes"] = fixtures.notes
        write_answers(answers_path, answers, scrub, ledger)

    if client:
        cloud_rows.settle(client, ledger, scrub,
                          (answers["rows"].get("q1", {}).get("measured") or {})
                          .get("list_match", list_match), say)
    carry(answers, previous, wanted, also_carried)
    write_answers(answers_path, answers, scrub, ledger)
    return summary(answers, ledger, say, answers_path)


def one_row(row, fixtures, client, ledger, scrub, say, save):
    if row == "q3":
        return local_rows.q3(fixtures.work, HERE)
    fixtures.build()
    if row == "q4":
        return local_rows.q4(fixtures.work, fixtures.extract)
    if row == "q7":
        return local_rows.q7(fixtures.work, HERE, save)
    if row == "q1":
        return cloud_rows.q1(client, ledger, scrub, fixtures.work, fixtures.seconds,
                             fixtures.pauses, say)
    if row == "q2":
        formats = fixtures.smaller_formats()
        answer = cloud_rows.q2(client, ledger, scrub, fixtures.work, fixtures.seconds,
                               formats, say)
        answer["measured"]["local"] = local_deltas(fixtures, formats)
        return answer
    if row == "q5":
        return cloud_rows.q5(client, ledger, scrub, fixtures.work, fixtures.seconds, say)
    if row == "q6":
        return cloud_rows.q6(client, ledger, scrub, fixtures.work, fixtures.seconds, say)
    fixtures.hour()
    return cloud_rows.q8(client, ledger, scrub, fixtures.work, fixtures.loop_seconds, say)


def local_deltas(fixtures, formats):
    """What the CONTAINER holds: AVFoundation's lag, and ffmpeg's with the
    edit list ignored — which is what an encoder's priming delay looks like
    to a decoder that does not read one."""
    rows = {"aac_refusals": getattr(fixtures, "aac_refusals", {}),
            "flac_write": getattr(fixtures, "flac", {}), "files": {}}
    for label, path in formats + [("wav", fixtures.path("speech.wav"))]:
        lag = local_rows.spoken(fixtures.run(
            [fixtures.extract, "lag", fixtures.path("speech.wav"), path, "40000"]))
        raw = os.path.join(fixtures.work, "fixtures", f"{label}.noeditlist.wav")
        fixtures.run(["ffmpeg", "-y", "-v", "error", "-ignore_editlist", "1", "-i", path,
                      "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", raw])
        raw_lag = local_rows.spoken(fixtures.run(
            [fixtures.extract, "lag", fixtures.path("speech.wav"), raw, "40000"])) \
            if os.path.exists(raw) else {"ok": False, "error": "ffmpeg wrote nothing"}
        rows["files"][label] = {
            "bytes": os.path.getsize(path) if os.path.exists(path) else None,
            "avfoundation_lag": lag,
            "ignore_editlist_lag": raw_lag,
            "tracks": local_rows.spoken(fixtures.run([fixtures.extract, "tracks", path])),
        }
    return rows


def carry(answers, previous, wanted, also_carried=None):
    rows = (previous or {}).get("rows") or {}
    dates = ((previous or {}).get("carriedForward") or {}).get("dates") or {}
    carried = dict(also_carried or {})
    for row in ROWS:
        if row not in wanted and row in rows:
            answers["rows"][row] = rows[row]
            carried[row] = dates.get(row, previous.get("date"))
    if carried:
        answers["carriedForward"] = {"rows": sorted(carried), "dates": carried}
        answers["truth_pauses"] = answers["truth_pauses"] or (previous.get("truth_pauses") or [])


def write_answers(path, answers, scrub, ledger):
    answers["spend"] = spend_from(ledger)
    text = json.dumps(answers, indent=2, sort_keys=True)
    scrub.assert_clean(text)
    with open(path, "w") as handle:
        handle.write(text)


def summary(answers, ledger, say, path):
    say("")
    owed = []
    for row in ROWS:
        state = (answers["rows"].get(row) or {}).get("state", "not_run")
        reason = (answers["rows"].get(row) or {}).get("reason")
        say(f"  {row}: {state}" + (f" — {reason}" if reason else ""))
        if state != "run":
            owed.append(f"{row} {state}: {reason or 'no reason recorded'}")
    for rid in ledger.open_rows():
        owed.append(f"reservation {rid} is still open")
    for rid in ledger.unresolved():
        owed.append(f"reservation {rid} is unresolved")
    spend = answers["spend"]
    say(f"spend: {len(spend['calls'])} calls, {spend['total_seconds']} s of audio, "
        f"${spend['dollars']:.4f} of the ${aai.BUDGET_DOLLARS:.2f} budget")
    say(f"answers in {path}")
    if owed:
        say("SPIKE INCOMPLETE")
        for line in owed:
            say(f"  owed: {line}")
        return 2
    say("every row ran; every reservation is closed")
    return 0


# ---- --leakcheck -----------------------------------------------------------

def leakcheck(paths):
    """In process, names only: never the secret, never the URL, never a line."""
    work = work_root()
    ledger_path = os.path.join(work, "ledger.json")
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
            print(f"  LEAK in {name}")
        return 1
    print("clean")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--only", help="rows to run, e.g. q1,q3")
    parser.add_argument("--remake", action="store_true")
    parser.add_argument("--allow-q8-rerun", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--leakcheck", nargs="+")
    arguments = parser.parse_args()
    if arguments.leakcheck:
        return leakcheck(arguments.leakcheck)
    if arguments.selftest:
        import selftest
        return selftest.run()
    if arguments.only:
        arguments.only = [q.strip() for q in arguments.only.split(",") if q.strip()]
        unknown = [q for q in arguments.only if q not in ROWS]
        if unknown:
            print(f"unknown rows: {unknown}")
            return 1
    return run(arguments)


if __name__ == "__main__":
    sys.exit(main())
