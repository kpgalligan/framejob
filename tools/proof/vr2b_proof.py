#!/usr/bin/env python3
"""Road map "creator-jobs" VR2b1 — a framing composed into a clip's actions,
and `reframe_clip`'s `replace` (spec §11 VR-27).

    python3 tools/proof/vr2b_proof.py [--only 1,4,5] [--app PATH]

One launch with `-RCDevAnalysisCanned YES`: the analyses are canned
(`canned_framing.py`, spec §11 CJ-26) over `face_fixtures.py`'s
`faces_moving.mov` (1920 × 1080, 30 fps, 60 s), copied once per document; row
2's copy carries a 440 Hz tone (ffmpeg, stream-copied picture). Every project
is 1080 × 1920 at 30 fps; every placement is read back through `get_project`.
With zoom 1 the window is 607.5 × 1080 source px at k = K = 16/9; a still
face at picture x 600 lies at source x 180, so the base is (K, 360K, 0).

1. A still face at picture x 600 on a clip at scale 1 (`set_video`; `add_clip`
   fits it at 0.5625) with a zoom action [2, 3) s ending
   at `{scale: 1.5, x: 180}` (which keeps the face at source x 180): the base
   and the action's end are F∘old with ONE (k, dx, dy), solved from each
   (`k = s′/s`, `dx = x′ − k·x`, `dy = y′ − k·y`) and equal to 1e-6; dx is
   360K to 1e-3 (the canned boxes are stored as float32).
2. A linear volume action [5, 15) s straddling the canned cut at frame 300
   (10 s): it is split into three, and an `audio_wav` export before and after
   is identical sample for sample (ffmpeg to float32).
3. An eased (`ease_in_out`) volume action at the same cut: the head keeps its
   id and `ease_in_out` and ends at `c − frame`, the cut piece is one frame of
   `linear`, and the tail runs from `c` with `ease_in_out` and the old end.
4. `replace: true` with `follow: fit` on a clip whose actions are `{video:
   {scale: 2, x: 10}, audio: {volume: 0.5}}` and `{video: {x: 50}}`: no end
   names x, y or scale, the volume is kept, the x-only action is gone, and the
   base is Fit (scale 0.5625, x = y = 0).
5. A speed action (×1.5) straddling the cut: its id, start and duration are
   unchanged, it is the only action over its span, and its end carries x, y
   and scale beside its speed.
8. A magenta canvas, a canned pan followed with a zoom action and a volume
   action on the clip: `render_frame`'s four corners are never magenta at 40
   frames across it.
Z1. The launch's parity grep.

The core's mutants run against `cargo test` (tools/proof/README.md's VR2b1
section names each and the test that catches it).
"""

import argparse
import array
import json
import sys
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

WORK = ROOT / "tools/proof/work/vr2b-proof"
HOME = WORK / "home"
CALL_BOUND = 400
FFMPEG_BOUND = 120
SEC = 600_000
FRAME = 20_000
W, H = 1080, 1920
MAGENTA = (255, 0, 255)
FIT = 0.5625
K = 1920 / 1080
CUT = 10 * SEC  # canned_framing.CUT_FRAMES[0] at 30 fps
ROWS = ["1", "2", "3", "4", "5", "8", "Z1"]

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


def close(a, b, tolerance=1e-6):
    return abs(a - b) <= tolerance


