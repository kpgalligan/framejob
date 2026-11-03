#!/usr/bin/env python3
"""Road map "creator-jobs" VR2a2 — `reframe_clip` (spec §11 VR-24…VR-26, VR-28).

    python3 tools/proof/vr2a_proof.py [--only 1,3,8] [--mutant NAME] [--app PATH]

The media is `face_fixtures.py`'s `faces_moving.mov` (1920 × 1080, 30 fps,
60 s), copied once per document; the analyses are canned
(`canned_framing.py`, spec §11 CJ-26) in launch 1 and real in launch 2. Every
project is 1080 × 1920 at 30 fps; every placement is read back through
`get_project` and evaluated here — the clip's base, then each action eased by
`actions::ease`'s four closed forms — and a face's canvas position is (★) at
θ = 0: `W/2 + x + scale·(fx − 960)`, `H/2 + y + scale·(fy − 540)`.

**Launch 1** (`-RCDevAnalysisCanned YES`), rows 1–8:
1. A canned face panning 400 → 1520 px over a 20 s clip, `follow: face`: the
   face is inside the canvas's central 60 % (the window IS the canvas) at
   ≥ 98 % of the 10-a-second samples and on the canvas at 100 %.
2. A magenta canvas, the canned exit (still, gone 4–6 s, back) followed with
   `where_empty: center`: `render_frame`'s four corners are never magenta at
   40 frames across the clip.
3. A still canned face: the clip gets a base and no action.
4. Canned cuts at frames 300 and 600: the placement's `x` is the same at every
   frame up to the one before each cut and changes exactly at the cut's frame.
5. The canned exit with a backdrop track: no action starts in the 1 s after
   the face is lost, the ease to fit starts exactly 1 s after it, and exactly
   one "Blurred Background" clip sits on the named track.
6. A ×2 clip and a reversed clip of the pan: each sample `get_media_analysis
   {clip, kind: faces}` places at its `clip_time` (the app's `SourceMap` and
   `ReverseMirror`) is contained as in row 1.
7. A `slide_left` arrival: the motion is kept and, outside its span, row 2's
   corners hold.
8. Every refusal is the core's sentence (a text clip, a clip with an action, a
   matte track's clip, a turned clip), a bad `zoom` the core's error, and a
   caller's own `subjects` the gate's stranger.

**Launch 2** (`-RCDevAnalysisHold 30`, an uncached copy), row 9: a clip on a
matte track answers the core's sentence within 5 s with no `analyzing` and the
lane's queued count unchanged; then a plain clip's call passes the 60 s bound
(the three kinds' 30 s holds run in series, `pictureWidth` 1) and answers
`analyzing` with `get_project` unchanged; once the three markers are on disk
the same call applies. Z1 is each launch's parity grep.

`--mutant bound-ignored`: `AgentServer+Framing.swift`'s wait given no deadline,
in a Release copy of the tree (`tree_copy.py`); CAUGHT (exit 0) when row 9
fails. The core's mutants run against `cargo test`.
"""

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import canned_framing  # noqa: E402
import face_fixtures  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
from e1_proof import decode_png  # noqa: E402

WORK = ROOT / "tools/proof/work/vr2a-proof"
HOME = WORK / "home"
CALL_BOUND = 400
BUILD_BOUND = 1500
SEC = 600_000
FRAME = 20_000
W, H = 1080, 1920
MAGENTA = (255, 0, 255)
FIT = 0.5625
K = 1920 / 1080
ROWS = [str(n) for n in range(1, 10)] + ["Z1"]
LAUNCH_1 = [str(n) for n in range(1, 9)]

