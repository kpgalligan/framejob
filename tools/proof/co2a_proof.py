#!/usr/bin/env python3
"""Road map "creator-jobs" CO2a1 — `video.cutout` and the recipe's `cutout`
key (spec §11 CO-20, CO-21, CO-23). Nothing is drawn yet (CO2a2); every row is
a read-back or a byte comparison with the cutout off.

    python3 tools/proof/co2a_proof.py [--only B0,D13p,…] [--app PATH]

The app fixture is a version-38 project over a copy of `media/A.mov` (640×360,
30 fps, 10 s): one clip at 0 for 6 s and one zoom action over [1 s, 3 s)
ending at scale 2, on a 1280×720 canvas.

**Probe row** (`co2a_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app):
- B0 the probe builds (a failed build is a scored FAIL, and so is D13p).
- D13p a two-media project (media 5 and 7, clips 11 and 12): `VideoProps.cutout`
  equals the JSON; `VideoPatch(cutout: .some(p))` writes all five keys and
  `.some(nil)` an `NSNull`; `recipe(at:)`'s layer `cutout` decodes mask media
  5 for clip 11 and 7 for clip 12, and the rest; `recipeJSON` names media 5.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`), one
launch on a scratch `CFFIXED_USER_HOME`:
- D8 each refusal in CO-20's sentence, `get_project` unchanged after each: a
  cutout on a text clip; an action end naming `video.cutout.subject`, then
  `.quality`; `off: ["video.cutout"]`; `edge: 2`.
- D10 the version-38 fixture as a package's `project.json`, opened: every key
  the fixture spells equal, `version` the header's, no `cutout` anywhere;
  `render_frame` at 3 times; `save_project` to a new package, `close_project`,
  `open_project`: `get_project` equal and the 3 PNGs byte-identical. "Before
  and after the bump" is the v38 file read through this build; no old build is
  driven.
- D13 `set_video {cutout: {}}` → the five defaults; `{background: "keep",
  edge: 0.25}` merges; `null` removes the key.
- D14 3 `render_frame`s of a clip with a cutout and of the same clip with none:
  byte-identical (a cut-out clip draws uncut until CO2a2, CO-23).
- Z1 the launch's `grep "Frame Job: "` prints nothing.

Prints `scores: P/N`; exits 0 iff every scored row passed.
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
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co2a"
HOME = WORK / "home"
HEADER = ROOT / "core/include/framejob_core.h"
MOVIE = ROOT / "tools/proof/media/A.mov"
CALL_BOUND = 300
SEC = 600_000
PROBE_ROWS = ["B0", "D13p"]
APP_ROWS = ["D8", "D10", "D13", "D14", "Z1"]
ROWS = PROBE_ROWS + APP_ROWS
RENDER_TIMES = [SEC // 2, 2 * SEC, 4 * SEC]
DEFAULTS = {"subject": "person", "quality": "standard", "background": "remove",
            "edge": 0.0, "feather": 0.0}
SUBJECT_SENTENCE = "video.cutout.subject is not an animation target"
QUALITY_SENTENCE = "video.cutout.quality is not an animation target"
OFF_SENTENCE = ("video.cutout cannot be keyed off at an action's end; "
                "set_video {cutout: null} removes it")
EDGE_SENTENCE = "video.cutout.edge must be between -1 and 1, not 2"

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, never a copy."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def movie():
    copy = WORK / "media" / "A.mov"
    if not copy.exists():
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOVIE, copy)
    return copy


def fixture():
    """The version-38 project: A.mov, one clip, one zoom action."""
    return {
        "version": 38,
        "canvas": {"width": 1280, "height": 720, "fps": [30, 1]},
        "media": [{"id": 1, "path": str(movie()), "kind": "video", "duration": 10 * SEC,
                   "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                   "has_audio": False}],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": 6 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "video": {},
                   "actions": [{"id": 4, "start": SEC, "duration": 2 * SEC,
                                "curve": "linear",
                                "end": {"video": {"scale": 2.0, "x": 120.0}}}]}],
        "next_id": 5,
    }


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the probe row -------------------------------------------------------------

def probe_rows():
    rows = [r for r in PROBE_ROWS if r in selected]
    if not rows:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co2a_probe.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = out / "co2a-probe"
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        detail = "the probe did not build: " + "; ".join(error.diagnostics[:6])
        for row in rows:
            check(row, False, detail)
        return
    check("B0", True, f"built {binary.name}")
    request = out / "request.json"
    request.write_text(json.dumps({"movie": str(movie())}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=300)
        answer = json.loads(run.stdout)["rows"]
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        for row in rows:
            if row != "B0":
                check(row, False, f"the probe gave no answer: {error}")
        return
    by_id = {r["id"]: r for r in answer}
    for row in rows:
        if row == "B0":
            continue
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def frames(self, tag):
        shots = []
        for t in RENDER_TIMES:
            out = WORK / f"{tag}-{t}.png"
            if out.exists():
                out.unlink()
            self.call("render_frame", t=t, path=str(out))
            shots.append(out.read_bytes() if out.exists() else None)
        return shots


def new_doc(client, name):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    doc.call("set_canvas", width=1280, height=720, fps=[30, 1])
    doc.call("save_project")
    return doc


def close(client, path):
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass


def error_of(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def contains(whole, part):
    """Every key `part` spells is in `whole` with an equal value; lists by index."""
    if isinstance(part, dict):
        return isinstance(whole, dict) and all(
            k in whole and contains(whole[k], v) for k, v in part.items())
    if isinstance(part, list):
        return isinstance(whole, list) and len(whole) == len(part) and all(
            contains(w, p) for w, p in zip(whole, part))
    if isinstance(part, (int, float)) and not isinstance(part, bool):
        return isinstance(whole, (int, float)) and not isinstance(whole, bool) and whole == part
    return whole == part


def media_clip(doc):
    """A.mov added and placed at 0 on the first track; the clip's id."""
    doc.call("add_media", descriptor={
        "path": str(movie()), "kind": "video", "duration": 10 * SEC, "width": 640,
        "height": 360, "fps": [30, 1], "has_video": True})
    project = doc.project()
    tracks = project["tracks"]
    if not tracks:
        doc.call("add_track")
        tracks = doc.project()["tracks"]
    doc.call("add_clip", track=tracks[0]["id"], media=project["media"][0]["id"], at=0)
    return doc.project()["clips"][0]["id"], tracks[0]["id"]