# ---- the documents --------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.name = name
        self.path = WORK / f"{name}.framejob"
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.state()["clips"] if c["id"] == clip)

    def track(self, index=0):
        return self.state()["tracks"][index]["id"]

    def media(self, faces_at, cut_frames=(), tone=False):
        copy = WORK / "media" / f"{self.name}.mov"
        copy.parent.mkdir(parents=True, exist_ok=True)
        if not copy.exists():
            source = face_fixtures.path("faces_moving")
            if tone:
                ran = bounded.run(
                    ["ffmpeg", "-v", "error", "-y", "-i", str(source), "-f", "lavfi", "-i",
                     "sine=frequency=440:sample_rate=48000:duration=60", "-map", "0:v:0",
                     "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-shortest", str(copy)],
                    FFMPEG_BOUND)
                if ran["expired"] or ran["rc"] != 0:
                    raise RuntimeError(f"ffmpeg: {ran['stderr'][-300:]}")
            else:
                copy.write_bytes(source.read_bytes())
        media = self.call("import_media", path=str(copy))["media"]
        row = next(m for m in self.state()["media"] if m["id"] == media)
        fps = row["fps"] if isinstance(row["fps"], list) else [row["fps"]["num"],
                                                               row["fps"]["den"]]
        canned_framing.write(self.path, media, copy, row["duration"], fps, faces_at,
                             cut_frames)
        return media

    def clip_of(self, media, seconds, at=0):
        clip = self.call("add_clip", track=self.track(), media=media, at=at)["new_clips"][0]
        self.call("trim_end", clip=clip, to=at + seconds * SEC)
        return clip

    def action(self, clip, at, duration, patch, curve=None):
        added = self.call("add_action", clip=clip, at=at, duration=duration)
        action = added["new_actions"][0]
        self.call("set_action_end", clip=clip, action=action, patch=patch)
        if curve not in (None, "linear"):
            self.call("set_action", clip=clip, action=action, curve=curve)
        return action

    def reframe(self, clip, **arguments):
        return self.call("reframe_clip", clip=clip, **arguments)

    def export_pcm(self, tag):
        out = WORK / "exports" / f"{self.name}-{tag}.wav"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.unlink(missing_ok=True)
        self.client.export_with({"project": str(self.path), "preset": "audio_wav",
                                 "path": str(out)})
        raw = out.with_name(out.name + ".f32")
        ran = bounded.run(["ffmpeg", "-v", "error", "-y", "-i", str(out), "-map", "0:a:0",
                           "-f", "f32le", "-acodec", "pcm_f32le", str(raw)], FFMPEG_BOUND)
        if ran["expired"] or ran["rc"] != 0:
            raise RuntimeError(f"ffmpeg: {ran['stderr'][-300:]}")
        data = array.array("f", raw.read_bytes())
        raw.unlink(missing_ok=True)
        return data

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


def video(end):
    return (end or {}).get("video") or {}


def at_600(t):
    return [canned_framing.face(600.0)]


# ---- the rows -------------------------------------------------------------------

def row1(client):
    doc = Doc(client, "zoom")
    media = doc.media(at_600)
    clip = doc.clip_of(media, 10)
    doc.call("set_video", clips=[clip], patch={"scale": 1.0})
    action = doc.action(clip, 2 * SEC, SEC, {"video": {"scale": 1.5, "x": 180.0}},
                        curve="ease_in_out")
    doc.reframe(clip, follow="face")
    framed = doc.clip(clip)
    base = framed.get("video") or {}
    actions = framed.get("actions", [])
    end = video(next((a for a in actions if a["id"] == action), {}).get("end"))

    def solve(new, old):
        k = new.get("scale", 1.0) / old[0]
        return (k, new.get("x", 0.0) - k * old[1], new.get("y", 0.0) - k * old[2])
    f0 = solve(base, (1.0, 0.0, 0.0))
    f1 = solve(end, (1.5, 180.0, 0.0))
    one = all(close(a, b) for a, b in zip(f0, f1))
    check("1", len(actions) == 1 and one and close(f0[0], K) and close(f0[1], 360 * K, 1e-3),
          f"{len(actions)} action(s); F from the base {tuple(round(v, 6) for v in f0)}, from "
          f"the end {tuple(round(v, 6) for v in f1)} (want one, (K, 360K, 0))")
    doc.close()


def cut_doc(client, name, tone=False):
    doc = Doc(client, name)
    media = doc.media(canned_framing.cuts, canned_framing.CUT_FRAMES, tone=tone)
    return doc, doc.clip_of(media, 15)


def row2(client):
    doc, clip = cut_doc(client, "linear", tone=True)
    doc.action(clip, 5 * SEC, 10 * SEC, {"audio": {"volume": 0.3}}, curve="linear")
    before = doc.export_pcm("before")
    doc.reframe(clip, follow="face")
    framed = doc.clip(clip)
    spans = sorted((a["start"], a["duration"]) for a in framed.get("actions", [])
                   if "audio" in (a.get("end") or {}))
    after = doc.export_pcm("after")
    differ = sum(1 for a, b in zip(before, after) if a != b)
    check("2", len(spans) == 3 and len(before) == len(after) and len(before) > 0
          and differ == 0,
          f"volume pieces {spans}; {len(before)} and {len(after)} samples, {differ} differ")
    doc.close()


