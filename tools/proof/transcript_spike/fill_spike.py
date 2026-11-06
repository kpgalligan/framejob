#!/usr/bin/env python3
"""Road map "creator-jobs" TX1, spike TX-S1 — the fill's cost (decides TX-12's
outcome and its priority).

    python3 tools/proof/transcript_spike/fill_spike.py --part short     # 600 s, once
    python3 tools/proof/transcript_spike/fill_spike.py --part long      # 3,600 s, twice
    python3 tools/proof/transcript_spike/fill_spike.py --part windows   # six 600 s windows
    python3 tools/proof/transcript_spike/fill_spike.py --part owner     # S-TH1, S-LONG1
    python3 tools/proof/transcript_spike/fill_spike.py --playback --socket <dir>/agent.sock
    python3 tools/proof/transcript_spike/fill_spike.py --part verdict

Each part is its own invocation (each under 30 minutes) and merges into
`tools/proof/work/creator_spike/TX-S1/results.json` (`rule.write_results`,
with the rule's `rule_sha256`, the OS build and the device).

`fill_spike.swift`, built from `app/Sources` through `swift_build.py`, runs ONE
`Transcriber.Job` through the app's own on-device path a process
(`requireModel`, `Transcriber().extractAudio`, `SpeechEngine.transcribe`) and
measures wall time, the peak `phys_footprint` above its value before the run,
the WAV's bytes and the words. Inputs: `say` phrases joined, with 0.6 s gaps,
into a 600 s and a 3,600 s 16 kHz WAV under `tools/proof/work/transcript_spike/`
(the phrases cycle continuously, so a 600 s window cuts through words); S-TH1
and S-LONG1 under `tools/proof/media/creator/<id>/` when they exist, else
skipped by name and owed. The 3,600 s run goes twice and is judged on the
slower. `windows` recognises the 3,600 s file as six 600 s windows and
compares each word's start with the whole run's (words matched by spelling, in
order: the next same spelling within 5 s; median and p95 |Δ|).

`--playback` (the Release app, `make app` first, launched with
`proof_app.py launch --app release`): `play_preview`'s composed frames over
10 s of a 1080p timeline (`analysis_fixtures.h264_1080`), three runs each,
median: idle; while the probe's 3,600 s run goes in a sibling process at
default QoS (played once it prints `recognising`, killed after); and the same
under `taskpolicy -c utility`. The fill does not exist yet, so this is the
reading of a sibling process, recorded as such.

Rules (the road map's, CJ0a's table holds their hash): outcome A, one
whole-file run per media, if the 3,600 s run finishes within 6 minutes and its
peak added memory is at most 1/32 of physical memory; otherwise outcome B. The
fill keeps `.userInitiated` if `play_preview` composes at least 95 % of its
idle count during it; else `.utility` if that reaches 95 %; else it pauses
while the transport plays.
"""

import argparse
import json
import re
import shutil
import statistics
import subprocess
import sys
import time
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(PROOF / "creator_spike"))
import analysis_fixtures as fixtures  # noqa: E402
import rule  # noqa: E402
import swift_build  # noqa: E402

SPIKE = "TX-S1"
WORK = ROOT / "tools/proof/work/transcript_spike"
RESULTS = ROOT / "tools/proof/work/creator_spike" / SPIKE / "results.json"
OWNER = {"S-TH1": ROOT / "tools/proof/media/creator/S-TH1",
         "S-LONG1": ROOT / "tools/proof/media/creator/S-LONG1"}
LANGUAGE = "en-US"
RUNS = 3
WALL = 1700  # one process's bound, under the 30-minute rule

PHRASES = [
    "The quick brown fox jumps over the lazy dog.",
    "Pack my box with five dozen liquor jugs.",
    "How vexingly quick daft zebras jump.",
    "Every morning the harbour fills with small boats and loud gulls.",
    "She opened the window and the whole room smelled of rain.",
    "Our project ships on Thursday if the last review goes well.",
    "Turn left at the old church, then follow the river for a mile.",
    "The orchestra tuned for a long time before the first note.",
    "Please write the totals in the third column of the sheet.",
    "A cold wind came down from the hills just after sunset.",
    "He kept a notebook of every bird he saw that summer.",
    "The bakery on the corner sells bread until noon.",
    "Measure twice and cut once, as my grandfather used to say.",
    "Bright lanterns hung along the pier for the festival.",
    "The train was late, so we walked the rest of the way.",
    "Nobody expected the meeting to end before lunch.",
]
GAP = 0.6


def say_phrases():
    """Each phrase as 16 kHz mono 16-bit samples, made once."""
    folder = WORK / "phrases"
    folder.mkdir(parents=True, exist_ok=True)
    bodies = []
    for index, text in enumerate(PHRASES):
        path = folder / f"{index:02d}.wav"
        if not path.exists():
            subprocess.run(["say", "-o", str(path), "--file-format=WAVE",
                            "--data-format=LEI16@16000", text], check=True, timeout=120)
        with wave.open(str(path), "rb") as source:
            assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == \
                (1, 2, 16000), path
            bodies.append(source.readframes(source.getnframes()))
    return bodies


