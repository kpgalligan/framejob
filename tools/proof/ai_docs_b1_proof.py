#!/usr/bin/env python3
"""ai-docs batch b1 (#524 #534, spec §11 #524, #534): crop, corner radius and chroma key are
refused on a text, shape or graphic clip and Paste Attributes leaves such a clip's own; a camera
layout that would crop or round a shape or graphic clip is refused up front; a media path is stored
and compared as given, never trimmed. Batch r2b (#535 #536, spec §11 #535, #536) adds the E rows
(`set_action_end` refuses the same keys at an action's end) and the A rows (an adjustment clip
takes none of the three, and Paste Attributes leaves its own).

    python3 tools/proof/ai_docs_b1_proof.py [--only V1,L2,M4,…] [--app PATH] [--expect-red]
    RC_PROOF_APP=release python3 tools/proof/ai_docs_b1_proof.py
    RC_PROOF_APP=<a base .app> python3 tools/proof/ai_docs_b1_proof.py --expect-red

The built app (`proof_app`'s choice) under a scratch home, driven over MCP, on projects built from
`tools/proof/media/A.mov` (CoW-copied under `tools/proof/work/ai-docs-b1/media/`, beside a copy
named `A.mov ` with a trailing space) and a VP9 WebM `talk.webm` made with ffmpeg (with its own
`talk.webm ` copy). `(c)` marks a CONTROL, which passes on the base too; every other row is red on
the frozen base app, and `--expect-red` exits 0 only when that holds and no row failed for want of
running.

Launch 1 (plain):
- V1 `set_video` crop l100, corner_radius 40 and a chroma key on a text, a shape and a graphic
  clip: nine errors, each with the core's sentence, and `get_project` unchanged.
- V2 (c) clearing each (crop all 0, radius 0, chroma null) on each: no error.
- V3 a text clip on a track `set_track {matte: alpha}`: crop l100 applies, radius 40 is the error.
- V4 (c) a text clip given a crop through `paste` (a hand-written payload) takes `opacity: 0.5`
  and keeps the crop; a crop of all 0 clears it.
- L1 a graphic clip as the camera in `corner circle`, at its first frame and mid-clip: both
  refused in the sentence (base: both applied).
- L2 a media camera with a graphic later on its track, `corner circle` at the camera's first
  frame: refused naming the graphic (base: applied).
- L3 (c) L2 with `through` before the graphic applies; a shape screen behind a media camera in
  `corner` (square) applies.
- P1 `paste_attributes` (default groups) from a media clip holding a crop, radius 30, a chroma
  key and opacity 0.5 onto a text, a shape and a graphic clip: each keeps its own three keys and
  takes opacity 0.5.
- P2 (c) the same onto a second media clip carries all three.
- M1 `add_media` with A.mov's probed descriptor at `…/A.mov `: the path keeps its space, and an
  `add_media` of `…/A.mov` then adds a second row.
- M2 `paste` of a payload whose media row is `…/A.mov `: a row with the space is appended.
- M3 `import_media` of `talk.webm ` (the built-in copy): its media's `original.path` ends in the
  space.
- M5 (c) `import_media` of `A.mov ` is still the probe's error.
- E1 on one project (A.mov on Track 1, a text, a shape and a graphic clip and an adjustment clip,
  each on a front track of its own and each with an action at 0 for 1 s): `set_action_end`
  `{video: {crop: {l: 100}}}`, `{video: {corner_radius: 40}}` and `{video: {chroma: …}}` on the
  text, shape and graphic clips: nine errors, each with the core's sentence, ends unchanged.
- E2 the same on the adjustment clip: three errors (`… an adjustment clip and cannot take a
  crop`).
- E3 (c) on each of the four, an end crop of all 0, `corner_radius: 0`, `chroma: null` and
  `off: ["video.chroma"]`: no error.
- E4 a text clip on a track `set_track {matte: alpha}`: an end crop l100 applies; an end
  corner_radius 40 is the error.
- E5 (c) the media clip's action end takes all three.
- A1 `set_video` crop l100, corner_radius 40 and a chroma key on the adjustment clip: three
  errors, the clip unchanged.
- A2 (c) clearing each on it: no error.
- A3 the adjustment clip's track `set_track {matte: alpha}`: `set_video` crop l100 is the error.
- A4 `paste_attributes` (default groups) from the media clip holding crop l120/t10, radius 30, a
  chroma key and opacity 0.5 onto the adjustment clip: its three stay neutral and its opacity is
  0.5.
Launch 2 (`-RCFFmpegImport always -RCFFmpegPath <ffmpeg>`):
- M4 `import_media` of `A.mov ` then `A.mov`, and the reverse order, each in a fresh project: the
  converted media's `original.path` keeps the space.
Both:
- Z1 (c) `grep "Frame Job: "` of each launch's log prints nothing.
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/ai-docs-b1"
HOME = WORK / "home"
MEDIA = WORK / "media"
CALL_BOUND = 600
SEC = 600_000

ROWS = ["V1", "V2", "V3", "V4", "L1", "L2", "L3", "P1", "P2", "M1", "M2", "M3", "M5",
        "E1", "E2", "E3", "E4", "E5", "A1", "A2", "A3", "A4", "M4", "Z1"]
CONTROLS = {"V2", "V4", "L3", "P2", "M5", "E3", "E5", "A2", "Z1"}
END_ROWS = {"E1", "E2", "E3", "E4", "E5", "A1", "A2", "A3", "A4"}
LAUNCH_ONE = {"V1", "V2", "V3", "V4", "L1", "L2", "L3", "P1", "P2", "M1", "M2", "M3",
              "M5"} | END_ROWS
LAUNCH_TWO = {"M4"}

MODULE = """export const schema = { title: { type: "string", default: "Hello" } };
export function render(ctx, props) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${ctx.width} ${ctx.height}"><rect width="100" height="100" fill="red"/></svg>`;
}
"""
CHROMA = {"key": [0.0, 1.0, 0.0], "tolerance": 0.3, "softness": 0.1, "spill": 0.5}
CLEAR = {"crop": {"l": 0, "t": 0, "r": 0, "b": 0}, "corner_radius": 0, "chroma": None}

results = {}
broken = set()
selected = set(ROWS)


def check(row, ok, detail):
    if row not in selected:
        return
    results.setdefault(row, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {row}: {detail}", flush=True)


def error_of(call):
    """The ToolError text `call()` raised, or None when it answered."""
    try:
        call()
    except mcp.ToolError as e:
        return str(e)
    return None


class Doc:
    """One project on the instance, closed (discarded) by `close`."""

    def __init__(self, client, name):
        self.c = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))

    def call(self, tool, **a):
        return self.c.call_with(tool, {"project": str(self.path), **a})

    def state(self):
        return self.call("get_project")["project"]

    def clip(self, cid):
        return next(x for x in self.state()["clips"] if x["id"] == cid)

    def video(self, cid):
        return self.clip(cid).get("video") or {}

    def track(self, name):
        """A new front track; answers its id."""
        self.c.call_with("add_track", {"project": str(self.path), "name": name})
        return self.state()["tracks"][-1]["id"]

    def new_clip(self, tool, **a):
        before = {x["id"] for x in self.state()["clips"]}
        self.c.call_with(tool, {"project": str(self.path), **a})
        made = [x["id"] for x in self.state()["clips"] if x["id"] not in before]
        return made[0]

    def close(self):
        try:
            self.c.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def neutral(video):
    crop = video.get("crop") or {}
    return (all((crop.get(k) or 0) == 0 for k in "ltrb") and (video.get("corner_radius") or 0) == 0
            and video.get("chroma") is None)


def kinds_doc(client, name):
    """A.mov on Track 1 and a text, a shape and a graphic clip each on a front track of its own:
    (doc, media clip, {kind: (clip, track)})."""
    d = Doc(client, name)
    media = d.call("import_media", path=str(MEDIA / "A.mov"))["media"]
    t0 = d.state()["tracks"][0]["id"]
    vclip = d.new_clip("add_clip", track=t0, media=media, at=0)
    d.call("write_graphic", name="box", source=MODULE)
    ids = {}
    for kind in ("text", "shape", "graphic"):
        tid = d.track(kind)
        if kind == "text":
            ids[kind] = (d.new_clip("add_text_clip", track=tid, at=0, duration=4 * SEC), tid)
        elif kind == "shape":
            ids[kind] = (d.new_clip("add_shape_clip", track=tid, at=0, duration=4 * SEC), tid)
        else:
            ids[kind] = (d.new_clip("add_graphic_clip", track=tid, at=0, duration=4 * SEC,
                                    name="box"), tid)
    return d, media, vclip, ids


def kind_word(kind):
    return f"a {kind} clip"


def video_rows(client):
    d, media, vclip, ids = kinds_doc(client, "kinds")
    try:
        before = d.state()
        wrong = []
        for kind, (cid, _) in ids.items():
            for patch, what in (({"crop": {"l": 100}}, "a crop off a matte track"),
                                ({"corner_radius": 40}, "a corner radius"),
                                ({"chroma": CHROMA}, "a chroma key")):
                said = error_of(lambda: d.call("set_video", clips=[cid], patch=patch))
                want = f"clip {cid} is {kind_word(kind)} and cannot take {what}"
                if said is None or want not in said:
                    wrong.append(f"{kind} {list(patch)[0]}: {said or 'applied'}")
                if said is None:
                    d.call("undo")
        same = d.state()["clips"] == before["clips"]
        check("V1", not wrong and same, f"{9 - len(wrong)}/9 errors in the sentence, "
              f"project unchanged {same}" + (f"; {wrong[:3]}" if wrong else ""))

        bad = []
        for kind, (cid, _) in ids.items():
            for patch in ({"crop": CLEAR["crop"]}, {"corner_radius": 0}, {"chroma": None}):
                said = error_of(lambda: d.call("set_video", clips=[cid], patch=patch))
                if said is not None and "made no change" not in said:
                    bad.append(f"{kind} {list(patch)[0]}: {said}")
        check("V2", not bad, "clearing each key on each kind: " + (f"{bad}" if bad else "no error"))

        text, track = ids["text"]
        d.call("set_track", track=track, matte="alpha")
        crop_err = error_of(lambda: d.call("set_video", clips=[text], patch={"crop": {"l": 100}}))
        cropped = (d.video(text).get("crop") or {}).get("l")
        radius_err = error_of(lambda: d.call("set_video", clips=[text], patch={"corner_radius": 40}))
        if radius_err is None:
            d.call("undo")
        want = f"clip {text} is a text clip and cannot take a corner radius"
        check("V3", crop_err is None and cropped == 100 and radius_err and want in radius_err,
              f"matte-track text: crop error {crop_err!r}, crop l {cropped}; radius error "
              f"{radius_err!r}")
        d.call("set_track", track=track, matte="none")
        d.call("set_video", clips=[text], patch={"crop": CLEAR["crop"]})

        # V4: a text clip given a crop through a full paste keeps it through another edit.
        src = dict(d.clip(text))
        src["video"] = dict(src.get("video") or {}, crop={"l": 100, "t": 0, "r": 0, "b": 0})
        src["track"] = 0
        src["start"] = 0
        pasted = d.new_clip("paste", at=6 * SEC, payload={"clips": [src], "media": []})
        held = (d.video(pasted).get("crop") or {}).get("l")
        faded = error_of(lambda: d.call("set_video", clips=[pasted], patch={"opacity": 0.5}))
        kept = (d.video(pasted).get("crop") or {}).get("l")
        cleared = error_of(lambda: d.call("set_video", clips=[pasted],
                                          patch={"crop": CLEAR["crop"]}))
        gone = all((d.video(pasted).get("crop") or {}).get(k, 0) == 0 for k in "ltrb")
        check("V4", held == 100 and faded is None and kept == 100 and cleared is None and gone,
              f"pasted crop l {held}; opacity edit {faded or 'applied'}, crop kept l {kept}; "
              f"clear {cleared or 'applied'}, crop all 0 {gone}")

        # P1/P2: Paste Attributes from the media clip.
        d.call("set_video", clips=[vclip], patch={"crop": {"l": 120, "t": 10}, "corner_radius": 30,
                                                  "chroma": CHROMA, "opacity": 0.5})
        payload_clip = dict(d.clip(vclip))
        payload_clip["track"] = 0
        payload = {"clips": [payload_clip],
                   "media": [m for m in d.state()["media"] if m["id"] == media]}
        targets = [cid for cid, _ in ids.values()]
        said = error_of(lambda: d.call("paste_attributes", clips=targets, payload=payload))
        rows = {kind: d.video(cid) for kind, (cid, _) in ids.items()}
        ok = said is None and all(neutral(v) and v.get("opacity") == 0.5 for v in rows.values())
        check("P1", ok, f"paste_attributes {said or 'applied'}; " + "; ".join(
            f"{k}: crop {v.get('crop')}, radius {v.get('corner_radius')}, chroma "
            f"{'set' if v.get('chroma') else None}, opacity {v.get('opacity')}"
            for k, v in rows.items()))
        second = d.new_clip("add_clip", track=d.state()["tracks"][0]["id"], media=media,
                            at=12 * SEC)
        said = error_of(lambda: d.call("paste_attributes", clips=[second], payload=payload))
        v = d.video(second)
        check("P2", said is None and (v.get("crop") or {}).get("l") == 120
              and v.get("corner_radius") == 30 and v.get("chroma") is not None,
              f"onto a media clip: {said or 'applied'}, crop {v.get('crop')}, radius "
              f"{v.get('corner_radius')}, chroma {'set' if v.get('chroma') else None}")
    finally:
        d.close()


def action_on(d, cid):
    """Adds an action at 0 for 1 s to clip `cid`; answers its id."""
    before = {a["id"] for a in d.clip(cid).get("actions") or []}
    d.call("add_action", clip=cid, at=0, duration=SEC)
    return next(a["id"] for a in d.clip(cid).get("actions") or [] if a["id"] not in before)


def end_of(d, cid, aid):
    return next(a for a in d.clip(cid).get("actions") or [] if a["id"] == aid).get("end") or {}


def end_rows(client):
    """#535 and #536: the E and A rows, on one project."""
    d, media, vclip, ids = kinds_doc(client, "ends")
    try:
        adj_track = d.track("adjustment")
        adj = d.new_clip("add_adjustment_clip", track=adj_track, at=0, duration=4 * SEC)
        clips = {kind: cid for kind, (cid, _) in ids.items()}
        clips["adjustment"] = adj
        words = {kind: kind_word(kind) for kind in ids} | {"adjustment": "an adjustment clip"}
        actions = {kind: action_on(d, cid) for kind, cid in clips.items()}
        media_action = action_on(d, vclip)

        def end_errors(kinds):
            wrong, seen = [], 0
            for kind in kinds:
                cid, aid = clips[kind], actions[kind]
                crop = "a crop" if kind == "adjustment" else "a crop off a matte track"
                for patch, what in (({"crop": {"l": 100}}, crop),
                                    ({"corner_radius": 40}, "a corner radius"),
                                    ({"chroma": CHROMA}, "a chroma key")):
                    seen += 1
                    said = error_of(lambda: d.call("set_action_end", clip=cid, action=aid,
                                                   patch={"video": patch}))
                    want = f"clip {cid} is {words[kind]} and cannot take {what}"
                    if said is None or want not in said:
                        wrong.append(f"{kind} {list(patch)[0]}: {said or 'applied'}")
                    if said is None:
                        d.call("undo")
            return wrong, seen

        before = d.state()
        wrong, seen = end_errors(["text", "shape", "graphic"])
        same = d.state()["clips"] == before["clips"]
        check("E1", not wrong and same, f"{seen - len(wrong)}/{seen} end errors in the sentence, "
              f"project unchanged {same}" + (f"; {wrong[:3]}" if wrong else ""))
        wrong, seen = end_errors(["adjustment"])
        same = d.state()["clips"] == before["clips"]
        check("E2", not wrong and same, f"{seen - len(wrong)}/{seen} end errors on the adjustment "
              f"clip, project unchanged {same}" + (f"; {wrong[:3]}" if wrong else ""))

        bad = []
        for kind, cid in clips.items():
            aid = actions[kind]
            for patch, off in (({"video": {"crop": CLEAR["crop"]}}, None),
                               ({"video": {"corner_radius": 0}}, None),
                               ({"video": {"chroma": None}}, None),
                               ({}, ["video.chroma"])):
                args = {"clip": cid, "action": aid, "patch": patch}
                if off:
                    args["off"] = off
                said = error_of(lambda: d.call("set_action_end", **args))
                if said is not None and "made no change" not in said:
                    bad.append(f"{kind} {off or list(patch['video'])[0]}: {said}")
        check("E3", not bad, "clearing at the end on each kind: " + (f"{bad}" if bad else "no error"))

        text, track = ids["text"]
        d.call("set_track", track=track, matte="alpha")
        crop_err = error_of(lambda: d.call("set_action_end", clip=text, action=actions["text"],
                                           patch={"video": {"crop": {"l": 100}}}))
        cropped = ((end_of(d, text, actions["text"]).get("video") or {}).get("crop") or {}).get("l")
        radius_err = error_of(lambda: d.call("set_action_end", clip=text, action=actions["text"],
                                             patch={"video": {"corner_radius": 40}}))
        if radius_err is None:
            d.call("undo")
        want = f"clip {text} is a text clip and cannot take a corner radius"
        check("E4", crop_err is None and cropped == 100 and radius_err and want in radius_err,
              f"matte-track text end: crop error {crop_err!r}, end crop l {cropped}; radius error "
              f"{radius_err!r}")
        d.call("set_track", track=track, matte="none")

        said = error_of(lambda: d.call("set_action_end", clip=vclip, action=media_action,
                                       patch={"video": {"crop": {"l": 100}, "corner_radius": 40,
                                                        "chroma": CHROMA}}))
        ev = end_of(d, vclip, media_action).get("video") or {}
        check("E5", said is None and (ev.get("crop") or {}).get("l") == 100
              and ev.get("corner_radius") == 40 and ev.get("chroma") is not None,
              f"media clip's end: {said or 'applied'}, crop {ev.get('crop')}, radius "
              f"{ev.get('corner_radius')}, chroma {'set' if ev.get('chroma') else None}")

        adj_before = d.video(adj)
        wrong = []
        for patch, what in (({"crop": {"l": 100}}, "a crop"),
                            ({"corner_radius": 40}, "a corner radius"),
                            ({"chroma": CHROMA}, "a chroma key")):
            said = error_of(lambda: d.call("set_video", clips=[adj], patch=patch))
            want = f"clip {adj} is an adjustment clip and cannot take {what}"
            if said is None or want not in said:
                wrong.append(f"{list(patch)[0]}: {said or 'applied'}")
            if said is None:
                d.call("undo")
        same = d.video(adj) == adj_before
        check("A1", not wrong and same, f"{3 - len(wrong)}/3 set_video errors on the adjustment "
              f"clip, unchanged {same}" + (f"; {wrong}" if wrong else ""))

        bad = []
        for patch in ({"crop": CLEAR["crop"]}, {"corner_radius": 0}, {"chroma": None}):
            said = error_of(lambda: d.call("set_video", clips=[adj], patch=patch))
            if said is not None and "made no change" not in said:
                bad.append(f"{list(patch)[0]}: {said}")
        check("A2", not bad, "clearing each on the adjustment clip: "
              + (f"{bad}" if bad else "no error"))

        d.call("set_track", track=adj_track, matte="alpha")
        said = error_of(lambda: d.call("set_video", clips=[adj], patch={"crop": {"l": 100}}))
        if said is None:
            d.call("undo")
        want = f"clip {adj} is an adjustment clip and cannot take a crop"
        check("A3", said is not None and want in said,
              f"an adjustment clip on a matte track, crop l100: {said or 'applied'}")
        d.call("set_track", track=adj_track, matte="none")

        d.call("set_video", clips=[vclip], patch={"crop": {"l": 120, "t": 10}, "corner_radius": 30,
                                                  "chroma": CHROMA, "opacity": 0.5})
        payload_clip = dict(d.clip(vclip))
        payload_clip["track"] = 0
        payload_clip["actions"] = []
        payload = {"clips": [payload_clip],
                   "media": [m for m in d.state()["media"] if m["id"] == media]}
        said = error_of(lambda: d.call("paste_attributes", clips=[adj], payload=payload))
        v = d.video(adj)
        check("A4", said is None and neutral(v) and v.get("opacity") == 0.5,
              f"paste_attributes onto the adjustment clip: {said or 'applied'}, crop "
              f"{v.get('crop')}, radius {v.get('corner_radius')}, chroma "
              f"{'set' if v.get('chroma') else None}, opacity {v.get('opacity')}")
    finally:
        d.close()


