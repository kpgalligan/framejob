#!/usr/bin/env python3
"""Speed ramps SR2a (spec §11 SR-10, SR-2), against the built app: an
action's `end.speed` through `set_action_end` over MCP — the door, the
slot rule's R1 sentence, the ×12 answer, undo and redo.

    env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py [--only IDS]

One owned instance (`mcp.launch` on `proof_app`'s app — Debug by default,
`RC_PROOF_APP=release` for the record), on a scratch socket, logging to
`tools/proof/work/ramp/framejob.log`, stopped by its PID; nothing else is
ever killed. Every project is written under `tools/proof/work/ramp/`, which
each run empties, and closed once its row is scored. No row performs a menu
item. The fixture is `tools/proof/media/AV.mov` (5 s, 30 fps, 48 kHz sound);
its absence is a scored FAIL.

D0  the instance listens, and `Frame Job: ` never appears in its log.
D1  a 2 s AV.mov clip, `add_action` [0, 1 s), `set_action_end {speed: 2}`
    applies; `get_project` holds `end.speed` 2 and the clip's start and
    duration as they were before the edit.
D2  a 2 s clip at in 0, an action over [0, 2 s) (linear, so S(D) = 1 s +
    x s): `speed: 5` is refused with R1, whose ×{fit} is this proof's own
    oracle from `get_project`'s media duration, floor(duration / 1 s − 1,
    0.001), and whose overrun is 6 s less that duration; then that rate
    applies.
D3  a 6-frame clip ramped over its length to ×20 answers `audio_left_out`
    [clip] and SpeedAudioDrop's one-clip `audio_note`, its template written
    here.
D4  `speed: "fast"`, and `speed: 2` on a text clip's action, are each an
    error carrying the core's exact sentence.
D5  `undo` takes D1's speed out of the end, and `redo` puts it back.

Rows print `<ID> pass|fail — <detail>`, then `n/m`; exit 0 iff every row
run passed. `--only D1,D5` runs those rows (D0 always).
"""

import argparse
import math
import os
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

WORK = ROOT / "tools/proof/work/ramp"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
ROWS = ["D0", "D1", "D2", "D3", "D4", "D5"]

rows = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


def attempt(client, tool, arguments):
    """One MCP call: a refusal or an error is an answer, not an exception."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}


def must(client, tool, arguments):
    got = attempt(client, tool, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{tool} {arguments}: {got['error']}")
    return got["reply"]


def rust_float(value):
    """A rate as the core's `{}` prints an f64: `4`, `2.666`."""
    return str(int(value)) if float(value).is_integer() else repr(float(value))


class Doc:
    """One project file, every call addressed to it."""

    def __init__(self, client, name):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        must(client, "new_project", {"path": self.path})

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=self.path))

    def must(self, tool, **arguments):
        return must(self.client, tool, dict(arguments, project=self.path))

    def project(self):
        return self.must("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def close(self):
        attempt(self.client, "close_project", {"project": self.path, "discard": True})

    def av_clip(self, length):
        """AV.mov at 0 on the first track, from in 0, cut to `length`; its
        clip id and media row."""
        media = self.must("import_media", path=str(AV_MOV))["media"]
        track = self.project()["tracks"][0]["id"]
        self.must("add_clip", track=track, media=media, at=0)
        project = self.project()
        clip = project["clips"][-1]["id"]
        if project["clips"][-1]["duration"] != length:
            self.must("trim_end", clip=clip, to=length)
        row = next(m for m in project["media"] if m["id"] == media)
        return clip, row

    def action(self, clip, at, duration):
        answer = self.must("add_action", clip=clip, at=at, duration=duration)
        return answer["new_actions"][0]


def media_name(row):
    """`MediaSnapshot.name`: the original's file name, else the path's."""
    original = row.get("original") or {}
    return os.path.basename(original.get("path") or row["path"])


def d1(client, state):
    doc = Doc(client, "d1")
    state["d1"] = doc
    clip, _ = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, SEC)
    before = doc.clip(clip)
    got = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 2})
    after = doc.clip(clip)
    end = after["actions"][0]["end"]
    kept = (after["start"], after["duration"]) == (before["start"], before["duration"])
    state["d1_clip"] = clip
    check("D1", got["ok"] and end.get("speed") == 2 and kept,
          f"answer {got.get('reply', got.get('error'))!r:.120}; end {end}; "
          f"start/duration {after['start']}/{after['duration']} "
          f"(were {before['start']}/{before['duration']})")


