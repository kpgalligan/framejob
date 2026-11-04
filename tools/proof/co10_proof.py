#!/usr/bin/env python3
"""Road map "creator-jobs" CO10a and CO10b — a picture's cutout (spec §11
CO-100…CO-109): `foreground` on an image clip only and the recipe's image arm
(CO10a), then a picture's masks made, waited for, drawn and analysed, and
pictures in Behind Subject (CO10b).

    python3 tools/proof/co10_proof.py [--only S1,S2,…] [--mutant NAME] [--app PATH]

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) in two
launches on one scratch `CFFIXED_USER_HOME`. The media are a copy of
`media/A.mov` (640×360, 30 fps, 10 s), a 64×48 RGB PNG this script writes with
`zlib` and `struct`, and a copy of `cutout_spike.FLEX` (a person photo) as
`person.jpg`.

Launch H (`-RCDevAnalysisHold 3600`: no mask is ever made), on 640×360 canvases:
- S2 `set_video {cutout: {subject: "foreground"}}` on a media clip and on a
  `freeze_frame` still each answers its exact sentence ("clip N is a media
  clip and cannot take a foreground cutout: only an image clip can", "… a
  still clip …"), `get_project` unchanged after each.
- S3 on an image clip, `{subject: "foreground"}` reads back all five keys,
  `{edge: 0.25}` merges, and `null` removes the key.
- S4 one `render_frame` with the image clip's `foreground` cutout on answers
  in 25–45 s with "Clip N is drawn uncut: its foreground masks were not ready
  within 30 s.", its PNG byte-equal to the one with the cutout off (CO-106).
- S5 a cut media clip at 0 and a cut image clip at 1 s:
  `analyze_cutout {clips: [image], wait: 0}` answers one row `analyzing`,
  frames 1, covered 0; `analyze_cutout {wait: 0}` answers the media row then
  the image row (CO-103 lifted, CO-108).
- S6 `text_behind_subject {clip: image, at}` answers `cutout_added: true`,
  and the image clip's cutout reads `background: keep` (CO-108).

Launch U (no hold), S1 on a canvas of `person.jpg`'s own size with background
`[0, 1, 0, 1]` and the picture at 0; a missing `cutout_spike.FLEX` is a scored
failure naming the path. Uncut, `render_frame` at 1 s has under 1 % green
pixels (r ≤ 2, g ≥ 253, b ≤ 2).
- S1a `{cutout: {}}`: `analyze_cutout {wait: 60}` answers `ready`, frames 1,
  covered 1, `subject_found` true; the render at 1 s is ≥ 20 % green, and
  ≥ 1 % of its pixels are not green and within ±2 of the uncut render.
- S1b `{subject: "foreground"}`: the same claims; `cache/analysis/foreground/
  <media>.json` holds a stamp whose `vision.request` is
  `foreground_instance_mask`, and its pack's `FJMP` footer width × height is
  the media's.
- Z1 both launches' `grep "Frame Job: "` print nothing.

`--mutant NAME` (CO-109): CO10b's decision broken in a `tree_copy.py` copy, the
copy built as the proof's configuration, and only its rows run (and Z1);
CAUGHT (exit 1) when one of them fails, SURVIVED exits 0, a control that could
not be performed exits 2. The tree's own file is hashed (SHA-256) before and
after and must not change.

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "cutout_spike"))
import bounded  # noqa: E402
import cutout_spike  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co10"
HOME = WORK / "home"
MOVIE = ROOT / "tools/proof/media/A.mov"
FFMPEG = cutout_spike.FFMPEG
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
ROWS = ["S1", "S2", "S3", "S4", "S5", "S6", "Z1"]
HELD_ROWS = ["S2", "S3", "S4", "S5", "S6"]
UNHELD_ROWS = ["S1"]
HELD = ["-RCDevAnalysisHold", "3600"]
PNG_W, PNG_H = 64, 48
S4_BOUND = 90
S4_LOW, S4_HIGH = 25, 45
GREEN_UNCUT = 0.01
GREEN_CUT = 0.20
KEPT_CUT = 0.01
DEFAULTS = {"subject": "person", "quality": "standard", "background": "remove",
            "edge": 0.0, "feather": 0.0}

FG_ANCHOR = "app/Sources/AnalysisMasks+Image.swift"
MUTANTS = {
    "foreground-in-masks": (["S1"], [(
        FG_ANCHOR, "            kind: request.kind, cacheDir: request.cacheDir,",
        "            kind: .masks, cacheDir: request.cacheDir,")]),
    "image-draw-off": (["S1"], [(
        "app/Sources/Compositor+Cutout.swift",
        "            return imageCutoutMask(for: layer, instruction: instruction, uniforms: &uniforms)\n",
        "            return placeholder\n")]),
    "frame-wait-no-images": (["S4"], [(
        "app/Sources/CutoutWants.swift",
        "                cutout.mask.kind == .image, case .image(let media) = layer.source,\n",
        "                cutout.mask.kind == .media, case .image(let media) = layer.source,\n")]),
    "noun-person": (["S4"], [(
        "app/Sources/Exporter+Masks.swift",
        "foreground.contains($0) ? \"foreground\" : \"person\"",
        "false ? \"foreground\" : \"person\"")]),
    "analyze-image-refused": (["S5"], [(
        "app/Sources/AgentServer+Cutout.swift",
        "                clips = named\n",
        "                if named.contains(where: {\n"
        "                    if case .image? = snapshot.clip($0)?.source { return true }\n"
        "                    return false\n"
        "                }) {\n"
        "                    throw ToolError(message: \"Clip is an image clip.\")\n"
        "                }\n"
        "                clips = named\n")]),
    "picture-not-cuttable": (["S6"], [(
        "app/Sources/CutoutStatus.swift",
        "            return snapshot.media(for: clip)?.kind == .image\n",
        "            return false\n")]),
    "subject-ignored": (["S1"], [(
        FG_ANCHOR,
        "request.kind == .foreground ? try foregroundMask(image) : try personMask(image)",
        "try personMask(image)")]),
}


def foreground_sentence(clip, what):
    return (f"clip {clip} is {what} and cannot take a foreground cutout: "
            "only an image clip can")


def uncut_sentence(clip):
    return f"Clip {clip} is drawn uncut: its foreground masks were not ready within 30 s."


results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the media ----------------------------------------------------------------------

def movie():
    copy = WORK / "media" / "A.mov"
    if not copy.exists():
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOVIE, copy)
    return copy


def picture():
    """A 64×48 8-bit RGB PNG: a red-to-blue ramp across, green down."""
    path = WORK / "media" / "picture.png"
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = b"".join(
        b"\x00" + bytes(v for x in range(PNG_W)
                        for v in (x * 255 // (PNG_W - 1), y * 255 // (PNG_H - 1),
                                  255 - x * 255 // (PNG_W - 1)))
        for y in range(PNG_H))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", PNG_W, PNG_H, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    return path


def person():
    """A copy of `cutout_spike.FLEX` as `person.jpg`; None when the photo is missing."""
    if not cutout_spike.FLEX.exists():
        return None
    copy = WORK / "media" / "person.jpg"
    if not copy.exists():
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(cutout_spike.FLEX, copy)
    return copy


def image_size(path):
    run = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
                         capture_output=True, text=True, timeout=60)
    values = {}
    for line in run.stdout.splitlines():
        parts = line.split(":")
        if len(parts) == 2 and parts[0].strip() in ("pixelWidth", "pixelHeight"):
            values[parts[0].strip()] = int(parts[1])
    return values.get("pixelWidth"), values.get("pixelHeight")


def decode_png(path):
    """`path` as raw RGBA bytes (ffmpeg); None when it does not decode."""
    run = subprocess.run([FFMPEG, "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt",
                          "rgba", "-"], capture_output=True, timeout=120,
                         env=bounded.child_env())
    return run.stdout if run.returncode == 0 and run.stdout else None


def green(frame, i):
    return frame[i] <= 2 and frame[i + 1] >= 253 and frame[i + 2] <= 2


def shares(frame, off):
    """(the green share, the share not green and within ±2 of `off` in R, G and B)."""
    pixels = len(frame) // 4
    greens = kept = 0
    for i in range(0, pixels * 4, 4):
        if green(frame, i):
            greens += 1
        elif all(abs(frame[i + c] - off[i + c]) <= 2 for c in range(3)):
            kept += 1
    return greens / pixels, kept / pixels


def read_footer(path):
    """A `masks.pack`'s `FJMP` footer width and height; None when it is not a pack."""
    try:
        data = Path(path).read_bytes()
    except OSError:
        return None
    foot = len(data) - 40
    if foot < 0 or data[foot:foot + 4] != b"FJMP":
        return None
    _, width, height = struct.unpack_from("<III", data, foot + 4)
    return width, height


