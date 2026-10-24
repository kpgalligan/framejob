#!/usr/bin/env python3
"""Speed ramp presets (#340, spec §11 SR-23..SR-25): `add_speed_ramp` over MCP and the sheet's arithmetic.

    make app-debug    # or make app, with RC_PROOF_APP=release for the recorded run
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_preset_proof.py [--only P1,P11]

One owned instance (`mcp.launch` on `proof_app`'s app — Debug by default,
`RC_PROOF_APP=release` for the recorded run), one project per row, each closed
with `discard`. The fixture of P1–P10 is `tools/proof/media/AV.mov` (5 s,
30 fps, with sound) placed at 0 from in 0 and cut to 2 s by `trim_end`, so 3 s
of media lie past its out point; P2 and P4 set the clip's speed first.

- P0  the log has no `Frame Job: ` line (the startup parity check).
- P1  Ramp Up ×2 over the whole clip: one action [0, D) `ease_in_out` ending at
      ×2, `new_actions` naming it, the slot kept.
- P2  Ramp Down ×0.5 at base ×1.5 over clip time 0.5–1.5 s, linear: one action.
- P3  Speed Dip ×0.5, hold 0.25, the whole clip: two actions of r = (D·0.75/2)
      snapped down, ending at ×0.5 and back at ×1.
- P4  Speed Burst ×2 at base ×1.25, the defaults: action 2 ends at ×1.25.
- P5  one `undo` removes both of P3's actions and `redo` restores them.
- P6  Up ×10 linear over the whole clip is refused naming the oracle's fit
      (S(D) = D(1 + x)/2), and that fit then applies.
- P7  an action inside a dip's hold gap is refused by its id; `add_action`'s
      answer has no new key.
- P8  the direction refusal, exact.
- P9  a 6-frame Up ×20 over the clip's last six frames answers
      `audio_left_out` [clip] with the one-clip note.
- P10 the errors carry their sentences: `hold` on Up, shape "zigzag", `from`
      without `to`; nothing applied.
- P11 `ramp_preset_probe.swift` built over `app/Sources` through
      `swift_build.build()` and run: A1 the span, A2 the op, A3 the applied
      readout, A4 a refusal's readout with Apply disabled, A5 the ×12 crossing
      and `mayCross`. A probe that does not build fails every A row.
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/ramp-preset"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
PROBE = ROOT / "tools/proof/ramp_preset_probe.swift"
PROBE_WORK = WORK / "probe"
PROBE_WALL = 60
CALL_BOUND = 600
SEC = 600_000
FRAME = 20_000
D = 2 * SEC
APP_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10"]
ROWS = ["P0"] + APP_ROWS + ["P11"]
A_ROWS = ["A1", "A2", "A3", "A4", "A5"]
NOTE_TAIL = ("”) now plays above ×12, so its audio is left out: it is silent in the preview "
             "and the export.")

rows = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


def rust_float(value):
    """A rate as the core's `{}` prints an f64: `4`, `2.333`."""
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def attempt(client, tool, arguments):
    """One MCP call: a refusal or an error is an answer, not an exception."""
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

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def close(self):
        attempt(self.client, "close_project", {"project": self.path, "discard": True})

    def fixture(self, speed=None):
        """AV.mov at 0 from in 0 (at `speed` when given), cut to 2 s: the clip
        id and its media's duration."""
        media = self.must("import_media", path=str(AV_MOV))["media"]
        track = self.project()["tracks"][0]["id"]
        clip = self.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
        if speed is not None:
            self.must("set_speed", clip=clip, rate=speed)
        self.must("trim_end", clip=clip, to=D)
        project = self.project()
        placed = next(c for c in project["clips"] if c["id"] == clip)
        if (placed["start"], placed["duration"], placed["source"].get("in")) != (0, D, 0):
            raise RuntimeError(f"the clip landed as {placed}")
        file = next(m for m in project["media"] if m["id"] == media)["duration"]
        return clip, file

    def ramp(self, clip, shape, rate, **more):
        return self.call("add_speed_ramp", clip=clip, shape=shape, rate=rate, **more)


def spans(clip_json):
    return [(a["start"], a["duration"], a["curve"], a["end"]) for a in clip_json["actions"]]


