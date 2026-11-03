#!/usr/bin/env python3
"""Road map "creator-jobs" VR2b1 and VR2b2 — a framing composed into a clip's
actions, `reframe_clip`'s `replace` (spec §11 VR-27), and Clip ▸ Follow
Subject… over it (VR-29).

    python3 tools/proof/vr2b_proof.py [--only 1,4,5] [--app PATH]

Two launches, both with `-RCDevAnalysisCanned YES` under the scratch
`CFFIXED_USER_HOME`: the analyses are canned (`canned_framing.py`, spec §11
CJ-26) over `face_fixtures.py`'s `faces_moving.mov` (1920 × 1080, 30 fps, 60 s),
copied once per document; row 2's copy carries a 440 Hz tone (ffmpeg,
stream-copied picture), row 6b's copy has no canned markers, so its analysis
runs on this Mac. Every project is 1080 × 1920 at 30 fps; every placement is
read back through `get_project`. Both launches pin the sheet's remembered keys
as launch arguments (the argument domain, so the shared defaults domain cannot
leak a value in, and Follow writes nothing back), as `switch_speaker_proof.py`
pins `-FrameJobSwitchSpeakerMinShot`. Launch 1 adds `-RCDevFollowAccept YES
-FrameJobFollowKind subject -FrameJobFollowWhereEmpty fit` and runs rows 1–8
and 7b; launch 2 is `-FrameJobFollowKind subject -FrameJobFollowWhereEmpty
center` and runs rows 9 and 10.
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
6. The canned exit (still, gone 4–6 s, back) on one 15 s clip, selected;
   Clip ▸ Follow Subject… (`perform_menu_item`, the dev accept presses Follow):
   within 30 s one new step, `undo` answers "Follow Subject" and gives back
   `get_project` exactly; the menu's `clips` and `tracks` equal a twin
   document's after `add_track {index: 0, name: "Backgrounds"}` and
   `reframe_clip {follow: "subject", zoom: 1, where_empty: "fit", replace:
   true, backdrop}`.
6b. An uncached copy, a 4 s clip, the same menu: the Analyzing sheet comes up
   and closes (within 300 s), then one step "Follow Subject".
7. Two canned-exit clips one after the other on one track leave exactly one
   new track, "Backgrounds", at index 0, holding two blurred copies; two
   still-face (x 600) clips leave the track count unchanged and no
   "Backgrounds" track.
7b. Two canned-exit clips on two tracks overlapping in time, both selected:
   exactly two tracks added as one step "Follow Subject" — the core's new
   back-most track at index 0 and "Backgrounds" in front of it at index 1 —
   each holding one blurred copy.
9. (launch 2) `reframe_clip {follow: "subject", backdrop}` with no
   `where_empty`, on the canned exit, still makes the blurred copy (`fit`'s
   span) although `FrameJobFollowWhereEmpty` is `center`: the tool reads no
   `UserDefaults` (AU-68 (f)).
10. (launch 2) The canned cuts on one 25 s clip with an `ease_in_out` volume
   action [5, 15) s and a `linear` one [16, 24) s, selected; the menu; the
   sheet's `follow.summary` read through `snapshot_ui` (polled up to 30 s past
   "Reading the analysis…") holds "Frames 1 clip." and "1 action re-eased at
   a cut.", and `follow.zoom` reads 100; `cancel_sheet` leaves `get_project`
   unchanged.
Z1. Each launch's parity grep.

The core's mutants run against `cargo test` (tools/proof/README.md's VR2b1
section names each and the test that catches it); VR2b2's run against a Debug
app built with each (its VR2b2 section).
"""

import argparse
import array
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
ROWS = ["1", "2", "3", "4", "5", "6", "6b", "7", "7b", "8", "9", "10", "Z1"]
MENU = ["Clip", "Follow Subject…"]
STEP = "Follow Subject"
READING = "Reading the analysis…"
LAUNCH_1 = ["-RCDevAnalysisCanned", "YES", "-RCDevFollowAccept", "YES",
            "-FrameJobFollowKind", "subject", "-FrameJobFollowWhereEmpty", "fit"]
