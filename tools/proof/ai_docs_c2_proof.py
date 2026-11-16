#!/usr/bin/env python3
"""ai-docs batch c2 (#521 #526 #532 #533, spec §11 #521, #526, #532): what the app prints. The
Transcript tab's overlap sentence names an overlap, not a transition; the app's own strings spell
color and center; a frames timecode at a fractional rate that is not NTSC counts real seconds;
`Fps.displayName` trims every trailing zero.

    python3 tools/proof/ai_docs_c2_proof.py [--only W1,S3,G1,…] [--app PATH] [--expect-red]
    RC_PROOF_APP=release python3 tools/proof/ai_docs_c2_proof.py
    RC_PROOF_APP=<a base .app> python3 tools/proof/ai_docs_c2_proof.py --expect-red

The built app (`proof_app`'s choice) under a scratch home, driven over MCP, on projects built from
media made into `tools/proof/work/ai-docs-c2/media/`: two `say`-voiced WAVs (speechA, speechB,
about 17 s each) and 30 fps 1280 × 720 clips with sound of 40 s (long40) and 3 s (short3), made
with ffmpeg. `(c)` marks a CONTROL, which passes on the base too; every other row is red on the
frozen base app, and `--expect-red` exits 0 only when that holds and no row failed for want of
running.

Launch 1 (plain):
- W1 speechA at 0 s trimmed to end at 11 s and speechB moved to start at 10 s, a bare 1 s overlap
  with no transition: every Transcript tab token (`transcript_view`) whose `why` is set reads
  "Near an overlap between two clips: a cut here would leave one clip's tail under the other.",
  and at least one such token lies wholly outside the overlap.
- W2 one such token selected in the tab, then Edit ▸ Delete: the clip count is unchanged and the
  inspector's strip reads "Refused: Near an overlap between two clips: …".
- W3 (c) every token at least 3 s from the overlap is editable, with no sentence.
- S1 the Document tab's layout dump holds a "Color" row label and no British colour form.
- S2–S6 the Sound, Shape, Picture and Color sub-tabs (an audio clip, a rectangle with a fill and a
  gradient, a video clip, an adjustment clip) and File ▸ Generate Captions…: no British
  colour/centre form in any text or tooltip of the dump, hidden views included, and in turn
  "center" (the pan readout), the gradient's "Fill color" note, the Obscure button's "center of
  the layer", the Qualifier's "Center" caption with the Pick tooltip "Click the preview to center
  the ranges on a color (Esc cancels)", and "split by speaker, colored in Subtitles".
- S7 `tools/list`: no word-bounded colour, colours, coloured, centre, centres or centred in any
  tool's or argument's text (the base: 67).
- G3 a 25/2 canvas over a 40 s clip: the toolbar reads 00:00:10:00 at 10 s and its end
  "/ 00:00:40:00".
- G5 (c) a 30000/1001 canvas over 80 s: the toolbar reads 00:00:59:28 at 60 s.
- G6 (c) the same at `[60000, 2002]`: 00:00:59:28 at 60 s.
- G7 `tools/list`: `render_frame`'s and `export`'s `burn_in_timecode` description says a frames
  timecode is non-drop at an NTSC rate and real seconds at any other fractional rate (the base:
  "non-drop" with no rate).
- F1 a 47300/1000 canvas: the Document tab shows "47.3 fps"; F2 120000/1000 "120 fps"; F3 25/2
  "12.5 fps"; F4 (c) 30000/1001 "29.97 fps" and 24000/1001 "23.976 fps".
Launch 2 (`-FrameJobExportChoice '{"preset_id":"gif"}'`, nothing persisted, Export never pressed):
- G1 File ▸ Export… over the 40 s clip: the readout is
  "480 × 270 · 12.5 fps · 00:00:40:00 · 500 frames, no audio".
- G2 over the 3 s clip: "480 × 270 · 12.5 fps · 00:00:03:00 · 37 frames, no audio".
Launch 3 (the GIF at `[24, 1]`):
- G4 (c) over the 3 s clip: "480 × 270 · 24 fps · 00:00:03:00 · 72 frames, no audio".
All:
- Z1 (c) `grep "Frame Job: "` of each launch's log prints nothing.
"""

import argparse
import json
import re
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
import word_onsets  # noqa: E402

WORK = ROOT / "tools/proof/work/ai-docs-c2"
HOME = WORK / "home"
MEDIA = WORK / "media"
CALL_BOUND = 600
SEC = 600_000

ROWS = ["W1", "W2", "W3", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "G3", "G5", "G6", "G7", "F1",
        "F2", "F3", "F4", "G1", "G2", "G4", "Z1"]