def switch(d, **a):
    """None when applied (and undone), else the ToolError's text."""
    said = error_of(lambda: d.call("switch_layout", **a))
    if said is None:
        d.call("undo")
    return said


def layout_rows(client):
    d = Doc(client, "layout-1")
    try:
        media = d.call("import_media", path=str(MEDIA / "A.mov"))["media"]
        d.new_clip("add_clip", track=d.state()["tracks"][0]["id"], media=media, at=0)
        d.call("write_graphic", name="box", source=MODULE)
        g = d.new_clip("add_graphic_clip", track=d.track("Graphic"), at=0, duration=4 * SEC,
                       name="box")
        want = f"clip {g} is a graphic clip and cannot take a camera layout's crop or corner radius"
        first = switch(d, camera=g, layout="corner", shape="circle", at=0)
        mid = switch(d, camera=g, layout="corner", shape="circle", at=2 * SEC)
        check("L1", first and want in first and mid and want in mid,
              f"at its first frame: {first or 'applied'}; mid-clip: {mid or 'applied'}")
    finally:
        d.close()

    d = Doc(client, "layout-2")
    try:
        media = d.call("import_media", path=str(MEDIA / "A.mov"))["media"]
        d.new_clip("add_clip", track=d.state()["tracks"][0]["id"], media=media, at=0)
        cam_track = d.track("Camera")
        cam = d.new_clip("add_clip", track=cam_track, media=media, at=0)
        d.call("trim_end", clip=cam, to=2 * SEC)
        d.call("write_graphic", name="box", source=MODULE)
        g = d.new_clip("add_graphic_clip", track=cam_track, at=2 * SEC, duration=2 * SEC,
                       name="box")
        want = f"clip {g} is a graphic clip and cannot take a camera layout's crop or corner radius"
        reach = switch(d, camera=cam, layout="corner", shape="circle", at=0)
        check("L2", reach and want in reach, f"a later graphic in the reach: {reach or 'applied'}")
        through = switch(d, camera=cam, layout="corner", shape="circle", at=0, through=SEC)
        check("L3", through is None, f"with through before the graphic: {through or 'applied'}")
    finally:
        d.close()

    d = Doc(client, "layout-3")
    try:
        media = d.call("import_media", path=str(MEDIA / "A.mov"))["media"]
        back = d.state()["tracks"][0]["id"]
        d.new_clip("add_shape_clip", track=back, at=0, duration=8 * SEC)
        cam = d.new_clip("add_clip", track=d.track("Camera"), media=media, at=0)
        square = switch(d, camera=cam, layout="corner", at=SEC)
        check("L3", square is None, f"a shape screen in corner square: {square or 'applied'}")
    finally:
        d.close()