LAUNCH_2 = ["-RCDevAnalysisCanned", "YES", "-FrameJobFollowKind", "subject",
            "-FrameJobFollowWhereEmpty", "center"]

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

    def media(self, faces_at, cut_frames=(), tone=False, canned=True):
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
        if canned:
            canned_framing.write(self.path, media, copy, row["duration"], fps, faces_at,
                                 cut_frames)
        return media

    def clip_of(self, media, seconds, at=0, track=0):
        clip = self.call("add_clip", track=self.track(track), media=media,
                         at=at)["new_clips"][0]
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

    def follow(self, clips):
        """Selects `clips` and chooses Clip ▸ Follow Subject…."""
        self.call("set_selection", clips=clips)
        return self.call("perform_menu_item", path=MENU)

    def sheet_up(self):
        return ((self.call("perform_menu_item").get("window") or {}).get("sheet")) is not None

    def sheet_views(self, tag):
        """The attached sheet's layout dump's views, or None with no sheet."""
        (WORK / "sheets").mkdir(parents=True, exist_ok=True)
        try:
            got = self.call("snapshot_ui", window="sheet",
                            path=str(WORK / "sheets" / f"{tag}.png"))
        except mcp.ToolError:
            return None
        path = got.get("layout_path") if isinstance(got, dict) else None
        if not path:
            return None
        return json.loads(Path(path).read_text()).get("views") or []

    def wait_change(self, before, bound=30):
        """`get_project` once it differs from `before`, within `bound` s, else None."""
        began = time.monotonic()
        while time.monotonic() - began < bound:
            now = self.state()
            if now != before:
                return now
            time.sleep(0.25)
        return None

    def wait_no_sheet(self, bound=30):
        began = time.monotonic()
        while time.monotonic() - began < bound:
            if not self.sheet_up():
                return True
            time.sleep(0.2)
        return False

    def undo_name(self):
        return self.call("undo").get("undone")

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


def view(views, ident):
    found = [v for v in views or [] if v.get("id") == ident and not v.get("hidden")]
    return found[0].get("text") if found else None


def on(state, track_id):
    return [c for c in state["clips"] if c["track"] == track_id]


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


def row6(client):
    doc = Doc(client, "follow")
    media = doc.media(canned_framing.exit_and_back)
    clip = doc.clip_of(media, 15)
    before = doc.state()
    doc.follow([clip])
    after = doc.wait_change(before)
    gone = doc.wait_no_sheet()
    undone = doc.undo_name()
    back = doc.state()
    twin = Doc(client, "follow-twin")
    twin_media = twin.media(canned_framing.exit_and_back)
    twin_clip = twin.clip_of(twin_media, 15)
    twin.call("add_track", index=0, name="Backgrounds")
    backdrop = twin.track(0)
    twin.reframe(twin_clip, follow="subject", zoom=1, where_empty="fit", replace=True,
                 backdrop=backdrop)
    want = twin.state()
    same = after is not None and all(after[k] == want[k] for k in ("clips", "tracks"))
    check("6", after is not None and gone and undone == STEP and back == before and same,
          f"changed {after is not None}, the sheet gone {gone}; undo {undone!r}, the project "
          f"given back {back == before}; clips and tracks equal the twin's {same} "
          f"({len((after or {}).get('clips', []))} clips, {len((after or {}).get('tracks', []))}"
          f" tracks; the twin's {len(want['clips'])}, {len(want['tracks'])})")
    twin.close()
    doc.close()


def row6b(client):
    doc = Doc(client, "uncached")
    media = doc.media(canned_framing.exit_and_back, canned=False)
    clip = doc.clip_of(media, 4)
    before = doc.state()
    doc.follow([clip])
    began = time.monotonic()
    analyzing = False
    while time.monotonic() - began < 60 and not analyzing:
        views = doc.sheet_views("uncached")
        analyzing = any(v.get("text") == "Analyzing" and not v.get("hidden")
                        for v in views or [])
        if not analyzing:
            time.sleep(0.2)
    seen = time.monotonic() - began
    closed = doc.wait_no_sheet(300)
    after = doc.wait_change(before, 30) if closed else None
    undone = doc.undo_name() if after is not None else None
    check("6b", analyzing and closed and after is not None and undone == STEP,
          f"the Analyzing sheet seen {analyzing} after {seen:.1f} s; closed {closed}; changed "
          f"{after is not None}; undo {undone!r}")
    doc.close()


def row7(client):
    doc = Doc(client, "two-exits")
    media = doc.media(canned_framing.exit_and_back)
    a = doc.clip_of(media, 15)
    b = doc.clip_of(media, 15, at=15 * SEC)
    before = doc.state()
    doc.follow([a, b])
    after = doc.wait_change(before) or before
    doc.wait_no_sheet()
    tracks = after["tracks"]
    first = tracks[0] if tracks else {}
    copies = on(after, first.get("id"))
    exits = (len(tracks) == len(before["tracks"]) + 1 and first.get("name") == "Backgrounds"
             and len(copies) == 2 and sum(t["name"] == "Backgrounds" for t in tracks) == 1)
    doc.close()

    still = Doc(client, "two-stills")
    media = still.media(at_600)
    a = still.clip_of(media, 10)
    b = still.clip_of(media, 10, at=10 * SEC)
    before = still.state()
    still.follow([a, b])
    framed = still.wait_change(before) or before
    still.wait_no_sheet()
    stills = (framed != before and len(framed["tracks"]) == len(before["tracks"])
              and not any(t["name"] == "Backgrounds" for t in framed["tracks"]))
    check("7", exits and stills,
          f"two exits: {len(before['tracks'])} → {len(tracks)} tracks, index 0 "
          f"{first.get('name')!r} holding {len(copies)} clip(s); two stills: framed "
          f"{framed != before}, {len(before['tracks'])} → {len(framed['tracks'])} tracks, names "
          f"{[t['name'] for t in framed['tracks']]}")
    still.close()


