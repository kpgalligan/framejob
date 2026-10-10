#!/usr/bin/env python3
"""Road map "grading", phase GR6a (spec §11 GR-8) — `.cube` LUTs end to end
over MCP: a LUT imported as media of kind `lut` (`import_media`, the core's
parser through `rc_cube_parse`), applied as `video.look {kind: "lut", media,
amount}` and drawn at step 4d from an `rgba16Float` `size³` texture, read back
as `render_frame` bytes; then the probe's rows over `app/Sources`.

    python3 tools/proof/lut_proof.py [--app PATH] [--only I1,S1,...] [--lut PATH]
    python3 tools/proof/lut_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/lut/home`, and
every package, fixture, `.cube` file and PNG is under `tools/proof/work/lut/`,
removed at the start and at exit. It performs no menu item. Every call is
bounded (`CALL_BOUND`), every ffmpeg too (120 s). Every project is closed
(`close_project`, discard).

Fixtures, written by this script — **every LUT is written here** (the Concat
rule): CHART, `look_proof.py`'s 640×360 grey ramp over six saturated
patches; `identity-N` (N = 2, 33, 65), out = in; `swap-N`, out = (g, b, r);
`invert`, out = 1 − in; `smooth-N` (17, 33, 65), out = (0.9·r^0.8 + 0.1·b,
0.15 + 0.7·g^1.2 + 0.1·r, 0.85·b + 0.1·(1 − g)); the refusal files of R1 and
the variants of R2. Values are written with six decimals, which hold every
lattice point of 2, 33 and 65 exactly. Frames are taken at t = 0.5 s unless a
row says otherwise and compared at `look_proof`'s SAMPLES (every 20th column
of six rows), ±0 unless a row says otherwise.

Project H (CHART on its first track, 30 fps 640×360, background black):
- **T0** (RECORD, unscored; its own projects): one 10-bit ProRes 422 chart
  (`prores_ks`) re-tagged without re-encoding (`-c copy -bsf:v
  prores_metadata=…`) as BT.709, BT.2020 primaries with the BT.709 transfer,
  HLG (`arib-std-b67`), PQ (`smpte2084`) and untagged, each in the ProRes
  headers alone and again with the container's `colr` atom; `render_frame`
  of each against the BT.709 movie tagged the same way, max |Δ| per tag.
- **I1**: `import_media` of `swap-33.cube` answers kind `lut`, duration 0,
  no video, audio or alpha, and a note naming `set_video {clips, patch:
  {look: {kind: "lut", media: N}}}` with its own id; `add_media {descriptor:
  {path, kind: "lut"}}` with no other key lands a `lut` row with no video.
- **R1**: each refusal file's `import_media` error ends with `“NAME.cube” is
  not a LUT Reelcut reads: <the core's sentence>.`, and the media count is
  unchanged.
- **R2**: the accepted variants (a BOM, CRLF, TITLE, comments, blank lines,
  the default DOMAIN_MIN/DOMAIN_MAX/LUT_3D_INPUT_RANGE; tabs) import as `lut`.
- **N1**: the chart under `identity-N` at amount 1, N = 2, 33, 65, is the
  neutral chart's bytes.
- **S1**: under `swap-N`, N = 2, 33, 65, every sample is the neutral
  sample's (g, b, r), exactly.
- **A1**: `swap-33` at amount 0.5 is within ±1 of the midpoint of the
  neutral sample and its (g, b, r).
- **F1**: `smooth-N`, N = 17, 33, 65 (and `--lut PATH`, an owner's file, for
  GR7's T4), within ±2 at every sample of `ffmpeg -vf
  lut3d=file=…:interp=trilinear` on the same chart PNG.
- **K1**: `{look: {kind: warm}}` on a LUT clip stores `{kind: warm, amount}`
  with no `media`; and each look rule's sentence: `media` missing with `lut`,
  `media` with a built-in kind, a media id the project lacks, a video media.
- **O1**: `add_clip` of the LUT is refused by `media N is a LUT: apply it as
  a look (…), it is not placed as a clip`.
- **X1**: copies of `swap-33` (A) and `invert` (B) imported one after the
  other, so at adjacent ids; base look A and a
  1 s action from 0 whose end is `{look: {media: B}}`: the frame at 0.75 s is
  A's static frame and at 1.5 s B's.
- **U1**: `render_frame {ungraded: true}` under A is the neutral chart.
- **J1**: no look on the clip, an adjustment clip on a new front track with
  A: within ±1 of A's static frame at every sample.
- **M1**: the clip under `m1.cube` (A's table): the file deleted draws the
  neutral bytes; the same bytes written to a new path and `relink_media` to
  it draw A's frame again. (Deleted rather than renamed: a rename is followed
  by the media's bookmark, so the file would never go missing.)
- **C1**: saved, `consolidate_media` points the LUT's row inside the package
  and the frame is A's frame.
- **D1**: `remove_media` of the LUT is refused naming the clip; `with_clips`
  keeps the clip, removes the row and the look (the neutral bytes); `undo`
  answers "Remove Media" and restores the look and the frame.
- **P1**: a `paste` payload of the clip (base look A, an end naming B, rows
  CHART, A and B) into project H2, which already holds B at another id, adds
  A by path, matches B by path, and remaps the base look to H2's A and the
  end to H2's B.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds
  no `Reelcut: ` line.
- **P2, T1, T2, P3**: `lut_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of all four): P2
  `EditorViewController.payloadMediaIDs`; T1 a size-2 asymmetric file through
  `LutTextures` read back red fastest, clamped, alpha 1; T2 a missing and a
  refused file answer nil; P3 `RecipeSource.lookURLs(for:)` answers the map
  published under an instruction's key after it was built with none, and the
  instruction's own for a key that never published.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row but T0 on it, the probe
built over the copy's `app/Sources`. A core mutant also runs `cargo test
--release --no-fail-fast --test cube --test lut` in the copy's own `core/`
(row CT). MUTANT PASS when every named row FAILED and no other scored row
did:
  blue-fastest            the upload reads the table blue fastest: N1 S1 A1 F1 T1
  domain-ignored          a non-default domain is read: R1 CT
  size-cap-dropped        LUT_3D_SIZE outside 2–65 is read: R1 CT
  media-interpolates      an end's `media` interpolates like a number: X1 CT
  builtin-keeps-media     a built-in kind keeps a stored `media`: K1 CT
  remove-deletes-clips    `with_clips` deletes a LUT's clips: D1 CT
  paste-not-remapped      `paste` leaves a look's id as the payload's: P1 CT
  urls-from-instruction   a look reads only its instruction's URLs: P3
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402
from look_proof import SAMPLES, write_chart  # noqa: E402
from tone_proof import Frame, decode, same_pixels  # noqa: E402

WORK = ROOT / "tools/proof/work/lut"
HOME = WORK / "home"
LUTS = WORK / "luts"
PROBE = ROOT / "tools/proof/lut_probe.swift"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
W, H = 640, 360
ROWS = ["T0", "I1", "R1", "R2", "N1", "S1", "A1", "F1", "K1", "O1", "X1", "U1", "J1",
        "M1", "C1", "D1", "P1", "P2", "T1", "T2", "P3", "Z1"]
RECORDS = {"T0"}
H_ROWS = {"I1", "R1", "R2", "N1", "S1", "A1", "F1", "K1", "O1", "X1", "U1", "J1", "M1",
          "C1", "D1", "P1"}
PROBE_ROWS = {"P2", "T1", "T2", "P3"}
# T0's tags: (name, primaries, transfer, matrix) for prores_metadata.
TAGS = [("bt709", "bt709", "bt709", "bt709"),
        ("bt2020-709", "bt2020", "bt709", "bt2020nc"),
        ("hlg", "bt2020", "arib-std-b67", "bt2020nc"),
        ("pq", "bt2020", "smpte2084", "bt2020nc"),
        ("untagged", "unknown", "unknown", "unknown")]
NOT_A_LUT = "is not a LUT Reelcut reads: "
LUT_TEXTURES = "app/Sources/LutTextures.swift"
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "blue-fastest": ([(
        LUT_TEXTURES,
        "min(max(lattice.rgb[point * 3 + channel], 0), 1)",
        "min(max(lattice.rgb[((point % n) * n * n + (point / n % n) * n + point / (n * n)) "
        "* 3 + channel], 0), 1)")], ["N1", "S1", "A1", "F1", "T1"]),
    "domain-ignored": ([(
        "core/src/cube.rs",
        "    if found.iter().zip(want).all(|(a, b)| a == b) {",
        "    if found.len() == want.len() {")], ["R1", "CT"]),
    "size-cap-dropped": ([(
        "core/src/cube.rs",
        "if value < f64::from(CUBE_SIZE_MIN) || value > f64::from(CUBE_SIZE_MAX) {",
        "if value < 0.0 {")], ["R1", "CT"]),
    "media-interpolates": ([(
        "core/src/actions.rs",
        'const OBJECT_DISCRIMINANTS: [&str; 2] = ["kind", "media"];',
        'const OBJECT_DISCRIMINANTS: [&str; 1] = ["kind"];')], ["X1", "CT"]),
    "builtin-keeps-media": ([(
        "core/src/lut.rs",
        "    if asked.get(\"kind\").is_some_and(|kind| !kind.is_null()) {\n"
        "        look.media = None;\n"
        "    }\n",
        "")], ["K1", "CT"]),
    "remove-deletes-clips": ([(
        "core/src/lut.rs",
        "            if base_lut(clip) == Some(media) {\n"
        "                if let Some(video) = clip.video.as_mut() {\n"
        "                    video.look = None;\n"
        "                }\n"
        "            }\n",
        "            if base_lut(clip) == Some(media) {\n"
        "                clip.duration = 0;\n"
        "            }\n"
        "        }\n"
        "        next.clips.retain(|clip| clip.duration > 0);\n"
        "        for nest in next.nests.iter_mut() {\n"
        "            nest.clips.retain(|clip| clip.duration > 0);\n")], ["D1", "CT"]),
    "paste-not-remapped": ([(
        "core/src/edit_paste.rs",
        "            remap_look_media(&mut clip, &media);\n",
        "")], ["P1", "CT"]),
    "urls-from-instruction": ([(
        "app/Sources/RecipeSource.swift",
        "return mediaURLs[instruction.recipeKey] ?? instruction.mediaURLs",
        "return instruction.mediaURLs")], ["P3"]),
}
rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    record = key in RECORDS
    mark = "  rec  " if record else ("  ok   " if good else "  FAIL ")
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    if client is None:
        return {"ok": False, "error": "no instance"}
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


# ---- the LUT files -------------------------------------------------------------

def cube_text(size, function, header="LUT_3D_SIZE {n}\n", newline="\n", separator=" "):
    """A `.cube` file's text: `header` (with `{n}`), then `size³` rows of
    `function(r, g, b)` at the lattice point (r, g, b) / (size − 1), red
    fastest — blue the outer loop, green the middle, red the inner."""
    step = size - 1
    lines = []
    for b in range(size):
        for g in range(size):
            for r in range(size):
                out = function(r / step, g / step, b / step)
                lines.append(separator.join(f"{v:.6f}" for v in out))
    return header.format(n=size).replace("\n", newline) + newline.join(lines) + newline


def identity(r, g, b):
    return (r, g, b)


def swap(r, g, b):
    return (g, b, r)


def invert(r, g, b):
    return (1 - r, 1 - g, 1 - b)


def smooth(r, g, b):
    return (0.9 * r ** 0.8 + 0.1 * b, 0.15 + 0.7 * g ** 1.2 + 0.1 * r, 0.85 * b + 0.1 * (1 - g))


def write_lut(name, size, function, **style):
    path = LUTS / f"{name}.cube"
    path.write_bytes(cube_text(size, function, **style).encode())
    return path


def refusal_files():
    """(path, the core's sentence) for each R1 file."""
    table2 = cube_text(2, identity, header="")
    cases = [
        ("size-200", "TITLE \"big\"\nLUT_3D_SIZE 200\n",
         "line 2: LUT_3D_SIZE 200 is outside 2–65"),
        ("one-d", "LUT_1D_SIZE 1024\n0 0 0\n",
         "line 1: LUT_1D_SIZE is a 1D LUT; only 3D LUTs are read"),
        ("domain", f"LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 -0.1\n{table2}",
         "line 2: DOMAIN_MIN must be 0 0 0, not 0 0 -0.1"),
        ("range", f"LUT_3D_INPUT_RANGE 0 4095\nLUT_3D_SIZE 2\n{table2}",
         "line 1: LUT_3D_INPUT_RANGE must be 0 1, not 0 4095"),
        ("keyword", f"LUT_3D_SIZE 2\nGAMMA 2.2\n{table2}", "line 2: unknown keyword GAMMA"),
        ("late", f"LUT_3D_SIZE 2\n{table2}TITLE \"late\"\n",
         "line 10: TITLE comes after the table"),
        ("short", "LUT_3D_SIZE 2\n" + "".join(table2.splitlines(True)[:7]),
         "LUT_3D_SIZE 2 needs 8 table rows, not 7"),
        ("word", "LUT_3D_SIZE 2\n0 0 0\n0.5x 0 0\n", "line 3: \"0.5x\" is not a number"),
        ("nan", "LUT_3D_SIZE 2\n0 0 0\n0 nan 0\n", "line 3: nan is not a finite number"),
        ("pair", "LUT_3D_SIZE 2\n0 0\n", "line 2: a table row has 3 numbers, not 2"),
        ("nosize", table2, "no LUT_3D_SIZE line"),
        ("twice", "LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n", "line 2: a second LUT_3D_SIZE"),
        ("count", "DOMAIN_MAX 1 1\n", "line 1: DOMAIN_MAX needs 3 numbers"),
    ]
    made = []
    for name, text, sentence in cases:
        path = LUTS / f"refused-{name}.cube"
        path.write_bytes(text.encode())
        made.append((path, sentence))
    binary = LUTS / "refused-binary.cube"
    binary.write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00\xff\xfe")
    made.append((binary, "the file is not text"))
    big = LUTS / "refused-big.cube"
    with open(big, "wb") as out:
        out.write(cube_text(2, identity).encode())
        out.truncate(32 * 1024 * 1024 + 1)
    made.append((big, "the file is larger than 32 MB"))
    return made


def accepted_files():
    body = cube_text(3, swap, header="")
    variants = {
        "dressed": "﻿# made by a script\r\nTITLE \"Dressed\"\r\n\r\nDOMAIN_MIN 0 0 0\r\n"
                   "DOMAIN_MAX 1 1 1\r\nLUT_3D_INPUT_RANGE 0 1\r\nLUT_3D_SIZE 3\r\n"
                   + body.replace("\n", "\r\n") + "\r\n\r\n",
        "tabs": "LUT_3D_SIZE 3\n" + body.replace(" ", "\t"),
    }
    made = []
    for name, text in variants.items():
        path = LUTS / f"accepted-{name}.cube"
        path.write_bytes(text.encode())
        made.append(path)
    return made


# ---- the documents ------------------------------------------------------------

class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path):
        self.client, self.path = client, path

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def tracks(self):
        return self.project().get("tracks") or []

    def clips(self):
        return self.project().get("clips") or []

    def clip(self, clip):
        return next((c for c in self.clips() if c.get("id") == clip), {})

    def look_of(self, clip):
        return (self.clip(clip).get("video") or {}).get("look")

    def media_rows(self):
        return self.project().get("media") or []

    def new_track(self):
        before = {t.get("id") for t in self.tracks()}
        self.call("add_track")
        made = [t.get("id") for t in self.tracks() if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def added(self, tool, **arguments):
        before = {c["id"] for c in self.clips()}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.clips() if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def media(self, path):
        """Imports `path` (a second import is an identity) and answers the id
        of the row holding it, read back by path: `import_media`'s own answer
        for a file already in the project is not its row's id."""
        self.call("import_media", path=str(path))
        return next((m.get("id") for m in self.media_rows() if m.get("path") == str(path)),
                    None)

    def look(self, clips, look):
        return self.call("set_video", clips=clips, patch={"look": look})

    def frame(self, tag, t=T, **options):
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out), **options)
        raw = decode(out, W, H) if got["ok"] and out.exists() else None
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        return Frame(out, raw, W)