def media_rows(client):
    spaced = str(MEDIA / "A.mov ")
    plain = str(MEDIA / "A.mov")

    d = Doc(client, "add-media")
    try:
        d.call("import_media", path=plain)
        row = d.state()["media"][0]
    finally:
        d.close()
    descriptor = {k: v for k, v in row.items() if k != "id"}

    d = Doc(client, "add-media-2")
    try:
        first = error_of(lambda: d.call("add_media", descriptor=dict(descriptor, path=spaced)))
        stored = [m["path"] for m in d.state()["media"]]
        second = error_of(lambda: d.call("add_media", descriptor=dict(descriptor, path=plain)))
        after = [m["path"] for m in d.state()["media"]]
        check("M1", first is None and stored == [spaced] and second is None
              and after == [spaced, plain],
              f"add 'A.mov ': {first or 'applied'}, stored {[repr(p[-7:]) for p in stored]}; "
              f"add 'A.mov': {second or 'applied'}, rows {[repr(p[-7:]) for p in after]}")
    finally:
        d.close()

    d = Doc(client, "paste-row")
    try:
        prow = dict(row, path=spaced)
        clip = {"id": 99, "track": 0, "start": 0, "duration": 30000,
                "source": {"kind": "media", "media": prow["id"], "in": 0}}
        said = error_of(lambda: d.call("paste", at=0, payload={"clips": [clip], "media": [prow]}))
        stored = [m["path"] for m in d.state()["media"]]
        check("M2", said is None and stored == [spaced],
              f"paste: {said or 'applied'}, rows {[repr(p[-7:]) for p in stored]}")
    finally:
        d.close()

    d = Doc(client, "webm")
    try:
        webm = MEDIA / "talk.webm "
        if not webm.exists():
            broken.add("M3")
            check("M3", False, "talk.webm could not be made with ffmpeg")
        else:
            said = error_of(lambda: d.call("import_media", path=str(webm)))
            rows = d.state()["media"]
            orig = [(m.get("original") or {}).get("path") for m in rows]
            check("M3", said is None and orig == [str(webm)],
                  f"import 'talk.webm ': {said or 'applied'}, original "
                  f"{[repr(Path(o).name) if o else None for o in orig]}")
    finally:
        d.close()

    d = Doc(client, "probe")
    try:
        said = error_of(lambda: d.call("import_media", path=spaced))
        check("M5", said is not None and not d.state()["media"],
              f"import 'A.mov ' with no ffmpeg: {said[:90] if said else 'applied'}")
    finally:
        d.close()


