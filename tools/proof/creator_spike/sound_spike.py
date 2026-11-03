#!/usr/bin/env python3
"""Road map "creator-jobs" FC3, spike FC-S1 — Sound Analysis as a signal
(decides FC-30).

    python3 tools/proof/creator_spike/sound_spike.py              # the run, on AC
    python3 tools/proof/creator_spike/sound_spike.py --selftest   # the deciders only

The probe is `sound_spike.swift` (built over `app/Sources`, optimised): its
`labels` mode answers FC-31's labels against `.version1`'s known
classifications and the window constraint; its `run` mode one file through
`SNAudioFileAnalyzer` or through `SNAudioStreamAnalyzer` fed by the app's
`MediaImporter.speechReader` (16 kHz mono float), at a window and overlap 0.5.

Inputs: `samples/Rode-usb-mic.m4a`, `tools/proof/media/filler-sample/
test-recording.aifc` and two `say` fixtures (`tools/proof/work/creator_spike/
FC-S1/`). S-EV (laughter, applause, cheering with an onset list), S-TH1 and
S-ST1 (10 minutes of speech only) and S-MU (music) do not exist yet: every
group is weak by rule (no labelled events), and the recall and false-call
rows skip by name and are owed.

- **Speed**: each window (1.0, 1.5, 3.0 s) × analyzer three times on a
  10-minute loop of the Rode file (ffmpeg `-stream_loop`), medians of the
  real-time factor; the window rule reads the stream analyzer's (the
  product's path).
- **Agreement** (`sound_deciders.agreement`, the owner's amendment of
  2026-11-02, option (a)): every input × window, the file and the stream
  analyzer's rising 0.5 crossings matched within one hop, or tolerated where
  the other side's value at the crossing or the window before is within
  ±0.1 of 0.5, both ways, every group. `agreement_strict` (attempt 1's
  metric) is recorded beside it, with its unmatched count.
- **Determinism**: the loop's stream runs at each window give byte-identical
  values (their `sha256`).

Writes `tools/proof/work/creator_spike/FC-S1/results.json`
(`rule.write_results`) and prints one `VERDICT` line.
"""

import argparse
import json
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(HERE))
import rule  # noqa: E402
import sound_deciders as deciders  # noqa: E402
import swift_build  # noqa: E402

WINDOWS = (1.0, 1.5, 3.0)
RUNS = 3
OUT = rule.WORK / "FC-S1"
RODE = ROOT / "samples/Rode-usb-mic.m4a"
FILLER = ROOT / "tools/proof/media/filler-sample/test-recording.aifc"
LABELS = ["laughter", "belly_laugh", "chuckle_chortle", "giggling", "snicker", "applause",
          "clapping", "cheering", "crowd", "music", "speech"]
SAY = {
    "say_samantha.aiff": ("Samantha", "The quick brown fox jumps over the lazy dog. "
                          "We recorded this sentence to measure when speech begins, and how "
                          "long it carries on, before a short pause and a second sentence."),
    "say_daniel.aiff": ("Daniel", "Sound events are read per window of the recording. "
                        "This is a second voice, a little slower, for the stream and the file "
                        "analyzers to agree on."),
}

AGREEMENT_METRIC = (
    "A rising 0.5 crossing at t on one analyzer's side is matched when the other side has a "
    "rising crossing of the same group within one hop of t, or when the other side's value "
    "at t or at t - hop (the two windows the crossing lies between) is within +/-0.1 of 0.5; "
    "both ways, every group, input and window length; the stream analyzer agrees when "
    "nothing is left unmatched (the owner's option (a), 2026-11-02).")


def log(message):
    print(message, flush=True)


def binary():
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(HERE / "sound_spike.swift", entry)
    out = OUT / "sound-spike"
    swift_build.build(sources=[*swift_build.app_sources(), entry], output=out, optimize=True)
    return out


def probe(exe, *args):
    done = subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True,
                          timeout=3600)
    if done.returncode != 0:
        raise SystemExit(f"sound_spike {' '.join(map(str, args))}: "
                         f"{(done.stderr or done.stdout)[-600:]}")
    return json.loads(done.stdout.strip().splitlines()[-1])


def fixtures():
    made = {}
    for name, (voice, text) in SAY.items():
        path = OUT / name
        if not path.exists():
            subprocess.run(["say", "-v", voice, "-o", str(path), text], check=True,
                           timeout=120)
        made[name] = path
    loop = OUT / "rode_loop_10min.m4a"
    if not loop.exists():
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-stream_loop", "19", "-i", str(RODE),
                        "-c", "copy", str(loop)], check=True, timeout=600)
    return made, loop