def opened(client, name):
    path = WORK / f"{name}.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    doc.call("set_canvas", width=W, height=H, fps=[30, 1], background=[0, 0, 0, 1])
    c = doc.project().get("canvas") or {}
    return doc, made["ok"] and c.get("width") == W and c.get("height") == H


def close(client, path):
    return attempt(client, "close_project", {"project": str(path), "discard": True})["ok"]


def spread(a, b):
    if a is None or b is None:
        return -1
    return max(max(abs(p - q) for p, q in zip(a.px(x, y), b.px(x, y))) for x, y in SAMPLES)


def misses(frame, want, tolerance=0):
    """The samples where `frame` is more than `tolerance` from `want(x, y)`;
    every sample when there is no frame."""
    if frame is None:
        return [("no frame",)]
    found = []
    for x, y in SAMPLES:
        expected = want(x, y)
        got = frame.px(x, y)
        if any(abs(a - b) > tolerance for a, b in zip(got, expected)):
            found.append((x, y, got, tuple(round(v, 1) for v in expected)))
    return found


# ---- T0: what AVFoundation does with HLG, PQ and BT.2020 tags ----------------

def tagged_movies():
    """The chart encoded once as 10-bit ProRes 422, then each tag by stream
    copy, twice: in the ProRes frame headers alone (`prores_metadata`), and
    there AND in the container's `colr` atom (the same values as stream
    options with `+write_colr`, which a stream copy writes only when they
    are given). Untagged is `unknown` (0, the bsf's one non-tag) in the
    headers and no `colr`.
    {name: (path, ffprobe's tags, the colr atom)} or None."""
    chart = write_chart(WORK / "t0-chart.png")
    base = WORK / "t0-base.mov"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-i", str(chart),
                        "-t", "1", "-r", "30", "-vf", "scale=out_color_matrix=bt709",
                        "-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le",
                        str(base)], 120)
    if made["rc"] != 0 or not base.exists():
        return None
    movies = {}
    for name, primaries, transfer, matrix in TAGS:
        for atom in (False, True):
            if atom and name == "untagged":
                continue
            out = WORK / f"t0-{name}{'-colr' if atom else ''}.mov"
            bsf = (f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:"
                   f"colorspace={matrix}")
            colr = ["-color_primaries", primaries, "-color_trc", transfer, "-colorspace",
                    matrix, "-movflags", "+write_colr"] if atom else []
            copied = bounded.run(["ffmpeg", "-y", "-v", "error", "-i", str(base), "-c", "copy",
                                  "-bsf:v", bsf, *colr, str(out)], 120)
            if copied["rc"] != 0 or not out.exists():
                return None
            probed = bounded.run(["ffprobe", "-v", "error", "-show_entries",
                                  "stream=color_primaries,color_transfer,color_space",
                                  "-of", "compact=p=0:nk=1", str(out)], 60)
            data = out.read_bytes()
            at = data.find(b"colrnclc")
            found = data[at + 8:at + 14].hex() if at >= 0 else "none"
            movies[out.stem[3:]] = (out, probed["stdout"].strip(), found)
    return movies