def joined(seconds):
    """WORK/say-<seconds>.wav: the phrases cycled with GAP between, cut at
    exactly `seconds`."""
    path = WORK / f"say-{seconds}.wav"
    frames = seconds * 16000
    if path.exists():
        with wave.open(str(path), "rb") as held:
            if held.getnframes() == frames:
                return path
    bodies = say_phrases()
    gap = b"\0\0" * int(16000 * GAP)
    body, index = bytearray(), 0
    while len(body) < frames * 2:
        body += bodies[index % len(bodies)] + gap
        index += 1
    part = path.with_suffix(".part")
    with wave.open(str(part), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(16000)
        out.writeframes(bytes(body[:frames * 2]))
    part.replace(path)
    return path


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "fill_spike.swift", entry)
    binary = WORK / "fill-spike"
    swift_build.build(sources=[*swift_build.app_sources(), entry], output=binary, optimize=True)
    return binary


def run_once(binary, path, start, length, tag, policy=None):
    out = WORK / f"run-{tag}.json"
    argv = [str(binary), str(path), str(start), str(length), LANGUAGE, str(out)]
    if policy:
        argv = ["taskpolicy", "-c", policy] + argv
    ran = subprocess.run(argv, capture_output=True, text=True, timeout=WALL)
    if not out.exists():
        return {"error": (ran.stderr or ran.stdout)[-400:]}
    answer = json.loads(out.read_text())
    print(f"{tag}: " + json.dumps({k: v for k, v in answer.items() if k != "words"}), flush=True)
    return answer


def summary(answer):
    return {k: v for k, v in answer.items() if k != "words"}


def load(path=RESULTS):
    return json.loads(path.read_text()) if path.exists() else {}


def tokens(words, offset=0.0):
    out = []
    for text, start, _ in words:
        token = re.sub(r"[^a-z0-9']", "", text.lower())
        if token:
            out.append((token, start + offset))
    return out


MATCH_REACH = 5.0  # seconds; the phrases cycle every ~55 s, so a spelling is unique within it


def window_deltas(whole, windows):
    """|Δ start| in seconds for every word matched by spelling, in order,
    between the whole run and each window's run: each window word takes the
    next whole-run word of the same spelling within MATCH_REACH, the walk
    never going back (a plain longest-match over cycling phrases pairs words
    a cycle apart)."""
    deltas = []
    for (start, length), run in windows:
        own = tokens(run["words"], start)
        span = [t for t in tokens(whole["words"]) if start <= t[1] < start + length]
        j = 0
        for token, at in own:
            k = j
            while k < len(span) and span[k][1] < at - MATCH_REACH:
                k += 1
            while k < len(span) and span[k][1] <= at + MATCH_REACH:
                if span[k][0] == token:
                    deltas.append(abs(span[k][1] - at))
                    j = k + 1
                    break
                k += 1
    return deltas


def part_short(results, binary):
    path = joined(600)
    results["short"] = summary(run_once(binary, path, 0, 600, "short"))


def part_long(results, binary):
    path = joined(3600)
    runs = []
    for n in range(2):
        answer = run_once(binary, path, 0, 3600, f"long-{n}")
        runs.append(answer)
    results["long"] = [summary(r) for r in runs]
    keep = max(runs, key=lambda r: r.get("wall_s", 0))
    (WORK / "long-words.json").write_text(json.dumps(keep.get("words", [])))


def part_windows(results, binary):
    path = joined(3600)
    words = WORK / "long-words.json"
    if not words.exists():
        raise SystemExit("run --part long first: the windows compare against its words")
    whole = {"words": json.loads(words.read_text())}
    windows = []
    for n in range(6):
        answer = run_once(binary, path, n * 600, 600, f"window-{n}")
        windows.append(((n * 600, 600), answer))
    deltas = sorted(window_deltas(whole, windows))
    p95 = deltas[min(len(deltas) - 1, int(round(0.95 * (len(deltas) - 1))))] if deltas else None
    results["windows"] = {
        "runs": [summary(a) for _, a in windows],
        "window_words": sum(a.get("word_count", 0) for _, a in windows),
        "whole_words": len(whole["words"]), "matched": len(deltas),
        "median_abs_delta_s": statistics.median(deltas) if deltas else None,
        "p95_abs_delta_s": p95, "max_abs_delta_s": deltas[-1] if deltas else None}
    print(json.dumps(results["windows"], indent=1), flush=True)


def part_owner(results, binary):
    owner = {}
    for name, folder in OWNER.items():
        found = sorted(p for p in folder.glob("*") if p.suffix.lower() in
                       (".mov", ".mp4", ".wav", ".m4a")) if folder.exists() else []
        if name == "S-TH1":
            # IMG_0181.MOV by name, never its side-on add-on (road map CJ7)
            import sth1
            found = [sth1.movie()] if sth1.movie() else []
        if not found:
            owner[name] = f"SKIP: {name} does not exist under {folder}; owed"
            print(owner[name], flush=True)
            continue
        seconds = float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
             "default=nw=1:nk=1", str(found[0])], capture_output=True, text=True).stdout or 0)
        owner[name] = summary(run_once(binary, found[0], 0, seconds, name))
    results["owner"] = owner
    results.setdefault("owner_runs", []).append(owner)