# ---- documents ----------------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def cutout(self, clip):
        return (self.clip(clip).get("video") or {}).get("cutout")

    def render(self, t, tag):
        out = WORK / f"{self.path.stem}-{tag}-{t}.png"
        if out.exists():
            out.unlink()
        text = self.call("render_frame", t=t, path=str(out))
        return (out.read_bytes() if out.exists() else None), out, str(text)


def new_doc(client, name, width=640, height=360, background=None):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    canvas = {"width": width, "height": height, "fps": [30, 1]}
    if background is not None:
        canvas["background"] = background
    doc.call("set_canvas", **canvas)
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


def track(doc):
    tracks = doc.project()["tracks"]
    if not tracks:
        doc.call("add_track")
        tracks = doc.project()["tracks"]
    return tracks[0]["id"]


def add_movie(doc, at=0, on=None):
    """A.mov added and placed at `at` on track `on` (the first); the clip's id."""
    before = {c["id"] for c in doc.project()["clips"]}
    doc.call("add_media", descriptor={
        "path": str(movie()), "kind": "video", "duration": 10 * SEC, "width": 640,
        "height": 360, "fps": [30, 1], "has_video": True})
    media = next(m["id"] for m in doc.project()["media"] if m["kind"] == "video")
    doc.call("add_clip", track=on or track(doc), media=media, at=at)
    return next(c["id"] for c in doc.project()["clips"] if c["id"] not in before)