MUTANTS = {
    "bound-ignored": (["9"], [(
        "app/Sources/AgentServer+Framing.swift",
        "            deadline: Date().addingTimeInterval(AnalysisLane.callWaitLimit),\n",
        "            deadline: .distantFuture,\n")]),
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


# ---- placement ------------------------------------------------------------------

def ease(curve, u):
    u = min(1.0, max(0.0, u))
    return {"linear": u, "ease_in": u * u, "ease_out": 1 - (1 - u) * (1 - u),
            "ease_in_out": u * u * (3 - 2 * u)}[curve]


def placement(clip, t):
    """(scale, x, y) at clip tick `t`: the base, each action eased from the
    value before it (`actions.rs`)."""
    video = clip.get("video") or {}
    cur = [video.get("scale", 1.0), video.get("x", 0.0), video.get("y", 0.0)]
    for action in sorted(clip.get("actions", []), key=lambda a: a["start"]):
        end = (action.get("end") or {}).get("video") or {}
        target = [end.get("scale", cur[0]), end.get("x", cur[1]), end.get("y", cur[2])]
        start, length = action["start"], action["duration"]
        if t >= start + length:
            cur = target
        elif t > start:
            e = ease(action.get("curve", "linear"), (t - start) / length)
            cur = [a + (b - a) * e for a, b in zip(cur, target)]
            break
        else:
            break
    return tuple(cur)


def on_canvas(clip, t, box):
    """A box's centre (0…1 of the 1920 × 1080 picture) on the canvas at `t`."""
    scale, x, y = placement(clip, t)
    fx, fy = (box[0] + box[2] / 2) * 1920, (box[1] + box[3] / 2) * 1080
    return W / 2 + x + scale * (fx - 960), H / 2 + y + scale * (fy - 540)


def containment(pairs):
    """`pairs` of (clip, t, box): (in the central 60 %, on the canvas, n)."""
    central = inside = 0
    for clip, t, box in pairs:
        cx, cy = on_canvas(clip, t, box)
        central += abs(cx - W / 2) <= 0.3 * W and abs(cy - H / 2) <= 0.3 * H
        inside += 0 <= cx <= W and 0 <= cy <= H
    return central, inside, len(pairs)


def box_of(face):
    return [face["x"], face["y"], face["w"], face["h"]]


# ---- the documents --------------------------------------------------------------

class Doc:
    def __init__(self, client, name, canned=True):
        self.client = client
        self.name = name
        self.path = WORK / f"{name}.framejob"
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        self.call("save_project")
        self.canned = canned

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.state()["clips"] if c["id"] == clip)

    def track(self, index=0):
        return self.state()["tracks"][index]["id"]

    def media(self, scenario=None, cut_frames=()):
        copy = WORK / "media" / f"{self.name}.mov"
        copy.parent.mkdir(parents=True, exist_ok=True)
        if not copy.exists():
            copy.write_bytes(face_fixtures.path("faces_moving").read_bytes())
        media = self.call("import_media", path=str(copy))["media"]
        row = next(m for m in self.state()["media"] if m["id"] == media)
        fps = row["fps"] if isinstance(row["fps"], list) else [row["fps"]["num"],
                                                               row["fps"]["den"]]
        if scenario is not None:
            canned_framing.write(self.path, media, copy, row["duration"], fps, scenario,
                                 cut_frames)
        return media

    def clip_of(self, media, seconds, track=None, at=0):
        track = track if track is not None else self.track()
        clip = self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]
        self.call("trim_end", clip=clip, to=at + seconds * SEC)
        return clip

    def reframe(self, clip, **arguments):
        return self.call("reframe_clip", clip=clip, **arguments)

    def corners(self, t):
        out = WORK / "frames" / f"{self.name}-{t}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        self.call("render_frame", t=int(t), path=str(out), max_width=270)
        width, height, depth, channels, rows = decode_png(str(out))
        step = 2 if depth == 16 else 1

        def pixel(x, y):
            row = rows[y]
            at = x * channels * step
            return tuple(row[at + c * step] for c in range(3))
        return [pixel(x, y) for x, y in ((1, 1), (width - 2, 1), (1, height - 2),
                                         (width - 2, height - 2))]

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def magenta(pixel):
    return all(abs(a - b) <= 8 for a, b in zip(pixel, MAGENTA))


def refused(body, sentence):
    """The tool's answer to a refused op: `editResult`'s "… was refused at
    reframe_clip: " and the core's sentence."""
    try:
        answer = body()
    except mcp.ToolError as error:
        text = str(error)
        return text.endswith(f"reframe_clip: {sentence}"), text
    return False, f"applied: {json.dumps(answer)[:200]}"


# ---- launch 1 -------------------------------------------------------------------