def run_t0(client, state):
    movies = tagged_movies()
    state["t0_fixture"] = movies is not None
    if movies is None:
        print("  T0: ffmpeg could not make the tagged movies", flush=True)
        return True
    frames, closed = {}, True
    for name, (path, _, _) in movies.items():
        doc, sized = opened(client, f"T0-{name}")
        track = (doc.tracks() or [{}])[0].get("id")
        media = doc.media(path)
        clip = doc.added("add_clip", track=track, media=media, at=0) \
            if media is not None else None
        frames[name] = doc.frame(f"t0-{name}") if sized and clip is not None else None
        closed = close(client, doc.path) and closed
    # Each variant against the BT.709 movie tagged the same way (headers alone,
    # or headers and colr), and the untagged one against both.
    deltas = {name: spread(frame, frames.get("bt709-colr" if name.endswith("-colr")
                                             else "bt709"))
              for name, frame in frames.items()}
    deltas["untagged vs bt709-colr"] = spread(frames.get("untagged"), frames.get("bt709-colr"))
    grey = {name: frame.px(320, 40) if frame else None for name, frame in frames.items()}
    red = {name: frame.px(26, 300) if frame else None for name, frame in frames.items()}
    tags = {name: f"{tags} colr {atom}" for name, (_, tags, atom) in movies.items()}
    check("T0 max |Δ| against the BT.709 frame tagged the same way at SAMPLES, per tag, in "
          "the ProRes headers alone and with the container's colr atom too (unscored)",
          all(frame is not None for frame in frames.values()),
          f"Δ {deltas}\n       ffprobe tags {tags}\n       grey (320,40) {grey}"
          f"\n       red patch (26,300) {red}")
    return closed