def add_picture(doc, at=0, on=None, path=None, width=PNG_W, height=PNG_H):
    """A picture added and placed at `at` on track `on` (the first); (clip, media)."""
    before = {c["id"] for c in doc.project()["clips"]}
    doc.call("add_media", descriptor={
        "path": str(path or picture()), "kind": "image", "width": width, "height": height})
    media = next(m["id"] for m in doc.project()["media"] if m["kind"] == "image")
    doc.call("add_clip", track=on or track(doc), media=media, at=at)
    return next(c["id"] for c in doc.project()["clips"] if c["id"] not in before), media


# ---- launch H -----------------------------------------------------------------------

def s2(client):
    doc = new_doc(client, "s2")
    try:
        clip = add_movie(doc)
        doc.call("freeze_frame", clip=clip, at=2 * SEC, duration=SEC)
        still = next(c["id"] for c in doc.project()["clips"]
                     if c["source"]["kind"] == "still")
        for what, target in [("a media clip", clip), ("a still clip", still)]:
            before = doc.project()
            sentence = foreground_sentence(target, what)
            message = error_of(lambda: doc.call(
                "set_video", clips=[target], patch={"cutout": {"subject": "foreground"}}))
            check("S2", message == f"set_video: {sentence}",
                  f"{what}: {message or 'no error'}")
            check("S2", doc.project() == before, f"{what}: get_project unchanged")
    finally:
        close(client, doc.path)


def s3(client):
    doc = new_doc(client, "s3")
    try:
        clip, _ = add_picture(doc)
        doc.call("set_video", clips=[clip], patch={"cutout": {"subject": "foreground"}})
        stored = doc.cutout(clip)
        want = dict(DEFAULTS, subject="foreground")
        check("S3", stored == want, f"{{subject: foreground}} stored {stored}")
        doc.call("set_video", clips=[clip], patch={"cutout": {"edge": 0.25}})
        merged = doc.cutout(clip)
        check("S3", merged == dict(want, edge=0.25), f"{{edge: 0.25}} merged to {merged}")
        doc.call("set_video", clips=[clip], patch={"cutout": None})
        video = doc.clip(clip).get("video") or {}
        check("S3", "cutout" not in video, f"null removed it: {sorted(video)}")
    finally:
        close(client, doc.path)


