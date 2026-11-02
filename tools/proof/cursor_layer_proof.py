#!/usr/bin/env python3
"""Road map "creator-jobs" CU3a1 — `media.cursor`, `video.cursor` and the
recipe's `cursor` key (spec §11 CU-30, CU-32, CU-35, CU-39). Nothing is drawn
yet (CU3a2); every row is a read-back.

    python3 tools/proof/cursor_layer_proof.py [--only B0,L1d,…] [--app PATH]

The fixture is a version-37 project over a copy of `media/A.mov` (640×360,
30 fps, 10 s): one clip at 0 for 6 s and one zoom action over [1 s, 3 s)
ending at scale 2, on a 1280×720 canvas.

**Probe rows** (`cursor_layer_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app):
- B0 the probe builds (a failed build is a scored FAIL, and so is every
  probe row after it).
- L1d `ReelProject.from(json:)` of the fixture with `media.cursor` and
  `video.cursor`: `MediaSnapshot.cursor` and `VideoProps.cursor` equal the
  JSON; `MediaDescriptor(media).dictionary["cursor"]` (and its probe's) is the
  JSON object; `VideoPatch(cursor: .some(p))` writes all eight keys, and
  `.some(nil)` an `NSNull`.
- L3r the fixture at five times: every layer's `cursor` null; with
  `media[0].cursor = {path, in_picture: true}` the `recipeJSON` text
  byte-identical at each time; the control, `in_picture: false`, not null.
- L9 base `cursor {smoothing: 0}`, an action over [1 s, 3 s) ending
  `{video: {cursor: {smoothing: 1, hide_idle: 5, scale: 3}}}`, at 0.5, 1.5,
  2.5 and 3.5 s: the key's and `props`' `smoothing` 0 and `hide_idle` null;
  `props.scale` 1, strictly between 1 and 3 twice, then 3; `recipe(at:)`'s
  `layers[0].cursor` decodes the same.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`), one
launch on a scratch `CFFIXED_USER_HOME`:
- Z1 the launch's `grep "Frame Job: "` prints nothing.
- L1 `add_media` with `cursor {path: <work>/A.fjcursor, in_picture: false}` →
  `get_project`'s `media[0].cursor` as given; an unknown cursor key →
  "Unknown cursor key"; `add_clip`, then `set_video {cursor: {scale: 2,
  clicks: "ripple", hide_idle: 3, click_color: "red"}}` → `video.cursor` with
  all eight keys, `click_color` "red"; `click_color: "#ffg"` and `scale: 9` →
  errors carrying CU-30's sentences, `get_project` unchanged.
- L3 the fixture as a package's `project.json`, opened: `project` is the
  fixture with the header's `version` (every key the fixture spells, equal,
  and no `cursor` anywhere); `render_frame` at 3 times; `save_project` to a
  new package, `close_project`, `open_project`: `get_project` equal and the 3
  PNGs byte-identical. "Before and after the bump" is the v37 file read
  through this build; no old build is driven.

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

WORK = ROOT / "tools/proof/work/cursor-layer"
HOME = WORK / "home"
HEADER = ROOT / "core/include/framejob_core.h"
MOVIE = ROOT / "tools/proof/media/A.mov"
CALL_BOUND = 300
SEC = 600_000
PROBE_ROWS = ["B0", "L1d", "L3r", "L9"]
APP_ROWS = ["L1", "L3", "Z1"]
ROWS = PROBE_ROWS + APP_ROWS
RENDER_TIMES = [SEC // 2, 2 * SEC, 4 * SEC]
SCALE_SENTENCE = "video.cursor.scale must be between 0.25 and 8, not 9"
COLOR_SENTENCE = 'video.cursor.click_color must be a CSS colour (spec §11 G-12), not "#ffg"'

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
    """The version-37 project: A.mov, one clip, one zoom action."""
    return {
        "version": 37,
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


# ---- the probe rows ------------------------------------------------------------

def probe_rows():
    rows = [r for r in PROBE_ROWS if r in selected]
    if not rows:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "cursor_layer_probe.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = out / "cursor-layer-probe"
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
    request.write_text(json.dumps({"fixture": json.dumps(fixture())}))
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


def l1(client):
    doc = new_doc(client, "l1")
    try:
        cursor_file = str(WORK / "A.fjcursor")
        descriptor = {"path": str(movie()), "kind": "video", "duration": 10 * SEC,
                      "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                      "cursor": {"path": cursor_file, "in_picture": False}}
        doc.call("add_media", descriptor=descriptor)
        project = doc.project()
        media = project["media"][0]
        check("L1", media.get("cursor") == {"path": cursor_file, "in_picture": False},
              f"add_media stored media.cursor {media.get('cursor')}")
        stranger = dict(descriptor, path=str(WORK / "other.mov"),
                        cursor={"path": cursor_file, "in_picture": False, "bogus": 1})
        message = error_of(lambda: doc.call("add_media", descriptor=stranger)) or ""
        check("L1", 'Unknown cursor key "bogus"' in message,
              f"an unknown cursor key: {message[:160] or 'no error'}")
        track = doc.project()["tracks"]
        if not track:
            doc.call("add_track")
            track = doc.project()["tracks"]
        doc.call("add_clip", track=track[0]["id"], media=media["id"], at=0)
        clip = doc.project()["clips"][0]["id"]
        doc.call("set_video", clips=[clip], patch={"cursor": {
            "scale": 2, "clicks": "ripple", "hide_idle": 3, "click_color": "red"}})
        before = doc.project()
        stored = before["clips"][0]["video"].get("cursor") or {}
        want = {"show": True, "scale": 2.0, "style": "recorded", "smoothing": 0.0,
                "hide_idle": 3.0, "clicks": "ripple", "click_color": "red", "click_size": 1.0}
        check("L1", stored == want, f"set_video stored video.cursor {stored}")
        for patch, sentence in [({"click_color": "#ffg"}, COLOR_SENTENCE),
                                ({"scale": 9}, SCALE_SENTENCE)]:
            message = error_of(lambda: doc.call("set_video", clips=[clip],
                                                patch={"cursor": patch})) or ""
            check("L1", sentence in message, f"{patch}: {message[:200] or 'no error'}")
        check("L1", doc.project() == before, "get_project unchanged by the two refusals")
    finally:
        close(client, doc.path)


def l3(client):
    made = new_doc(client, "v37")
    close(client, made.path)
    old = fixture()
    (made.path / "project.json").write_text(json.dumps(old, indent=2))
    client.call("open_project", path=str(made.path))
    doc = Doc(client, made.path)
    saved = WORK / "v38.framejob"
    try:
        first = doc.project()
        expected = dict(old, version=format_version())
        check("L3", first.get("version") == format_version() and contains(first, expected)
              and '"cursor"' not in json.dumps(first),
              f"the v37 file opened as version {first.get('version')}, the fixture's every "
              "key equal, no cursor key")
        shots = doc.frames("v37")
        check("L3", all(s for s in shots), f"{sum(1 for s in shots if s)} frames rendered")
        if saved.exists():
            shutil.rmtree(saved)
        doc.call("save_project", path=str(saved))
        close(client, saved)
        close(client, made.path)
        client.call("open_project", path=str(saved))
        again = Doc(client, saved)
        second = again.project()
        check("L3", second == first, "saved, closed and reopened: get_project equal")
        reshots = again.frames("v38")
        same = [a is not None and a == b for a, b in zip(shots, reshots)]
        check("L3", all(same), f"the 3 PNGs byte-identical: {same}")
    finally:
        close(client, saved)
        close(client, made.path)


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
        for name, body in [("L1", l1), ("L3", l3)]:
            if name not in selected:
                continue
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
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
        if selected & {"L1", "L3"}:
            selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    print(f"CU3a1 — the cursor in the model and the recipe ({proof_app.config()} build)",
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
