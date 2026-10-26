#!/usr/bin/env python3
"""Captions follow a speed or ramp edit (#341, spec §11 SR-27): the six op tools over MCP.

    make app-debug    # or make app, with RC_PROOF_APP=release for the recorded run
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/caption_retime_proof.py [--only C1,C7]

One owned instance (`mcp.launch` on `proof_app`'s app — Debug by default,
`RC_PROOF_APP=release` for the recorded run), one project per row, each closed
with `discard`. The fixture is `tools/proof/media/AV.mov` (5 s, 30 fps, with
sound) placed at 0 from in 0 and cut to D by `trim_end`, and a track named
"Captions" holding plain text clips (`add_text_clip`). Every expected place is
a literal oracle: a constant rate's halving, or the closed form of a linear
ramp ×1 → ×r over [0, D), S(t) = t + (r − 1)t²/(2D), snapped to the nearest
frame (20 000 ticks).

- C0  the log has no `Frame Job: ` line (the startup parity check).
- C1  `set_speed` ×2 (D = 3 s): three abutting captions halve; the answer's
      `captions_retimed` names them, one step named "Speed and Re-time Captions"
      (read back as `undo` answering it).
- C2  `rate_stretch` to 1.5 s: the same halving.
- C3  `add_speed_ramp` ramp_up ×2 linear over the whole clip: c′ = D(√(1 + 2c/D) − 1).
- C4  `set_action_end {speed: 2}` on a linear action over the whole clip: C3's oracle.
- C5  `set_action` shortening a linear ×2 speed action from [0, D) to [0, D/2)
      (D = 2 s): each caption through the old map and the new one's inverse.
- C6  `remove_action` of C3's ramp: back to ×1, a caption whose source the
      clip no longer plays in `captions_removed`.
- C7  one `undo` after C6 puts every clip back byte for byte in `get_project`;
      `redo` re-applies C6's answer byte for byte.
- C8  `set_speed` ×2 with `scope` the nest holding the clip and its captions:
      the nest's captions halve and the answer names them.
- C9  CONTROLS: a zoom action's `set_action`, a "Titles" track's caption and a
      straddling caption: no `captions_` key, the caption unmoved.
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/caption-retime"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
CALL_BOUND = 600
SEC = 600_000
FRAME = 20_000
ROWS = ["C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9"]

rows = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


def snap(t):
    """The nearest frame, as the core snaps."""
    return int(math.floor(round(t) / FRAME + 0.5)) * FRAME


def ramp_inverse(s, rate, d):
    """t with t + (rate − 1)t²/(2d) = s."""
    k = (rate - 1) / (2 * d)
    return (-1 + math.sqrt(1 + 4 * k * s)) / (2 * k)


def ramp_forward(t, rate, d):
    return t + (rate - 1) * t * t / (2 * d)


def attempt(client, tool, arguments):
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}


class Doc:
    """One project file, every call addressed to it."""

    def __init__(self, client, name):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        self.must("new_project", path=self.path)

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=self.path))

    def must(self, tool, **arguments):
        got = self.call(tool, **arguments)
        if not got["ok"]:
            raise RuntimeError(f"{tool} {arguments}: {got['error']}")
        return got["reply"]

    def project(self):
        return self.must("get_project")["project"]

    def close(self):
        attempt(self.client, "close_project", {"project": self.path, "discard": True})

    def clip(self, length):
        """AV.mov at 0 from in 0, cut to `length`; its id."""
        media = self.must("import_media", path=str(AV_MOV))["media"]
        track = self.project()["tracks"][0]["id"]
        clip = self.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
        self.must("trim_end", clip=clip, to=length)
        return clip

    def track(self, name):
        self.must("add_track", index=len(self.project()["tracks"]), name=name)
        return [t for t in self.project()["tracks"] if t["name"] == name][-1]["id"]

    def caption(self, track, start, end):
        return self.must("add_text_clip", track=track, at=start, duration=end - start,
                         text={"content": f"cue {start}"})["new_clips"][0]

    def captions(self, marks, name="Captions"):
        track = self.track(name)
        return [self.caption(track, a, b) for a, b in zip(marks, marks[1:])]

    def action(self, clip, at, duration, speed=None):
        action = self.must("add_action", clip=clip, at=at, duration=duration)["new_actions"][0]
        self.must("set_action", clip=clip, action=action, curve="linear") \
            if self.find(clip)["actions"][0]["curve"] != "linear" else None
        if speed is not None:
            self.must("set_action_end", clip=clip, action=action, patch={"speed": speed})
        return action

    def find(self, clip, project=None):
        clips = (project or self.project())["clips"]
        return next((c for c in clips if c["id"] == clip), None)


def spans(clips, ids):
    by_id = {c["id"]: c for c in clips}
    return [[by_id[i]["start"], by_id[i]["start"] + by_id[i]["duration"]] if i in by_id else None
            for i in ids]


def placed(marks, mapping):
    """Abutting captions on `marks`, each end through `mapping` and snapped."""
    ends = [snap(mapping(m)) for m in marks]
    return [[a, b] for a, b in zip(ends, ends[1:])]


def retimed_row(row, doc, tool, arguments, ids, want, *, removed=None, name=None):
    answer = doc.call(tool, **arguments)
    reply = answer.get("reply", {})
    got = spans(doc.project()["clips"], ids)
    kept = [i for i, w in zip(ids, want) if w is not None]
    good = (answer["ok"] and got == want and reply.get("captions_retimed") == kept
            and reply.get("captions_removed") == removed)
    detail = (f"{answer.get('error', 'applied')}; got {got}; want {want}; captions_retimed "
              f"{reply.get('captions_retimed')} captions_removed {reply.get('captions_removed')}")
    if name is not None:
        undone = doc.call("undo")
        said = json.dumps(undone.get("reply", undone.get("error")))
        good = good and undone["ok"] and name in said
        detail += f"; undo answered {said[:200]}"
    check(row, good, detail)
    return answer


# ---- the rows ---------------------------------------------------------------

def c1(client):
    doc = Doc(client, "c1")
    try:
        d = 3 * SEC
        clip = doc.clip(d)
        marks = [0, SEC, 2 * SEC, 3 * SEC]
        ids = doc.captions(marks)
        retimed_row("C1", doc, "set_speed", {"clip": clip, "rate": 2}, ids,
                    placed(marks, lambda t: t / 2), name="Speed and Re-time Captions")
    finally:
        doc.close()


def c2(client):
    doc = Doc(client, "c2")
    try:
        d = 3 * SEC
        clip = doc.clip(d)
        marks = [0, SEC, 2 * SEC, 3 * SEC]
        ids = doc.captions(marks)
        retimed_row("C2", doc, "rate_stretch", {"clip": clip, "to_end": d // 2}, ids,
                    placed(marks, lambda t: t / 2))
    finally:
        doc.close()


def c3(client):
    doc = Doc(client, "c3")
    try:
        d = 3 * SEC
        clip = doc.clip(d)
        marks = [0, SEC, 2 * SEC, 3 * SEC]
        ids = doc.captions(marks)
        retimed_row("C3", doc, "add_speed_ramp",
                    {"clip": clip, "shape": "ramp_up", "rate": 2, "curve": "linear"}, ids,
                    placed(marks, lambda c: ramp_inverse(c, 2, d)))
    finally:
        doc.close()


def c4(client):
    doc = Doc(client, "c4")
    try:
        d = 3 * SEC
        clip = doc.clip(d)
        action = doc.action(clip, 0, d)
        marks = [0, SEC, 2 * SEC, 3 * SEC]
        ids = doc.captions(marks)
        retimed_row("C4", doc, "set_action_end",
                    {"clip": clip, "action": action, "patch": {"speed": 2}}, ids,
                    placed(marks, lambda c: ramp_inverse(c, 2, d)))
    finally:
        doc.close()


def c5(client):
    doc = Doc(client, "c5")
    try:
        d = 2 * SEC
        h = d / 2
        clip = doc.clip(d)
        action = doc.action(clip, 0, d, speed=2)
        marks = [0, SEC // 2, 3 * SEC // 2]
        ids = doc.captions(marks)

        def new_inverse(s):
            held = ramp_forward(h, 2, h)
            return ramp_inverse(s, 2, h) if s <= held else h + (s - held) / 2

        retimed_row("C5", doc, "set_action", {"clip": clip, "action": action, "duration": d // 2},
                    ids, placed(marks, lambda c: new_inverse(ramp_forward(c, 2, d))))
    finally:
        doc.close()


def c6_c7(client):
    doc = Doc(client, "c6")
    try:
        d = 3 * SEC
        clip = doc.clip(d)
        doc.must("add_speed_ramp", clip=clip, shape="ramp_up", rate=2, curve="linear")
        action = doc.find(clip)["actions"][0]["id"]
        marks = [0, SEC, 2 * SEC, 5 * SEC // 2, 3 * SEC]
        ids = doc.captions(marks)
        before = doc.project()["clips"]
        want = placed(marks[:4], lambda c: ramp_forward(c, 2, d))
        want[2][1] = d          # its end's source is past the window: clamped to the clip's end
        want.append(None)       # its source start is past the window: removed
        answer = retimed_row("C6", doc, "remove_action", {"clip": clip, "action": action}, ids,
                             want, removed=[ids[3]])
        after = doc.project()["clips"]
        undone = doc.call("undo")
        back = doc.project()["clips"]
        redone = doc.call("redo")
        again = doc.project()["clips"]
        good = (answer["ok"] and undone["ok"] and redone["ok"]
                and json.dumps(back, sort_keys=True) == json.dumps(before, sort_keys=True)
                and json.dumps(again, sort_keys=True) == json.dumps(after, sort_keys=True)
                and after != before)
        check("C7", good, f"undo {undone.get('error', 'ok')}, restores every clip "
              f"{back == before}; redo {redone.get('error', 'ok')}, re-applies {again == after}")
    finally:
        doc.close()


def c8(client):
    doc = Doc(client, "c8")
    try:
        d = 3 * SEC
        clip = doc.clip(d)
        marks = [0, SEC, 2 * SEC, 3 * SEC]
        ids = doc.captions(marks)
        doc.must("nest", clips=[clip] + ids)
        nest = (doc.project().get("nests") or [{}])[0]
        answer = doc.call("set_speed", clip=clip, rate=2, scope=nest.get("id"))
        reply = answer.get("reply", {})
        inner = (doc.project().get("nests") or [{}])[0]
        got = spans(inner.get("clips") or [], ids)
        want = placed(marks, lambda t: t / 2)
        check("C8", answer["ok"] and got == want and reply.get("captions_retimed") == ids
              and reply.get("scope") is not None,
              f"nest {nest.get('id')}; {answer.get('error', 'applied')}; got {got}; want {want}; "
              f"captions_retimed {reply.get('captions_retimed')} scope {reply.get('scope')}")
    finally:
        doc.close()


def c9(client):
    found = []

    def control(name, build):
        doc = Doc(client, f"c9-{name}")
        try:
            tool, arguments, caption = build(doc)
            before = spans(doc.project()["clips"], [caption])
            answer = doc.call(tool, **arguments)
            keys = [k for k in answer.get("reply", {}) if k.startswith("captions_")]
            now = spans(doc.project()["clips"], [caption])
            good = answer["ok"] and not keys and now == before
            found.append((good, f"{name}: {answer.get('error', 'applied')}, keys {keys}, "
                                f"{before} → {now}"))
        finally:
            doc.close()

    def zoom(doc):
        clip = doc.clip(3 * SEC)
        caption = doc.captions([SEC, 2 * SEC])[0]
        zoomed = doc.must("add_zoom_action", clip=clip, at=0, duration=SEC,
                          region={"x": 0, "y": 0, "width": 960, "height": 540})
        return "set_action", {"clip": clip, "action": zoomed["new_actions"][0],
                              "start": SEC}, caption

    def titles(doc):
        clip = doc.clip(3 * SEC)
        return "set_speed", {"clip": clip, "rate": 2}, doc.captions([SEC, 2 * SEC], "Titles")[0]

    def straddling(doc):
        clip = doc.clip(3 * SEC)
        doc.must("move_clip", clips=[clip], delta=SEC)
        return "set_speed", {"clip": clip, "rate": 2}, doc.captions([SEC // 2, 3 * SEC // 2])[0]

    for name, build in [("zoom", zoom), ("titles", titles), ("straddling", straddling)]:
        try:
            control(name, build)
        except Exception as error:  # a broken control is a FAIL, not an exit
            found.append((False, f"{name}: could not run: {error}"))
    check("C9", len(found) == 3 and all(g for g, _ in found), "; ".join(d for _, d in found))


RUNNERS = {"C1": c1, "C2": c2, "C3": c3, "C4": c4, "C5": c5, "C6": c6_c7, "C8": c8, "C9": c9}


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def run_app(binary, chosen):
    log = WORK / "framejob.log"
    launched = mcp.launch(str(binary), env=bounded.child_env(), log_path=str(log),
                          timeout=CALL_BOUND)
    up = launched.client is not None
    try:
        if not up:
            for name in chosen:
                check(name, False, f"the app did not listen at {launched.socket_path}")
        else:
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            for name in [n for n in chosen if n in RUNNERS]:
                if not AV_MOV.exists():
                    check(name, False, f"the fixture is missing: {AV_MOV}")
                    continue
                try:
                    RUNNERS[name](launched.client)
                except Exception as error:  # an instrument that breaks is a FAIL, not an exit
                    check(name, False, f"the row could not run: {type(error).__name__}: {error}")
                    if name == "C6" and "C7" in chosen and "C7" not in rows:
                        check("C7", False, "C6's project could not be made")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("C0", up and found == [], f"listening {up}; complaints {found[:5]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    binary = args.app or proof_app.binary()
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    started = time.monotonic()
    if not Path(binary).exists():
        print(f"the app is not built: {binary}")
        return 1
    only = [r for r in args.only.split(",") if r]
    chosen = [r for r in ROWS[1:] if not only or r in only]
    if "C7" in chosen and "C6" not in chosen:
        chosen.insert(chosen.index("C7"), "C6")
    print(f"captions follow a speed or ramp edit (#341) — {binary}", flush=True)
    run_app(binary, chosen)
    scored = ["C0"] + chosen
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