# ---- project H: the chart and its LUTs -----------------------------------------

def run_h(client, chart, owner_lut, state):
    doc, sized = opened(client, "H")
    track = (doc.tracks() or [{}])[0].get("id")
    chart_media = doc.media(chart)
    clip = doc.added("add_clip", track=track, media=chart_media, at=0) \
        if chart_media is not None else None
    base = doc.frame("neutral")
    corner = base.px(W - 1, 10) if base is not None else None
    fixture = sized and clip is not None and base is not None and corner == (255, 255, 255)
    state["h_fixture"] = fixture
    print(f"  H: chart clip {clip}, media {chart_media}; ramp end {corner}", flush=True)
    if not fixture:
        return close(client, doc.path)
    ids = [clip]
    # The neutral sample's (g, b, r): the swap's oracle.
    swapped = (lambda x, y: (base.px(x, y)[1], base.px(x, y)[2], base.px(x, y)[0]))

    # I1
    before = len(doc.media_rows())
    imported = doc.call("import_media", path=str(LUTS / "swap-33.cube"))
    answer = reply(imported)
    a_id = answer.get("media")
    note = answer.get("note", "")
    want_note = ('set_video {clips, patch: {look: {kind: "lut", media: '
                 f'{a_id}}}}}')
    added = doc.call("add_media", descriptor={"path": str(LUTS / "identity-2.cube"),
                                              "kind": "lut"})
    rows_now = doc.media_rows()
    plain = next((m for m in rows_now if m.get("path") == str(LUTS / "identity-2.cube")), {})
    check("I1 import_media of a .cube answers kind lut, duration 0, no video, audio or alpha "
          "and a note naming set_video's lut look with its id; add_media {path, kind: lut} "
          "lands a lut row with no video",
          imported["ok"] and answer.get("kind") == "lut" and answer.get("duration") == 0
          and not answer.get("has_video") and not answer.get("has_audio")
          and not answer.get("has_alpha") and want_note in note and added["ok"]
          and plain.get("kind") == "lut" and not plain.get("has_video")
          and len(rows_now) == before + 2,
          f"answer {({k: answer.get(k) for k in ('media', 'kind', 'duration', 'has_video')})}; "
          f"note {note!r}; add_media {added.get('error', 'ok')} {plain}")

    # R1
    count = len(doc.media_rows())
    wrong = []
    for path, sentence in refusal_files():
        got = doc.call("import_media", path=str(path))
        want = f"“{path.name}” {NOT_A_LUT}{sentence}."
        error = got.get("error", "")
        if got["ok"] or not error.rstrip().endswith(want):
            wrong.append((path.name, error[-160:] or "accepted"))
            if got["ok"]:
                doc.call("undo")
    check("R1 every refusal file's import_media error ends with “NAME.cube” is not a LUT "
          "Reelcut reads: <the core's sentence>., and the media count is unchanged",
          not wrong and len(doc.media_rows()) == count, f"wrong {wrong[:4]}")

    # R2
    landed = []
    for path in accepted_files():
        got = reply(doc.call("import_media", path=str(path)))
        landed.append((path.name, got.get("kind")))
    check("R2 the accepted variants (BOM, CRLF, TITLE, comments, blank lines, default domain "
          "and input range; tabs) import as lut",
          all(kind == "lut" for _, kind in landed) and len(landed) == 2, f"{landed}")

    def lut_frame(name, tag, amount=1.0):
        media = doc.media(LUTS / f"{name}.cube")
        if media is None:
            return None, None
        set_to = doc.look(ids, {"kind": "lut", "media": media, "amount": amount})
        return (doc.frame(tag) if set_to["ok"] else None), media

    # N1
    identical = {}
    for n in (2, 33, 65):
        frame, _ = lut_frame(f"identity-{n}", f"n1-{n}")
        identical[n] = same_pixels(frame, base)
    check("N1 the chart under an identity LUT of 2, 33 and 65 at amount 1 is the neutral "
          "chart's bytes", all(identical.values()), f"{identical}")

    # S1
    swap_misses = {}
    swap_frames = {}
    for n in (2, 33, 65):
        frame, _ = lut_frame(f"swap-{n}", f"s1-{n}")
        swap_frames[n] = frame
        swap_misses[n] = misses(frame, swapped)
    check("S1 under a channel-swap LUT of 2, 33 and 65 every sample is the neutral sample's "
          "(g, b, r), exactly", not any(swap_misses.values()),
          f"{ {n: m[:2] for n, m in swap_misses.items() if m} }")

    # A1
    half, _ = lut_frame("swap-33", "a1", amount=0.5)
    midway = misses(half, lambda x, y: [(p + q) / 2 for p, q in
                                        zip(base.px(x, y), swapped(x, y))], 1)
    check("A1 swap-33 at amount 0.5 is within ±1 of the midpoint of the neutral sample and "
          "its (g, b, r)", half is not None and not midway, f"{midway[:3]}")

    # F1
    f1 = {}
    smooths = [(f"smooth-{n}", LUTS / f"smooth-{n}.cube") for n in (17, 33, 65)]
    if owner_lut is not None:
        smooths.append(("owner", owner_lut))
    for name, path in smooths:
        media = doc.media(path)
        set_to = doc.look(ids, {"kind": "lut", "media": media, "amount": 1}) \
            if media is not None else {"ok": False}
        got = doc.frame(f"f1-{name}") if set_to["ok"] else None
        reference = WORK / f"f1-{name}-ffmpeg.png"
        made = bounded.run(["ffmpeg", "-y", "-v", "error", "-i", str(chart), "-vf",
                            f"lut3d=file={path}:interp=trilinear", str(reference)], 120)
        raw = decode(reference, W, H) if made["rc"] == 0 and reference.exists() else None
        want = Frame(reference, raw, W) if raw is not None else None
        f1[name] = spread(got, want) if got is not None and want is not None else None
    check("F1 the smooth LUTs (17, 33, 65) are within ±2 of ffmpeg's trilinear lut3d on the "
          "same chart at every sample" + (" (and the owner's file)" if owner_lut else ""),
          all(d is not None and 0 <= d <= 2 for d in f1.values()), f"max |Δ| {f1}")

    # K1
    a_set = doc.look(ids, {"kind": "lut", "media": a_id, "amount": 0.75})
    warm = doc.look(ids, {"kind": "warm"})
    replaced = doc.look_of(clip)
    sentences = {
        "required": (doc.look(ids, {"kind": "lut"}),
                     "video.look.media is required with kind lut"),
        "builtin": (doc.look(ids, {"kind": "cool", "media": a_id}),
                    "video.look.media goes with kind lut, not cool"),
        "absent": (doc.look(ids, {"kind": "lut", "media": 9999}),
                   "video.look.media 9999 is not a media of this project"),
        "video": (doc.look(ids, {"kind": "lut", "media": chart_media}),
                  f"video.look.media {chart_media} is an image media, not a lut"),
    }
    said = {name: (not got["ok"] and want in got.get("error", ""), got.get("error", "")[-90:])
            for name, (got, want) in sentences.items()}
    check("K1 a built-in kind on a LUT clip stores {kind: warm, amount} with no media, and "
          "each look rule answers in its own sentence",
          a_set["ok"] and warm["ok"] and replaced == {"kind": "warm", "amount": 0.75}
          and all(ok for ok, _ in said.values()),
          f"replaced {replaced}; {said}")

    # O1
    placed = doc.call("add_clip", track=track, media=a_id, at=10 * SEC)
    want_o1 = (f"media {a_id} is a LUT: apply it as a look (set_video {{look: {{kind: "
               f"\"lut\", media: {a_id}}}}}), it is not placed as a clip")
    check("O1 add_clip of the LUT is refused by its sentence",
          not placed["ok"] and want_o1 in placed.get("error", ""),
          f"{placed.get('error', 'placed')[-200:]}")

    # X1, U1
    run_x1_u1(doc, clip, ids, base, swap_frames.get(33), state)
    # J1
    run_j1(doc, clip, ids, a_id, swap_frames.get(33))
    # M1, C1, D1
    run_m1_c1_d1(doc, clip, ids, base, swap_frames.get(33))
    closed = close(client, doc.path)
    # P1
    return run_p1(client, chart, state) and closed