def s4(client):
    doc = new_doc(client, "s4")
    try:
        clip, _ = add_picture(doc)
        doc.call("set_video", clips=[clip], patch={"scale": 4.0})
        off, _, _ = doc.render(SEC, "off")
        doc.call("set_video", clips=[clip], patch={"cutout": {"subject": "foreground"}})
        client.timeout = S4_BOUND
        start = time.monotonic()
        try:
            cut, _, text = doc.render(SEC, "held")
        except Exception as error:  # noqa: BLE001 — a timeout is the row's failure
            check("S4", False, f"render_frame did not return within {S4_BOUND} s: {error}")
            return
        finally:
            client.timeout = CALL_BOUND
        took = time.monotonic() - start
        sentence = uncut_sentence(clip)
        check("S4", S4_LOW <= took <= S4_HIGH and cut is not None and cut == off
              and sentence in text,
              f"render_frame took {took:.1f} s ({S4_LOW}–{S4_HIGH}); byte-identical to cutout "
              f"off {cut is not None and cut == off}; the sentence "
              f"{'present' if sentence in text else 'absent: ' + text[-200:]}")
    finally:
        close(client, doc.path)


def s5(client):
    doc = new_doc(client, "s5")
    try:
        first = track(doc)
        doc.call("add_track")
        second = next(t["id"] for t in doc.project()["tracks"] if t["id"] != first)
        media = add_movie(doc, on=first)
        image, _ = add_picture(doc, at=SEC, on=second)
        doc.call("set_video", clips=[media, image], patch={"cutout": {}})
        answer = doc.call("analyze_cutout", clips=[image], wait=0)
        rows = answer.get("clips", []) if isinstance(answer, dict) else []
        row = rows[0] if len(rows) == 1 else {}
        check("S5", len(rows) == 1 and row.get("clip") == image
              and row.get("state") == "analyzing" and row.get("frames") == 1
              and row.get("covered") == 0,
              f"a named image clip: {rows if rows else answer}")
        answer = doc.call("analyze_cutout", wait=0)
        order = [r.get("clip") for r in answer.get("clips", [])]
        check("S5", order == [media, image],
              f"clips left out: rows for {order}, the media clip {media} then the image {image}")
    finally:
        close(client, doc.path)


