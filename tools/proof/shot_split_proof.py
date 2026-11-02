#!/usr/bin/env python3
"""Road map "creator-jobs" CJ2b — the Analyzing sheet and Clip ▸ Split at Shot
Changes (spec §11 CJ-28, CJ-29).

    python3 tools/proof/shot_split_proof.py [--only S1,S4,…] [--mutant NAME]

The fixtures are `analysis_fixtures.py`'s `shots.mov` (cuts at frames 60, 120,
180 and 240, a flash at 150, a dissolve over 300…329) and `shots_sound.mov`
(the same picture with a sine track). Every row is a read-back: the tool's
answer, `get_project`, `undo`'s name, or the cache's marker. Each launch runs
on a scratch `CFFIXED_USER_HOME`; its packages are saved under
`tools/proof/work/shot-split-proof/`.

**Launch 1** (no hold), through `split_at_shots`:
- S1 `shots.mov` placed whole at 0 on a 30 fps canvas splits into five clips
  starting at frames 0, 60, 120, 180 and 240, each later piece's source `in`
  its cut's time; none at the flash (150) or inside the dissolve; `undo`
  answers "Split at Shot Changes" and one clip; `redo`.
- S2 a trimmed (in 1 s…9 s), a ×2 and a reversed placement: each clip's new
  starts are the proof's own arithmetic (in, speed, start, the media's
  duration, the nearest canvas frame, the edge rule), each cut once.
- S3 a placement from one frame before cut 60 to one frame after cut 240
  splits at 120 and 180 only (the edge rule).
- S4 `shots_sound.mov` detached (a linked sound), fillers to 4,091 clips:
  refused naming 8 and 5, the clip count and the undo top unchanged; three
  fillers deleted, it adds 8 and cuts the sound at the same four times.
- S4n a nest holding `shots.mov`, fillers to 4,093 clips counted with the
  nests; inside the nest refused naming 4 and 3 (the composite's sentence,
  not the core's "too many clips"); one filler deleted, it adds 4.
- S8 two placements playing 0…2 s and 8…10 s: the marker's coverage holds no
  range over index 150 (the union of the windows, never their hull).

**Launch 2** (`-RCDevAnalysisHold 3`), through the menu, each row on its own
fresh package so every press misses the cache:
- S5 Clip ▸ Split at Shot Changes puts the Analyzing sheet up; `cancel_sheet`
  (Stop): for 10 s no clip is added and no marker appears.
- S6 the sheet up; within 30 s the clip is split as S1, and `undo` answers
  "Split at Shot Changes".
- S7 the sheet up; `add_marker` while it is held: after it goes, nothing is
  split and the marker is kept.

Z1 is each launch's `grep "Frame Job: "`.

`--mutant NAME`: the named decision broken in a tree copy built by
`tree_copy.py` and only its row run; CAUGHT (exit 0) when that row fails.
"""

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import analysis_fixtures as fixtures  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/shot-split-proof"
HOME = WORK / "home"
CALL_BOUND = 600
BUILD_BOUND = 1500
SEC = 600_000
FRAME = 20_000  # ticks a frame at 30 fps
ACTION = "Split at Shot Changes"
MENU = ["Clip", ACTION]
PLAIN = ["S1", "S2", "S3", "S4", "S4n", "S8"]
HELD = ["S5", "S6", "S7"]
ROWS = PLAIN + HELD + ["Z1"]
HOLD = ["-RCDevAnalysisHold", "3"]
CEILING = 4096