def row3(client):
    doc, clip = cut_doc(client, "eased")
    action = doc.action(clip, 5 * SEC, 10 * SEC, {"audio": {"volume": 0.3}},
                        curve="ease_in_out")
    doc.reframe(clip, follow="face")
    framed = doc.clip(clip)
    pieces = sorted(((a["start"], a["duration"], a.get("curve", "linear"), a["id"], a["end"])
                     for a in framed.get("actions", []) if "audio" in (a.get("end") or {})),
                    key=lambda p: p[0])
    want = [(5 * SEC, CUT - FRAME - 5 * SEC, "ease_in_out"), (CUT - FRAME, FRAME, "linear"),
            (CUT, 5 * SEC, "ease_in_out")]
    got = [p[:3] for p in pieces]
    ok = (got == want and pieces[0][3] == action
          and pieces[2][4].get("audio") == {"volume": 0.3})
    check("3", ok, f"pieces {[(p[0], p[1], p[2], p[3]) for p in pieces]} (want {want}, the head "
          f"id {action}); the tail's end {pieces[2][4] if len(pieces) > 2 else None}")
    doc.close()


def row4(client):
    doc = Doc(client, "replace")
    media = doc.media(at_600)
    clip = doc.clip_of(media, 10)
    kept = doc.action(clip, SEC, SEC, {"video": {"scale": 2.0, "x": 10.0},
                                       "audio": {"volume": 0.5}})
    gone = doc.action(clip, 3 * SEC, SEC, {"video": {"x": 50.0}})
    doc.reframe(clip, follow="fit", replace=True)
    framed = doc.clip(clip)
    actions = framed.get("actions", [])
    named = [a["id"] for a in actions if any(k in video(a.get("end")) for k in ("x", "y",
                                                                               "scale"))]
    base = framed.get("video") or {}
    volume = next((a["end"].get("audio") for a in actions if a["id"] == kept), None)
    fit = (close(base.get("scale", 1.0), FIT) and close(base.get("x", 0.0), 0.0)
           and close(base.get("y", 0.0), 0.0))
    check("4", not named and volume == {"volume": 0.5}
          and all(a["id"] != gone for a in actions) and fit,
          f"ends naming x, y or scale {named}; action {kept}'s audio {volume}; action {gone} "
          f"{'gone' if all(a['id'] != gone for a in actions) else 'kept'}; base "
          f"{base.get('scale')}, {base.get('x')}, {base.get('y')}")
    doc.close()


def row5(client):
    doc, clip = cut_doc(client, "speed")
    action = doc.action(clip, 5 * SEC, 10 * SEC, {"speed": 1.5})
    before = doc.clip(clip)
    old = next(a for a in before["actions"] if a["id"] == action)
    doc.reframe(clip, follow="face")
    framed = doc.clip(clip)
    a = next((x for x in framed.get("actions", []) if x["id"] == action), None)
    inside = [x["id"] for x in framed.get("actions", []) if x["id"] != action
              and x["start"] < old["start"] + old["duration"]
              and x["start"] + x["duration"] > old["start"]]
    end = (a or {}).get("end") or {}
    names = all(isinstance(video(end).get(k), (int, float)) for k in ("scale", "x", "y"))
    check("5", a is not None and (a["start"], a["duration"]) == (old["start"], old["duration"])
          and end.get("speed") == 1.5 and names and not inside,
          f"action {action}: {old['start']}+{old['duration']} → "
          f"{(a or {}).get('start')}+{(a or {}).get('duration')}, end {json.dumps(end)}; "
          f"other actions over it {inside}")
    doc.close()


def row8(client):
    doc = Doc(client, "cover")
    doc.call("set_canvas", background=[1, 0, 1, 1])
    media = doc.media(lambda t: canned_framing.pan(t, 20.0))
    clip = doc.clip_of(media, 20)
    doc.action(clip, 4 * SEC, 2 * SEC, {"video": {"scale": 1.5}}, curve="ease_in_out")
    doc.action(clip, 10 * SEC, 4 * SEC, {"audio": {"volume": 0.5}})
    doc.reframe(clip, follow="face")
    bad = []
    for n in range(40):
        t = n * 20 * SEC // 40
        corners = doc.corners(t)
        if any(magenta(c) for c in corners):
            bad.append((t, corners))
    actions = len(doc.clip(clip).get("actions", []))
    check("8", not bad, f"{actions} actions; 40 frames over 20 s, magenta corners at "
          f"{bad[:3] or 'none'}")
    doc.close()


ROW_BODIES = {"1": row1, "2": row2, "3": row3, "4": row4, "5": row5, "8": row8}


# ---- the launch -----------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
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
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"VR2b1 — reframe_clip composed into actions ({proof_app.config()} build)", flush=True)
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), ["-RCDevAnalysisCanned", "YES"],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in ROW_BODIES:
                check(row, False, "the app did not listen")
        else:
            print(f"  instance PID {launched.child.pid}", flush=True)
            for row, body in ROW_BODIES.items():
                if row in selected:
                    attempt(lambda: body(launched.client), row)
    finally:
        launched.stop()
    parity(log)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