def s6(client):
    doc = new_doc(client, "s6")
    try:
        image, _ = add_picture(doc)
        answer = doc.call("text_behind_subject", clip=image, at=SEC // 2)
        added = answer.get("cutout_added") if isinstance(answer, dict) else None
        cutout = doc.cutout(image) or {}
        check("S6", added is True and cutout.get("background") == "keep"
              and cutout.get("subject") == "person",
              f"cutout_added {added}; the image's cutout {cutout}")
    finally:
        close(client, doc.path)


# ---- launch U -----------------------------------------------------------------------

def s1(client):
    photo = person()
    if photo is None:
        check("S1", False, f"the person photo is missing: {cutout_spike.FLEX}")
        return
    width, height = image_size(photo)
    if not width or not height:
        check("S1", False, f"{photo}'s size could not be read")
        return
    doc = new_doc(client, "s1", width=width, height=height, background=[0, 1, 0, 1])
    try:
        clip, media = add_picture(doc, path=photo, width=width, height=height)
        off_bytes, off_path, _ = doc.render(SEC, "off")
        off = decode_png(off_path) if off_bytes else None
        if off is None or len(off) != width * height * 4:
            check("S1", False, f"the uncut render did not decode to {width} × {height}")
            return
        uncut_green, _ = shares(off, off)
        check("S1", uncut_green < GREEN_UNCUT,
              f"uncut: {uncut_green:.4f} green (< {GREEN_UNCUT})")
        for tag, patch in [("S1a", {}), ("S1b", {"subject": "foreground"})]:
            doc.call("set_video", clips=[clip], patch={"cutout": patch})
            answer = doc.call("analyze_cutout", clips=[clip], wait=60)
            rows = answer.get("clips", []) if isinstance(answer, dict) else []
            row = rows[0] if rows else {}
            check("S1", row.get("state") == "ready" and row.get("frames") == 1
                  and row.get("covered") == 1 and row.get("subject_found") is True,
                  f"{tag} analyze_cutout: state {row.get('state')}, frames "
                  f"{row.get('frames')}, covered {row.get('covered')}, subject_found "
                  f"{row.get('subject_found')}{', error ' + row['error'] if 'error' in row else ''}")
            cut_bytes, cut_path, _ = doc.render(SEC, tag)
            cut = decode_png(cut_path) if cut_bytes else None
            if cut is None or len(cut) != len(off):
                check("S1", False, f"{tag}: the cut render did not decode")
                continue
            cut_green, kept = shares(cut, off)
            check("S1", cut_green >= GREEN_CUT and kept >= KEPT_CUT,
                  f"{tag}: {cut_green:.4f} green (≥ {GREEN_CUT}), {kept:.4f} kept within ±2 "
                  f"of uncut (≥ {KEPT_CUT})")
            kind = "foreground" if tag == "S1b" else "masks"
            footer = read_footer(doc.path / f"cache/analysis/{kind}/{media}/masks.pack")
            if tag == "S1a":
                print(f"       S1a's masks pack is {footer} (the media {width} × {height})")
                continue
            try:
                marker = json.loads(
                    (doc.path / f"cache/analysis/foreground/{media}.json").read_text())
            except (OSError, ValueError):
                marker = {}
            request = ((marker.get("stamp") or {}).get("vision") or {}).get("request")
            check("S1", request == "foreground_instance_mask",
                  f"S1b: the foreground marker's vision.request {request}")
            check("S1", footer == (width, height),
                  f"S1b: the foreground pack's FJMP footer {footer}, the media {width} × {height}")
    finally:
        close(client, doc.path)


HELD_BODIES = [("S2", s2), ("S3", s3), ("S4", s4), ("S5", s5), ("S6", s6)]
UNHELD_BODIES = [("S1", s1)]


def launch_rows(binary, arguments, log, bodies):
    """`bodies` in one launch of `binary`; their Z1 line from its log."""
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for name, _ in bodies:
                check(name, False, "the app did not listen")
            return False
        print(f"  instance PID {launched.child.pid} ({log.name})", flush=True)
        for name, body in bodies:
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace")
                     if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return True


def app_rows(binary):
    held = [(n, b) for n, b in HELD_BODIES if n in selected]
    unheld = [(n, b) for n, b in UNHELD_BODIES if n in selected]
    listened = True
    if held:
        listened &= launch_rows(binary, HELD, WORK / "held.log", held)
    if unheld:
        listened &= launch_rows(binary, [], WORK / "unheld.log", unheld)
    return listened


# ---- mutants ------------------------------------------------------------------------

def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def run_mutant(name):
    global selected
    named, edits = MUTANTS[name]
    print(f"CO10b — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
    before = {path: digest(path) for path, _, _ in edits}
    selected = set(named) | {"Z1"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    if not why:
        for path, anchor, replacement in edits:
            target = Path(made) / path
            text = target.read_text()
            if text.count(anchor) != 1:
                why = f"the anchor occurs {text.count(anchor)} times in {path}"
                break
            target.write_text(text.replace(anchor, replacement))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, why = tree_copy.build_app(Path(made), BUILD_BOUND)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    listened = app_rows(proof_app.executable(app))
    after = {path: digest(path) for path, _, _ in edits}
    print(f"  the tree's files unchanged by SHA-256: {before == after}")
    if not listened or not all(row in results for row in named):
        print(f"mutant {name}: the control could not be performed — {named} never scored")
        return 2
    caught = any(not all(ok for ok, _ in results[row]) for row in named)
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    if args.mutant:
        return run_mutant(args.mutant)
    print(f"CO10 — a picture's cutout ({proof_app.config()} build)", flush=True)
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