CONTROLS = {"W3", "G5", "G6", "F4", "G4", "Z1"}
LAUNCH_ONE = {"W1", "W2", "W3", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "G3", "G5", "G6", "G7",
              "F1", "F2", "F3", "F4"}
LAUNCH_TWO = {"G1", "G2"}
LAUNCH_THREE = {"G4"}

NEAR = "Near an overlap between two clips: a cut here would leave one clip's tail under the other."
PICK_TIP = "Click the preview to center the ranges on a color (Esc cancels)"
BRITISH = re.compile(r"\b(colour|colours|coloured|centre|centres|centred)\b", re.I)

results = {}
broken = set()
selected = set(ROWS)


def check(row, ok, detail):
    if row not in selected:
        return
    results.setdefault(row, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {row}: {detail}", flush=True)


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

    def track0(self):
        return self.state()["tracks"][0]["id"]

    def add(self, file, at=0.0):
        media = self.call("import_media", path=str(MEDIA / file))["media"]
        answer = self.call("add_clip", track=self.track0(), media=media, at=round(at * SEC))
        return media, answer["new_clips"][0]

    def views(self, name, **a):
        """(text, tooltip, hidden) of every view in a `snapshot_ui` layout dump."""
        png = WORK / f"{name}.png"
        self.call("snapshot_ui", path=str(png), **a)
        dump = json.loads(png.with_suffix(".layout.json").read_text())
        return [(v.get("text"), v.get("tooltip"), v.get("hidden")) for v in dump.get("views", [])]

    def close(self):
        try:
            self.c.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def strings_of(views):
    return [s for text, tip, _ in views for s in (text, tip) if s]


def british(views):
    return [s for s in strings_of(views) if BRITISH.search(s)]


# ---- #521 ------------------------------------------------------------------------------------

def wall_rows(client):
    d = Doc(client, "wall")
    try:
        ma = d.call("import_media", path=str(MEDIA / "speechA.wav"))["media"]
        mb = d.call("import_media", path=str(MEDIA / "speechB.wav"))["media"]
        ready = [word_onsets.wait_voice(d.path, m) for m in (ma, mb)]
        track = d.track0()
        a = d.call("add_clip", track=track, media=ma, at=0)["new_clips"][0]
        d.call("trim_end", clip=a, to=11 * SEC)
        b = d.call("add_clip", track=track, media=mb, at=30 * SEC)["new_clips"][0]
        d.call("move_clip", clips=[b], delta=-20 * SEC)
        clips = {c["id"]: c for c in d.state()["clips"]}
        lo, hi = clips[b]["start"], clips[a]["start"] + clips[a]["duration"]
        bare = not any(c.get("transition") for c in clips.values())
        d.call("select_inspector_tab", tab="transcript")
        tokens = d.call("transcript_view", wait=60).get("tokens", [])
        whys = [t for t in tokens if t.get("why")]
        outside = [t for t in whys if t["end"] <= lo or t["start"] >= hi]
        sentences = sorted({t["why"] for t in whys})
        check("W1", whys and all(t["why"] == NEAR for t in whys) and outside and bare,
              f"caches ready {ready}; overlap {lo / SEC}–{hi / SEC} s, no transition {bare}; "
              f"{len(whys)} of {len(tokens)} tokens with a sentence, {len(outside)} wholly outside "
              f"the overlap; sentences {sentences}")
        far = [t for t in tokens if abs(t["start"] - lo) >= 3 * SEC and abs(t["start"] - hi) >= 3 * SEC]
        check("W3", far and all(t["editable"] and not t.get("why") for t in far),
              f"{len(far)} tokens ≥ 3 s from the overlap, all editable "
              f"{all(t['editable'] for t in far)}, any sentence {any(t.get('why') for t in far)}")
        if not outside:
            check("W2", False, "no token with a sentence lies outside the overlap")
            return
        pick = outside[0]
        d.call("transcript_view", focus=True, select=[pick["index"], pick["index"]])
        before = len(d.state()["clips"])
        d.call("perform_menu_item", path=["Edit", "Delete"])
        after = len(d.state()["clips"])
        views = d.views("w2-inspector", window="editor", view="inspector")
        strip = [t for t, _, hidden in views if t and not hidden and t.startswith("Refused")]
        check("W2", before == after and strip == [f"Refused: {NEAR}"],
              f"token {pick['index']} {pick['text']!r}: clips {before} → {after}; strip {strip}")
    finally:
        d.close()


# ---- #526 ------------------------------------------------------------------------------------

def spelling_rows(client):
    d = Doc(client, "spell")
    try:
        _, video = d.add("short3.mov", at=0)
        _, audio = d.add("speechA.wav", at=3)
        track = d.track0()
        shape = d.call("add_shape_clip", track=track, at=25 * SEC, duration=3 * SEC,
                       shape={"kind": "rectangle", "fill": [1, 0, 0, 1],
                              "gradient": {"kind": "linear", "angle": 0,
                                           "stops": [{"at": 0, "color": [0, 0, 0, 1]},
                                                     {"at": 1, "color": [1, 1, 1, 1]}]}}
                       )["new_clips"][0]
        adjust = d.call("add_adjustment_clip", track=track, at=30 * SEC,
                        duration=3 * SEC)["new_clips"][0]

        d.call("select_inspector_tab", tab="document")
        views = d.views("s1-document", window="editor", view="inspector")
        labels = [t for t, _, hidden in views if t in ("Color", "Colour") and not hidden]
        check("S1", "Color" in labels and not british(views),
              f"row labels {labels}; British {british(views) or 'none'}")

        wants = (("S2", audio, "sound", lambda s: "center" in s, "the pan readout 'center'"),
                 ("S3", shape, "shape",
                  lambda s: "The gradient covers the Fill color above; Reset brings it back." in s,
                  "the gradient's 'Fill color' note"),
                 ("S4", video, "picture",
                  lambda s: any("pixelated box at the center of the layer" in x for x in s),
                  "the Obscure button's 'center of the layer'"),
                 ("S5", adjust, "color", lambda s: "Center" in s and PICK_TIP in s,
                  "the 'Center' caption and the Pick tooltip"))
        for row, clip, sub, holds, what in wants:
            d.call("set_selection", clips=[clip])
            d.call("select_inspector_tab", tab="clip", sub_tab=sub)
            views = d.views(f"{row.lower()}-{sub}", window="editor", view="inspector")
            found = strings_of(views)
            check(row, holds(found) and not british(views),
                  f"{sub}: {what} {'shown' if holds(found) else 'MISSING'}; British "
                  f"{british(views) or 'none'}")

        d.call("set_selection", clips=[audio])
        d.call("perform_menu_item", path=["File", "Generate Captions…"])
        views = d.views("s6-captions", window="sheet")
        d.call("cancel_sheet")
        found = strings_of(views)
        want = "split by speaker, colored in Subtitles"
        check("S6", want in found and not british(views),
              f"'{want}' {'shown' if want in found else 'MISSING'}; British "
              f"{british(views) or 'none'}")
    finally:
        d.close()

    count, tools = 0, []
    for name, tool in client.schemas().items():
        texts = [tool.get("description", "")] + descriptions(tool.get("inputSchema", {}), [])
        n = sum(len(BRITISH.findall(t)) for t in texts)
        if n:
            count += n
            tools.append(f"{name} ({n})")
    check("S7", count == 0, f"tools/list: {count} British forms in {len(tools)} tools "
          f"{tools[:8] or ''}")


def descriptions(node, out):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "description" and isinstance(value, str):
                out.append(value)
            else:
                descriptions(value, out)
    elif isinstance(node, list):
        for value in node:
            descriptions(value, out)
    return out


# ---- #532 and #533 ---------------------------------------------------------------------------

def toolbar_codes(d, name, t):
    d.call("set_playhead", t=t)
    views = d.views(name, window="editor", view="toolbar")
    return [x for x, _, _ in views if x and x.count(":") == 3]


def burn_in_row(client):
    schemas = client.schemas()
    want = "non-drop at an NTSC rate, real seconds at any other fractional rate"
    seen = {}
    for tool in ("render_frame", "export"):
        props = schemas.get(tool, {}).get("inputSchema", {}).get("properties", {})
        text = props.get("burn_in_timecode", {}).get("description", "")
        seen[tool] = (want in text, "non-drop," in text)
    check("G7", all(has and not bare for has, bare in seen.values()),
          f"burn_in_timecode: (the rule, a bare 'non-drop,') per tool {seen}")


def timecode_rows(client):
    d = Doc(client, "canvas125")
    try:
        d.add("long40.mov", at=0)
        d.call("set_canvas", fps=[25, 2])
        at10 = toolbar_codes(d, "g3-10", 10 * SEC)
        check("G3", "00:00:10:00" in at10 and "/ 00:00:40:00" in at10,
              f"25/2 canvas, playhead 10 s: toolbar {at10}")
    finally:
        d.close()
    for row, fps in (("G5", [30000, 1001]), ("G6", [60000, 2002])):
        d = Doc(client, f"canvas-{fps[0]}-{fps[1]}")
        try:
            media, _ = d.add("long40.mov", at=0)
            d.call("add_clip", track=d.track0(), media=media, at=40 * SEC)
            d.call("set_canvas", fps=fps)
            at60 = toolbar_codes(d, f"{row.lower()}-60", 60 * SEC)
            check(row, "00:00:59:28" in at60, f"{fps} canvas, playhead 60 s: toolbar {at60}")
        finally:
            d.close()


def rate_rows(client):
    def shown(fps):
        d = Doc(client, f"fps-{fps[0]}-{fps[1]}")
        try:
            d.add("short3.mov", at=0)
            d.call("set_canvas", fps=fps)
            d.call("select_inspector_tab", tab="document")
            views = d.views(f"fps-{fps[0]}-{fps[1]}", window="editor", view="inspector")
            return [t for t, _, hidden in views if t and not hidden and t.endswith(" fps")]
        finally:
            d.close()

    for row, fps, want in (("F1", [47300, 1000], "47.3 fps"), ("F2", [120000, 1000], "120 fps"),
                           ("F3", [25, 2], "12.5 fps")):
        got = shown(fps)
        check(row, want in got, f"{fps}: Document tab {got}, want {want!r}")
    ntsc = shown([30000, 1001])
    film = shown([24000, 1001])
    check("F4", "29.97 fps" in ntsc and "23.976 fps" in film,
          f"30000/1001 {ntsc}, 24000/1001 {film}")


def readout(client, name, file):
    d = Doc(client, name)
    try:
        d.add(file, at=0)
        d.call("perform_menu_item", path=["File", "Export…"])
        views = d.views(name, window="sheet")
        d.call("cancel_sheet")
        return [t for t, _, _ in views if t and " fps · " in t]
    finally:
        d.close()


def gif_rows(client):
    for row, name, file, want in (
            ("G1", "gif-long40", "long40.mov",
             "480 × 270 · 12.5 fps · 00:00:40:00 · 500 frames, no audio"),
            ("G2", "gif-short3", "short3.mov",
             "480 × 270 · 12.5 fps · 00:00:03:00 · 37 frames, no audio")):
        if row in selected:
            got = readout(client, name, file)
            check(row, want in got, f"readout {got}")


def gif24_rows(client):
    want = "480 × 270 · 24 fps · 00:00:03:00 · 72 frames, no audio"
    got = readout(client, "gif24-short3", "short3.mov")
    check("G4", want in got, f"readout {got}")


# ---- launches --------------------------------------------------------------------------------

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


def choice(value):
    """An argument-domain string: the JSON as a quoted plist string."""
    return '"' + json.dumps(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def make_media():
    MEDIA.mkdir(parents=True)
    a = ("Every morning the harbour fills with small boats and loud gulls, and the fishermen call "
         "to each other across the water.")
    b = ("Please write the totals in the third column of the sheet before the meeting on Thursday "
         "afternoon.")
    c = ("Turn left at the old church, then follow the river for a mile until you reach the stone "
         "bridge.")
    for name, words in (("speechA.wav", f"{a} {b} {c}"), ("speechB.wav", f"{c} {a} {b}")):
        subprocess.run(["say", "-o", str(MEDIA / name), "--file-format=WAVE",
                        "--data-format=LEI16@16000", words], check=True)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        return False
    for name, seconds in (("long40.mov", 40), ("short3.mov", 3)):
        subprocess.run([ffmpeg, "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size=1280x720:rate=30:duration={seconds}", "-f", "lavfi", "-i",
                        f"sine=frequency=440:duration={seconds}", "-pix_fmt", "yuv420p", "-c:v",
                        "libx264", "-preset", "ultrafast", "-c:a", "aac", "-shortest",
                        str(MEDIA / name)], check=True)
    return True


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
    if not make_media():
        print("ffmpeg is not on PATH: the clips cannot be made")
        return 1

    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"ai-docs c2 — what the app prints ({binary})", flush=True)

    first = selected & LAUNCH_ONE
    if first:
        def body(client):
            if first & {"W1", "W2", "W3"}:
                wall_rows(client)
            if first & {"S1", "S2", "S3", "S4", "S5", "S6", "S7"}:
                spelling_rows(client)
            if first & {"G3", "G5", "G6"}:
                timecode_rows(client)
            if "G7" in first:
                burn_in_row(client)
            if first & {"F1", "F2", "F3", "F4"}:
                rate_rows(client)
        launch(binary, [], first, body, "launch-1")
    if selected & LAUNCH_TWO:
        launch(binary, ["-FrameJobExportChoice", choice({"preset_id": "gif"})],
               selected & LAUNCH_TWO, gif_rows, "launch-2")
    if selected & LAUNCH_THREE:
        launch(binary, ["-FrameJobExportChoice", choice({"preset_id": "gif", "fps": [24, 1]})],
               selected & LAUNCH_THREE, gif24_rows, "launch-3")

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