MUTANTS = {
    "edge-rule-removed": (["S3"], [(
        "app/Sources/ShotSplit.swift",
        "                if t - clip.start <= frame || clip.end - t <= frame { continue }\n", "")]),
    "mirror-skipped": (["S2"], [(
        "app/Sources/AgentServer+Analysis.swift",
        "let played = pivot.map { ReverseMirror.mirrored(source, about: $0) } ?? source",
        "let played = source")]),
    "ceiling-after-first-split": (["S4"], [(
        "app/Sources/ShotSplit.swift",
        "guard added <= room else { throw Refusal.ceiling(added: added, room: max(0, room)) }",
        "_ = room")]),
    "partners-uncounted": (["S4"], [(
        "app/Sources/ShotSplit.swift",
        "if let partner, partner.start < t, t < partner.end { added += 1 }",
        "_ = partner")]),
    "ceiling-counts-scope": (["S4n"], [(
        "app/Sources/ShotSplit.swift",
        "clipCount(document.project.snapshot)", "clipCount(document.editedProject.snapshot)")]),
    "windows-hulled": (["S8"], [(
        "app/Sources/ShotSplit.swift",
        "let spans = group.map(\\.times.window)",
        "let spans = [(group.map(\\.times.window.lowerBound).min() ?? 0)"
        "...(group.map(\\.times.window.upperBound).max() ?? 0)]")]),
    "stop-keeps-want": (["S5"], [(
        "app/Sources/AnalyzingSheetController.swift",
        "        lane.release(owner: owner)\n", "")]),
    "stale-test-removed": (["S7"], [(
        "app/Sources/EditorViewController+ShotSplit.swift",
        "guard document.project === asked, document.scope == scope else {",
        "guard true else {")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


class Doc:
    """One saved package on a 1280 × 720, 30 fps canvas."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=1280, height=720, fps=[30, 1])
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def media(self, fixture):
        return self.call("import_media", path=str(fixture))["media"]

    def track(self, index=0):
        tracks = self.state()["tracks"]
        while len(tracks) <= index:
            self.call("add_track")
            tracks = self.state()["tracks"]
        return tracks[index]["id"]

    def place(self, media, track, at=0):
        return self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def split(self, **arguments):
        return self.call("split_at_shots", **arguments)

    def marker_path(self, media):
        return self.path / "cache/analysis/shots" / f"{media}.json"

    def coverage(self, media):
        path = self.marker_path(media)
        return json.loads(path.read_bytes())["coverage"] if path.exists() else None

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def all_clips(project):
    """Every clip the core's ceiling counts: the top level's and every nest's."""
    return len(project["clips"]) + sum(len(n.get("clips") or []) for n in project.get("nests") or [])


def on_track(project, track):
    return sorted((c for c in project["clips"] if c["track"] == track), key=lambda c: c["start"])


def frames_of(clips):
    return [c["start"] / FRAME for c in clips]


def expected_starts(clip, duration):
    """The proof's own arithmetic: the starts a split leaves on `clip`'s track."""
    source = clip["source"]
    cin, speed, start = source.get("in", 0), clip.get("speed", 1), clip["start"]
    end = start + clip["duration"]
    reversed_ = source.get("reversed", False)
    length = round(clip["duration"] * speed)
    low, high = (duration - cin - length, duration - cin) if reversed_ else (cin, cin + length)
    starts = {start}
    for k in fixtures.SHOTS_CUTS:
        s = k * FRAME
        if not low <= s < high:
            continue
        played = duration - s if reversed_ else s
        t = start + round((played - cin) / speed)
        t = round(t / FRAME) * FRAME
        if t - start <= FRAME or end - t <= FRAME:
            continue
        starts.add(t)
    return sorted(starts)


def fill(doc, track, count):
    """`count` one-frame text clips on `track`, by doubling `duplicate`s."""
    first = doc.call("add_text_clip", track=track, at=0, duration=FRAME)["new_clips"][0]
    ids = [first]
    while len(ids) * 2 <= count:
        doc.call("duplicate", clips=ids)
        ids = [c["id"] for c in on_track(doc.state(), track)]
    rest = count - len(ids)
    if rest:
        doc.call("duplicate", clips=ids[-rest:])
        ids = [c["id"] for c in on_track(doc.state(), track)]
    return ids


def undo_top(doc):
    """The undo stack's top step's name, read by an undo and its redo."""
    name = doc.call("undo").get("undone")
    doc.call("redo")
    return name


def refused(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


# ---- launch 1: the tool ----------------------------------------------------------

def s1(client):
    doc = Doc(client, "s1")
    media = doc.media(fixtures.shots())
    track = doc.track()
    doc.place(media, track)
    answer = doc.split()
    pieces = on_track(doc.state(), track)
    starts = frames_of(pieces)
    ins = [c["source"].get("in", 0) / FRAME for c in pieces]
    want = [0] + fixtures.SHOTS_CUTS
    undone = doc.call("undo").get("undone")
    after_undo = len(doc.state()["clips"])
    doc.call("redo")
    redone = len(doc.state()["clips"])
    check("S1", starts == want and ins == want and answer.get("added") == 4
          and undone == ACTION and after_undo == 1 and redone == 5,
          f"starts {starts}, ins {ins} (want {want}; none at {fixtures.FLASH} or in "
          f"{fixtures.DISSOLVE}); added {answer.get('added')}; undo {undone!r} → "
          f"{after_undo} clip(s); redo → {redone}")
    doc.close()


def s2(client):
    doc = Doc(client, "s2")
    media = doc.media(fixtures.shots())
    track = doc.track()
    made = []
    for at, edit in ((0, "trim"), (20 * SEC, "speed"), (40 * SEC, "reverse")):
        clip = doc.place(media, track, at)
        if edit == "trim":
            doc.call("trim_start", clip=clip, to=at + SEC)
            doc.call("trim_end", clip=clip, to=at + 9 * SEC)
        elif edit == "speed":
            doc.call("set_speed", clip=clip, rate=2)
        else:
            doc.call("set_reversed", clip=clip, reversed=True)
        made.append((edit, clip))
    project = doc.state()
    duration = next(m for m in project["media"] if m["id"] == media)["duration"]
    clips = {c["id"]: c for c in project["clips"]}
    want = {edit: expected_starts(clips[clip], duration) for edit, clip in made}
    spans = {edit: (clips[clip]["start"], clips[clip]["start"] + clips[clip]["duration"])
             for edit, clip in made}
    answer = doc.split()
    after = doc.state()["clips"]
    details, ok = [], True
    for edit, _ in made:
        low, high = spans[edit]
        got = sorted(c["start"] for c in after if c["track"] == track and low <= c["start"] < high)
        good = got == want[edit] and len(got) == len(set(got))
        ok = ok and good
        details.append(f"{edit}: {[g / FRAME for g in got]}"
                       + ("" if good else f" (want {[w / FRAME for w in want[edit]]})"))
    check("S2", ok and answer.get("added") == sum(len(w) - 1 for w in want.values()),
          "; ".join(details) + f"; added {answer.get('added')}")
    doc.close()


def s3(client):
    doc = Doc(client, "s3")
    media = doc.media(fixtures.shots())
    track = doc.track()
    clip = doc.place(media, track)
    doc.call("trim_start", clip=clip, to=59 * FRAME)
    doc.call("trim_end", clip=clip, to=241 * FRAME)
    answer = doc.split()
    starts = frames_of(on_track(doc.state(), track))
    check("S3", starts == [59, 120, 180] and answer.get("added") == 2,
          f"starts {starts} (want [59.0, 120.0, 180.0]: 60 and 240 lie one frame from an "
          f"edge); added {answer.get('added')}")
    doc.close()


def s4(client):
    doc = Doc(client, "s4")
    media = doc.media(fixtures.shots_sound())
    picture_track = doc.track()
    picture = doc.place(media, picture_track)
    doc.call("detach_audio", clip=picture)
    project = doc.state()
    sound = next(c for c in project["clips"] if c.get("linked") == picture)
    filler_track = doc.track(len(project["tracks"]))
    filler = fill(doc, filler_track, CEILING - 5 - 2)
    before = doc.state()
    top = undo_top(doc)
    message = refused(lambda: doc.split(clips=[picture])) or ""
    after = doc.state()
    top_after = undo_top(doc)
    held = (all_clips(before) == 4091 and all_clips(after) == 4091 and top_after == top
            and "would add 8 clips" in message and "5 more clips would fit" in message)
    doc.call("delete", clips=filler[-3:])
    answer = attempt(lambda: doc.split(clips=[picture]), "S4") or {}
    final = doc.state()
    pictures = frames_of(on_track(final, picture_track))
    sounds = frames_of(on_track(final, sound["track"]))
    want = [0] + fixtures.SHOTS_CUTS
    check("S4", held and answer.get("added") == 8 and pictures == want and sounds == want,
          f"at {all_clips(before)} clips refused: {message[:220]!r}; clips after "
          f"{all_clips(after)}, undo top {top!r} → {top_after!r}; three fillers deleted: added "
          f"{answer.get('added')}, picture {pictures}, sound {sounds} (want {want})")
    doc.close()


def s4n(client):
    doc = Doc(client, "s4n")
    media = doc.media(fixtures.shots())
    track = doc.track()
    picture = doc.place(media, track)
    doc.call("nest", clips=[picture])
    project = doc.state()
    nest = project["nests"][0]["id"]
    filler_track = doc.track(len(project["tracks"]))
    filler = fill(doc, filler_track, CEILING - 3 - 2)
    before = doc.state()
    doc.call("set_scope", nest=nest)
    message = refused(lambda: doc.split(clips=[picture])) or ""
    doc.call("set_scope")
    unchanged = all_clips(doc.state()) == all_clips(before)
    held = (all_clips(before) == 4093 and unchanged and "would add 4 clips" in message
            and "3 more clips would fit" in message and "too many clips" not in message)
    doc.call("delete", clips=filler[-1:])
    doc.call("set_scope", nest=nest)
    answer = attempt(lambda: doc.split(clips=[picture]), "S4n") or {}
    doc.call("set_scope")
    check("S4n", held and answer.get("added") == 4,
          f"at {all_clips(before)} clips (nests counted), inside the nest refused: "
          f"{message[:220]!r}; unchanged {unchanged}; one filler deleted: added "
          f"{answer.get('added')}")
    doc.close()


def s8(client):
    doc = Doc(client, "s8")
    media = doc.media(fixtures.shots())
    track = doc.track()
    first = doc.place(media, track, 0)
    doc.call("trim_end", clip=first, to=2 * SEC)
    second = doc.place(media, track, 3 * SEC)
    doc.call("trim_end", clip=second, to=5 * SEC)
    doc.call("slip", clip=second, delta=8 * SEC)
    answer = doc.split()
    coverage = doc.coverage(media) or []
    flash = fixtures.FLASH
    holds = [r for r in coverage if r[0] <= flash <= r[1]]
    check("S8", coverage and not holds,
          f"coverage {coverage} (no range may hold {flash}); added {answer.get('added')}")
    doc.close()


def plain_rows(client):
    for name, body in (("S1", s1), ("S2", s2), ("S3", s3), ("S4", s4), ("S4n", s4n),
                       ("S8", s8)):
        if name in selected:
            attempt(lambda: body(client), name)


# ---- launch 2: the menu, held -----------------------------------------------------

def menu_doc(client, name):
    doc = Doc(client, name)
    media = doc.media(fixtures.shots())
    track = doc.track()
    clip = doc.place(media, track)
    doc.call("save_project")
    doc.call("set_selection", clips=[clip])
    pressed = doc.call("perform_menu_item", path=MENU)
    return doc, media, track, clip, pressed.get("sheet")


def sheet_up(doc):
    return ((doc.call("perform_menu_item").get("window") or {}).get("sheet")) is not None


def wait_no_sheet(doc, bound=30):
    began = time.monotonic()
    while time.monotonic() - began < bound:
        if not sheet_up(doc):
            return time.monotonic() - began
        time.sleep(0.1)
    return None


def s5(client):
    doc, media, _, _, sheet = menu_doc(client, "s5")
    doc.call("cancel_sheet")
    began = time.monotonic()
    clips, marker = 1, False
    while time.monotonic() - began < 10:
        clips = len(doc.state()["clips"])
        marker = doc.marker_path(media).exists()
        if clips != 1 or marker:
            break
        time.sleep(0.5)
    check("S5", sheet is not None and clips == 1 and not marker,
          f"sheet {sheet!r}; after Stop, over {time.monotonic() - began:.1f} s: clips {clips}, "
          f"marker {'WRITTEN' if marker else 'absent'}")
    doc.close()


def s6(client):
    doc, _, track, _, sheet = menu_doc(client, "s6")
    began = time.monotonic()
    starts = []
    while time.monotonic() - began < 30:
        starts = frames_of(on_track(doc.state(), track))
        if len(starts) > 1:
            break
        time.sleep(0.25)
    gone = wait_no_sheet(doc)
    undone = doc.call("undo").get("undone")
    want = [0] + fixtures.SHOTS_CUTS
    check("S6", sheet is not None and starts == want and gone is not None and undone == ACTION,
          f"sheet {sheet!r}; after {time.monotonic() - began:.1f} s starts {starts} (want "
          f"{want}); the sheet gone {gone is not None}; undo {undone!r}")
    doc.close()


def s7(client):
    doc, _, track, _, sheet = menu_doc(client, "s7")
    doc.client.call_with("add_marker", {"project": str(doc.path), "at": 30 * FRAME,
                                        "name": "while analyzing"})
    gone = wait_no_sheet(doc)
    time.sleep(1)
    project = doc.state()
    starts = frames_of(on_track(project, track))
    markers = [m.get("name") for m in project.get("markers") or []]
    check("S7", sheet is not None and gone is not None and starts == [0]
          and markers == ["while analyzing"],
          f"sheet {sheet!r}; gone after {gone if gone is None else round(gone, 2)} s; starts "
          f"{starts} (want [0.0]: the project changed); markers {markers}")
    doc.close()


def held_rows(client):
    for name, body in (("S5", s5), ("S6", s6), ("S7", s7)):
        if name in selected:
            attempt(lambda: body(client), name)


# ---- launches ---------------------------------------------------------------------

def launch(binary, arguments, tag):
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    plans = [("plain", [], plain_rows, set(PLAIN)), ("held", HOLD, held_rows, set(HELD))]
    for tag, arguments, body, rows in plans:
        if not selected & rows:
            continue
        launched, log = launch(binary, arguments, tag)
        try:
            if launched.client is None:
                for row in selected & rows:
                    check(row, False, f"the app did not listen ({tag})")
                continue
            print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
            body(launched.client)
        finally:
            launched.stop()
        parity(log, tag)


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    fixtures.shots()
    fixtures.shots_sound()
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"CJ2b — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CJ2b — Split at Shot Changes ({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