def pan_rows(client):
    def row1():
        doc = Doc(client, "pan")
        media = doc.media(lambda t: canned_framing.pan(t, 20.0))
        clip = doc.clip_of(media, 20)
        answer = doc.reframe(clip, follow="face")
        framed = doc.clip(clip)
        pairs = [(framed, n * SEC // 10, box_of(canned_framing.pan(n / 10, 20.0)[0]))
                 for n in range(200)]
        central, inside, n = containment(pairs)
        check("1", answer.get("ok") and answer.get("cached") is True and central >= 0.98 * n
              and inside == n,
              f"{central}/{n} samples in the central 60 % (want ≥ 98 %), {inside}/{n} on the "
              f"canvas; {len(framed.get('actions', []))} actions; cached {answer.get('cached')}")
        doc.close()
    if "1" in selected:
        attempt(row1, "1")

    def row6():
        doc = Doc(client, "rates")
        media = doc.media(lambda t: canned_framing.pan(t, 60.0))
        fast = doc.clip_of(media, 20)
        doc.call("set_speed", clip=fast, rate=2.0)
        back = doc.call("add_track")["new_tracks"][0]
        reverse = doc.clip_of(media, 20, track=back)
        doc.call("set_reversed", clip=reverse, reversed=True)
        details, ok = [], True
        for name, clip in (("×2", fast), ("reversed", reverse)):
            doc.reframe(clip, follow="face")
            framed = doc.clip(clip)
            rows = doc.call("get_media_analysis", clip=clip, kind="faces")["samples"]
            pairs = [(framed, r["clip_time"], r["faces"][0]["box"]) for r in rows
                     if r.get("clip_time") is not None and r["faces"]
                     and 0 <= r["clip_time"] < framed["duration"]]
            central, inside, n = containment(pairs)
            good = n > 0 and central >= 0.98 * n and inside == n
            ok = ok and good
            details.append(f"{name}: {central}/{n} central, {inside}/{n} on the canvas")
        check("6", ok, "; ".join(details))
        doc.close()
    if "6" in selected:
        attempt(row6, "6")


def coverage_rows(client):
    def row2():
        doc = Doc(client, "cover")
        doc.call("set_canvas", background=[1, 0, 1, 1])
        media = doc.media(canned_framing.exit_and_back)
        clip = doc.clip_of(media, 10)
        doc.reframe(clip, follow="face", where_empty="center")
        bad = []
        for n in range(40):
            t = n * 10 * SEC // 40
            corners = doc.corners(t)
            if any(magenta(c) for c in corners):
                bad.append((t, corners))
        check("2", not bad, f"40 frames over 10 s, magenta corners at {bad[:3] or 'none'}")
        doc.close()
    if "2" in selected:
        attempt(row2, "2")

    def row7():
        doc = Doc(client, "slide")
        doc.call("set_canvas", background=[1, 0, 1, 1])
        media = doc.media(lambda t: canned_framing.pan(t, 20.0))
        clip = doc.clip_of(media, 20)
        doc.call("set_video", clips=[clip],
                 patch={"motion": {"in": {"kind": "slide_left", "duration": SEC // 2}}})
        doc.reframe(clip, follow="face")
        framed = doc.clip(clip)
        motion = ((framed.get("video") or {}).get("motion") or {}).get("in") or {}
        bad = []
        for n in range(40):
            t = SEC // 2 + FRAME + n * (20 * SEC - SEC // 2 - FRAME) // 40
            corners = doc.corners(t)
            if any(magenta(c) for c in corners):
                bad.append((t, corners))
        check("7", motion.get("kind") == "slide_left" and not bad,
              f"motion in {motion}; 40 frames after its span, magenta corners at "
              f"{bad[:3] or 'none'}")
        doc.close()
    if "7" in selected:
        attempt(row7, "7")


def path_rows(client):
    def row3():
        doc = Doc(client, "still")
        media = doc.media(canned_framing.still)
        clip = doc.clip_of(media, 10)
        doc.reframe(clip, follow="face")
        framed = doc.clip(clip)
        scale, x, y = placement(framed, 0)
        check("3", not framed.get("actions") and abs(scale - K) < 1e-9 and abs(x) < 1e-3,
              f"{len(framed.get('actions', []))} actions (want 0); base scale {scale:.6f} x {x} "
              f"y {y}")
        doc.close()
    if "3" in selected:
        attempt(row3, "3")

    def row4():
        doc = Doc(client, "cuts")
        media = doc.media(canned_framing.cuts, canned_framing.CUT_FRAMES)
        clip = doc.clip_of(media, 30)
        doc.reframe(clip, follow="face")
        framed = doc.clip(clip)
        details, ok = [], True
        for cut in canned_framing.CUT_FRAMES:
            xs = {f: placement(framed, f * FRAME)[1] for f in range(cut - 5, cut + 6)}
            held = all(abs(xs[f] - xs[cut - 5]) < 1e-9 for f in range(cut - 5, cut))
            after = all(abs(xs[f] - xs[cut]) < 1e-9 for f in range(cut, cut + 6))
            changed = abs(xs[cut] - xs[cut - 1]) > 1.0
            ok = ok and held and after and changed
            details.append(f"frame {cut}: x {xs[cut - 1]:.2f} at {cut - 1}, {xs[cut]:.2f} at "
                           f"{cut} (held before {held}, held after {after})")
        check("4", ok, "; ".join(details))
        doc.close()
    if "4" in selected:
        attempt(row4, "4")

    def row5():
        doc = Doc(client, "exit")
        media = doc.media(canned_framing.exit_and_back)
        front = doc.track()
        behind = doc.call("add_track", index=0)["new_tracks"][0]
        clip = doc.clip_of(media, 10, track=front)
        doc.reframe(clip, follow="face", backdrop=behind)
        state = doc.state()
        framed = next(c for c in state["clips"] if c["id"] == clip)
        starts = [(a["start"], a["duration"], (a["end"].get("video") or {}).get("scale"))
                  for a in framed.get("actions", [])]
        lost = 4 * SEC
        quiet = not any(lost <= s < lost + SEC for s, _, _ in starts)
        ease_at = next((s for s, d, scale in starts if s >= lost and scale is not None
                        and abs(scale - FIT) < 1e-9), None)
        copies = [c for c in state["clips"] if c["track"] == behind]
        check("5", quiet and ease_at == lost + SEC and len(copies) == 1
              and copies[0].get("name") == "Blurred Background",
              f"actions {starts}; the ease to fit starts at {ease_at} (want {lost + SEC}); "
              f"{len(copies)} clip(s) on track {behind}: "
              f"{[c.get('name') for c in copies]}")
        doc.close()
    if "5" in selected:
        attempt(row5, "5")


def refusal_row(client):
    doc = Doc(client, "refusals")
    media = doc.media(canned_framing.still)
    track = doc.track()
    details, ok = [], True

    def expect(label, clip, sentence, **arguments):
        nonlocal ok
        good, text = refused(lambda: doc.reframe(clip, **arguments), sentence)
        ok = ok and good
        details.append(f"{label}: {'ok' if good else text}")

    text = doc.call("add_text_clip", track=track, at=0)["new_clips"][0]
    expect("text", text, f"clip {text} is a text clip, with no picture to frame; only keep "
           "reframes it", follow="fit")
    acted = doc.clip_of(media, 4, at=10 * SEC)
    doc.call("add_action", clip=acted, at=0)
    expect("actions", acted, f"clip {acted} carries actions, which framing cannot compose with "
           "in this build", follow="center")
    turned = doc.clip_of(media, 4, at=20 * SEC)
    doc.call("set_video", clips=[turned], patch={"rotation": 90})
    expect("turned", turned, f"clip {turned} is turned 90°, and framing works on an upright "
           "picture; only keep reframes it", follow="face")
    matte_track = doc.call("add_track")["new_tracks"][0]
    doc.call("set_track", track=matte_track, matte="alpha")
    matted = doc.clip_of(media, 4, track=matte_track, at=30 * SEC)
    expect("matte", matted, f"clip {matted} is on a matte track, which framing would move; only "
           "keep reframes it", follow="fit")
    plain = doc.clip_of(media, 4, at=40 * SEC)
    try:
        doc.reframe(plain, follow="center", zoom=5)
        good, why = False, "applied"
    except mcp.ToolError as error:
        why = str(error)
        good = "zoom must be between 1 and 4 times fill, not 5" in why
    ok = ok and good
    details.append(f"zoom 5: {'ok' if good else why}")
    try:
        doc.reframe(plain, follow="face", subjects={"samples": [], "shots": []})
        good, why = False, "applied"
    except mcp.ToolError as error:
        why = str(error)
        good = "subjects" in why
    ok = ok and good
    details.append(f"a caller's subjects: {'ok' if good else why}")
    check("8", ok, "; ".join(details))
    doc.close()


# ---- launch 2 -------------------------------------------------------------------

def held_row(client):
    doc = Doc(client, "held", canned=False)
    media = doc.media()
    # An empty track between, so the matte cuts it and not the plain clip's.
    doc.call("add_track")
    matte_track = doc.call("add_track")["new_tracks"][0]
    doc.call("set_track", track=matte_track, matte="alpha")
    matted = doc.clip_of(media, 3, track=matte_track, at=20 * SEC)
    clip = doc.clip_of(media, 3, track=doc.track(), at=0)
    doc.call("save_project")
    queued = doc.call("analysis_job")["lane_queued"]
    began = time.monotonic()
    good, text = refused(lambda: doc.reframe(matted, follow="face"),
                         f"clip {matted} is on a matte track, which framing would move; only "
                         "keep reframes it")
    quick = time.monotonic() - began
    unqueued = doc.call("analysis_job")["lane_queued"] == queued
    first_ok = good and quick <= 5 and unqueued
    before = doc.clip(clip)
    began = time.monotonic()
    answer = doc.reframe(clip, follow="face")
    waited = time.monotonic() - began
    after = doc.clip(clip)
    analyzing = answer.get("analyzing")
    unchanged = before == after
    markers = [doc.path / "cache/analysis" / kind / f"{media}.json"
               for kind in ("shots", "faces", "subjects")]
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline and not all(m.exists() for m in markers):
        time.sleep(1)
    landed = all(m.exists() for m in markers)
    applied = doc.reframe(clip, follow="face") if landed else {}
    framed = doc.clip(clip)
    check("9", first_ok and analyzing is not None and unchanged and landed
          and applied.get("ok") and "analyzing" not in applied and framed != before,
          f"matte clip: refused {good} in {quick:.2f} s, lane queue unchanged {unqueued} "
          f"({text if not good else 'the core sentence'}); plain clip after {waited:.1f} s: "
          f"analyzing {analyzing}, note {answer.get('note')!r}, project unchanged {unchanged}; "
          f"markers landed {landed}; the same call then applied {bool(applied.get('ok'))} "
          f"(cached {applied.get('cached')})")
    doc.close()


# ---- launches -------------------------------------------------------------------

def launch(binary, arguments, label):
    log = WORK / f"instance-{label}.log"
    launched = mcp.launch(str(binary), list(arguments),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def run_launch(binary, arguments, label, rows, body):
    launched, log = launch(binary, arguments, label)
    try:
        if launched.client is None:
            for row in rows:
                check(row, False, "the app did not listen")
        else:
            print(f"  {label} instance PID {launched.child.pid}", flush=True)
            body(launched.client)
    finally:
        launched.stop()
    parity(log)


def launch_one(client):
    pan_rows(client)
    coverage_rows(client)
    path_rows(client)
    if "8" in selected:
        attempt(lambda: refusal_row(client), "8")


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "vr2a-mutant"))
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
        selected = {r.strip() for r in args.only.split(",") if r.strip()} | {"Z1"}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    try:
        face_fixtures.make()
    except face_fixtures.Missing as missing:
        print(f"  FAIL fixtures: {missing} is missing")
        return 1
    binary = Path(args.app) if args.app else None
    if args.mutant:
        print(f"VR2a2 — the {args.mutant} MUTANT (row 9 must FAIL)", flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"VR2a2 — reframe_clip ({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    if selected & set(LAUNCH_1):
        run_launch(binary, ["-RCDevAnalysisCanned", "YES"], "canned", LAUNCH_1, launch_one)
    if "9" in selected:
        run_launch(binary, ["-RCDevAnalysisHold", "30"], "held", ["9"],
                   lambda client: attempt(lambda: held_row(client), "9"))
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        caught = "9" in failed
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: row 9 "
              f"{'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