def ffmpeg_rows(client):
    spaced, plain = MEDIA / "A.mov ", MEDIA / "A.mov"
    seen = []
    for name, order in (("spaced-first", [spaced, plain]), ("plain-first", [plain, spaced])):
        d = Doc(client, name)
        try:
            for f in order:
                d.call("import_media", path=str(f))
            origs = [(m.get("original") or {}).get("path") for m in d.state()["media"]]
            seen.append((name, [repr(Path(o).name) if o else None for o in origs],
                         str(spaced) in origs))
        except mcp.ToolError as e:
            seen.append((name, str(e)[:90], False))
        finally:
            d.close()
    check("M4", all(ok for _, _, ok in seen), f"originals {[(n, o) for n, o, _ in seen]}")


def parity(log, tag):
    try:
        lines = [line for line in log.read_text(errors="replace").splitlines()
                 if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def launch(binary, arguments, rows, body, tag):
    log = WORK / f"{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(rows):
                broken.add(row)
                check(row, False, "the instance did not listen")
            return
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)


def make_media():
    MEDIA.mkdir(parents=True)
    source = ROOT / "tools/proof/media/A.mov"
    for name in ("A.mov", "A.mov "):
        subprocess.run(["cp", "-c", str(source), str(MEDIA / name)], check=True)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        made = subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
                               "testsrc=size=320x240:rate=30", "-t", "2", "-pix_fmt", "yuv420p",
                               "-c:v", "libvpx-vp9",
                               "-an", str(MEDIA / "talk.webm")], capture_output=True)
        if made.returncode == 0:
            subprocess.run(["cp", "-c", str(MEDIA / "talk.webm"), str(MEDIA / "talk.webm ")],
                           check=True)
    return ffmpeg


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--expect-red", action="store_true")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        shutil.rmtree(WORK)
    HOME.mkdir(parents=True)
    ffmpeg = make_media()

    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"ai-docs b1 — drawn clips' pixel keys and exact media paths ({binary})", flush=True)

    first = selected & LAUNCH_ONE
    if first:
        def body(client):
            if first & {"V1", "V2", "V3", "V4", "P1", "P2"}:
                video_rows(client)
            if first & {"L1", "L2", "L3"}:
                layout_rows(client)
            if first & {"M1", "M2", "M3", "M5"}:
                media_rows(client)
            if first & END_ROWS:
                end_rows(client)
        launch(binary, [], first, body, "launch-1")
    second = selected & LAUNCH_TWO
    if second:
        if ffmpeg is None:
            broken.add("M4")
            check("M4", False, "no ffmpeg on PATH")
        else:
            launch(binary, ["-RCFFmpegImport", "always", "-RCFFmpegPath", ffmpeg], second,
                   ffmpeg_rows, "launch-2")

    scored = {name: all(ok for ok, _ in runs) for name, runs in results.items()}
    failed = [name for name, ok in scored.items() if not ok]
    passed = [name for name, ok in scored.items() if ok]
    missing = sorted(selected - set(results), key=ROWS.index)
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else "")
          + (f"; never scored {missing}" if missing else ""))
    if args.expect_red:
        green = [name for name in passed if name not in CONTROLS]
        red_controls = [name for name in failed if name in CONTROLS]
        print(f"expect red: {len(failed) - len(red_controls)} rows red, green {green or 'none'}, "
              f"red controls {red_controls or 'none'}, unrun {sorted(broken) or 'none'}")
        return 0 if not green and not red_controls and not broken and not missing else 1
    return 0 if not failed and not missing and results else 1


if __name__ == "__main__":
    sys.exit(main())