def video_of(doc, clip):
    return next(c for c in doc.project()["clips"] if c["id"] == clip).get("video") or {}


def d8(client):
    doc = new_doc(client, "d8")
    try:
        clip, track = media_clip(doc)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        doc.call("add_text_clip", track=track, at=11 * SEC)
        text = next(c["id"] for c in doc.project()["clips"] if c["id"] != clip)
        doc.call("add_action", clip=clip, at=SEC)
        action = next(c for c in doc.project()["clips"] if c["id"] == clip)["actions"][0]["id"]
        before = doc.project()
        cases = [
            ("a text clip", f"clip {text} is a text clip and cannot take a cutout",
             lambda: doc.call("set_video", clips=[text], patch={"cutout": {}})),
            ("an end's subject", SUBJECT_SENTENCE,
             lambda: doc.call("set_action_end", clip=clip, action=action,
                              patch={"video": {"cutout": {"subject": "person"}}})),
            ("an end's quality", QUALITY_SENTENCE,
             lambda: doc.call("set_action_end", clip=clip, action=action,
                              patch={"video": {"cutout": {"quality": "standard"}}})),
            ("off video.cutout", OFF_SENTENCE,
             lambda: doc.call("set_action_end", clip=clip, action=action, patch={},
                              off=["video.cutout"])),
            ("edge 2", EDGE_SENTENCE,
             lambda: doc.call("set_video", clips=[clip], patch={"cutout": {"edge": 2}})),
        ]
        for what, sentence, body in cases:
            message = error_of(body) or ""
            check("D8", sentence in message, f"{what}: {message[:200] or 'no error'}")
            check("D8", doc.project() == before, f"{what}: get_project unchanged")
    finally:
        close(client, doc.path)


def d10(client):
    made = new_doc(client, "v38")
    close(client, made.path)
    old = fixture()
    (made.path / "project.json").write_text(json.dumps(old, indent=2))
    client.call("open_project", path=str(made.path))
    doc = Doc(client, made.path)
    saved = WORK / "v39.framejob"
    try:
        first = doc.project()
        expected = dict(old, version=format_version())
        check("D10", first.get("version") == format_version() and contains(first, expected)
              and '"cutout"' not in json.dumps(first),
              f"the v38 file opened as version {first.get('version')}, the fixture's every "
              "key equal, no cutout key")
        shots = doc.frames("v38")
        check("D10", all(s for s in shots), f"{sum(1 for s in shots if s)} frames rendered")
        if saved.exists():
            shutil.rmtree(saved)
        doc.call("save_project", path=str(saved))
        close(client, saved)
        close(client, made.path)
        client.call("open_project", path=str(saved))
        again = Doc(client, saved)
        second = again.project()
        check("D10", second == first, "saved, closed and reopened: get_project equal")
        reshots = again.frames("v39")
        same = [a is not None and a == b for a, b in zip(shots, reshots)]
        check("D10", all(same), f"the 3 PNGs byte-identical: {same}")
    finally:
        close(client, saved)
        close(client, made.path)


def d13_d14(client):
    doc = new_doc(client, "d13")
    try:
        clip, _ = media_clip(doc)
        uncut = doc.frames("uncut") if "D14" in selected else []
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        stored = video_of(doc, clip).get("cutout")
        check("D13", stored == DEFAULTS, f"{{cutout: {{}}}} stored {stored}")
        doc.call("set_video", clips=[clip], patch={"cutout": {"background": "keep", "edge": 0.25}})
        merged = video_of(doc, clip).get("cutout")
        want = dict(DEFAULTS, background="keep", edge=0.25)
        check("D13", merged == want, f"a patch merged to {merged}")
        if "D14" in selected:
            cut = doc.frames("cut")
            same = [a is not None and a == b for a, b in zip(uncut, cut)]
            check("D14", len(uncut) == 3 and all(same),
                  f"3 frames with the cutout equal the uncut ones: {same}")
        doc.call("set_video", clips=[clip], patch={"cutout": None})
        removed = video_of(doc, clip)
        check("D13", "cutout" not in removed, f"null removed it: {sorted(removed)}")
    finally:
        close(client, doc.path)


def app_rows(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected & set(APP_ROWS):
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        for names, body in [({"D8"}, d8), ({"D10"}, d10), ({"D13", "D14"}, d13_d14)]:
            if not names & selected:
                continue
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                for name in names & selected:
                    check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(APP_ROWS):
            selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    print(f"CO2a1 — the cutout in the model and the recipe ({proof_app.config()} build)",
          flush=True)
    probe_rows()
    if selected & set(APP_ROWS):
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
