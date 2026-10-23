#!/usr/bin/env python3
"""Road map "cut-by-transcript", CT-0 — the filler spike: does the on-device
engine (`SpeechEngine`, the app's own) report fillers at all?

    python3 tools/proof/filler_spike/filler_spike.py [--remake] [--no-owner]
    python3 tools/proof/filler_spike/filler_spike.py --selftest [--mutant keep-punctuation|replaced-as-kept|o2-ignored]

Rows: f1 (eight scripted fillers), f2 (the same with 300 ms of silence around
each), f3 (the control: the fillers and their commas removed), o1 (the owner's
one real recording, counts only), o2 (the owner's own reading of `O2_SCRIPT`,
eight scripted fillers, from `tools/proof/media/filler-sample/`; skipped by
name while that folder holds no file). The answers go to
`tools/proof/work/filler_spike/answers.json` and into the road map's CT-0
record (`archive/cut-by-transcript.md`), never into this directory.

Exit 0: every row ran. Exit 2, `SPIKE INCOMPLETE`: a row did not run (named,
with its reason). Exit 1: an instrument failed (the probe would not build or
crashed or ran out of time, the f3 control did not hold, o2 is not a reading
of its script, a selftest row failed). `answers.json` is
written on 0 and 2. Nothing here costs money or touches the network.
"""

import argparse
import datetime
import difflib
import json
import os
import platform
import shutil
import string
import subprocess
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/filler_spike"
PROBE = HERE / "filler_spike_probe.swift"
OWNER = ROOT / "tools/proof/media/owner-sync/record.aifc"
SAMPLE = ROOT / "tools/proof/media/filler-sample"  # o2: the one file in it, any format AVFoundation reads
FILE_BOUND = 900  # seconds, the probe's own bound on each file (`filler_spike_probe.swift`)

F1_TEXT = ("So, um, I was thinking, uh, that we could, um, start the meeting early. "
           "Uh, well, er, maybe not. Hmm, let me, um, check the, uh, calendar first.")
SCRIPTED = 8
# o2's script: the owner reads it aloud, naturally, fillers and all (README,
# "Recording the owner's sample"). Eight scripted fillers: um 3, uh 3, er 2.
O2_SCRIPT = ("Okay, so, um, this is a short test recording for the filler spike. "
             "I'm going to, uh, read a few sentences out loud. The weather today is, um, "
             "pretty nice, I think. Er, I had coffee this morning and, uh, then I went for "
             "a walk. Um, after that I sat down to, uh, work on the editor for a while. "
             "And, er, that's about it.")