def d2(client, state):
    doc = Doc(client, "d2")
    clip, media = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, 2 * SEC)
    duration = media["duration"]
    fit = math.floor((duration / SEC - 1) * 1000) / 1000
    over = 6 * SEC - duration
    expected = (f"ending action {action} at ×5 would read clip {clip} {over} ticks past the "
                f"end of its media; the largest end rate that fits is ×{rust_float(fit)}")
    refused = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 5})
    named = (not refused["ok"]) and refused["error"].endswith(expected)
    applied = doc.call("set_action_end", clip=clip, action=action, patch={"speed": fit})
    end = doc.clip(clip)["actions"][0]["end"]
    check("D2", named and applied["ok"] and end.get("speed") == fit,
          f"media {duration} ticks; refusal {refused.get('error', 'none')!r}; "
          f"expected …{expected!r}; ×{rust_float(fit)} "
          f"{'applied' if applied['ok'] else applied.get('error')}, end {end}")
    doc.close()


def d3(client, state):
    doc = Doc(client, "d3")
    clip, media = doc.av_clip(6 * FRAME)
    action = doc.action(clip, 0, 6 * FRAME)
    got = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 20})
    answer = got.get("reply") if got["ok"] else {}
    note = (f"Clip {clip} (“{media_name(media)}”) now plays above ×12, so its audio is left "
            f"out: it is silent in the preview and the export.")
    good = (got["ok"] and isinstance(answer, dict)
            and answer.get("audio_left_out") == [clip] and answer.get("audio_note") == note)
    check("D3", good,
          f"audio_left_out {answer.get('audio_left_out') if isinstance(answer, dict) else None}; "
          f"audio_note {answer.get('audio_note') if isinstance(answer, dict) else got}; "
          f"expected {note!r}")
    doc.close()


def d4(client, state):
    doc = Doc(client, "d4")
    clip, _ = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, SEC)
    fast = doc.call("set_action_end", clip=clip, action=action, patch={"speed": "fast"})
    number = 'speed must be a number, not "fast"'
    track = doc.project()["tracks"][0]["id"]
    doc.must("add_text_clip", track=track, at=3 * SEC, duration=SEC)
    text = doc.project()["clips"][-1]["id"]
    text_action = doc.action(text, 0, SEC // 2)
    on_text = doc.call("set_action_end", clip=text, action=text_action, patch={"speed": 2})
    media_only = (f"clip {text} is not a media clip, and only a media clip's action can end "
                  f"at a speed")
    good = (not fast["ok"] and number in fast["error"]
            and not on_text["ok"] and media_only in on_text["error"])
    check("D4", good, f"fast: {fast.get('error', fast.get('reply'))!r}; "
                      f"text clip: {on_text.get('error', on_text.get('reply'))!r}")
    doc.close()


def d5(client, state):
    doc = state.get("d1")
    if doc is None:
        doc = Doc(client, "d1")
        state["d1"] = doc
        clip, _ = doc.av_clip(2 * SEC)
        action = doc.action(clip, 0, SEC)
        doc.must("set_action_end", clip=clip, action=action, patch={"speed": 2})
        state["d1_clip"] = clip
    clip = state["d1_clip"]
    undone = doc.call("undo")
    after_undo = doc.clip(clip)["actions"][0]["end"]
    redone = doc.call("redo")
    after_redo = doc.clip(clip)["actions"][0]["end"]
    check("D5", undone["ok"] and "speed" not in after_undo and redone["ok"]
          and after_redo.get("speed") == 2,
          f"undo {undone.get('reply', undone.get('error'))!r:.80} → end {after_undo}; "
          f"redo {redone.get('reply', redone.get('error'))!r:.80} → end {after_redo}")
    doc.close()


RUNNERS = {"D1": d1, "D2": d2, "D3": d3, "D4": d4, "D5": d5}


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def run_all(binary, chosen):
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
            state = {}
            for name in chosen:
                if not AV_MOV.exists():
                    check(name, False, f"the fixture is missing: {AV_MOV}")
                    continue
                try:
                    RUNNERS[name](launched.client, state)
                except Exception as error:  # an instrument that breaks is a FAIL, not an exit
                    check(name, False, f"the row could not run: {type(error).__name__}: {error}")
            if "d1" in state:
                state["d1"].close()
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("D0", up and found == [], f"listening {up}; complaints {found[:5]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    chosen = [r for r in ROWS[1:] if not args.only or r in args.only.split(",")]
    binary = args.app or proof_app.binary()
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    started = time.monotonic()
    if not Path(binary).exists():
        print(f"the app is not built: {binary}")
        return 1
    print(f"speed ramps SR2a — set_action_end's speed over MCP — {binary}", flush=True)
    run_all(binary, chosen)
    scored = ["D0"] + chosen
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