def by_group(answer):
    groups = answer["groups"]
    out = {g: [] for g in groups}
    for w in answer["windows"]:
        for g, v in zip(groups, w["values"]):
            out[g].append((w["start"], v))
    return out


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return 1 if deciders.selftest() else 0
    if deciders.selftest():
        raise SystemExit("the deciders' selftest failed")
    rule.check_rule("FC-S1")
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    if not host["ac_power"]:
        log("NOTE: not on AC power; the timings are recorded as they ran")
    for need in (RODE, FILLER):
        if not need.exists():
            log(f"FAIL input {need} is missing")
            return 1
    exe = binary()
    labels = probe(exe, "labels")
    missing = [name for name in LABELS if not labels["labels"].get(name)]
    log(f"labels: {labels['known_count']} known; FC-31's missing: {missing or 'none'}; "
        f"constraint {labels['constraint']}; windows set {labels['windows_set']}")
    say, loop = fixtures()
    inputs = {"rode": RODE, "filler": FILLER, **{k.split('.')[0]: v for k, v in say.items()}}

    timing, determinism, loop_rows = {}, {}, {}
    for w in WINDOWS:
        for mode in ("file", "stream"):
            runs = [probe(exe, "run", loop, w, mode) for _ in range(RUNS)]
            factors = [r["realtime"] for r in runs]
            timing[f"{w}/{mode}"] = {"realtime": factors, "median": statistics.median(factors),
                                     "seconds": [r["seconds"] for r in runs],
                                     "duration": runs[0]["duration"],
                                     "sha256": [r["sha256"] for r in runs]}
            log(f"speed {w} s {mode}: {', '.join(f'{f:.1f}' for f in factors)}× "
                f"(median {statistics.median(factors):.1f}×) over {runs[0]['duration']:.1f} s; "
                f"{len(runs[0]['windows'])} windows")
            if mode == "stream":
                determinism[str(w)] = len({r["sha256"] for r in runs}) == 1
            loop_rows[f"{w}/{mode}"] = runs[0]

    agreement, misses_all, strict, strict_misses, tolerated_all = {}, {}, {}, {}, {}
    for w in WINDOWS:
        for name, path in [*inputs.items(), ("rode_loop", loop)]:
            if name == "rode_loop":
                f, s = loop_rows[f"{w}/file"], loop_rows[f"{w}/stream"]
            else:
                f, s = probe(exe, "run", path, w, "file"), probe(exe, "run", path, w, "stream")
            hop = s["window_set"] * 0.5
            ok, misses, tolerated = deciders.agreement(by_group(f), by_group(s), hop)
            strict_ok, strict_left = deciders.agreement_strict(by_group(f), by_group(s), hop)
            agreement[f"{w}/{name}"] = ok
            misses_all[f"{w}/{name}"] = misses[:20]
            strict[f"{w}/{name}"] = strict_ok
            strict_misses[f"{w}/{name}"] = strict_left
            tolerated_all[f"{w}/{name}"] = tolerated
            onset = {}
            for side, answer in (("file", f), ("stream", s)):
                c = deciders.crossings(by_group(answer)["speech"], deciders.CROSSING)
                onset[side] = c[0] if c else None
            log(f"agreement {w} s {name}: {'agree' if ok else 'DISAGREE'} ({len(misses)} "
                f"unmatched {misses[:3]}; {len(tolerated)} tolerated {tolerated}; strict "
                f"{len(strict_left)} unmatched); speech onset file {onset['file']} stream "
                f"{onset['stream']}; windows {len(f['windows'])} / {len(s['windows'])}")

    realtime = {w: timing[f"{w}/stream"]["median"] for w in WINDOWS}
    window = deciders.window_rule(realtime, {})
    kept = window["window"]
    groups = {g: deciders.group_rule([], [], [])
              for g in ("laughter", "applause", "cheering", "crowd", "music", "speech")}
    owed = ["S-EV missing: every group's recall at a threshold, and laughter recall per window, "
            "owed; every group weak by rule",
            "S-TH1 and S-ST1 missing: the false calls per 10 min of speech only owed",
            "S-MU missing: the false calls per 10 min of music owed"]
    for line in owed:
        log(f"SKIP {line}")
    agrees = all(agreement.values())
    strict_unmatched = sum(len(v) for v in strict_misses.values())
    deterministic = all(determinism.values())
    hop = kept * 0.5
    line = (f"VERDICT window={kept} hop={hop} groups=weak(all, no S-EV) "
            f"labels={'all' if not missing else 'missing:' + ','.join(missing)} "
            f"stream_agrees={'yes' if agrees else 'no'} strict_unmatched={strict_unmatched} "
            f"deterministic="
            f"{'yes' if deterministic else 'no'} "
            + " ".join(f"rt_{k.replace('/', '_')}={v['median']:.1f}" for k, v in timing.items()))
    results = {"labels": labels, "labels_missing": missing, "timing": timing,
               "determinism": determinism, "agreement_metric": AGREEMENT_METRIC,
               "value_tolerance": deciders.VALUE_TOLERANCE, "agreement": agreement,
               "unmatched": misses_all, "agreement_strict": strict,
               "unmatched_strict": strict_misses, "tolerated": tolerated_all,
               "window": window, "groups": groups, "owed": owed, "verdict_line": line,
               "inputs": {k: str(v) for k, v in inputs.items()}, "loop": str(loop)}
    written = rule.write_results("FC-S1", results)
    log(line)
    log(f"results: {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
