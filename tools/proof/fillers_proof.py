#!/usr/bin/env python3
"""Cut by transcript CT-2 (spec §11 TR-4, TR-7, TR-9): `detect_fillers`, its
grid rule, and the cut through `ripple_delete_ranges` — #92's done-when.

    python3 tools/proof/fillers_proof.py [--mutant NAME] [--only IDS]

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything, and the
instance is given the dummy key `proof-key` against `assemblyai_fake.py`.

Probe rows (`fillers_probe.swift`, copied in as `main.swift` and built with
`swift_build.build()` over `swift_build.app_sources()` of `app/Sources`, or
of a mutant's copy, run once under `tools/proof/work/fillers/<tree|mutant-NAME>/`,
killed at a 240 s wall):
  P0  the probe builds (a build failure is this row's scored FAIL).
  P1  `gridded` widens a run outward to the 32 ms grid when its neighbours
      are far: [1470000, 1770000) → [1459200, 1785600).
  P2  a neighbour inside the outward grid point bounds it, at
      ceil(previousEnd) and floor(nextStart).
  P3  `runs`: "um, Uh er" consecutive is one run (taken in (start, end)
      order), "um word uh" two, "umbrella" none, each with its bounds.
  P4  `placed` through start 1 s, in 0.5 s, speed 2 at 30 fps: start up,
      end down, exact ticks.
  P5  a 40 ms filler squeezed between words is `tooShort`.
  P6  another clip's non-filler word over a candidate drops it with
      `overlapsWord(clip:text:)`, in scope and only as a neighbour; the
      candidate's own clip's words never drop it.
  P7  a nest extent and a transition wall each drop a candidate.
  P8  `fillersFile` over a temp cache: a `disfluencies` marker → the file,
      a marker without → nil, a changed source → nil; `transcriptFile(…,
      use: .captions)` over the marker without → the file.
  P9  `onUnlockedTracks`: a clip on a locked track goes to `locked`; one on
      an unlocked track and one whose track is absent are kept.

App rows (the app `proof_app` chooses — Debug by default, `RC_PROOF_APP=release`
for the record — through `cloud_captions_proof.Instance`/`Session` and the fake
serving `cloud_captions_proof.DISFLUENT_WORDS`; host-state input
`media/speech.mov`, whose absence is a scored FAIL):
  M0  the startup parity log is empty, and `detect_fillers` is listed with
      exactly `clips` and `project`.
  M1  a 5 s clip at 0, `transcribe` engine `assemblyai`, `place: false`:
      `detect_fillers` answers [[1460000, 1780000]] — the Python TR-9 rule
      over the served words — with words ["um,", "Uh", "er"], and
      `get_project` is unchanged by the call.
  M2  `ripple_delete_ranges` of those ranges: two clips [0, 1460000) in 0
      and start 1460000 in 1780000, each cut edge the frame snap of a
      multiple of the grid, the filler's source span outside both windows;
      one `undo` restores the single clip.
  M3  a clip at start 1 s with in 0.5 s → [[1760000, 2080000]].
  M4  a transcript whose marker and `requested` lost `disfluencies`, and a
      media never transcribed, each answer no ranges, the media under
      `needs_transcript` and the TR-7 note.
  M5  `clips: []` and an unknown clip id are refused by sentence.
  M6  a second clip on a new track at 0.3 s drops M1's filler as overlapping
      its "everyone"; with that track locked the filler is back; with it
      unlocked and track 0 locked, nothing, `locked` [first] and the note.

Mutants (`--mutant`, probe rows only), each anchor asserted to occur once:
  grid-nearest             the run's edges to the NEAREST grid point (P1)
  no-neighbour-bound       the neighbours' grid points not applied (P2)
  no-run-merge             every filler its own run (P3)
  frame-outward            start snapped down, end up (P4)
  no-word-conflict         no neighbour's word drops a candidate (P6)
  no-walls                 neither a nest nor a transition drops one (P7)
  fillers-from-any-marker  the scope's transcript read through `.captions` (P8)
  no-lock-filter           `onUnlockedTracks` keeps every clip (P9)

Exit: a plain run exits 0 iff every row passed, else 1. A `--mutant` run
exits 0 when every row the mutant names failed (caught), 1 when one passed
(survived), and 2 when the control could not be performed: an anchor not
found exactly once, the copy did not build, or a named row was not scored.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import string
import subprocess
import sys
import traceback

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/fillers"
PROBE = ROOT / "tools/proof/fillers_probe.swift"
PROBE_ROWS = ["P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9"]
APP_ROWS = ["M0", "M1", "M2", "M3", "M4", "M5", "M6"]
ROWS = PROBE_ROWS + APP_ROWS
WALL = 240
SEC = 600_000

FD = "FillerDetector.swift"
# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "grid-nearest": (["P1"], [
        (FD, "max(down(run.source.start, grid)", "max(down(run.source.start + grid / 2, grid)"),
        (FD, "min(up(run.source.end, grid)", "min(down(run.source.end + grid / 2, grid)")]),
    "no-neighbour-bound": (["P2"], [
        (FD, "max(down(run.source.start, grid), up(run.previousEnd, grid))",
         "down(run.source.start, grid)"),
        (FD, "min(up(run.source.end, grid), down(run.nextStart, grid))",
         "up(run.source.end, grid)")]),
    "no-run-merge": (["P3"], [
        (FD, "            open.append(index)", "            close()\n            open.append(index)")]),
    "frame-outward": (["P4"], [
        (FD, "start: SilenceDetector.snapUpToFrame(", "start: SilenceDetector.snapDownToFrame("),
        (FD, "end: SilenceDetector.snapDownToFrame(", "end: SilenceDetector.snapUpToFrame(")]),
    "no-word-conflict": (["P6"], [
        (FD, "for neighbour in guarded where neighbour.clip != clip {",
         "for neighbour in guarded where false {")]),
    "no-walls": (["P7"], [
        (FD, "input.nests.first(where: { SilenceDetector.overlap(span, $0.span) > 0 })",
         "input.nests.first(where: { _ in false })"),
        (FD, "input.walls.contains(where: { SilenceDetector.overlap(span, $0) > 0 })",
         "input.walls.contains(where: { _ in false })")]),
    "fillers-from-any-marker": (["P8"], [(FD, "use: .fillers", "use: .captions")]),
    "no-lock-filter": (["P9"], [
        (FD, "if snapshot.track(clip.track)?.locked == true {", "if false {")]),
}


# --------------------------------------------------------------------------
# The probe


def build(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "fillers-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def mutate(name, dest):
    """A copy of `app/Sources` with the mutant's edits; why, when an anchor is
    not found exactly once."""
    shutil.copytree(ROOT / "app/Sources", dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    try:
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=WALL,
                                cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


# --------------------------------------------------------------------------
# TR-9 in Python: the rule the app's answers are compared against

G = 19_200  # 512 samples at 16 kHz, in ticks
FILLERS = {"um", "uh", "hmm", "mhm", "uh-huh", "ah", "huh", "hm", "m", "er", "erm"}


def is_filler(text):
    return text.lower().strip(string.punctuation + string.whitespace) in FILLERS


def floor_to(t, step):
    return (t // step) * step


def ceil_to(t, step):
    return -((-t) // step) * step


def tr9(words, start, source_in, length, frame):
    """[(words, grid span, project span)] for a speed-1 clip at `start` with
    `in` = `source_in` and `length` source ticks, at `frame` ticks a frame."""
    end = source_in + length
    timed = sorted(((w["start"] * 600, max(w["start"], w["end"]) * 600, w["text"])
                    for w in words if source_in <= w["start"] * 600 < end),
                   key=lambda w: (w[0], w[1]))
    out = []
    index = 0
    while index < len(timed):
        if not is_filler(timed[index][2]):
            index += 1
            continue
        last = index
        while last + 1 < len(timed) and is_filler(timed[last + 1][2]):
            last += 1
        run = timed[index:last + 1]
        before = max([source_in] + [w[1] for w in timed[:index] if not is_filler(w[2])])
        after = min([end] + [w[0] for w in timed[last + 1:] if not is_filler(w[2])])
        grid = (max(floor_to(run[0][0], G), ceil_to(before, G)),
                min(ceil_to(max(w[1] for w in run), G), floor_to(after, G)))
        if grid[1] > grid[0]:
            placed = (ceil_to(start + grid[0] - source_in, frame),
                      floor_to(start + grid[1] - source_in, frame))
            if placed[1] > placed[0]:
                out.append(([w[2] for w in run], grid, placed))
        index = last + 1
    return out


# --------------------------------------------------------------------------
# The app rows


class Rows:
    def __init__(self):
        self.results = {}

    def score(self, row, ok, detail):
        self.results[row] = (bool(ok), detail)


def media_clips(session):
    clips = [c for c in session.project()["clips"] if c["source"]["kind"] == "media"]
    return sorted(clips, key=lambda c: (c["start"], c["track"]))


def detect(session, **arguments):
    return session.op("detect_fillers", **arguments)


def close(session):
    try:
        session.op("close_project", discard=True)
    except Exception:  # noqa: BLE001 — closing is housekeeping
        pass


def app_rows(results, wanted, binary, speech):
    import cloud_captions_proof as cloud
    import cloud_captions_probe
    import proof_app

    os.makedirs(cloud.WORK, exist_ok=True)
    words = cloud.DISFLUENT_WORDS
    try:
        proof_app.require_fresh(binary)
    except proof_app.StaleApp as stale:
        for row in wanted:
            results.score(row, False, f"not run: {stale}")
        return
    lock, waited, holder = cloud_captions_probe.hold_cloud_lock(1800)
    if lock is None:
        for row in wanted:
            results.score(row, False, f"not run: the cloud instruments' lock is held by {holder}")
        return

    def run(row, body):
        if row not in wanted:
            return
        try:
            ok, detail = body()
        except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
            ok, detail = False, f"{type(problem).__name__}: {problem}; " + \
                traceback.format_exc(limit=2).splitlines()[-1]
        results.score(row, ok, detail)

    # The lock is released however the run ends: closing() is entered first.
    with contextlib.closing(lock), cloud_captions_probe.Fake("fillers") as fake:
        instance = cloud.Instance("fillers", fake, str(binary))
        try:
            def m0():
                log = cloud.read(instance.log).decode("utf-8", "replace")
                complaints = [line for line in log.splitlines() if "Frame Job: " in line]
                schema = instance.mcp.schemas().get("detect_fillers", {})
                keys = sorted(schema.get("inputSchema", {}).get("properties", {}))
                return (not complaints and keys == ["clips", "project"],
                        f"parity lines {complaints[:3]}; detect_fillers properties {keys}")
            run("M0", m0)

            state = {}

            def m1():
                cloud.scenario(fake, disfluent_words=words)
                session = cloud.Session(instance, "fillers-M1")
                state["m1"] = session
                media = session.media_of(speech)
                clip = session.add(media, at=0, duration=5 * SEC)
                state.update(media=media, clip=clip)
                session.op("transcribe", engine="assemblyai", place=False)
                session.save()
                project = session.project()
                fps = list(project["canvas"]["fps"])
                frame = SEC * fps[1] // fps[0]
                rule = tr9(words, 0, 0, 5 * SEC, frame)
                state["rule"] = rule
                before = session.op("get_project")
                answer = detect(session)
                after = session.op("get_project")
                state["ranges"] = answer.get("ranges")
                fillers = answer.get("fillers") or [{}]
                want = [list(placed) for _, _, placed in rule]
                return (fps == [30, 1] and want == [[1460000, 1780000]]
                        and answer.get("ranges") == want
                        and fillers[0].get("words") == ["um,", "Uh", "er"]
                        and [g for _, g, _ in rule] == [(1459200, 1785600)]
                        and before == after,
                        f"fps {fps}; rule {rule}; ranges {answer.get('ranges')}, fillers "
                        f"{answer.get('fillers')}, dropped {answer.get('dropped')}, note "
                        f"{answer.get('note')!r}; get_project unchanged {before == after}")
            run("M1", m1)

            def m2():
                session, ranges = state.get("m1"), state.get("ranges")
                if session is None or not ranges:
                    return False, "M1 gave no ranges to cut"
                session.op("ripple_delete_ranges", ranges=ranges)
                clips = media_clips(session)
                shape = [(c["start"], c["duration"], c["source"]["in"]) for c in clips]
                (_, grid, placed), = state["rule"]
                on_grid = (grid[0] % G == 0 and grid[1] % G == 0
                           and ceil_to(grid[0], 20_000) == placed[0] == 1460000
                           and floor_to(grid[1], 20_000) == placed[1] == 1780000)
                windows = [(c["source"]["in"], c["source"]["in"] + c["duration"]) for c in clips]
                outside = all(hi <= 1470000 or lo >= 1770000 for lo, hi in windows)
                ok = (len(clips) == 2 and clips[0]["start"] == 0 and clips[0]["duration"] == 1460000
                      and clips[0]["source"]["in"] == 0 and clips[1]["start"] == 1460000
                      and clips[1]["source"]["in"] == 1780000 and on_grid and outside)
                session.op("undo")
                restored = media_clips(session)
                back = [(c["start"], c["duration"], c["source"]["in"]) for c in restored]
                return (ok and back == [(0, 5 * SEC, 0)],
                        f"after the cut (start, duration, in) {shape}, source windows {windows}, "
                        f"edges on the grid {on_grid}; after undo {back}")
            run("M2", m2)

            def m3():
                cloud.scenario(fake, disfluent_words=words)
                session = cloud.Session(instance, "fillers-M3")
                try:
                    media = session.media_of(speech)
                    clip = session.add(media, at=SEC // 2, duration=5 * SEC)
                    session.op("trim_start", clip=clip, to=SEC)
                    session.op("transcribe", engine="assemblyai", place=False)
                    placed = session.clip(clip)
                    rule = tr9(words, placed["start"], placed["source"]["in"],
                               placed["duration"], 20_000)
                    answer = detect(session, clips=[clip])
                    want = [list(p) for _, _, p in rule]
                    return (placed["start"] == SEC and placed["source"]["in"] == SEC // 2
                            and want == [[1760000, 2080000]] and answer.get("ranges") == want,
                            f"clip start {placed['start']} in {placed['source']['in']}; rule "
                            f"{rule}; ranges {answer.get('ranges')}")
                finally:
                    close(session)
            run("M3", m3)

            def m4():
                session, media = state.get("m1"), state.get("media")
                if session is None:
                    return False, "M1's session is not available"
                edits = ((cloud.cache_path(session, media, marker=True), '"disfluencies":true,', ""),
                         (cloud.cache_path(session, media), '"requested":{"disfluencies":true,',
                          '"requested":{'))
                found = []
                for path, before, after in edits:
                    text = cloud.read(path).decode("utf-8")
                    found.append(text.count(before) == 1)
                    with open(path, "wb") as handle:
                        handle.write(text.replace(before, after).encode("utf-8"))
                old = detect(session)
                fresh = cloud.Session(instance, "fillers-M4")
                try:
                    other = fresh.media_of(speech)
                    fresh.add(other, at=0, duration=5 * SEC)
                    never = detect(fresh)
                finally:
                    close(fresh)

                def fine(answer, media_id):
                    note = answer.get("note") or ""
                    return (answer.get("ranges") == [] and answer.get("needs_transcript") == [media_id]
                            and f"Media {media_id} has no transcript made with filler words" in note
                            and "(spec §11 TR-7)" in note and "refresh: true" in note)
                return (all(found) and fine(old, media) and fine(never, other),
                        f"raw edits found {found}; old transcript → ranges {old.get('ranges')}, "
                        f"needs {old.get('needs_transcript')}, note {old.get('note')!r}; never "
                        f"transcribed → ranges {never.get('ranges')}, needs "
                        f"{never.get('needs_transcript')}")
            run("M4", m4)

            def m5():
                session = state.get("m1")
                if session is None:
                    return False, "M1's session is not available"
                empty = session.error("detect_fillers", clips=[])
                unknown = session.error("detect_fillers", clips=[987654])
                return (empty == "detect_fillers: clips is empty — name at least one clip."
                        and unknown == "detect_fillers: No clip has id 987654. get_project lists "
                        "the clips.",
                        f"clips: [] → {empty!r}; unknown → {unknown!r}")
            run("M5", m5)
            if state.get("m1") is not None:
                close(state["m1"])

            def m6():
                cloud.scenario(fake, disfluent_words=words)
                session = cloud.Session(instance, "fillers-M6")
                try:
                    media = session.media_of(speech)
                    first = session.add(media, at=0, duration=5 * SEC)
                    tracks = [t["id"] for t in session.project()["tracks"]]
                    session.op("add_track")
                    new = [t["id"] for t in session.project()["tracks"] if t["id"] not in tracks][0]
                    second = session.add(media, at=180_000, track=new, duration=5 * SEC)
                    session.op("transcribe", engine="assemblyai", place=False)
                    covered = detect(session, clips=[first])
                    reason = ((covered.get("dropped") or [{}])[0]).get("reason", "")
                    session.op("set_track", track=new, locked=True)
                    open_ = detect(session, clips=[first])
                    session.op("set_track", track=new, locked=False)
                    session.op("set_track", track=tracks[0], locked=True)
                    locked = detect(session, clips=[first])
                    note = locked.get("note") or ""
                    return (covered.get("ranges") == []
                            and reason == f'it overlaps "everyone" in clip {second}'
                            and open_.get("ranges") == [[1460000, 1780000]]
                            and locked.get("ranges") == [] and locked.get("locked") == [first]
                            and f"Clip {first} is on a locked track" in note,
                            f"second clip unlocked → ranges {covered.get('ranges')}, reason "
                            f"{reason!r}; its track locked → {open_.get('ranges')}; track 0 "
                            f"locked → ranges {locked.get('ranges')}, locked "
                            f"{locked.get('locked')}, note {note!r}")
                finally:
                    close(session)
            run("M6", m6)
        finally:
            instance.stop()


# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    wanted = args.only.split(",") if args.only else (PROBE_ROWS if args.mutant else ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    if args.mutant and any(row in APP_ROWS for row in wanted):
        print("a mutant runs the probe rows only")
        return 2
    probe_wanted = [row for row in wanted if row in PROBE_ROWS]
    app_wanted = [row for row in wanted if row in APP_ROWS]
    if probe_wanted and "P0" not in probe_wanted:
        probe_wanted = ["P0"] + probe_wanted
    if app_wanted and "M0" not in app_wanted:
        app_wanted = ["M0"] + app_wanted
    wanted = [row for row in ROWS if row in probe_wanted + app_wanted]
    results = Rows()
    not_scored = []

    if probe_wanted:
        here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
        if here.exists():
            shutil.rmtree(here)
        here.mkdir(parents=True)
        sources = ROOT / "app/Sources"
        if args.mutant:
            why = mutate(args.mutant, here / "Sources")
            if why:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            sources = here / "Sources"
        binary, why = build(sources, here)
        results.score("P0", binary is not None, why or f"built from {sources}")
        if binary is None and args.mutant:
            print(f"P0 fail — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — the copy did "
                  "not build")
            return 2
        answers, why = (probe(binary, here) if binary is not None
                        else (None, "not run: the probe did not build"))
        for row in probe_wanted:
            if row == "P0":
                continue
            answer = next((a for a in answers or [] if a.get("id") == row), None)
            if answer is None:
                not_scored.append(row)
                results.score(row, False, f"no row: {why or 'the probe did not answer it'}")
            else:
                results.score(row, answer.get("pass") is True, answer.get("detail", ""))

    if app_wanted:
        import proof_app
        speech = ROOT / "tools/proof/media/speech.mov"
        if not speech.exists():
            for row in app_wanted:
                results.score(row, False, "media/speech.mov is missing: tools/proof/README.md "
                              "(\"Phase 4 adds a recording of SPEECH\") says how to make it")
        else:
            app_rows(results, app_wanted, proof_app.binary(), str(speech))
        for row in app_wanted:
            if row not in results.results:
                results.score(row, False, "not scored")

    for row in wanted:
        good, detail = results.results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results.results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored or row not in results.results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results.results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 1
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        cloud = sys.modules.get("cloud_captions_proof")
        if cloud is not None:
            from mcp import remove_scratch
            for scratch in cloud.SCRATCH:
                remove_scratch(scratch)
    sys.exit(code)