def run_x1_u1(doc, clip, ids, base, a_frame, state):
    # Fresh copies imported one after the other, so their ids are adjacent
    # and an interpolated id would land on the other LUT.
    shutil.copyfile(LUTS / "swap-33.cube", LUTS / "x1-a.cube")
    shutil.copyfile(LUTS / "invert.cube", LUTS / "x1-b.cube")
    a_id = doc.media(LUTS / "x1-a.cube")
    b_id = doc.media(LUTS / "x1-b.cube")
    doc.look(ids, {"kind": "lut", "media": b_id, "amount": 1})
    b_frame = doc.frame("x1-b")
    adjacent = a_id is not None and b_id == a_id + 1
    state["x1_fixture"] = adjacent
    based = doc.look(ids, {"kind": "lut", "media": a_id, "amount": 1})
    added = doc.call("add_action", clip=clip, at=0, duration=SEC)
    actions = doc.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=clip, action=action,
                     patch={"video": {"look": {"media": b_id}}}) if action else {"ok": False}
    three_quarters = doc.frame("x1-75", t=3 * SEC // 4)
    end = doc.frame("x1-end", t=SEC + SEC // 2)
    check("X1 an action from LUT A to LUT B (adjacent ids) shows A at 75% of its span and B "
          "after its end",
          adjacent and based["ok"] and added["ok"] and ended["ok"]
          and same_pixels(three_quarters, a_frame) and same_pixels(end, b_frame)
          and not same_pixels(a_frame, b_frame),
          f"ids {a_id}, {b_id}; end {ended.get('error', 'ok')}; 75% is A "
          f"{same_pixels(three_quarters, a_frame)}, is B {same_pixels(three_quarters, b_frame)}"
          f"; end is B {same_pixels(end, b_frame)}")
    if action:
        doc.call("remove_action", clip=clip, action=action)
    ungraded = doc.frame("u1", ungraded=True)
    look = doc.frame("u1-look")
    check("U1 render_frame {ungraded: true} under LUT A is the neutral chart's bytes",
          same_pixels(ungraded, base) and same_pixels(look, a_frame),
          f"ungraded {same_pixels(ungraded, base)}; graded is A {same_pixels(look, a_frame)}")


def run_j1(doc, clip, ids, a_id, a_frame):
    removed = doc.look(ids, None)
    front = doc.new_track()
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    set_to = doc.look([adjustment], {"kind": "lut", "media": a_id}) if adjustment else \
        {"ok": False}
    j1 = doc.frame("j1")
    wrong = misses(j1, a_frame.px, 1) if a_frame is not None else [("no A frame",)]
    check("J1 an adjustment clip with LUT A over the look-less chart is within ±1 of A's "
          "frame at every sample", removed["ok"] and set_to["ok"] and not wrong,
          f"adjustment {adjustment} {set_to.get('error', 'ok')}; {wrong[:3]}")
    if front is not None:
        doc.call("remove_track", track=front, with_clips=True)


def run_m1_c1_d1(doc, clip, ids, base, a_frame):
    # M1
    first = LUTS / "m1.cube"
    shutil.copyfile(LUTS / "swap-33.cube", first)
    m_id = doc.media(first)
    set_to = doc.look(ids, {"kind": "lut", "media": m_id})
    present = doc.frame("m1-present")
    data = first.read_bytes()
    first.unlink()
    gone = doc.frame("m1-gone")
    moved = LUTS / "moved" / "m1.cube"
    moved.parent.mkdir(parents=True, exist_ok=True)
    moved.write_bytes(data)
    relinked = doc.call("relink_media", media=m_id, path=str(moved))
    back = doc.frame("m1-back")
    check("M1 the LUT's file deleted draws the neutral bytes; relink_media to the same bytes "
          "at a new path draws its look again",
          set_to["ok"] and same_pixels(present, a_frame) and same_pixels(gone, base)
          and relinked["ok"] and same_pixels(back, a_frame),
          f"present {same_pixels(present, a_frame)}; gone {same_pixels(gone, base)}; relink "
          f"{relinked.get('error', 'ok')}; back {same_pixels(back, a_frame)}")

    # C1
    saved_path = WORK / "H-saved.reelcut"
    saved = doc.call("save_project", path=str(saved_path))
    doc.path = saved_path
    consolidated = doc.call("consolidate_media")
    row = next((m for m in doc.media_rows() if m.get("id") == m_id), {})
    inside = str(row.get("path", "")).startswith(str(saved_path.resolve()) + "/") or \
        str(row.get("path", "")).startswith(str(saved_path) + "/")
    after = doc.frame("c1")
    check("C1 consolidate_media points the LUT's row inside the package and the frame is "
          "unchanged",
          saved["ok"] and consolidated["ok"] and inside and Path(row.get("path", "")).exists()
          and same_pixels(after, a_frame),
          f"save {saved.get('error', 'ok')}; consolidate {consolidated.get('error', 'ok')}; "
          f"row {row.get('path')}; frame {same_pixels(after, a_frame)}")

    # D1
    refused = doc.call("remove_media", media=m_id)
    want = (f"media {m_id} is the look of clip {clip}; pass with_clips: true to remove it "
            "and clear their looks")
    cleared = doc.call("remove_media", media=m_id, with_clips=True)
    kept = bool(doc.clip(clip))
    look_gone = doc.look_of(clip) is None
    row_gone = all(m.get("id") != m_id for m in doc.media_rows())
    d1_frame = doc.frame("d1")
    undone = reply(doc.call("undo")).get("undone")
    restored = doc.look_of(clip)
    d1_back = doc.frame("d1-back")
    check("D1 remove_media of a used LUT is refused naming the clip; with_clips keeps the "
          "clip and clears its look; undo restores both",
          not refused["ok"] and want in refused.get("error", "") and cleared["ok"] and kept
          and look_gone and row_gone and same_pixels(d1_frame, base)
          and undone == "Remove Media" and (restored or {}).get("media") == m_id
          and same_pixels(d1_back, a_frame),
          f"refused {refused.get('error', 'removed')[-150:]!r}; kept {kept}; look gone "
          f"{look_gone}; row gone {row_gone}; undo {undone!r} → {restored}")


def run_p1(client, chart, state):
    source, sized = opened(client, "P-source")
    track = (source.tracks() or [{}])[0].get("id")
    chart_media = source.media(chart)
    clip = source.added("add_clip", track=track, media=chart_media, at=0) \
        if chart_media is not None else None
    a_id = source.media(LUTS / "swap-33.cube")
    b_id = source.media(LUTS / "invert.cube")
    source.look([clip], {"kind": "lut", "media": a_id})
    source.call("add_action", clip=clip, at=0, duration=SEC)
    actions = source.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = source.call("set_action_end", clip=clip, action=action,
                        patch={"video": {"look": {"media": b_id}}}) if action else {"ok": False}
    project = source.project()
    copied = dict(source.clip(clip))
    copied["track"] = 0
    payload = {"clips": [copied],
               "media": [m for m in project.get("media") or []
                         if m.get("id") in (chart_media, a_id, b_id)]}
    closed = close(client, source.path)

    target, target_sized = opened(client, "P-target")
    target_b = target.media(LUTS / "invert.cube")
    # One more row first, so no id the paste mints can equal its source's.
    target.media(LUTS / "identity-2.cube")
    target.media(chart)
    before = {c["id"] for c in target.clips()}
    pasted = target.call("paste", at=0, payload=payload)
    rows_after = target.media_rows()
    by_path = {m.get("path"): m.get("id") for m in rows_after}
    new = [c for c in target.clips() if c["id"] not in before]
    got = new[0] if len(new) == 1 else {}
    base_look = (got.get("video") or {}).get("look") or {}
    end_look = (((got.get("actions") or [{}])[0].get("end") or {}).get("video") or {}) \
        .get("look") or {}
    target_a = by_path.get(str(LUTS / "swap-33.cube"))
    state["p1_fixture"] = sized and target_sized and clip is not None and ended["ok"]
    check("P1 a paste into another project adds LUT A by path, matches LUT B by path, and "
          "remaps the base look to the target's A and the end to the target's B",
          pasted["ok"] and target_a is not None and target_a != a_id
          and base_look.get("media") == target_a and end_look.get("media") == target_b
          and target_b != b_id and len(rows_after) == 4,
          f"paste {pasted.get('error', 'ok')}; source A {a_id} B {b_id}; target A {target_a} "
          f"B {target_b}; base {base_look}; end {end_look}; rows {len(rows_after)}")
    return close(client, target.path) and closed


# ---- the probe ----------------------------------------------------------------

def run_probe(sources):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "lut_probe", defines=["REELCUT_DEV_TOOLS"],
                                  timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        for name in sorted(selected & PROBE_ROWS):
            check(f"{name} the probe builds over app/Sources", False,
                  f"{error} {error.diagnostics[:6]}")
        return
    request, answer = folder / "request.json", folder / "answer.json"
    if answer.exists():
        answer.unlink()
    request.write_text(json.dumps({"folder": str(folder / "files")}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(selected & PROBE_ROWS):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---- the run ------------------------------------------------------------------

def fixtures():
    LUTS.mkdir(parents=True, exist_ok=True)
    chart = write_chart(WORK / "chart.png")
    for n in (2, 33, 65):
        write_lut(f"identity-{n}", n, identity)
        write_lut(f"swap-{n}", n, swap)
    for n in (17, 33, 65):
        write_lut(f"smooth-{n}", n, smooth)
    write_lut("invert", 33, invert)
    return chart


def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Reelcut: " in line]
    except OSError:
        return [f"{log} could not be read"]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's edits, built by its own
    `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if any(path.startswith("core/") for path, _, _ in edits):
        reason = own_core(copy)
        if reason:
            return None, reason
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            return None, f"the copy's core/tests could not be linked: {error}"
    for path, anchor, replacement in edits:
        target = copy / path
        if not target.resolve().is_relative_to(WORK):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    print(f"  building the copy ({len(edits)} edit(s), each anchor found once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND)
    if app is None:
        return None, reason
    return app, copy


def core_test(copy):
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "cube",
                       "--test", "lut"], 900, cwd=str(copy / "core"))
    lines = (ran["stdout"] + ran["stderr"]).strip().splitlines()
    failed = [line.strip() for line in lines if line.strip().startswith("`--test ")]
    return ran["rc"] == 0 and not ran["expired"], failed or lines[-3:]


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--lut", default=None, help="an owner's .cube file F1 also runs (T4)")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mutant:
        selected.discard("T0")
    owner_lut = Path(args.lut).resolve() if args.lut else None
    if owner_lut is not None and not owner_lut.is_file():
        print(f"no file at {owner_lut}")
        return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][1] if args.mutant else []
    scored = [name for name in ROWS if name in selected and name not in RECORDS]
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading GR6a — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
        sources = copy / "app/Sources"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test cube "
                  "--test lut in the copy's core\n       " + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print(f"grading GR6a — LUTs over MCP ({config} build {binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    chart = fixtures()
    log = WORK / "instance.log"
    state, closed = {}, True
    if selected & (H_ROWS | {"T0"}):
        launched = mcp.launch(str(binary), [],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                print(f"instrument failure: the app did not listen at {launched.socket_path}")
                return 2
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            try:
                if "T0" in selected:
                    closed = run_t0(launched.client, state) and closed
                if selected & H_ROWS:
                    closed = run_h(launched.client, chart, owner_lut, state) and closed
            except Exception as error:  # a row that could not run is a failure
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
                closed = False
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    if selected & PROBE_ROWS:
        run_probe(sources)
    found = complaints(log) if log.exists() else []
    fixtures_ok = all(value for key, value in state.items() if key.endswith("fixture"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Reelcut: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; fixtures {state}; complaints {found}")
    if log.exists():
        print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing or not fixtures_ok:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}, fixtures {state}")
            return 2
        survived = [name for name in named if rows.get(name)]
        others = [name for name in scored if not rows.get(name) and name not in named]
        caught = not survived and not others
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy" + (f"; survived {survived}" if survived else "")
              + (f"; others failed {others}" if others else ""))
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