FILLERS = {"um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "hm", "mm", "mhm", "uh-huh"}
STRIP = string.punctuation + "“”‘’…—–«»"
MUTANT = None  # --mutant: "keep-punctuation", "replaced-as-kept" or "o2-ignored"


# ---- the classifier ---------------------------------------------------------


def normalize(token):
    token = token.lower()
    return token if MUTANT == "keep-punctuation" else token.strip(STRIP)


def tokens(text):
    return [t for t in (normalize(w) for w in text.split()) if t]


def recognised(runs):
    return [t for run in runs for t in tokens(run["text"])]


def filler_tally(words):
    found = Counter(w for w in words if w in FILLERS)
    return sum(found.values()), dict(sorted(found.items()))


def classify(script, heard):
    """Each scripted filler, aligned script → recognised: `kept`, `dropped` or
    `replaced:<word>`."""
    opcodes = difflib.SequenceMatcher(None, script, heard, autojunk=False).get_opcodes()
    answer = []
    for index, word in enumerate(script):
        if word not in FILLERS:
            continue
        disposition = "dropped"
        for tag, i1, i2, j1, j2 in opcodes:
            if not i1 <= index < i2:
                continue
            if tag == "equal":
                disposition = "kept"
            elif tag == "replace":
                j = j1 + (index - i1)
                if MUTANT == "replaced-as-kept":
                    disposition = "kept"
                elif j < j2:
                    disposition = f"replaced:{heard[j]}"
            break
        answer.append({"index": index, "filler": word, "disposition": disposition})
    return answer


def recognised_share(script, heard):
    matcher = difflib.SequenceMatcher(None, script, heard, autojunk=False)
    same = sum(block.size for block in matcher.get_matching_blocks())
    return same / len(script) if script else 0.0


# ---- the fixtures -----------------------------------------------------------


def f2_text():
    out = []
    for word in F1_TEXT.split():
        out.append(f"[[slnc 300]] {word} [[slnc 300]]" if normalize(word) in FILLERS else word)
    return " ".join(out)


def f3_text():
    return " ".join(w for w in F1_TEXT.split() if normalize(w) not in FILLERS)


FIXTURES = {"f1": F1_TEXT, "f2": f2_text(), "f3": f3_text()}
ROWS = ("f1", "f2", "f3", "o1", "o2")


def without_fillers(text):
    return [t for t in tokens(text) if t not in FILLERS]


def make_fixtures(remake):
    folder = WORK / "fixtures"
    folder.mkdir(parents=True, exist_ok=True)
    paths = {}
    for row, text in FIXTURES.items():
        path = folder / f"{row}.aiff"
        if remake or not path.exists():
            path.unlink(missing_ok=True)
            done = subprocess.run(["say", "-o", str(path), text], capture_output=True,
                                  text=True, timeout=120)
            if done.returncode != 0 or not path.exists():
                raise RuntimeError(f"say failed for {row}: {done.stderr.strip()[-300:]}")
        paths[row] = path
    return paths


# ---- the probe --------------------------------------------------------------


def build_probe():
    folder = WORK / "build"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = WORK / "bin" / "filler-spike-probe"
    binary.parent.mkdir(parents=True, exist_ok=True)
    swift_build.build(sources=swift_build.app_sources() + [entry], output=binary, timeout=900)
    return binary


def run_probe(binary, media):
    """(installed, [line per media, in `media`'s order]) — the probe's stdout,
    parsed and held in memory only (o1's and o2's runs never reach a file or
    the terminal)."""
    wavs = WORK / "wav"
    done = subprocess.run([str(binary), str(wavs)] + [str(m) for m in media],
                          capture_output=True, text=True,
                          timeout=FILE_BOUND * len(media) + 60)
    lines = [json.loads(line) for line in done.stdout.splitlines() if line.startswith("{")]
    if not lines or "installed" not in lines[0]:
        raise RuntimeError(f"probe exited {done.returncode} with no locale line; stderr: "
                           f"{done.stderr.strip()[-400:]}")
    installed = lines[0]["installed"]
    if installed is not True:
        return installed, {}
    if done.returncode != 0:
        raise RuntimeError(f"probe exited {done.returncode}; stderr: {done.stderr.strip()[-400:]}")
    return True, lines[1:]


# ---- the rows ---------------------------------------------------------------


def scripted_row(line, text):
    heard = recognised(line["runs"])
    count, found = filler_tally(heard)
    scripted = classify(tokens(text), heard)
    return {"ran": True, "seconds": round(line["seconds"], 3), "word_count": len(heard),
            "filler_count": count, "filler_tokens": found, "scripted": scripted,
            "dispositions": dict(Counter(s["disposition"] for s in scripted))}


def control_row(line):
    heard = recognised(line["runs"])
    count, found = filler_tally(heard)
    share = recognised_share(tokens(FIXTURES["f3"]), heard)
    return {"ran": True, "seconds": round(line["seconds"], 3), "word_count": len(heard),
            "filler_count": count, "filler_tokens": found,
            "script_recognised": round(share, 3)}


def sample_row(line):
    """o2: the owner's reading of O2_SCRIPT, aligned like f1; the share of the
    script's other words recognised says whether it is a reading of the script."""
    row = scripted_row(line, O2_SCRIPT)
    row["script_recognised"] = round(
        recognised_share(without_fillers(O2_SCRIPT),
                         [w for w in recognised(line["runs"]) if w not in FILLERS]), 3)
    return row


def owner_row(line):
    heard = recognised(line["runs"])
    count, found = filler_tally(heard)
    return {"ran": True, "seconds": round(line["seconds"], 3), "word_count": len(heard),
            "filler_count": count, "filler_tokens": found}


def verdict(rows):
    f1, f2, o1, o2 = (rows.get(r, {}) for r in ("f1", "f2", "o1", "o2"))
    if not (f1.get("ran") and f2.get("ran")):
        return "unmeasured"
    if o2.get("ran") and MUTANT != "o2-ignored":  # o2, the owner's scripted reading, is the real-speech row
        return "reports-real" if o2["filler_count"] > 0 else "does-not-report"
    synthetic = f1["filler_count"] > 0 or f2["filler_count"] > 0
    if synthetic and not o1.get("ran"):
        return "unmeasured"
    if o1.get("ran") and o1["filler_count"] > 0:
        return "reports-real"
    if synthetic:
        return "tts-only"
    return "does-not-report"


def host():
    def out(argv):
        try:
            return subprocess.run(argv, capture_output=True, text=True, cwd=ROOT,
                                  timeout=30).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""
    version = out(["sw_vers", "-productVersion"]) or platform.mac_ver()[0]
    build = out(["sw_vers", "-buildVersion"])
    tree = out(["git", "rev-parse", "--short", "HEAD"])
    if out(["git", "status", "--porcelain"]):
        tree += " (with uncommitted changes)"
    return f"macOS {version} ({build})", tree


def sample_file():
    """(path, None) for o2's one file, else (None, why it is skipped)."""
    where = SAMPLE.relative_to(ROOT)
    files = sorted(p for p in SAMPLE.iterdir() if p.is_file() and not p.name.startswith(".")) \
        if SAMPLE.is_dir() else []
    if not files:
        return None, f"the owner's sample is absent (no file in {where}/)"
    if len(files) > 1:
        return None, (f"{where}/ holds {len(files)} files ({', '.join(p.name for p in files)}); "
                      "leave exactly one")
    return files[0], None


def spike(args):
    paths = make_fixtures(args.remake)
    try:
        binary = build_probe()
    except swift_build.SwiftBuildFailed as error:
        print("INSTRUMENT FAILED: the probe will not build\n  " + "\n  ".join(error.diagnostics))
        return 1
    owner = None
    skipped = {}
    if args.no_owner:
        skipped["o1"] = "--no-owner was given"
    elif not OWNER.exists():
        skipped["o1"] = f"the owner's recording is absent ({OWNER.relative_to(ROOT)})"
    else:
        owner = OWNER
    sample = None
    if args.no_owner:
        skipped["o2"] = "--no-owner was given"
    else:
        sample, why = sample_file()
        if why:
            skipped["o2"] = why
    sources = {"f1": paths["f1"], "f2": paths["f2"], "f3": paths["f3"]}
    if owner:
        sources["o1"] = owner
    if sample:
        sources["o2"] = sample
    media = list(sources.values())
    try:
        installed, lines = run_probe(binary, media)
    except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print(f"INSTRUMENT FAILED: {error}")
        return 1
    rows, failures = {}, []
    if installed is not True:
        why = f"en-US is not installed on this host (isInstalled answered {installed})"
        for row in sources:
            skipped[row] = why
    else:
        by_row = dict(zip(sources, lines))
        for row in sources:
            line = by_row.get(row)
            if line is None or not line.get("ok"):
                why = "no probe line" if line is None else f"the probe answered {line.get('error')}"
                if row == "f3":
                    failures.append(f"f3: the control did not run ({why})")
                else:
                    skipped[row] = why
                continue
            if row in ("f1", "f2"):  # f2 speaks F1's words; its [[slnc]] markup is not a word
                rows[row] = scripted_row(line, F1_TEXT)
            elif row == "f3":
                rows[row] = control_row(line)
                if rows[row]["filler_count"] != 0 or rows[row]["script_recognised"] < 0.8:
                    failures.append(f"f3: the control did not hold ({rows[row]['filler_count']} "
                                    f"fillers, {rows[row]['script_recognised']:.0%} of the "
                                    "script recognised; wanted 0 and at least 80%)")
            elif row == "o2":
                rows[row] = sample_row(line)
                if rows[row]["script_recognised"] < 0.8:
                    failures.append(f"o2: the sample is not a reading of the script "
                                    f"({rows[row]['script_recognised']:.0%} of its other words "
                                    "recognised; wanted at least 80%)")
            else:
                rows[row] = owner_row(line)
    for row, why in skipped.items():
        rows[row] = {"ran": False, "reason": why}
    for row in ROWS:
        print(f"  {row}: {json.dumps(rows.get(row), sort_keys=True)}")
    if failures:
        print("INSTRUMENT FAILED:\n  " + "\n  ".join(failures))
        return 1
    macos, tree = host()
    answers = {"date": datetime.date.today().isoformat(), "tree": tree, "macos": macos,
               "rows": {r: rows[r] for r in ROWS if r in rows},
               "reported_in": [r for r in ROWS
                               if rows.get(r, {}).get("filler_count", 0) > 0],
               "verdict": verdict(rows)}
    (WORK / "answers.json").write_text(json.dumps(answers, indent=1, sort_keys=True) + "\n")
    print(f"verdict: {answers['verdict']} (reported in {answers['reported_in'] or 'no row'}); "
          f"{(WORK / 'answers.json').relative_to(ROOT)}")
    if skipped:
        print("SPIKE INCOMPLETE: " + "; ".join(f"{r} did not run — {w}"
                                               for r, w in skipped.items()))
        return 2
    return 0


# ---- the selftest -----------------------------------------------------------


def runs(*words):
    return [{"text": w, "start": i * 0.3, "end": i * 0.3 + 0.25} for i, w in enumerate(words)]


def o2_heard():
    """O's hand-written reading of O2_SCRIPT: the 1st filler kept with its comma,
    the 2nd dropped, the 4th ("Er,") heard as "or", the 8th dropped, the rest
    kept, and an unscripted "Um," before it all."""
    words = O2_SCRIPT.split()
    at = [i for i, w in enumerate(words) if w.lower().strip(STRIP) in FILLERS]
    words[at[3]] = "Or,"
    for i in (at[7], at[1]):
        del words[i]
    return runs("Um,", *words)


def selftest():
    cases = [
        ("K", "So um I was thinking", runs("So,", "um,", "I", "was", "thinking."),
         ["kept"], 1),
        ("D", "we could um start", runs("we", "could", "start"), ["dropped"], 0),
        ("R", "we could um start", runs("we", "could", "a", "start"), ["replaced:a"], 0),
        ("Z", "we could start the meeting", runs("we", "could", "start", "the", "meeting"),
         [], 0),
        ("O", O2_SCRIPT, o2_heard(),
         ["kept", "dropped", "kept", "replaced:or", "kept", "kept", "kept", "dropped"], 6),
    ]
    failed = []
    for name, script, heard_runs, want, want_count in cases:
        heard = recognised(heard_runs)
        got = [s["disposition"] for s in classify(tokens(script), heard)]
        count, _ = filler_tally(heard)
        good = got == want and count == want_count
        if not good:
            failed.append(name)
        print(f"  {'ok  ' if good else 'FAIL'} {name} — dispositions {got} (wanted {want}), "
              f"filler_count {count} (wanted {want_count})")
    # V: the verdict, o2 first when it ran.
    ran = lambda n: {"ran": True, "filler_count": n}  # noqa: E731
    absent = {"ran": False, "reason": "absent"}
    verdicts = [
        ("V1", {"f1": ran(6), "f2": ran(7), "o1": ran(0), "o2": ran(3)}, "reports-real"),
        ("V2", {"f1": ran(6), "f2": ran(7), "o1": ran(0), "o2": ran(0)}, "does-not-report"),
        ("V3", {"f1": ran(6), "f2": ran(7), "o1": ran(0), "o2": absent}, "tts-only"),
        ("V4", {"f1": absent, "f2": ran(7), "o1": ran(0), "o2": ran(3)}, "unmeasured"),
    ]
    for name, rows, want in verdicts:
        got = verdict(rows)
        if got != want:
            failed.append(name)
        print(f"  {'ok  ' if got == want else 'FAIL'} {name} — verdict {got} (wanted {want})")
    texts = {"f2 silences": f2_text().count("[[slnc 300]]") == 2 * SCRIPTED,
             "f3 control": filler_tally(tokens(f3_text()))[0] == 0,
             "f1 scripted": filler_tally(tokens(F1_TEXT))[0] == SCRIPTED,
             "o2 scripted": filler_tally(tokens(O2_SCRIPT))[0] == SCRIPTED}
    for name, good in texts.items():
        if not good:
            failed.append(name)
        print(f"  {'ok  ' if good else 'FAIL'} {name}")
    total = len(cases) + len(verdicts) + len(texts)
    print(f"\n{total - len(failed)}/{total} selftest rows "
          f"passed{f' under --mutant {MUTANT}' if MUTANT else ''}"
          f"{'; failed: ' + ', '.join(failed) if failed else ''}")
    return 1 if failed else 0


def main(argv=None):
    global MUTANT
    parser = argparse.ArgumentParser(description="CT-0's filler spike")
    parser.add_argument("--selftest", action="store_true", help="K, D, R, Z, O, V1-V4; no engine, no build")
    parser.add_argument("--mutant", choices=("keep-punctuation", "replaced-as-kept", "o2-ignored"))
    parser.add_argument("--remake", action="store_true", help="remake the three say fixtures")
    parser.add_argument("--no-owner", action="store_true", help="skip o1 and o2 by name")
    args = parser.parse_args(argv)
    if args.mutant and not args.selftest:
        parser.error("--mutant runs only with --selftest")
    MUTANT = args.mutant
    if args.selftest:
        return selftest()
    WORK.mkdir(parents=True, exist_ok=True)
    return spike(args)


if __name__ == "__main__":
    sys.exit(main())