def row7b(client):
    doc = Doc(client, "overlap")
    media = doc.media(canned_framing.exit_and_back)
    a = doc.clip_of(media, 15)
    doc.call("add_track", name="Second")
    b = doc.clip_of(media, 15, at=2 * SEC, track=1)
    before = doc.state()
    doc.follow([a, b])
    after = doc.wait_change(before) or before
    doc.wait_no_sheet()
    tracks = after["tracks"]
    known = {t["id"] for t in before["tracks"]}
    added = [t for t in tracks if t["id"] not in known]
    index = {t["id"]: n for n, t in enumerate(tracks)}
    held = {t["id"]: len(on(after, t["id"])) for t in added}
    backgrounds = [t for t in added if t["name"] == "Backgrounds"]
    other = [t for t in added if t["name"] != "Backgrounds"]
    undone = doc.undo_name()
    ok = (len(added) == 2 and len(backgrounds) == 1 and len(other) == 1
          and index[other[0]["id"]] == 0 and index[backgrounds[0]["id"]] == 1
          and all(n == 1 for n in held.values()) and undone == STEP
          and doc.state() == before)
    check("7b", ok, f"added {[(t['name'], index[t['id']], held[t['id']]) for t in added]} "
          f"(name, index, clips); undo {undone!r}")
    doc.close()


def row9(client):
    doc = Doc(client, "tool-default")
    media = doc.media(canned_framing.exit_and_back)
    clip = doc.clip_of(media, 15)
    doc.call("add_track", index=0, name="Behind")
    backdrop = doc.track(0)
    doc.reframe(clip, follow="subject", backdrop=backdrop)
    copies = on(doc.state(), backdrop)
    check("9", len(copies) == 1, f"{len(copies)} blurred cop(ies) on the backdrop track with "
          f"no where_empty while FrameJobFollowWhereEmpty is center")
    doc.close()


def row10(client):
    doc = Doc(client, "summary")
    media = doc.media(canned_framing.cuts, canned_framing.CUT_FRAMES)
    clip = doc.clip_of(media, 25)
    doc.action(clip, 5 * SEC, 10 * SEC, {"audio": {"volume": 0.3}}, curve="ease_in_out")
    doc.action(clip, 16 * SEC, 8 * SEC, {"audio": {"volume": 0.6}}, curve="linear")
    before = doc.state()
    doc.follow([clip])
    began = time.monotonic()
    summary = zoom = None
    while time.monotonic() - began < 30:
        views = doc.sheet_views("summary")
        summary = view(views, "follow.summary")
        zoom = view(views, "follow.zoom")
        if summary not in (None, READING):
            break
        time.sleep(0.25)
    doc.call("cancel_sheet")
    unchanged = doc.state() == before
    ok = (summary is not None and "Frames 1 clip." in summary
          and "1 action re-eased at a cut." in summary and zoom == "100" and unchanged)
    check("10", ok, f"summary {summary!r}; zoom {zoom!r}; after Cancel the project unchanged "
          f"{unchanged}")
    doc.close()


ROW_BODIES = {"1": row1, "2": row2, "3": row3, "4": row4, "5": row5, "6": row6, "6b": row6b,
              "7": row7, "7b": row7b, "8": row8}
LAUNCH_2_BODIES = {"9": row9, "10": row10}


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
    print(f"VR2b — reframe_clip composed into actions and Clip ▸ Follow Subject… "
          f"({proof_app.config()} build)", flush=True)
    for tag, arguments, bodies in (("1", LAUNCH_1, ROW_BODIES), ("2", LAUNCH_2, LAUNCH_2_BODIES)):
        if not selected & set(bodies):
            continue
        log = WORK / f"instance-{tag}.log"
        launched = mcp.launch(str(binary), arguments,
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                for row in bodies:
                    check(row, False, "the app did not listen")
            else:
                print(f"  launch {tag}: instance PID {launched.child.pid}", flush=True)
                for row, body in bodies.items():
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