def playback(socket, binary):
    import mcp  # noqa: E402

    client = mcp.MCP(socket)
    movie = fixtures.h264_1080()
    package = WORK / "playback.framejob"
    try:
        client.call("close_project", project=str(package), discard=True)
    except Exception:  # noqa: BLE001 — not open
        pass
    if package.exists():
        shutil.rmtree(package)
    client.call("new_project", path=str(package))
    state = client.call("get_project", project=str(package))["project"]
    track = state["tracks"][0]["id"]
    media = client.call("import_media", project=str(package), path=str(movie))["media"]
    client.call("add_clip", project=str(package), track=track, media=media, at=0)
    client.call("save_project", project=str(package))
    long = joined(3600)

    def composed():
        client.call("set_playhead", project=str(package), t=0)
        return client.call("play_preview", project=str(package), seconds=10)["frames_composed"]

    def during(policy, tag):
        out = WORK / f"run-sibling-{tag}.json"
        argv = [str(binary), str(long), "0", "3600", LANGUAGE, str(out)]
        if policy:
            argv = ["taskpolicy", "-c", policy] + argv
        child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 text=True)
        try:
            deadline = time.time() + 300
            line = ""
            while time.time() < deadline:
                line = child.stdout.readline()
                if not line or line.strip() == "recognising":
                    break
            if line.strip() != "recognising":
                return None
            time.sleep(2)  # the analysis under way, not its first allocation
            return composed()
        finally:
            child.kill()
            child.wait()

    rows = {"idle": [], "user_initiated_sibling": [], "utility_sibling": []}
    for n in range(RUNS):
        rows["idle"].append(composed())
        rows["user_initiated_sibling"].append(during(None, f"default-{n}"))
        rows["utility_sibling"].append(during("utility", f"utility-{n}"))
        print(json.dumps({k: v[-1] for k, v in rows.items()}), flush=True)
    try:
        client.call("close_project", project=str(package), discard=True)
    except Exception:  # noqa: BLE001
        pass
    medians = {k: statistics.median([x for x in v if x is not None]) if any(
        x is not None for x in v) else None for k, v in rows.items()}
    idle = medians["idle"]
    share = {k: (medians[k] / idle if idle and medians[k] is not None else None)
             for k in ("user_initiated_sibling", "utility_sibling")}
    return {"runs": rows, "medians": medians, "share_of_idle": share,
            "reading": "a sibling process's whole-file run, the fill not yet built"}


def verdict(results):
    memory = int(rule.sysctl("hw.memsize") or 0)
    long = results.get("long") or []
    walls = [r.get("wall_s") for r in long if "wall_s" in r]
    peaks = [r.get("peak_added_bytes") for r in long if "peak_added_bytes" in r]
    out = {"physical_memory": memory, "memory_limit": memory // 32}
    if len(walls) == 2 and len(peaks) == 2:
        slow = max(walls)
        peak = max(peaks)
        out.update({"long_wall_s_judged": slow, "long_peak_added_judged": peak,
                    "outcome": "A" if slow <= 360 and peak <= memory // 32 else "B"})
        out["rate_s_per_minute"] = slow / 60
    playback = results.get("playback")
    if playback:
        share = playback["share_of_idle"]
        if share["user_initiated_sibling"] is not None and share["user_initiated_sibling"] >= 0.95:
            out["priority"] = "userInitiated"
        elif share["utility_sibling"] is not None and share["utility_sibling"] >= 0.95:
            out["priority"] = "utility"
        else:
            out["priority"] = "pause"
    return out


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--part", choices=["short", "long", "windows", "owner", "verdict"])
    parser.add_argument("--playback", action="store_true")
    parser.add_argument("--socket")
    args = parser.parse_args(argv)
    rule.check_rule(SPIKE)
    # --part owner keeps its runs apart (road map CJ7): TX-S1-STH1/, each run appended
    folder = "TX-S1-STH1" if args.part == "owner" else None
    results = load(RESULTS.parent.parent / folder / "results.json") if folder else load()
    for key in ("spike", "rule_sha256", "rule_sha256_recorded", "rule_matches", "os_build",
                "os", "device", "cores", "memory", "ac_power", "uptime"):
        results.pop(key, None)
    if args.playback:
        if not args.socket:
            raise SystemExit("--playback needs --socket of a running Release Frame Job")
        results["playback"] = playback(args.socket, build())
        print(json.dumps(results["playback"], indent=1))
    elif args.part == "verdict":
        pass
    elif args.part:
        globals()[f"part_{args.part}"](results, build())
    else:
        raise SystemExit("name a --part or --playback")
    results["verdict"] = verdict(results)
    print("VERDICT " + json.dumps(results["verdict"], sort_keys=True))
    written = rule.write_results(SPIKE, results, folder=folder)
    print(f"results: {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