def ramp_length(span, hold):
    return max(int(span * (1 - hold) / 2) // FRAME * FRAME, FRAME)


def refused_with(answer, reason):
    return not answer["ok"] and answer["error"].endswith(": " + reason)


# ---- the app rows ----------------------------------------------------------

def p1(client):
    doc = Doc(client, "p1")
    try:
        clip, _ = doc.fixture()
        answer = doc.ramp(clip, "ramp_up", 2)
        after = doc.clip(clip)
    finally:
        doc.close()
    reply = answer.get("reply", {})
    ids = [a["id"] for a in after["actions"]]
    good = (answer["ok"] and spans(after) == [(0, D, "ease_in_out", {"speed": 2})]
            and reply.get("new_actions") == ids and "audio_left_out" not in reply
            and (after["start"], after["duration"]) == (0, D))
    check("P1", good, f"{answer.get('error', 'applied')}; actions {spans(after)}; "
          f"new_actions {reply.get('new_actions')}")


def p2(client):
    doc = Doc(client, "p2")
    try:
        clip, _ = doc.fixture(speed=1.5)
        answer = doc.ramp(clip, "ramp_down", 0.5, **{"from": SEC // 2, "to": 3 * SEC // 2},
                          curve="linear")
        after = doc.clip(clip)
    finally:
        doc.close()
    good = (answer["ok"] and after["speed"] == 1.5
            and spans(after) == [(SEC // 2, SEC, "linear", {"speed": 0.5})]
            and len(answer["reply"].get("new_actions", [])) == 1)
    check("P2", good, f"{answer.get('error', 'applied')}; base {after.get('speed')}; "
          f"actions {spans(after)}")


def p3_p5(client):
    doc = Doc(client, "p3")
    try:
        clip, _ = doc.fixture()
        answer = doc.ramp(clip, "speed_dip", 0.5, hold=0.25)
        after = doc.clip(clip)
        undone = doc.call("undo")
        after_undo = doc.clip(clip)
        redone = doc.call("redo")
        after_redo = doc.clip(clip)
    finally:
        doc.close()
    r = ramp_length(D, 0.25)
    want = [(0, r, "ease_in_out", {"speed": 0.5}), (D - r, r, "ease_in_out", {"speed": 1})]
    ids = [a["id"] for a in after["actions"]]
    good = (answer["ok"] and r == 22 * FRAME and spans(after) == want
            and answer["reply"].get("new_actions") == ids)
    check("P3", good, f"{answer.get('error', 'applied')}; r {r}; actions {spans(after)}; "
          f"new_actions {answer.get('reply', {}).get('new_actions')}")
    good = (good and undone["ok"] and after_undo["actions"] == [] and redone["ok"]
            and spans(after_redo) == want)
    check("P5", good, f"undo {undone.get('error', 'ok')} → {spans(after_undo)}; redo "
          f"{redone.get('error', 'ok')} → {spans(after_redo)}")


def p4(client):
    doc = Doc(client, "p4")
    try:
        clip, _ = doc.fixture(speed=1.25)
        answer = doc.ramp(clip, "speed_burst", 2)
        after = doc.clip(clip)
    finally:
        doc.close()
    r = ramp_length(D, 0.5)
    want = [(0, r, "ease_in_out", {"speed": 2}), (D - r, r, "ease_in_out", {"speed": 1.25})]
    check("P4", answer["ok"] and spans(after) == want,
          f"{answer.get('error', 'applied')}; actions {spans(after)} (want {want})")


def p6(client):
    doc = Doc(client, "p6")
    try:
        clip, file = doc.fixture()
        refused = doc.ramp(clip, "ramp_up", 10, curve="linear")
        # S(D) = D(1 + x)/2 for a linear ramp from ×1 over the whole clip.
        over = round(D * 11 / 2) - file
        fit = next((k / 1000 for k in range(9999, 1000, -1)
                    if round(D * (1 + k / 1000) / 2) <= file), None)
        want = (f"a ramp up to ×10 would read clip {clip} {over} ticks past the end of its "
                f"media; the largest rate that fits is ×{rust_float(fit)}")
        applied = doc.ramp(clip, "ramp_up", fit, curve="linear") if fit else {"ok": False}
        after = doc.clip(clip)
    finally:
        doc.close()
    good = (refused_with(refused, want) and applied["ok"]
            and spans(after) == [(0, D, "linear", {"speed": fit})])
    check("P6", good, f"media {file}; {refused.get('error', 'APPLIED')!r} (want …{want!r}); "
          f"×{fit} {applied.get('error', 'applied')} → {spans(after)}")


def p7(client):
    doc = Doc(client, "p7")
    try:
        clip, _ = doc.fixture()
        added = doc.must("add_action", clip=clip, at=27 * FRAME, duration=6 * FRAME)
        action = added["new_actions"][0]
        refused = doc.ramp(clip, "speed_dip", 0.5)
        after = doc.clip(clip)
    finally:
        doc.close()
    want = (f"action {action} on clip {clip} already runs from {27 * FRAME} to {33 * FRAME} "
            f"ticks, and two actions on one clip may not overlap")
    keys = sorted(added)
    good = (refused_with(refused, want) and len(after["actions"]) == 1
            and keys == ["clip", "new_actions", "ok", "project"])
    check("P7", good, f"{refused.get('error', 'APPLIED')!r} (want …{want!r}); add_action "
          f"keys {keys}")


def p8(client):
    doc = Doc(client, "p8")
    try:
        clip, _ = doc.fixture()
        refused = doc.ramp(clip, "ramp_up", 0.5)
    finally:
        doc.close()
    want = (f"a ramp up needs a rate above ×1, the rate clip {clip} plays at 0 ticks into it; "
            f"×0.5 is not")
    check("P8", refused_with(refused, want),
          f"{refused.get('error', 'APPLIED')!r} (want …{want!r})")


def p9(client):
    doc = Doc(client, "p9")
    try:
        clip, _ = doc.fixture()
        answer = doc.ramp(clip, "ramp_up", 20, **{"from": D - 6 * FRAME, "to": D})
        after = doc.clip(clip)
    finally:
        doc.close()
    reply = answer.get("reply", {})
    note = reply.get("audio_note", "")
    good = (answer["ok"] and reply.get("audio_left_out") == [clip]
            and note.startswith(f"Clip {clip} (“") and note.endswith(NOTE_TAIL)
            and spans(after) == [(D - 6 * FRAME, 6 * FRAME, "ease_in_out", {"speed": 20})])
    check("P9", good, f"{answer.get('error', 'applied')}; audio_left_out "
          f"{reply.get('audio_left_out')}; note {note!r}")


def p10(client):
    doc = Doc(client, "p10")
    try:
        clip, _ = doc.fixture()
        hold = doc.ramp(clip, "ramp_up", 2, hold=0.5)
        shape = doc.ramp(clip, "zigzag", 2)
        lone = doc.ramp(clip, "speed_dip", 0.5, **{"from": SEC})
        after = doc.clip(clip)
    finally:
        doc.close()
    wants = [(hold, "hold is for speed_dip and speed_burst only"),
             (shape, 'shape must be one of ramp_up, ramp_down, speed_dip, speed_burst '
                     '(got "zigzag").'),
             (lone, "from and to are given together or not at all")]
    good = all(not got["ok"] and want in got["error"] for got, want in wants)
    check("P10", good and after["actions"] == [],
          "; ".join(repr(got.get("error", "APPLIED")) for got, _ in wants)
          + f"; actions {after['actions']}")


RUNNERS = {"P1": p1, "P2": p2, "P3": p3_p5, "P4": p4, "P6": p6, "P7": p7, "P8": p8,
           "P9": p9, "P10": p10}


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
                    if name == "P3" and "P5" in chosen:
                        check("P5", False, "P3's project could not be made")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("P0", up and found == [], f"listening {up}; complaints {found[:5]}")


# ---- the probe -------------------------------------------------------------

def probe():
    """(readings, None) or (None, why)."""
    PROBE_WORK.mkdir(parents=True, exist_ok=True)
    entry = PROBE_WORK / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = PROBE_WORK / "ramp-preset-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(ROOT / "app/Sources") + [entry],
                          output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    try:
        ran = subprocess.run([str(binary)], capture_output=True, text=True,
                             timeout=PROBE_WALL, cwd=PROBE_WORK)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {PROBE_WALL} s"
    (PROBE_WORK / "stderr.txt").write_text(ran.stderr)
    (PROBE_WORK / "answer.json").write_text(ran.stdout)
    try:
        answer = json.loads(ran.stdout)
    except ValueError:
        return None, f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"
    if answer.get("error") or answer.get("problems"):
        return None, f"the fixtures: {answer.get('error')} {answer.get('problems', '')}"
    return answer, None


def a1(got):
    found = got["A1"]
    want = {"inside": [SEC // 2, 3 * SEC // 2], "past_end": None, "before_start": None,
            "empty": None, "absent": None, "exact": [0, D]}
    return found == want, f"{found}"


def a2(got):
    found, x = got["A2"], got["clips"]["X"]["id"]
    span = {"from": SEC // 2, "to": 3 * SEC // 2}
    want = {
        "dip": {"name": "add_speed_ramp", "args": {"clip": x, "shape": "speed_dip", "rate": 0.5,
                                                   "curve": "ease_in_out", "hold": 0.25}},
        "burst": {"name": "add_speed_ramp", "args": dict(
            {"clip": x, "shape": "speed_burst", "rate": 2, "curve": "ease_in_out", "hold": 0},
            **span)},
        "up": {"name": "add_speed_ramp", "args": dict(
            {"clip": x, "shape": "ramp_up", "rate": 2, "curve": "linear"}, **span)},
        "down": {"name": "add_speed_ramp", "args": {"clip": x, "shape": "ramp_down",
                                                    "rate": 0.5, "curve": "ease_in_out"}},
        "defaults": [["ramp_up", 2], ["ramp_down", 0.5], ["speed_dip", 0.5],
                     ["speed_burst", 2]],
        "holds": [0, 0.25, 0.5, 0.75],
        "names": ["Ramp Up", "Ramp Down", "Speed Dip", "Speed Burst"],
    }
    return found == want, f"{found}"


def a3(got):
    found, tc = got["A3"], got["tc"]
    want = {
        "dip": {"lines": [f"Speed Dip · the whole clip {tc['0']} – {tc[str(D)]}",
                          "×1 → ×0.5, held 1.00 s, → ×1"], "can_apply": True},
        "up": {"lines": [f"Ramp Up · the range {tc[str(SEC // 2)]} – {tc[str(3 * SEC // 2)]}",
                         "×1 → ×2"], "can_apply": True},
    }
    return found == want, f"{found}"


def a4(got):
    found, tc = got["A4"], got["tc"]
    x, gap, file = got["clips"]["X"]["id"], got["gap_action"], got["media_duration"]
    over = round(D * 11 / 2) - file
    fit = next((k / 1000 for k in range(9999, 1000, -1)
                if round(D * (1 + k / 1000) / 2) <= file), None)
    whole = f"the whole clip {tc['0']} – {tc[str(D)]}"
    want = {
        "overrun": {"lines": [f"Ramp Up · {whole}",
                              f"a ramp up to ×10 would read clip {x} {over} ticks past the end "
                              f"of its media; the largest rate that fits is ×{rust_float(fit)}"],
                    "can_apply": False},
        "overlap": {"lines": [f"Speed Dip · {whole}",
                              f"action {gap} on clip {x} already runs from {27 * FRAME} to "
                              f"{33 * FRAME} ticks, and two actions on one clip may not overlap"],
                    "can_apply": False},
        "direction": {"lines": [f"Ramp Up · {whole}",
                                f"a ramp up needs a rate above ×1, the rate clip {x} plays at 0 "
                                f"ticks into it; ×0.5 is not"], "can_apply": False},
    }
    return found == want, f"{found}"


def a5(got):
    found, x = got["A5"], got["clips"]["X"]["id"]
    want = {"x14": [x], "x12": [], "may_cross": True}
    return found == want, f"{found}"


def run_probe(chosen):
    if "P11" not in chosen:
        return
    got, why = probe()
    scored = []
    for name, score in zip(A_ROWS, [a1, a2, a3, a4, a5]):
        if got is None:
            good, detail = False, f"the probe did not build or run: {why}"
        else:
            try:
                good, detail = score(got)
            except Exception as error:  # a reading that is missing is a FAIL
                good, detail = False, f"the reading could not be scored: {error!r}"
        print(f"  {name} {'pass' if good else 'fail'} — {detail}", flush=True)
        scored.append(good)
    check("P11", all(scored), f"{sum(scored)}/{len(A_ROWS)} A rows")


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
    if "P5" in chosen and "P3" not in chosen:
        chosen.insert(chosen.index("P5"), "P3")
    print(f"speed ramp presets (#340) — add_speed_ramp and Clip ▸ Speed Ramp…'s arithmetic — "
          f"{binary}", flush=True)
    run_app(binary, chosen)
    run_probe(chosen)
    scored = ["P0"] + chosen
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
