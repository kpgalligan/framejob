#!/usr/bin/env python3
"""Issue #375 part 1, spec §11 PR-13: every gradient tiny-skia draws for a
graphic is dithered where it is rounded to 8 bits, by a fixed pattern of
pixel position under half a level (the vendored patch in `graphic/vendor/`);
flat colours, images and text keep their bytes.

    python3 tools/proof/raster_dither_proof.py [--only ROWS] [--control DIR] [--base DIR]
    python3 tools/proof/raster_dither_proof.py capture DIR    # the CONTROL tree: every file kept in DIR
    python3 tools/proof/raster_dither_proof.py --mutant NAME  # cargo only, no app

And issue #374, spec §11 PR-15: a frame delivered deeper than 8 bits draws its
graphics from a 16-bit raster with no dither, and every 8-bit frame keeps
PR-13's bytes (rows E1 and D1–D6, below, scored against `--base DIR`).

Launches the app `proof_app` picks (Debug unless `RC_PROOF_APP=release`) on
a scratch socket of its own and stops only that process. The instance runs in
a scratch home, `CFFIXED_USER_HOME=tools/proof/work/raster-dither/run/home`;
every package, sheet, frame and export is under `tools/proof/work/
raster-dither/run/`, removed at the start and at exit. No menu item is
performed and no default written. Every call is bounded (`CALL_BOUND`), every
ffmpeg and cargo too. Every project is closed (`close_project`, discard).
This script never records the screen and spends nothing.

Fixtures, written with `write_graphic` into 1920×1080 30 fps projects, each
ignoring `frame` but the moving one:
- `band374`: a full-canvas rect filled by a `radialGradient` (userSpaceOnUse,
  centre 960, 540, r 1100) from `#2A4F3D` to `#0D1512` — #374's span, about
  43 green levels along row 540, x 0–800. `e`, the exact value in levels at
  a pixel centre, is worked out here from that geometry.
- `band374m`: `band374` with its centre drifting, `cx = 960 + 0.5 × frame`,
  on a 5 s clip, so the encoder cannot coast on repeated frames.
- `flat`: solid `#336699` rects (opaque and at fill-opacity 0.6), a
  one-colour `#336699` gradient rect and white Anton text.

Rows:
- **B1** `render_graphic band374` frame 0 at 1920×1080, default `max_width`
  (the cell at scale 1, at the sheet's top left, `GraphicContactSheet.
  layout`). Row 540, x 0–800, G: distinct levels, median and widest run,
  beside the control's. Holds: the median run ≤ ½ the control's; the 50-px
  block means strictly increase; every G in rows 500–580, x 0–800, is in
  [floor(e − 1/16), ceil(e + 1/16)].
- **B2** the same cell, rows 500–580, 16-px column blocks over x 0–800: max
  |mean(G − e)| ≤ 0.1; the control's printed.
- **B3** a 1 s `band374` clip covering the canvas, its 8-bit frame: B1's and
  B2's rules. Since PR-20 (below) a `render_frame` PNG of it is 16-bit, so B3
  reads the 8-bit door: an `apng` export of the in/out range 0.48–0.56 s at
  1920×1080 (`APNG_RANGE`), its first frame (the fixture ignores `frame`).
- **B4a** a `prores_422` export of that project, the frame at 0.5 s decoded
  by ffmpeg to `rgb48le` (16 bits; its `rgb24` conversion of 10-bit ProRes
  adds a dither of its own): the banding RMS — column means of G over rows
  530–550, less a 31-column moving average, RMS over x 32–768 — ≤ ½ the
  control's; the row-540 50-px block means strictly increase.
- **B4b** a `hevc_10bit` export of a 5 s `band374m` clip, the frame at 2.5 s
  decoded to `rgb48le`: banding RMS ≤ 0.15 and under the control's.
- **L1–L3**, printed and NOT scored (spec §11 PR-13's recorded limit: the
  8-bit lossy codecs strip the dither): `h264` and `hevc` at default
  quality of the static clip, and `h264` at `video_bitrate` 16000000 of the
  moving clip, decoded to `rgb24`; banding RMS and file size beside the
  control's. L1 and L2 run with B4a, L3 with B4b.
- **F1** `render_graphic flat`: the decoded RGBA equals the control's, and
  the one-colour rect is exactly (51, 102, 153, 255).
- **F2** a `flat` clip's 8-bit frame (B3's APNG door): the decoded RGBA
  equals the control's.
- **S1** `render_graphic band374` frames [0, 30] with `max_width` 8192: the
  two cells are equal, and equal to B1's cell.
- **Z1** no `Frame Job: ` log line; every project closed.

PR-15's rows, scored against `--base DIR`, a `capture` made by the app as it
was BEFORE PR-15 (any build of a commit before it, named by `RC_PROOF_APP`),
whose 8-bit raster is PR-13's dithered one:
- **E1** the 8-bit paths are byte for byte the base's: B1's, S1's and F1's
  sheets decode equal to the base's files, and B3's and F2's APNG frames
  (PR-20's 8-bit door) decode equal to the base's `render_frame` PNGs of those
  frames. On a `capture` by an app before PR-20 that comparison is the door's
  own check: the app's APNG frame against its own 8-bit PNG. Printed: each
  APNG's header, and the base's own APNG frame against its PNG when it has both.
- **D1** `render_frame` at 0.5 s of a `band374` clip with a 64×64 16-bit PNG
  still at the canvas centre (outside the row read): a 16-bit PNG; row 540,
  x 0–800, G holds ≥ 400 distinct 16-bit values, every one within 1/8 of an
  8-bit level of `e`.
- **D3** the `prores_422` export B4a reads, the frame at 0.5 s as `rgb48le`:
  the per-pixel noise kept ≤ ½ the base's (the dither is gone); rows 530–550,
  x 32–768, RMS of G − e less its mean ≤ ½ the base's (each pixel is nearer
  its exact value); the banding RMS ≤ 0.15 (B4b's bound; printed beside the base's,
  whose dither that figure cannot tell from 10-bit steps: an undithered 8-bit
  raster measured 0.3249 there, PR-13's control); and the row-540
  block means strictly increase.
- **D4** the `hevc_10bit` export B4b reads, the frame at 2.5 s (its centre at
  cx 997.5): banding RMS ≤ 0.15 and the noise kept ≤ 0.85 × the base's.
- **D5** `render_frame` at 0.5 s of a `band374` clip with a 256×144 10-bit
  HEVC clip at the canvas centre, the only video track (the generator answers
  deep, PR-14's case): D1's rule.
- **D7** the same with a 256×144 H.264 clip on a new back-most track under
  the 10-bit HEVC clip (the generator answers 8 bits and PR-14 re-reads the
  frame): D1's rule.
- **D6** an HLG project (`set_canvas {output: "hlg"}`): `render_frame` of the
  `band374` clip is a 16-bit PNG whose row 540, x 0–800, G holds ≥ 400
  distinct values (the lift and the layer stage take the 16-bit texture).
Without `--base` (and not `capture`) E1, D3 and D4 FAIL. A `capture` writes
D1's, D5's and D6's frames too, so a base folder shows what they were.

Issue #563, spec §11 PR-16: a shape's gradient, which Core Graphics draws,
measured as PR-15 measured a graphic's and then drawn at 16-bit float where
its frame is delivered deeper than 8 bits. Fixture `shape563`: no graphic
module, one 1 s rectangle shape clip covering the canvas with a linear 0°
gradient `#0D1512` → `#2A4F3D`, so `e(x) = 21 + 58 × (x + 0.5) / 1920` green
levels, 24 of them over x 0–800. The rows, scored against `--base DIR`, a
`capture` made by the app as it was BEFORE PR-16:
- **G0** `render_frame` of `shape563` alone. Until PR-21 (#605, below) it was
  PR-16's measurement, an 8-bit PNG with its figures printed; since PR-21 a
  gradient shape is a deep source of a saved frame, so it is D1's rule against
  the shape's `e`. Printed: its bytes and **G0h**, the same frame as HEIC,
  `sips -g bitsPerSample`.
- **G1** the frame beside D1's 16-bit still: D1's rule against the shape's `e`.
- **G3** a `prores_422` export, the frame at 0.5 s as `rgb48le`: D3's rule
  against the base. **G4**, printed with it and NOT scored (PR-15's limit),
  a `hevc_10bit` export of the same clip.
- **G5** beside D5's 10-bit HEVC clip, **G7** with D7's H.264 clip under it:
  G1's rule. **G6** an HLG project: a 16-bit PNG, ≥ 400 distinct values.
- **GEa** the 8-bit door keeps Core Graphics' dithered bytes: an `apng` export
  of `shape563`'s project (B3's door, `APNG_RANGE`), its first frame, decodes
  equal to the base's same file (`gea-apng.png`). Until PR-21 GEa was G0's own
  frame equal to the base's. Printed: the base's APNG frame against its own G0
  PNG, when that is 8-bit (the door's own check, as E1 prints). **GEb** the HLG
  project's frame as a JPEG (its SDR version) decodes equal to the base's.
  **GEc** a frame of flat shapes (a `#336699` rectangle, the same at alpha 0.6,
  a stroked ellipse) beside the 16-bit still: a 16-bit PNG equal to the base's.
A capture also prints #563's verdict from its own G3 file: the cure is built
when the 8-bit ramp's ProRes file keeps at least the noise and the error PR-15
measured for a graphic's dithered raster (`VERDICT_NOISE`, `VERDICT_ERROR`).
Without `--base` (and not `capture`) G3 and GEa–GEd FAIL.

Issue #588, spec §11 PR-17: what PR-16 left unmeasured.
- **GEd** `shape563` exported `h264`, the frame at 0.5 s as `rgb24`: decodes
  equal to the base's (the 8-bit rows mark nothing deep, so the shape keeps
  Core Graphics' dithered draw). Printed: the worst and mean |Δ| against the
  base over rows 500–580.
- **GM** project `shapematte`, canvas background black: a flat white
  full-canvas rectangle on the back track and `shape563` on a `luma` matte
  track in front of it (read back through `get_project`), exported
  `prores_422`, the frame at 0.5 s as `rgb48le`. The picture's green is the
  matte's coverage, whose exact value is the gradient's Rec. 709 luma, `m(x)`
  (19.08 → 69.83 levels). Holds: banding RMS ≤ 0.15 (D3's and B4b's
  bound) and the row-540 50-px block means strictly increase. An 8-bit
  coverage (`r8`, PR-5) rounds a ramp drawn at 16-bit float with no dither,
  and it banded; PR-17 kept a matte member's 8-bit dithered draw until
  PR-19 made the coverage of a deep frame 16-bit and drew the member deep.
  Printed, not scored: the noise kept, RMS of G − m less its mean, the
  row-540 runs, and the base's same figures.
- **GMg** (#596, spec §11 PR-18): the same project with `band374`, a
  graphic, as the `luma` matte, `m` its radial gradient's Rec. 709 luma:
  GM's rule. PR-15's deep raster takes no dither either, so PR-18 drew a
  matte member's graphic as PR-13's dithered 8-bit raster in every frame,
  until PR-19 (a 16-bit coverage in a deep frame) drew it deep again. Until
  PR-18 it was printed and not scored.

Issue #597, spec §11 PR-19: a matte's coverage in a frame delivered deeper than
8 bits. The sources are precision_proof's own fixtures (`ramp_clip()`, the
10-bit ProRes 422 HQ ramp, every 10-bit code 64..940 across 1920 px, grey;
`still16_png()`, `ramp16.png`, every column X at X/1919 of full scale), each
placed at 0 on a track of its own at its own size, which is the canvas's, and
1 s long (read back through `get_project`). Its exact green is
`e(x) = 255 × x / 1919` levels, which the picture shows as is: grey's Rec. 709
luma is its own value.
- **GMc** a white full-canvas card under the ramp clip on a `luma` matte
  track, canvas background black, exported `prores_422`, the frame at 0.5 s as
  `rgb48le`; **GMs** the same with `ramp16.png` as the matte. Each beside its
  control, **GMc0** / **GMs0**, the same source placed plainly (no card, no
  matte), exported the same way. Holds: banding RMS ≤ `MATTE_BOUND`, the
  row-540 block means strictly increase, and row 540, x 0–800, holds at least
  half the distinct stored 16-bit greens its control holds. Printed: the
  noise kept, RMS of G − e less its mean, the row's runs, the bytes, and the
  base's same figures. An 8-bit coverage rounds the ramp to 8-bit levels (a
  run of 7.5 px each), which these measures see and GM's `runs` cannot.
- **GMe** a 60 % grey card under the ramp clip on a `luma` matte track,
  exported `h264`, the frame at 0.5 s as `rgb24`: decodes equal to the
  base's (an 8-bit row keeps the 8-bit coverage; a white card would hide it,
  since round(1 × c) is the same either way).
- **GMf** `render_frame` at 0.5 s of GMc's project, beside **GMf0**, the
  ramp clip's own frame: a 16-bit PNG, banding RMS ≤ `MATTE_BOUND`, and row
  540 at least half GMf0's distinct 16-bit greens (the generator answers that
  frame deep with its key unmarked, so it is read again with the key deep).
Without `--base` (and not `capture`) GMe FAILS.

Issue #566, spec §11 PR-20: a graphic is a deep source of a saved frame, so a
`render_frame` or Save Frame… as PNG or HEIC of a frame whose recipe draws a
graphic is read through export's reader and is deep, beside anything.
- **DG** `render_frame` at 0.5 s of `band374` alone (B3's project, its file
  `b3-frame.png`): D1's rule. Printed: its bytes and wall time, and **DGh**,
  the same frame as HEIC, `sips -g bitsPerSample`.
- **DGf** `render_frame` of `flat` alone (F2's project, `f2-frame.png`): a
  16-bit PNG whose one-colour gradient rect (x 1110–1489, y 110–389) holds one
  RGB value, each channel within 1/8 level of (51, 102, 153): exact levels, no
  dither.
- **DGv** `band374` with a 256×144 8-bit H.264 clip at the canvas centre and no
  deep source: D1's rule (a graphic beside an 8-bit clip makes the frame deep).
- **DGo** a `band374` clip from 0 to 1 s and a flat 400×300 shape from 1 s:
  the frame at 0.5 s is a 16-bit PNG, the frame at 1.5 s (no graphic, a FLAT
  shape, which PR-21 leaves 8-bit) an 8-bit PNG (the recipe at the frame time
  is asked, not the project).
- **DGj** `band374` alone as a JPEG: decodes equal to the base's.
- **DGs**, printed and NOT scored (needs the owner's `tools/proof/media/
  owner-sync/IMG_0018.MOV`): the PNG's depth, bytes and base64 bytes beside the
  Anthropic API's 5 MB image limit, unscaled and at `max_width` 1280, of a
  1920×1080 8-bit H.264 cut of that clip under `flat`, of the cut beside a
  64×64 16-bit still, and of the clip itself (HEVC Main 10); since PR-22 each
  beside its image block's own base64 bytes, the default block.
Without `--base` (and not `capture`) DGj FAILS. On a `capture` by an app before
PR-20, DG, DGf, DGv and DGo FAIL.

Issue #605, spec §11 PR-21: a gradient shape is a deep source of a saved frame,
beside anything, as a graphic is (G0 above, on D1's rule since).
- **GV** `shape563` with a 256×144 8-bit H.264 clip at the canvas centre (in
  front, outside the row read) and no other deep source: D1's rule against the
  shape's `e` (DGv's twin).
- **GMr** GMc's project with a 256×144 8-bit H.264 clip on a new back-most
  track, `render_frame` at 0.5 s: GMf's rule. The generator's depth follows the
  lowest track that has video, so it answers this frame at 8 bits, and PR-14's
  re-read, with its mark, is what makes the coverage 16 bits (PR-19). G7, the
  row that held that mark until PR-21, is now read by the gradient arm first.
On a `capture` by an app before PR-21, G0 and GV FAIL (8-bit PNGs).

Issue #604, spec §11 PR-22: `render_frame`'s image block (what the model sees)
is an 8-bit PNG copy of a deep frame, and `full_depth_image: true` asks for the
file in it; the file and the path stay as deep as the frame. Generated media
only (`blk1080`: a 1 s 1920×1080 `testsrc2` with temporal noise, 8-bit H.264 at
20 Mbit/s, which `canvas_media` places covering the canvas), read through
`mcp.call_content`, which keeps the image block:
- **BK1** `blk1080` under `flat` (deep by PR-20), default: the file is a 16-bit
  PNG whose base64 is OVER the API's 5,242,880 bytes (the premise, asserted, so
  the row cannot pass on an easy picture); the block is `image/png`, an 8-bit
  PNG of the file's width and height whose base64 is at most 5,242,880 bytes,
  every sample within 1 level of the file's rounded to 8 bits; the text holds
  the copy sentence and still ends "Written to <path>.".
- **BK2** the same with `full_depth_image: true`: the block's bytes are the
  file's, and no copy sentence.
- **BK3** `blk1080` alone (an 8-bit frame), default: an 8-bit PNG whose block's
  bytes are the file's, and no copy sentence (nothing is re-encoded when nothing
  is deep).
- **BK4** BK1's frame as `heic`: the file 10 bits a sample (`sips`); the default
  block an 8-bit PNG, `image/png`, with the HEIC copy sentence; with
  `full_depth_image: true` the block is `image/heic` and the file's bytes.
- **BK5** `full_depth_image: "yes"` is refused naming the argument, and
  `tools/list` publishes `full_depth_image` as a boolean.
- **BK6** (#611) an HLG project, D6's recipe under its own name (a `band374`
  clip, `set_canvas {output: "hlg"}`), default: the canvas reads back `hlg`;
  the file is a 16-bit PNG; the block, the copy drawn in BT.2100 HLG, is
  `image/png`, an 8-bit PNG of the file's width and height, every sample within
  1 level of the file's rounded to 8 bits; the copy sentence, and "Written to
  <path>." last. BK1's size premise is not asserted: a graphic's frame is small.
- **BKk** (#610, spec §11 PR-23; printed and not scored until then): a 3840×2160
  `testsrc2` frame (`blk2160`) under `flat` on a 3840×2160 canvas, default: the
  file a 16-bit PNG of 3840×2160 whose base64 is over the limit (the premise);
  the block `image/png`, 8-bit, base64 at most 5,242,880, narrower than 3840
  and shorter than 2160 with the aspect kept (|w·2160 − h·3840| ≤ 3840); the copy
  sentence, then the scale sentence naming exactly the block's w×h, then
  "Written to <path>." last; and the block is the frame (`thumb_gap`: block and
  file each reduced by ffmpeg to 64×36 `rgb24`, area scaling, mean |Δ| at most
  `THUMB_BOUND` levels).
- **BKp** (#610): `blk2160` alone on the 3840×2160 canvas (an 8-bit frame),
  default: the file an 8-bit PNG of 3840×2160 over the limit (the premise); the
  block BKk's rule, with the scale sentence and NO copy sentence.
- **BKj** (#610): a 3840×2160 uniform-noise still (`noise2160.png`) alone,
  `format: "jpeg"`, default: the JPEG file 3840×2160 (`sips`) over the limit (the
  premise); the block `image/jpeg`, at most the limit, smaller, aspect kept;
  the scale sentence and no copy sentence; `thumb_gap` as BKk.
- **BKd** (#612, spec §11 PR-24; no media, no render): `tools/list`'s
  `render_frame` says what the API does with a large image, apart from the
  scale-down sentence: its description holds each of `SIDES_SAID` (8000 px,
  3000 px, more than 20 images, 2576 px, 10 MB, Amazon Bedrock, and "max_width
  is the caller's control"); `max_width`'s description each of `WIDTH_SAID`
  (8000 px, 3000 px, 2576 px, "the height follows") with its schema still
  `minimum` 16 and `maximum` 8192 (no cap added); and none of the description,
  `max_width`'s and `full_depth_image`'s says `OLD_ATTRIBUTION` ("Anthropic
  API's 5 MB": the 5 MB is Amazon Bedrock's). The three texts are printed.
BK2 is PR-23's exemption: a `full_depth_image` block over the limit stays the
file's bytes. BK1 and BK3 are its other side: a block that fits is untouched.
On a `capture` by an app before PR-22, BK1, BK2, BK4, BK5 and BK6 FAIL (the
block is the file, an `image/heic` one for a HEIC, and `full_depth_image` is a
stranger); by an app before PR-23, BKk, BKp and BKj FAIL (the block over the
limit, no scale sentence).

`capture DIR` runs every row and keeps every file in DIR; its own files are
the control it is scored against, so on the control tree B1, B3, B4a and B4b
are expected to FAIL. Without `--control` (and not `capture`) B1–B4b, F1 and
F2 FAIL: they have nothing to be compared with. B4a and B4b print the
per-pixel noise each codec kept (RMS of G less its column mean, rows
530–550, x 32–768) beside the control's.

`--mutant NAME` follows `image_cache_proof.run_graphic_mutant`: `graphic/`
copied (no `target`) to `work/raster-dither/mutant/` beside an `app`
symlink, each anchor in the vendored crate replaced exactly once, then
`cargo test --release --test dither` (PR-15's mutants: `--test deep`) with
`CARGO_TARGET_DIR=work/raster-dither-target`. `core-unpatched` copies `core/`
too, removes core's `[patch]` table and builds `cargo test --release --offline
--test graphic_ffi`: since PR-15 the staticlib does not build against the
registry's tiny-skia at all (`with_deep_pixmaps` is the vendored crate's), so
the mutant is caught when the build fails naming it. MUTANT PASS when every
named test FAILED. PR-15's app mutants are `--app-mutant NAME`: `app/`,
`core/`, `graphic/` and the rest of the tree copied by `tree_copy`, the anchor
replaced, the Debug app built there, and the named rows run against it with
`--base`; MUTANT PASS when every named row FAILED, and every row `KEPT_ROWS`
names for the mutant (run beside them) passed (#611). PR-16's app mutants
(`shape-never-deep` … `sdr-version-marked`; `shape-always-deep` scored on GEa's
APNG door and GEd since PR-21, `reread-not-marked`, PR-14's mark, on GMr, and
`shape-generator-frame-not-deep` gone with the code PR-21 removed) run the same
way against PR-16's base, as do #588's `export-always-marked` and PR-19's three
(`coverage-never-deep`, the coverage's depth read off the frame's, which GMc,
GMs, GM and GMg see; `coverage-always-deep`, its 8-bit case;
`frame-matte-not-reread`, the frame path's new arm), whose GMc, GMs, GM, GMg
and GMf rules are absolute and GMe's against the base. PR-17's and PR-18's
matte mutants went with the code PR-19 withdrew. PR-20's three
(`graphic-not-a-source`, the arm gone; `graphic-anywhere`, the arm asking the
project instead of the recipe; `graphic-frame-pin-not-marked`, the frame's
graphics left 8-bit) run against PR-20's base; PR-15's
`generator-frame-not-deep` and `reread-not-deep` went with the code PR-20
removed (a frame with a graphic no longer reaches the generator's paths).
PR-21's two (`gradient-not-a-source`, the arm gone: G0, GV, G5;
`flat-shape-a-source`, every shape counted: DGo) and PR-22's five
(`block-is-the-file`: BK1, BK4; `full-depth-ignored`: BK2, BK4;
`block-always-recoded`, an 8-bit PNG copied too: BK3; `heic-block-follows-file`:
BK4; `hlg-block-not-copied`, #611, the copy refused in BT.2100 HLG only: BK6,
with BK1–BK5 kept passing) and PR-23's seven (`block-not-bounded`, the size test
always fits: BKk, BKp, BKj; `block-always-scaled`, the scale entered whatever the
size: BK1, BK3; `full-depth-scaled`, the exemption dropped: BK2;
`limit-counts-raw-bytes`, the raw bytes compared with the limit: BKk, whose
unscaled block is under 5,242,880 raw bytes and over it as base64;
`scale-sentence-dropped`: BKk, BKp, BKj; `scaled-jpeg-as-png`: BKj;
`aspect-not-kept`, the scaled height left at the frame's: BKk, BKp) run against
any base.

Exit 0 when every scored row passes (a mutant: caught); 1 when one failed (a
mutant: survived); 2 when the control could not be performed.
"""

import argparse
import array
import atexit
import base64
import json
import math
import os
import shutil
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import hdr_proof as hdr  # noqa: E402
import mcp  # noqa: E402
import precision_proof as precision  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/raster-dither"
WORK = BASE / "run"
HOME = WORK / "home"
MUTANT_DIR = BASE / "mutant"
TARGET = ROOT / "tools/proof/work/raster-dither-target"
CALL_BOUND = 300
TOOL_BOUND = 120
CARGO_BOUND = 1800
W, H = 1920, 1080
SEC = 600_000
ROWS = ["B1", "B2", "B3", "B4a", "B4b", "F1", "F2", "S1", "E1", "D1", "D3", "D4", "D5", "D6",
        "D7", "G0", "G1", "G3", "G5", "G6", "G7", "GV", "GEa", "GEb", "GEc", "GEd", "GM", "GMg",
        "GMc", "GMs", "GMe", "GMf", "GMr", "DG", "DGf", "DGv", "DGo", "DGj", "DGs", "BK1", "BK2",
        "BK3", "BK4", "BK5", "BK6", "BKk", "BKp", "BKj", "BKd", "Z1"]
# Every file a run keeps, by the row that writes it (L1–L3 are printed only).
FILES = {"B1": "b1-sheet.png", "B3": "b3-frame.png", "B3a": "b3-apng.png",
         "B4a": "b4a-prores.mov",
         "B4b": "b4b-hevc10-moving.mp4", "L1": "l1-h264-static.mp4",
         "L2": "l2-hevc-static.mp4", "L3": "l3-h264-16M-moving.mp4",
         "F1": "f1-sheet.png", "F2": "f2-frame.png", "F2a": "f2-apng.png", "S1": "s1-sheet.png",
         "D1": "d1-frame-still.png", "D5": "d5-frame-hevc10.png", "D6": "d6-frame-hlg.png",
         "D7": "d7-frame-h264-under-hevc10.png",
         "G0": "g0-frame-shape.png", "G1": "g1-frame-shape-still.png",
         "G3": "g3-shape-prores.mov", "G4": "g4-shape-hevc10.mp4",
         "G5": "g5-frame-shape-hevc10.png", "G6": "g6-frame-shape-hlg.png",
         "G7": "g7-frame-shape-h264-under-hevc10.png", "GEb": "geb-frame-shape-hlg.jpg",
         "GEc": "gec-frame-flat-shapes-still.png", "GEd": "ged-shape-h264.mp4",
         "GM": "gm-shape-matte-prores.mov", "GMg": "gmg-graphic-matte-prores.mov",
         "GMc": "gmc-clip-matte-prores.mov", "GMc0": "gmc0-clip-prores.mov",
         "GMs": "gms-still-matte-prores.mov", "GMs0": "gms0-still-prores.mov",
         "GMe": "gme-clip-matte-grey-h264.mp4", "GMf": "gmf-frame-clip-matte.png",
         "GMf0": "gmf0-frame-clip.png", "DGj": "dgj-frame.jpg", "DGh": "dgh-frame.heic",
         "DGv": "dgv-frame-h264.png", "DGo": "dgo-frame-graphic.png", "DGo2": "dgo2-frame-shape.png",
         "DGsg": "dgs-graphic-over-8bit.png", "DGsg1280": "dgs-graphic-over-8bit-1280.png",
         "DGss": "dgs-still-over-8bit.png", "DGss1280": "dgs-still-over-8bit-1280.png",
         "DGsi": "dgs-iphone.png", "DGsi1280": "dgs-iphone-1280.png",
         # Spec §11 PR-21 (#605).
         "G0h": "g0h-frame-shape.heic", "GV": "gv-frame-shape-h264.png", "GEa": "gea-apng.png",
         "GMr": "gmr-frame-clip-matte-over-h264.png",
         # Spec §11 PR-22 (#604): each frame's file, and its image block kept beside it.
         "BK1": "bk1-frame.png", "BK1b": "bk1-block.png", "BK2": "bk2-frame.png",
         "BK2b": "bk2-block.png", "BK3": "bk3-frame.png", "BK3b": "bk3-block.png",
         "BK4": "bk4-frame.heic", "BK4b": "bk4-block.png", "BK4f": "bk4f-frame.heic",
         "BK4fb": "bk4f-block.heic", "BKk": "bkk-frame.png", "BKkb": "bkk-block.png",
         # #611: an HLG project's deep frame and its block.
         "BK6": "bk6-frame-hlg.png", "BK6b": "bk6-block-hlg.png",
         # #610, spec §11 PR-23: 3840×2160 frames over the limit, each block scaled to fit.
         "BKp": "bkp-frame.png", "BKpb": "bkp-block.png", "BKj": "bkj-frame.jpg",
         "BKjb": "bkj-block.jpg"}
# Spec §11 PR-16's fixture: the shape's gradient, and its exact G in levels.
SHAPE_FROM, SHAPE_TO = (13, 21, 18), (42, 79, 61)    # #0D1512 at x 0, #2A4F3D at x 1920
SHAPE_563 = {"kind": "rectangle", "stroke": None, "width": W, "height": H, "fill": [1, 1, 1, 1],
             "gradient": {"kind": "linear", "angle": 0, "stops": [
                 {"at": 0, "color": [c / 255 for c in SHAPE_FROM] + [1]},
                 {"at": 1, "color": [c / 255 for c in SHAPE_TO] + [1]}]}}
# GM's card (spec §11 PR-17): flat white over the canvas, so the picture is the matte's coverage.
WHITE_CARD = {"kind": "rectangle", "stroke": None, "width": W, "height": H, "fill": [1, 1, 1, 1]}
LUMA = (0.2126, 0.7152, 0.0722)    # `framejob_matte_resolve_fragment`'s weights
MATTE_BOUND = 0.15                 # GM's banding RMS bound: D3's and B4b's
# GMe's card (spec §11 PR-19): 60 % grey, so an 8-bit and a 16-bit coverage round apart.
GREY_CARD = dict(WHITE_CARD, fill=[0.6, 0.6, 0.6, 1])
RAMP_LAST = 1919                   # precision_proof's ramps: column X at X / 1919 of full scale
# GEc's flat shapes: (shape, video patch).
FLAT_SHAPES = [
    ({"kind": "rectangle", "stroke": None, "width": 400, "height": 300,
      "fill": [0.2, 0.4, 0.6, 1]}, {"x": -600, "y": -200}),
    ({"kind": "rectangle", "stroke": None, "width": 400, "height": 300,
      "fill": [0.2, 0.4, 0.6, 0.6]}, {"x": 0, "y": -300}),
    ({"kind": "ellipse", "stroke": {"color": [1, 1, 1, 1], "width": 9}, "width": 400,
      "height": 300, "fill": [0.2, 0.4, 0.6, 1]}, {"x": 600, "y": 200}),
]
# #563's verdict rule: what PR-15's base measured for a graphic's dithered 8-bit raster in a
# `prores_422` file (its noise kept, its RMS of G − e less its mean).
VERDICT_NOISE, VERDICT_ERROR = 0.3306, 0.3460
# The limits: (row, title, which project, export arguments, seek seconds).
LIMITS = [("L1", "h264, default quality, static 1 s", "band", {"preset": "h264"}, 0.5),
          ("L2", "hevc, default quality, static 1 s", "band", {"preset": "hevc"}, 0.5),
          ("L3", "h264 at video_bitrate 16000000, moving 5 s", "moving",
           {"preset": "h264", "video_bitrate": 16_000_000}, 2.5)]
INNER, OUTER = (42, 79, 61), (13, 21, 18)    # #2A4F3D at the centre, #0D1512 at r
CX, CY, RADIUS = 960.0, 540.0, 1100.0

BAND_JS = """export const meta = { name: "Band 374", durationInFrames: 60 };
export function render(frame, props, ctx) {
  return svg(ctx, `<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="960"
      cy="540" r="1100"><stop offset="0" stop-color="#2A4F3D"/>
      <stop offset="1" stop-color="#0D1512"/></radialGradient></defs>
    <rect x="0" y="0" width="1920" height="1080" fill="url(#g)"/>`);
}
"""
MOVING_JS = """export const meta = { name: "Band 374 moving", durationInFrames: 150 };
export function render(frame, props, ctx) {
  const cx = 960 + frame * 0.5;
  return svg(ctx, `<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="${cx}"
      cy="540" r="1100"><stop offset="0" stop-color="#2A4F3D"/>
      <stop offset="1" stop-color="#0D1512"/></radialGradient></defs>
    <rect x="0" y="0" width="1920" height="1080" fill="url(#g)"/>`);
}
"""
FLAT_JS = """export const meta = { name: "Flat", durationInFrames: 60 };
export function render(frame, props, ctx) {
  return svg(ctx, `<defs><linearGradient id="one" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#336699"/><stop offset="1" stop-color="#336699"/>
    </linearGradient></defs>
    <rect x="100" y="100" width="400" height="300" fill="#336699"/>
    <rect x="600" y="100" width="400" height="300" fill="#336699" fill-opacity="0.6"/>
    <rect x="1100" y="100" width="400" height="300" fill="url(#one)"/>
    <text x="100" y="800" font-family="Anton" font-size="300" fill="#ffffff">FLAT 375</text>`);
}
"""
ONE_COLOUR_AT = (1300, 250)
# The one-colour gradient rect's interior, x0, y0, x1, y1 (DGf).
ONE_COLOUR_RECT = (1110, 110, 1490, 390)
# Spec §11 PR-20's 8-bit door for B3, F2 and E1: an `apng` export of the in/out range 0.48–0.56 s
# (the preset's 25 fps: two frames) at 1920×1080, which `renderFrameReported` draws with
# `keepsDepth` false, read at its first frame. The fixtures ignore `frame`, so the frame at
# 0.48 s is the one at 0.5 s.
APNG_RANGE = (288_000, 336_000)
# DGs (printed): the Anthropic API's limit on one image, set beside the base64 the assistant's
# helper forwards (`agent/Sources/FrameJobAgentKit/ToolResults.swift`); and the owner's iPhone clip (1920×1080 HEVC Main 10,
# HLG), which the 8-bit fixture is made from. Absent media prints "no fixture".
API_IMAGE_LIMIT = 5 * 1024 * 1024
OWNER_CLIP = ROOT / "tools/proof/media/owner-sync/IMG_0018.MOV"
# render_frame's wall time per file, in seconds (DG's detail).
FRAME_SECONDS = {}
# Spec §11 PR-22 (#604): `Doc.frame_block`'s answers by row, the sentence a copy adds, and the
# generated footage (`testsrc2` with temporal noise, so its PNG does not compress like a flat
# card's). Tuned once on the app before PR-22 (Debug at aa5a1512), the 16-bit file of BK1's frame
# against the 8-bit file of BK3's, base64: noise 8 at 60 Mbit/s 4,894,540 and 2,660,884 (the
# 16-bit one under the limit); 16 at 60 Mbit/s 2,176,948 and 1,279,260 (the encoder smoothed it);
# 16 at 100 Mbit/s 7,597,788 and 4,335,348; 12 at 80 Mbit/s 5,202,172 and 2,864,756; 10 at
# 100 Mbit/s 5,736,776 and 3,165,620; 12 at 100 Mbit/s 6,406,520 and 3,595,204, chosen: its nearer
# side is 22 % from the limit, the most of the six.
BLOCKS = {}
COPY_PNG = "The image here is an 8-bit PNG copy of the 16-bit PNG file."
COPY_HEIC = "The image here is an 8-bit PNG copy of the HEIC file."
COPY_SAID = "8-bit PNG copy"    # in either sentence
BLOCK_NOISE = 12
BLOCK_RATE = "100M"
# #610, spec §11 PR-23: the sentence a block scaled to fit adds (after a copy's), the words every
# such sentence holds, and the bound on `thumb_gap`, the mean |Δ| in levels between the block and
# the file each reduced to 64×36.
SCALE_SAID = ("The image here is scaled down to {w}×{h} px to fit the API's 5 MB image limit; "
              "the file is not scaled.")
SCALED_WORDS = "to fit the API's 5 MB image limit"
THUMB = (64, 36)
THUMB_BOUND = 2.0
# BKj's still: uniform noise over grey at 3840×2160, which a JPEG at 0.9 cannot make small.
NOISE_STILL = ["-f", "lavfi", "-i", "color=c=gray:s=3840x2160:d=1", "-vf",
               "noise=alls=100:allf=u", "-frames:v", "1"]


def block_footage(size):
    """`fixture`'s arguments for 1 s of `testsrc2` at `size` with temporal noise, 8-bit H.264."""
    return ["-f", "lavfi", "-i", f"testsrc2=size={size}:rate=30:duration=1,"
            f"noise=alls={BLOCK_NOISE}:allf=t+u,format=yuv420p", "-c:v", "h264_videotoolbox",
            "-b:v", BLOCK_RATE]

VENDOR = "graphic/vendor/tiny-skia/src"
HIGHP = f"{VENDOR}/pipeline/highp.rs"
LOWP = f"{VENDOR}/pipeline/lowp.rs"
GRADIENT = f"{VENDOR}/shaders/gradient.rs"
SHADERS = f"{VENDOR}/shaders/mod.rs"
CLAMP = "    p.{c} = (p.{c} + d).max(f32x8::default()).min(p.a);\n"
PER_CHANNEL = """    let mut dg = [0.0f32; STAGE_WIDTH];
    for (i, v) in dg.iter_mut().enumerate() {
        let h = dither_hash(dither_hash(row ^ (p.dx + i) as u32));
        *v = ((h >> 8) as f32 / 16_777_216.0 - 0.5) * DITHER_SPAN / 255.0;
    }
    p.g = (p.g + f32x8::from(dg)).max(f32x8::default()).min(p.a);
"""
# name: ([(file, anchor, replacement)], the tests that must FAIL)
MUTANTS = {
    "span-full": ([(HIGHP, "const DITHER_SPAN: f32 = 0.875;", "const DITHER_SPAN: f32 = 1.75;")],
                  ["a_colour_on_a_level_stays_exact"]),
    "no-dither": ([(GRADIENT, "        p.push(pipeline::Stage::Dither);\n", "")],
                  ["every_gradient_kind_brackets_its_exact_value",
                   "column_means_follow_the_exact_value"]),
    "rows-only": ([(HIGHP, "    let y = p.dy as u32;\n", "    let y = 0u32;\n")],
                  ["column_means_follow_the_exact_value"]),
    "per-channel": ([(HIGHP, CLAMP.format(c="g"), PER_CHANNEL)],
                    ["one_offset_for_every_channel"]),
    "alpha-dithered": ([(HIGHP, CLAMP.format(c="b"), CLAMP.format(c="b") + "    p.a = p.a + d;\n")],
                       ["alpha_is_not_dithered"]),
    "no-clamp": ([(HIGHP, CLAMP.format(c=c), CLAMP.format(c=c).replace(".min(p.a)", ""))
                  for c in "rgb"], ["alpha_is_not_dithered"]),
    "lowp-kept": ([(LOWP, "    null_fn, // Dither\n", "    dither_pass, // Dither\n"),
                   (LOWP, "pub fn null_fn(_: &mut Pipeline) {\n",
                    "pub fn dither_pass(p: &mut Pipeline) {\n    p.next_stage();\n}\n\n"
                    "pub fn null_fn(_: &mut Pipeline) {\n")],
                  ["every_gradient_kind_brackets_its_exact_value"]),
    "every-paint": ([(SHADERS, "                p.push_uniform_color(color);\n",
                      "                p.push_uniform_color(color);\n"
                      "                p.push(crate::pipeline::Stage::Dither);\n")],
                    ["solid_paints_text_and_images_are_not_dithered"]),
    "core-unpatched": ([], ["a_gradient_is_dithered_through_the_ffi"]),
}
# Spec §11 PR-15's crate mutants, run against `--test deep`.
PIXMAP = f"{VENDOR}/pixmap.rs"
BLITTER = f"{VENDOR}/pipeline/blitter.rs"
DEEP_MUTANTS = {
    "dither-in-deep": ([(GRADIENT, "        if !p.deep_dst {\n", "        {\n")],
                       ["the_gradient_keeps_its_levels"]),
    "root-only": ([(PIXMAP, "            lo: if deep_pixmaps() { vec![0; data_len] } else { Vec::new() },",
                    "            lo: if deep_pixmaps() && width == 1920 && height == 1080 "
                    "{ vec![0; data_len] } else { Vec::new() },")],
                  ["the_levels_survive_every_layer"]),
    "lowp-on-deep": ([(BLITTER, "        let force_hq = paint.force_hq_pipeline || deep;",
                       "        let force_hq = paint.force_hq_pipeline;")],
                     ["the_levels_survive_every_layer"]),
    "no-load-mask": ([(HIGHP, "    p.a = f32x8::from(c) / f32x8::splat(255.0);\n",
                       "    p.a = f32x8::splat(1.0);\n    let _ = c;\n")],
                     ["the_levels_survive_every_layer"]),
    "plain-collapse": ([(PIXMAP, "            px[c] = ((v + offset + 128) >> 8).clamp(0, alpha) as u8;",
                         "            px[c] = ((v + 128 + offset * 0) >> 8).clamp(0, alpha) as u8;")],
                       ["a_layer_read_at_eight_bits_is_dithered"]),
    "door-leaks": ([(PIXMAP, "            DEEP.with(|deep| deep.set(self.0));",
                     "            let _ = self.0;")],
                   ["the_eight_bit_raster_is_unchanged_beside_a_deep_one"]),
    "zero-run-drops": ([(PIXMAP, "            let flat = lo.is_empty() || is_zero(lo);",
                         "            let flat = lo.is_empty() || is_zero(lo) || is_zero(hi);")],
                       ["a_fade_to_nothing_keeps_its_tail"]),
}
MUTANTS.update(DEEP_MUTANTS)
# Spec §11 PR-15's app mutants: (file, anchor, replacement), the rows that must FAIL.
SOURCES = "app/Sources"
APP_MUTANTS = {
    "never-deep": ([(f"{SOURCES}/GraphicRegistry.swift",
                     "budgetMs: Self.offlineBudgetMs, deep: pinned.deep)",
                     "budgetMs: Self.offlineBudgetMs, deep: false)")], ["D1", "D3", "D5", "D6"]),
    "always-deep": ([(f"{SOURCES}/GraphicRegistry.swift",
                      "budgetMs: Self.previewBudgetMs, deep: false)",
                      "budgetMs: Self.previewBudgetMs, deep: true)"),
                     (f"{SOURCES}/GraphicRegistry.swift",
                      "budgetMs: Self.offlineBudgetMs, deep: pinned.deep)",
                      "budgetMs: Self.offlineBudgetMs, deep: true)")], ["E1"]),
    "hevc10-not-deep": ([(f"{SOURCES}/ExporterGraphics.swift",
                          "        default: return true\n        }\n    }\n\n    /// Whether the recipe",
                          "        default: return settings.preset != \"hevc_10bit\"\n        }\n    }\n\n"
                          "    /// Whether the recipe")], ["D4"]),
    # Spec §11 PR-16's seven, one per decision it adds.
    "shape-never-deep": ([(f"{SOURCES}/Compositor+Sources.swift",
                           "renderers.shape(props, hash: hash, deep: deep)",
                           "renderers.shape(props, hash: hash, deep: deep && false)")],
                         ["G1", "G3", "G5", "G6"]),
    "shape-always-deep": ([(f"{SOURCES}/Compositor+Sources.swift",
                            "renderers.shape(props, hash: hash, deep: deep)",
                            "renderers.shape(props, hash: hash, deep: deep || true)")],
                          ["GEa", "GEd"]),
    "flat-shape-deep": ([(f"{SOURCES}/LayerRenderers.swift",
                          "        let deep = deep && props.drawsGradient\n",
                          "        let deep = deep || (false && props.drawsGradient)\n")],
                        ["GEc"]),
    "export-not-marked": ([(f"{SOURCES}/Exporter.swift",
                            "        if Exporter.graphicsDeep(settings) { "
                            "RecipeSource.shared.markDeep(key) }\n", "")], ["G3"]),
    # PR-14's re-read mark (spec §11 PR-21: G7 no longer reaches it, so GMr, a matted frame the
    # generator answers 8-bit, holds it).
    "reread-not-marked": ([(f"{SOURCES}/Exporter+Frame.swift",
                            "            DeepVideoFrame.showsDeepSource(project, built, at: t, "
                            "options: options)\n        {\n            RecipeSource.shared.markDeep("
                            "key)\n",
                            "            DeepVideoFrame.showsDeepSource(project, built, at: t, "
                            "options: options)\n        {\n")], ["GMr"]),
    "sdr-version-marked": ([(f"{SOURCES}/Exporter+Frame.swift",
                             "            if keepsDepth { RecipeSource.shared.markDeep(key) }\n",
                             "            RecipeSource.shared.markDeep(key)\n")], ["GEb"]),
    # #588: the export's mark without its guard (GEd).
    "export-always-marked": ([(f"{SOURCES}/Exporter.swift",
                               "        if Exporter.graphicsDeep(settings) { "
                               "RecipeSource.shared.markDeep(key) }\n",
                               "        RecipeSource.shared.markDeep(key)\n")], ["GEd"]),
    # #597, spec §11 PR-19: the coverage's depth follows the frame's (GMc, GMs, and GM and GMg,
    # whose members are drawn deep), stays 8-bit in an 8-bit row (GMe), and a matted frame the
    # generator answers deep is read again (GMf).
    "coverage-never-deep": ([(f"{SOURCES}/MetalRenderer.swift",
                              "            deep: RecipeSource.shared.deliversDeep(instruction?."
                              "recipeKey ?? 0))\n", "            deep: false)\n")],
                            ["GMc", "GMs", "GM", "GMg"]),
    "coverage-always-deep": ([(f"{SOURCES}/MetalRenderer.swift",
                               "            deep: RecipeSource.shared.deliversDeep(instruction?."
                               "recipeKey ?? 0))\n", "            deep: true)\n")], ["GMe"]),
    "frame-matte-not-reread": ([(f"{SOURCES}/Exporter+Frame.swift",
                                 "            drawsMatte(project, at: t, options: options)\n",
                                 "            false\n")], ["GMf"]),
    # #566, spec §11 PR-20: a graphic is a deep source of a saved frame (DG, DGf, DGv, and D5 and
    # D7, whose generator paths no longer read a graphic again), asked of the recipe at the frame
    # time (DGo), and its frame's pin is marked deep (DG, D1, DGv).
    "graphic-not-a-source": ([(f"{SOURCES}/DeepVideoFrame.swift",
                               "                && (Exporter.drawsGraphic(project, at: t, options: "
                               "options)\n                    || Exporter.drawsGradientShape(",
                               "                && (Exporter.drawsGradientShape(")],
                             ["DG", "DGf", "DGv", "D5", "D7"]),
    "graphic-anywhere": ([(f"{SOURCES}/DeepVideoFrame.swift",
                           "Exporter.drawsGraphic(project, at: t, options: options)",
                           "Playback.drawsGraphics(project.snapshot)")], ["DGo"]),
    "graphic-frame-pin-not-marked": ([(f"{SOURCES}/Exporter+Frame.swift",
                                       "            if keepsDepth { GraphicRegistry.shared.markDeep("
                                       "key) }\n", "")], ["DG", "D1", "DGv"]),
    # #605, spec §11 PR-21: a gradient shape is a deep source of a saved frame (G0, GV, and G5,
    # whose generator path no longer reads a gradient again), and a flat shape is not (DGo).
    "gradient-not-a-source": ([(f"{SOURCES}/DeepVideoFrame.swift",
                                "                    || Exporter.drawsGradientShape(project, at: "
                                "t, options: options)\n", "")], ["G0", "GV", "G5"]),
    "flat-shape-a-source": ([(f"{SOURCES}/ExporterGraphics.swift",
                              "$0.source { return props.drawsGradient }",
                              "$0.source { return props.drawsGradient || !props.drawsGradient }")],
                            ["DGo"]),
    # #604, spec §11 PR-22: the image block is an 8-bit PNG copy of a deep frame (BK1) and of a
    # HEIC (BK4), the file with `full_depth_image` (BK2, BK4), and the file of an 8-bit PNG (BK3).
    "block-is-the-file": ([(f"{SOURCES}/FrameBlock.swift",
                            "        guard !fullDepth, copies(image, as: format),",
                            "        guard false, !fullDepth, copies(image, as: format),")],
                          ["BK1", "BK4"]),
    "full-depth-ignored": ([(f"{SOURCES}/FrameBlock.swift",
                             "        guard !fullDepth, copies(image, as: format),",
                             "        guard copies(image, as: format),")], ["BK2", "BK4"]),
    "block-always-recoded": ([(f"{SOURCES}/FrameBlock.swift",
                               "        case .png: return image.bitsPerComponent > 8\n",
                               "        case .png: return true\n")], ["BK3"]),
    "heic-block-follows-file": ([(f"{SOURCES}/FrameBlock.swift",
                                  "        case .heic: return true\n",
                                  "        case .heic: return false\n")], ["BK4"]),
    # #611: the copy cannot be made in the BT.2100 HLG space only, so an HLG project's block
    # falls back to the 16-bit file (BK6) while every BT.709 block is a copy (`KEPT_ROWS`).
    "hlg-block-not-copied": ([(f"{SOURCES}/FrameBlock.swift",
                               "        guard labelled.width > 0, labelled.height > 0,",
                               "        guard !FrameWriter.isHLG(labelled), labelled.width > 0, "
                               "labelled.height > 0,")], ["BK6"]),
    # #610, spec §11 PR-23: a default block whose base64 would pass the limit is drawn smaller
    # until it fits (BKk, BKp, BKj), one that fits is untouched (BK1, BK3), `full_depth_image` is
    # exempt (BK2), the test is on the base64 (BKk: its unscaled block is 5,086,992 raw bytes,
    # under 5,242,880, and 6,782,656 as base64), the sentence says so, a JPEG's block stays a
    # JPEG (BKj) and the aspect is kept (BKk, BKp).
    "block-not-bounded": ([(f"{SOURCES}/FrameBlock.swift",
                            "        4 * ((data.count + 2) / 3) <= limit\n", "        true\n")],
                          ["BKk", "BKp", "BKj"]),
    "block-always-scaled": ([(f"{SOURCES}/FrameBlock.swift",
                              "        guard !fullDepth, !fits(whole.data),\n",
                              "        guard !fullDepth,\n")], ["BK1", "BK3"]),
    "full-depth-scaled": ([(f"{SOURCES}/FrameBlock.swift",
                            "        guard !fullDepth, !fits(whole.data),\n",
                            "        guard !fits(whole.data),\n")], ["BK2"]),
    "limit-counts-raw-bytes": ([(f"{SOURCES}/FrameBlock.swift",
                                 "        4 * ((data.count + 2) / 3) <= limit\n",
                                 "        data.count <= limit\n")], ["BKk"]),
    "scale-sentence-dropped": ([(f"{SOURCES}/FrameBlock.swift",
                                 "            note: [whole.note, scaleNote(width: scaled.width, "
                                 "height: scaled.height)]\n                .compactMap { $0 }"
                                 ".joined(separator: \" \"))\n",
                                 "            note: whole.note)\n")], ["BKk", "BKp", "BKj"]),
    "scaled-jpeg-as-png": ([(f"{SOURCES}/FrameBlock.swift",
                             "        format == .jpeg ? .jpeg : .png\n", "        .png\n")],
                           ["BKj"]),
    "aspect-not-kept": ([(f"{SOURCES}/FrameBlock.swift",
                          "            let size = Exporter.scaledSize(full, to: next)\n",
                          "            let size = CGSize(width: next, height: labelled.height)\n")],
                        ["BKk", "BKp"]),
}
# The rows an app mutant must leave PASSING, beside the ones it must fail: what tells a mutant
# that acts in one case from one that acts in all (#611: `block-is-the-file` fails BK6 too).
# A mutant with no row here is scored on its failing rows alone.
KEPT_ROWS = {"hlg-block-not-copied": ["BK1", "BK2", "BK3", "BK4", "BK5"]}
# Spec §11 PR-24 (#612): what `render_frame`'s and `max_width`'s descriptions say of the API's
# limits on an image, and the attribution PR-24 corrected.
SIDES_SAID = ["8000 px", "3000 px", "more than 20 images", "2576 px", "10 MB", "Amazon Bedrock",
              "max_width is the caller's control"]
WIDTH_SAID = ["8000 px", "3000 px", "2576 px", "the height follows"]
OLD_ATTRIBUTION = "Anthropic API's 5 MB"
CORE_PATCH = "[patch.crates-io]\n"

rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def attempt(client, tool, arguments):
    try:
        answer = (client.export_with(arguments) if tool == "export"
                  else client.call_with(tool, arguments))
        return {"ok": True, "reply": answer}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


# ---- reading pictures -------------------------------------------------------------

class Picture:
    """A decoded frame: width, height, channels (RGBA or RGB) and its samples
    as stored (`array`); `at` answers 8-bit levels (a 16-bit sample / 257)."""

    def __init__(self, width, height, channels, samples, scale=1.0):
        self.width, self.height, self.channels = width, height, channels
        self.samples, self.scale = samples, scale

    def at(self, x, y, c):
        return self.samples[(y * self.width + x) * self.channels + c] / self.scale

    def g(self, x, y):
        return self.at(x, y, 1)

    def crop(self, x0, y0, width, height):
        """The `width`×`height` block at (x0, y0) as a Picture."""
        out = array.array(self.samples.typecode)
        for y in range(y0, y0 + height):
            start = (y * self.width + x0) * self.channels
            out.extend(self.samples[start:start + width * self.channels])
        return Picture(width, height, self.channels, out, self.scale)


def png_header(path):
    """(width, height, bit depth) off a PNG's IHDR, or None."""
    data = Path(path).read_bytes()[:25]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">IIB", data[16:25])


def ffmpeg_raw(path, pix_fmt, seek=None):
    argv = ["ffmpeg", "-nostdin", "-v", "error"] + (["-ss", seek] if seek else []) + [
        "-i", str(path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pix_fmt, "-"]
    try:
        return subprocess.run(argv, capture_output=True, timeout=TOOL_BOUND,
                              env=bounded.child_env()).stdout or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def read_png(path):
    """A PNG as RGBA: an 8-bit one decoded to `rgba`, a 16-bit one to
    `rgba64le` (ffmpeg's 8 → 16-bit conversion is not exact), or None."""
    if path is None or not Path(path).exists():
        return None
    header = png_header(path)
    if header is None:
        return None
    width, height, depth = header
    deep = depth == 16
    raw = ffmpeg_raw(path, "rgba64le" if deep else "rgba")
    if raw is None or len(raw) != width * height * (8 if deep else 4):
        return None
    if not deep:
        return Picture(width, height, 4, array.array("B", raw))
    words = array.array("H")
    words.frombytes(raw)
    if sys.byteorder != "little":
        words.byteswap()
    return Picture(width, height, 4, words, 257.0)


def read_movie(path, seek, deep):
    """The frame at `seek` s of a 1920×1080 movie as rgb48le (`deep`) or
    rgb24, or None."""
    if path is None or not Path(path).exists():
        return None
    raw = ffmpeg_raw(path, "rgb48le" if deep else "rgb24", seek=str(seek))
    if raw is None or len(raw) != W * H * (6 if deep else 3):
        return None
    if not deep:
        return Picture(W, H, 3, array.array("B", raw))
    words = array.array("H")
    words.frombytes(raw)
    if sys.byteorder != "little":
        words.byteswap()
    return Picture(W, H, 3, words, 257.0)


def deep_row(picture):
    """Row 540, x 0–800, G as stored 16-bit values, or None for an 8-bit picture."""
    if picture is None or picture.scale != 257.0:
        return None
    return [picture.samples[(540 * picture.width + x) * picture.channels + 1] for x in range(801)]


def fixture(name, arguments):
    """An ffmpeg-made fixture in WORK, or None."""
    out = WORK / name
    got = bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *arguments, str(out)], TOOL_BOUND,
                      env=bounded.child_env())
    if got["rc"] != 0 or not out.exists():
        print(f"       fixture {name}: rc {got['rc']} {got['stderr'][-300:]}", flush=True)
        return None
    return out


def exact(x, y):
    """`band374`'s exact G in levels at pixel (x, y)'s centre."""
    t = min(math.hypot(x + 0.5 - CX, y + 0.5 - CY) / RADIUS, 1.0)
    return INNER[1] + (OUTER[1] - INNER[1]) * t


def shape_exact(x, y):
    """`shape563`'s exact G in levels at pixel (x, y)'s centre."""
    return SHAPE_FROM[1] + (SHAPE_TO[1] - SHAPE_FROM[1]) * (x + 0.5) / W


def matte_exact(x, y):
    """GM's exact G in levels: `shape563`'s Rec. 709 luma at pixel (x, y)'s
    centre, which a `luma` matte over a white card on black shows as is."""
    t = (x + 0.5) / W
    return sum(w * (a + (b - a) * t) for w, a, b in zip(LUMA, SHAPE_FROM, SHAPE_TO))


def band_matte_exact(x, y):
    """GMg's exact G in levels: `band374`'s Rec. 709 luma at pixel (x, y)'s centre."""
    t = min(math.hypot(x + 0.5 - CX, y + 0.5 - CY) / RADIUS, 1.0)
    return sum(w * (a + (b - a) * t) for w, a, b in zip(LUMA, INNER, OUTER))


def ramp_exact(x, y):
    """GMc's and GMs's exact G in levels: precision_proof's ramps hold column
    x at x / 1919 of full scale, grey, so a `luma` matte of either over a
    white card on black shows it as is."""
    return 255.0 * x / RAMP_LAST


def deep_distinct(picture):
    """How many distinct stored 16-bit greens row 540, x 0–800, holds, or None
    for an 8-bit picture or none."""
    values = deep_row(picture)
    return None if values is None else len(set(values))


# ---- the figures --------------------------------------------------------------------

def runs(picture):
    """Row 540, x 0–800, G rounded to 8-bit levels: (distinct levels, median
    run, widest run)."""
    values = [round(picture.g(x, 540)) for x in range(800)]
    lengths, length = [], 1
    for a, b in zip(values, values[1:]):
        if a == b:
            length += 1
        else:
            lengths.append(length)
            length = 1
    lengths.append(length)
    return len(set(values)), statistics.median(lengths), max(lengths)


def block_means(picture, y=540):
    return [sum(picture.g(x, y) for x in range(x0, x0 + 50)) / 50 for x0 in range(0, 800, 50)]


def increasing(values):
    return all(b > a for a, b in zip(values, values[1:]))


def bracket_misses(picture):
    misses, first = 0, None
    for y in range(500, 581):
        for x in range(800):
            e, v = exact(x, y), picture.g(x, y)
            if not math.floor(e - 1 / 16) - 1e-6 <= v <= math.ceil(e + 1 / 16) + 1e-6:
                misses += 1
                first = first or f"({x}, {y}) G {v:.3f}, e {e:.3f}"
    return misses, first


def block_bias(picture, e=None):
    """Rows 500–580, 16-px column blocks over x 0–800: max |mean(G − e)|, `e`
    `band374`'s unless a function is given."""
    e = e or exact
    worst = 0.0
    for x0 in range(0, 800, 16):
        gaps = [picture.g(x, y) - e(x, y) for y in range(500, 581) for x in range(x0, x0 + 16)]
        worst = max(worst, abs(sum(gaps) / len(gaps)))
    return worst


def banding(picture):
    """B4's figure: column means of G over rows 530–550, less a 31-column
    moving average, RMS over x 32–768."""
    means = [sum(picture.g(x, y) for y in range(530, 551)) / 21 for x in range(800)]
    gaps = [means[x] - sum(means[x - 15:x + 16]) / 31 for x in range(32, 769)]
    return math.sqrt(sum(g * g for g in gaps) / len(gaps))


def noise(picture):
    """The per-pixel noise kept: RMS of G less its column mean over rows
    530–550, x 32–768."""
    gaps = []
    for x in range(32, 769):
        column = [picture.g(x, y) for y in range(530, 551)]
        mean = sum(column) / len(column)
        gaps.extend(v - mean for v in column)
    return math.sqrt(sum(g * g for g in gaps) / len(gaps))


def pixel_error(picture, cx=CX, e=None):
    """Rows 530–550, x 32–768: RMS of G − e less its mean (a decode's constant
    offset is not the raster's), `e` for a gradient centred at `cx`, or the
    function `e` when one is given."""
    gaps = []
    for y in range(530, 551):
        for x in range(32, 769):
            if e is not None:
                gaps.append(picture.g(x, y) - e(x, y))
                continue
            t = min(math.hypot(x + 0.5 - cx, y + 0.5 - CY) / RADIUS, 1.0)
            gaps.append(picture.g(x, y) - (INNER[1] + (OUTER[1] - INNER[1]) * t))
    mean = sum(gaps) / len(gaps)
    return math.sqrt(sum((g - mean) ** 2 for g in gaps) / len(gaps))


def movie_figures(path, seek, deep):
    """(banding, noise, row-540 runs, block means, bytes) of a movie, or None."""
    movie = read_movie(path, seek, deep)
    if movie is None:
        return None
    return (banding(movie), noise(movie), runs(movie), block_means(movie),
            Path(path).stat().st_size)


def shown(figures):
    if figures is None:
        return "not read"
    band, kept, (levels, median, widest), _, size = figures
    return (f"banding RMS {band:.4f}, noise kept {kept:.4f}, row 540 {levels} levels, median "
            f"run {median}, widest {widest}, {size} bytes")


def band_rows(row, picture, control, scope):
    """B1 (or B3) and B2's rules over `picture` against `control`."""
    first = row
    if picture is None:
        check(f"{first} {scope}: not read", False)
        if row == "B1":
            check(f"B2 {scope}: not read", False)
        return
    levels, median, widest = runs(picture)
    means = block_means(picture)
    misses, where = bracket_misses(picture)
    then = runs(control) if control else None
    figures = (f"row 540 x 0–800 G: {levels} levels, median run {median}, widest {widest}; "
               f"control: {then[0]} levels, median run {then[1]}, widest {then[2]}"
               if then else f"row 540 x 0–800 G: {levels} levels, median run {median}, widest "
               f"{widest}; no control")
    good = (then is not None and median <= then[1] / 2 and increasing(means) and misses == 0)
    check(f"{first} {scope}: median run ≤ ½ the control's, 50-px block means strictly increase, "
          "every G in rows 500–580 x 0–800 within [floor(e − 1/16), ceil(e + 1/16)]", good,
          f"{figures}\n       block means {[round(m, 2) for m in means]}\n       "
          f"{misses} outside the bracket{f', first {where}' if where else ''}")
    bias = block_bias(picture)
    was = block_bias(control) if control else None
    label = "B2 B1's cell" if row == "B1" else "B3 (B2's rule)"
    check(f"{label}: rows 500–580, 16-px blocks over x 0–800, max |mean(G − e)| ≤ 0.1",
          was is not None and bias <= 0.1,
          f"max |mean(G − e)| {bias:.4f}; control's {f'{was:.4f}' if was is not None else 'none'}")


# ---- the app rows -------------------------------------------------------------------

class Doc:
    def __init__(self, client, name, module=None, source=None):
        """`module` None makes a project with no graphic module (PR-16's rows:
        a shape's depth must not depend on a graphic set)."""
        self.client, self.name, self.module = client, name, module
        self.path = WORK / f"{name}.framejob"
        steps = [attempt(client, "new_project", {"path": str(self.path)})["ok"]]
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        canvas = self.project().get("canvas") or {}
        steps.append(canvas.get("width") == W and canvas.get("height") == H
                     and canvas.get("fps") == [30, 1])
        wrote = {}
        if module is not None:
            wrote = reply(self.call("write_graphic", name=module, source=source))
            steps.append(bool(wrote.get("ok")))
        self.ok = all(steps)
        self.why = None if self.ok else f"project, canvas, write_graphic: {steps} {wrote}"

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def clip(self, seconds=1, track=None, at=0):
        """A `seconds` clip of the module at `at`, covering the canvas, on the
        first track (made when there is none) or on `track`."""
        tracks = self.project().get("tracks") or []
        if not tracks:
            self.call("add_track")
            tracks = self.project().get("tracks") or []
        if not tracks:
            return False, "no track"
        deadline, got = time.monotonic() + 5, {"error": "not tried"}
        while time.monotonic() < deadline:
            got = self.call("add_graphic_clip", track=track or tracks[0]["id"], at=at,
                            duration=seconds * SEC, name=self.module)
            if got["ok"]:
                return True, ""
            time.sleep(0.2)
        return False, got.get("error")

    def shape_clip(self, shape, video=None, seconds=1, at=0):
        """A `seconds` shape clip at `at` on a NEW track (kept as `self.track`),
        with `video` patched on it."""
        fresh = [self.new_track()]
        if fresh[0] is None:
            return False, "no new track"
        clips = {clip["id"] for clip in self.project().get("clips") or []}
        got = self.call("add_shape_clip", track=fresh[0], at=at, duration=seconds * SEC,
                        shape=shape)
        made = [clip["id"] for clip in self.project().get("clips") or []
                if clip["id"] not in clips]
        if not (got["ok"] and len(made) == 1):
            return False, got.get("error", f"{len(made)} new clips")
        if video:
            got = self.call("set_video", clips=made, patch=video)
        return got["ok"], got.get("error", "")

    def new_track(self):
        """A new track's id (kept as `self.track`), or None."""
        before = {track["id"] for track in self.project().get("tracks") or []}
        self.call("add_track")
        fresh = [track["id"] for track in self.project().get("tracks") or []
                 if track["id"] not in before]
        self.track = fresh[0] if fresh else None
        return self.track

    def luma_matte(self):
        """`self.track` made a `luma` matte, in front of every other track and
        read back: (True, "") or (False, why)."""
        got = self.call("set_track", track=self.track, matte="luma")
        tracks = self.project().get("tracks") or []
        mine = [track for track in tracks if track.get("id") == self.track]
        if not (got["ok"] and mine and mine[0].get("matte") == "luma"):
            return False, f"set_track matte: {got.get('error', mine)}"
        if tracks[-1].get("id") != self.track or len(tracks) < 2:
            return False, f"the matte track is not in front: {[t.get('id') for t in tracks]}"
        return True, ""

    def sheet(self, file, **extra):
        out = WORK / file
        out.unlink(missing_ok=True)
        got = self.call("render_graphic", name=self.module, width=W, height=H, path=str(out),
                        **extra)
        if not (got["ok"] and out.exists()):
            print(f"       render_graphic {file}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def frame(self, file, t=SEC // 2, **extra):
        out = WORK / file
        out.unlink(missing_ok=True)
        started = time.monotonic()
        got = self.call("render_frame", t=t, path=str(out), **extra)
        FRAME_SECONDS[file] = time.monotonic() - started
        if not (got["ok"] and out.exists()):
            print(f"       render_frame {file}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def frame_block(self, file, block_file, t=SEC // 2, **extra):
        """`frame` through `mcp.call_content`, which keeps the image block (spec §11 PR-22):
        {ok, file, block (its decoded bytes kept as `block_file`), mime, b64 (the block's base64
        length, what the assistant's helper forwards), text}, or {ok: False, error}."""
        out, kept = WORK / file, WORK / block_file
        out.unlink(missing_ok=True)
        kept.unlink(missing_ok=True)
        started = time.monotonic()
        try:
            content = self.client.call_content(
                "render_frame", dict(extra, t=t, path=str(out), project=str(self.path)))
        except mcp.ToolError as error:
            return {"ok": False, "error": str(error)}
        except Exception as error:  # a socket timeout is the expiry
            return {"ok": False, "error": f"{type(error).__name__}: {error}"}
        FRAME_SECONDS[file] = time.monotonic() - started
        images = [part for part in content if part.get("type") == "image"]
        text = "".join(part.get("text", "") for part in content if part.get("type") == "text")
        if len(images) != 1 or not out.exists():
            return {"ok": False, "error": f"{len(images)} image blocks, file {out.exists()}: {text}"}
        data = images[0].get("data") or ""
        kept.write_bytes(base64.b64decode(data))
        return {"ok": True, "file": out, "block": kept, "mime": images[0].get("mimeType"),
                "b64": len(data), "text": text}

    def apng(self, file):
        """PR-20's 8-bit door: the in/out range `APNG_RANGE` exported `apng` at
        1920×1080 (its first frame is read), or None."""
        got = self.call("set_range", start=APNG_RANGE[0], end=APNG_RANGE[1])
        if not got["ok"]:
            print(f"       set_range for {file}: {got.get('error')}", flush=True)
            return None
        return self.export(file, preset="apng", range="in_out", size=[W, H])

    def export(self, file, **arguments):
        out = WORK / file
        out.unlink(missing_ok=True)
        got = self.call("export", path=str(out), **arguments)
        if not (got["ok"] and out.exists()):
            print(f"       export {file}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def media_clip(self, path, index=None):
        """`path` imported and placed at 0 on a NEW track (at `index`: 0 is the
        back-most), at its own size at the canvas centre (smaller than the
        canvas, so nothing fits it)."""
        if path is None:
            return False, "no fixture"
        got = self.call("import_media", path=str(path))
        media = reply(got).get("media")
        if media is None:
            return False, f"import_media: {got.get('error', got)}"
        before = {track["id"] for track in self.project().get("tracks") or []}
        self.call("add_track", **({} if index is None else {"index": index}))
        fresh = [track["id"] for track in self.project().get("tracks") or []
                 if track["id"] not in before]
        if not fresh:
            return False, "no new track"
        got = self.call("add_clip", track=fresh[0], media=media, at=0)
        return got["ok"], got.get("error", "")

    def canvas_media(self, path, seconds=1):
        """`path` imported and placed at 0 on a NEW track (kept as `self.track`),
        `seconds` long, read back covering the canvas exactly: its media W×H and
        the clip at scale 1, centred. (True, "") or (False, why)."""
        if path is None:
            return False, "no fixture"
        got = self.call("import_media", path=str(path))
        media = reply(got).get("media")
        if media is None:
            return False, f"import_media: {got.get('error', got)}"
        if self.new_track() is None:
            return False, "no new track"
        before = {clip["id"] for clip in self.project().get("clips") or []}
        got = self.call("add_clip", track=self.track, media=media, at=0)
        made = [clip for clip in self.project().get("clips") or [] if clip["id"] not in before]
        if not (got["ok"] and len(made) == 1):
            return False, f"add_clip: {got.get('error', f'{len(made)} new clips')}"
        if made[0].get("duration") != seconds * SEC:
            got = self.call("trim_end", clip=made[0]["id"], to=seconds * SEC)
            if not got["ok"]:
                return False, f"trim_end: {got.get('error')}"
        project = self.project()
        clip = [c for c in project.get("clips") or [] if c["id"] == made[0]["id"]]
        item = [m for m in project.get("media") or [] if m.get("id") == media]
        video = (clip[0].get("video") or {}) if clip else {}
        size = [item[0].get("width"), item[0].get("height")] if item else None
        placed = (clip and clip[0].get("start") == 0 and clip[0].get("duration") == seconds * SEC
                  and size == [W, H] and video.get("scale") == 1 and video.get("x") == 0
                  and video.get("y") == 0)
        return bool(placed), "" if placed else (
            f"read back: media size {size}, clip {clip[0].get('start') if clip else None}+"
            f"{clip[0].get('duration') if clip else None}, video scale {video.get('scale')} "
            f"at ({video.get('x')}, {video.get('y')})")

    def close(self):
        return attempt(self.client, "close_project", {"project": str(self.path),
                                                       "discard": True})["ok"]


def cell(picture, index=0):
    """Cell `index` of a scale-1 sheet (1920×1080 at x = index × 1928), or None."""
    if picture is None or picture.height < H or picture.width < index * (W + 8) + W:
        return None
    return picture.crop(index * (W + 8), 0, W, H)


def same(a, b):
    return a is not None and b is not None and a.samples == b.samples


def run(client, files):
    closed = True
    band = Doc(client, "band", "band374", BAND_JS)
    if not band.ok:
        print(f"       band project: {band.why}", flush=True)
    if band.ok and selected & {"B1", "B2", "S1", "E1"}:
        files["B1"] = band.sheet(FILES["B1"], frames=[0])
    if band.ok and selected & {"S1", "E1"}:
        files["S1"] = band.sheet(FILES["S1"], frames=[0, 30], max_width=8192)
    if band.ok and selected & {"B3", "B4a", "E1", "D3", "DG", "DGj"}:
        made, why = band.clip()
        if not made:
            print(f"       band clip: {why}", flush=True)
        else:
            # B3's frame is PR-20's DG since a graphic is a deep source; B3 and E1 read the
            # APNG door's frame of the same project.
            if "DG" in selected:
                files["B3"] = band.frame(FILES["B3"])
                files["DGh"] = band.frame(FILES["DGh"])
            if "DGj" in selected:
                files["DGj"] = band.frame(FILES["DGj"])
            if selected & {"B3", "E1"}:
                files["B3a"] = band.apng(FILES["B3a"])
            if selected & {"B4a", "D3"}:
                files["B4a"] = band.export(FILES["B4a"], preset="prores_422")
            if "B4a" in selected:
                for row, _, project, arguments, _ in LIMITS:
                    if project == "band":
                        files[row] = band.export(FILES[row], **arguments)
    closed = band.close() and closed
    if selected & {"B4b", "D4"}:
        moving = Doc(client, "moving", "band374m", MOVING_JS)
        made, why = moving.clip(5) if moving.ok else (False, moving.why)
        if made:
            files["B4b"] = moving.export(FILES["B4b"], preset="hevc_10bit")
            for row, _, project, arguments, _ in LIMITS:
                if project == "moving" and "B4b" in selected:
                    files[row] = moving.export(FILES[row], **arguments)
        else:
            print(f"       moving project: {why}", flush=True)
        closed = moving.close() and closed
    closed = run_deep(client, files) and closed
    closed = run_shapes(client, files) and closed
    closed = run_graphic_sources(client, files) and closed
    closed = run_blocks(client, files) and closed
    flat = Doc(client, "flat", "flat", FLAT_JS)
    if not flat.ok:
        print(f"       flat project: {flat.why}", flush=True)
    if flat.ok and selected & {"F1", "E1"}:
        files["F1"] = flat.sheet(FILES["F1"], frames=[0])
    if flat.ok and selected & {"F2", "E1", "DGf"}:
        made, why = flat.clip()
        if made:
            # F2's frame is PR-20's DGf; F2 and E1 read the APNG door's frame.
            if "DGf" in selected:
                files["F2"] = flat.frame(FILES["F2"])
            if selected & {"F2", "E1"}:
                files["F2a"] = flat.apng(FILES["F2a"])
        else:
            print(f"       flat clip: {why}", flush=True)
    closed = flat.close() and closed
    return closed


def run_graphic_sources(client, files):
    """Spec §11 PR-20's projects (#566): `band374` over an 8-bit H.264 clip (DGv), a `band374`
    clip followed by a flat shape (DGo), and DGs's printed sizes, each when selected."""
    closed = True
    if "DGv" in selected:
        doc = Doc(client, "graphich264", "band374", BAND_JS)
        made, why = doc.clip() if doc.ok else (False, doc.why)
        if made:
            made, why = doc.media_clip(fixture("dgvh264.mov", [
                "-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p",
                "-c:v", "h264_videotoolbox", "-b:v", "2M"]))
        if made:
            files["DGv"] = doc.frame(FILES["DGv"])
        else:
            print(f"       DGv project: {why}", flush=True)
        closed = doc.close() and closed
    if "DGo" in selected:
        doc = Doc(client, "graphicthenshape", "band374", BAND_JS)
        made, why = doc.clip() if doc.ok else (False, doc.why)
        if made:
            made, why = doc.shape_clip(*FLAT_SHAPES[0], at=SEC)
        if made:
            files["DGo"] = doc.frame(FILES["DGo"])
            files["DGo2"] = doc.frame(FILES["DGo2"], t=3 * SEC // 2)
        else:
            print(f"       DGo project: {why}", flush=True)
        closed = doc.close() and closed
    if "DGs" in selected:
        closed = run_sizes(client, files) and closed
    return closed


def run_sizes(client, files):
    """DGs (printed, not scored): the PNG `render_frame` answers, and the assistant's helper
    forwards as base64, for a 1920×1080 frame of camera footage: an 8-bit H.264 cut of the
    owner's iPhone clip under the `flat` graphic (PR-20's new case), the same cut beside a 64×64
    16-bit still, and the iPhone clip itself (10-bit HEVC; both already deep before PR-20);
    each unscaled and at `max_width` 1280."""
    if not OWNER_CLIP.exists():
        print(f"  --   DGs (NOT scored) no fixture: {OWNER_CLIP} is absent", flush=True)
        return True
    closed = True
    cut = fixture("dgs-owner-8bit.mov", [
        "-i", str(OWNER_CLIP), "-t", "1", "-an", "-vf", "format=yuv420p", "-c:v",
        "h264_videotoolbox", "-b:v", "20M", "-color_primaries", "bt709", "-color_trc", "bt709",
        "-colorspace", "bt709"])
    still = fixture("dgs-still16.png", ["-f", "lavfi", "-i", "color=c=gray:size=64x64",
                                        "-frames:v", "1", "-pix_fmt", "rgb48be"])
    for key, name, source, beside in [("DGsg", "sizegraphic", cut, "graphic"),
                                      ("DGss", "sizestill", cut, still),
                                      ("DGsi", "sizeiphone", OWNER_CLIP, None)]:
        doc = Doc(client, name, "flat", FLAT_JS) if beside == "graphic" else Doc(client, name)
        made, why = doc.canvas_media(source) if doc.ok else (False, doc.why)
        if made and beside == "graphic":
            made, why = ((False, "no new track") if doc.new_track() is None
                         else doc.clip(track=doc.track))
        elif made and beside is not None:
            made, why = doc.media_clip(beside)
        if made:
            # Spec §11 PR-22: each frame's default image block is kept beside its file.
            for suffix, extra in [("", {}), ("1280", {"max_width": 1280})]:
                got = doc.frame_block(FILES[key + suffix], f"{key.lower()}{suffix}-block.png",
                                      **extra)
                BLOCKS[key + suffix] = got
                files[key + suffix] = got["file"] if got["ok"] else None
                if not got["ok"]:
                    print(f"       render_frame {key + suffix}: {got['error']}", flush=True)
        else:
            print(f"       {key} project: {why}", flush=True)
        closed = doc.close() and closed
    return closed


def run_blocks(client, files):
    """Spec §11 PR-22's frames (#604), each through `Doc.frame_block`: `blk1080` under `flat`
    (BK1, BK2, BK4), alone (BK3, BK5), and an HLG project's `band374` clip, D6's recipe under its
    own name (BK6, #611); PR-23's 3840×2160 frames (#610), `blk2160` under `flat` (BKk) and alone
    (BKp), and a noise still as a JPEG (BKj)."""
    closed = True
    clip = (fixture("blk1080.mov", block_footage("1920x1080"))
            if selected & {"BK1", "BK2", "BK3", "BK4", "BK5"} else None)
    clip4k = (fixture("blk2160.mov", block_footage("3840x2160"))
              if selected & {"BKk", "BKp"} else None)
    asks = []
    if selected & {"BK1", "BK2", "BK4"}:
        asks.append(("blockgraphic", clip, None, [
            ("BK1", "BK1", "BK1b", {}), ("BK2", "BK2", "BK2b", {"full_depth_image": True}),
            ("BK4", "BK4", "BK4b", {}), ("BK4", "BK4f", "BK4fb", {"full_depth_image": True})]))
    if selected & {"BK3", "BK5"}:
        asks.append(("blockplain", clip, None, [
            ("BK3", "BK3", "BK3b", {}),
            ("BK5", "BK5", "BK5b", {"full_depth_image": "yes"})]))
    if "BKk" in selected:
        asks.append(("block4k", clip4k, (3840, 2160), [("BKk", "BKk", "BKkb", {})]))
    if "BKp" in selected:
        asks.append(("block4kplain", clip4k, (3840, 2160), [("BKp", "BKp", "BKpb", {})]))
    if "BKj" in selected:
        asks.append(("block4kjpeg", fixture("noise2160.png", NOISE_STILL), (3840, 2160),
                     [("BKj", "BKj", "BKjb", {"format": "jpeg"})]))
    for name, media, size, frames in asks:
        graphic = name in {"blockgraphic", "block4k"}
        doc = Doc(client, name, "flat", FLAT_JS) if graphic else Doc(client, name)
        made, why = (True, "") if doc.ok else (False, doc.why)
        if made and size:
            got = doc.call("set_canvas", width=size[0], height=size[1])
            made, why = got["ok"], f"set_canvas: {got.get('error', '')}"
            # At its own size, centred: the canvas's size, so it covers it.
            made, why = doc.media_clip(media) if made else (made, why)
        elif made:
            made, why = doc.canvas_media(media)
        if made and graphic:
            made, why = ((False, "no new track") if doc.new_track() is None
                         else doc.clip(track=doc.track))
        if not made:
            print(f"       {name} project: {why}", flush=True)
        for row, key, block, extra in frames if made else []:
            if row not in selected:
                continue
            BLOCKS[key] = doc.frame_block(FILES.get(key, f"{key.lower()}-frame.png"),
                                          FILES.get(block, f"{key.lower()}-block.png"), **extra)
            if BLOCKS[key]["ok"]:
                files[key], files[block] = BLOCKS[key]["file"], BLOCKS[key]["block"]
        closed = doc.close() and closed
    if "BK6" in selected:
        # A graphic alone is deep (PR-20), and the HLG project's frame is labelled BT.2100 HLG,
        # the space the copy is drawn in. The canvas is read back, or the row is BK1 again.
        doc = Doc(client, "blockhlg", "band374", BAND_JS)
        made, why = doc.clip() if doc.ok else (False, doc.why)
        if made:
            got = doc.call("set_canvas", output="hlg")
            made, why = got["ok"], f"set_canvas: {got.get('error', '')}"
        if made:
            BLOCKS["BK6output"] = (doc.project().get("canvas") or {}).get("output")
            BLOCKS["BK6"] = doc.frame_block(FILES["BK6"], FILES["BK6b"])
            if BLOCKS["BK6"]["ok"]:
                files["BK6"], files["BK6b"] = BLOCKS["BK6"]["file"], BLOCKS["BK6"]["block"]
        else:
            print(f"       blockhlg project: {why}", flush=True)
        closed = doc.close() and closed
    if selected & {"BK5", "BKd"}:
        try:
            schema = client.schemas().get("render_frame") or {}
        except Exception as error:  # a socket timeout is the expiry
            schema = {"error": f"{type(error).__name__}: {error}"}
        BLOCKS["BK5schema"] = ((schema.get("inputSchema") or {}).get("properties")
                               or {}).get("full_depth_image") or {}
        # Spec §11 PR-24 (#612): the whole tool, for its descriptions.
        BLOCKS["BKdtool"] = schema
    return closed


def run_deep(client, files):
    """PR-15's frames: D1 (a deep still beside the graphic), D5 (a 10-bit HEVC
    clip beside it) and D6 (an HLG project)."""
    closed = True
    plans = []
    if "D1" in selected:
        still = fixture("still16.png", ["-f", "lavfi", "-i", "color=c=gray:size=64x64", "-frames:v",
                                        "1", "-pix_fmt", "rgb48be"])
        plans.append(("D1", "deepstill", still, None))
    if "D5" in selected:
        movie = fixture("hevc10.mov", [
            "-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p10le",
            "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v",
            "hvc1", "-b:v", "2M"])
        plans.append(("D5", "deephevc", movie, None))
    if "D7" in selected:
        movie = fixture("hevc10b.mov", [
            "-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p10le",
            "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v",
            "hvc1", "-b:v", "2M"])
        under = fixture("h264.mov", [
            "-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p",
            "-c:v", "h264_videotoolbox", "-b:v", "2M"])
        plans.append(("D7", "deepreread", movie, under))
    if "D6" in selected:
        plans.append(("D6", "hlg", None, "hlg"))
    for row, name, media, output in plans:
        back = output if row == "D7" else None
        output = None if row == "D7" else output
        doc = Doc(client, name, "band374", BAND_JS)
        made, why = doc.clip() if doc.ok else (False, doc.why)
        if made and output:
            got = doc.call("set_canvas", output=output)
            made, why = got["ok"], got.get("error", "")
        if made and output is None:
            made, why = doc.media_clip(media)
        if made and row == "D7":
            made, why = doc.media_clip(back, index=0)
        if made:
            files[row] = doc.frame(FILES[row])
        else:
            print(f"       {row} project: {why}", flush=True)
        closed = doc.close() and closed
    return closed


def run_shapes(client, files):
    """PR-16's frames and exports: `shape563` alone (G0, G3, G4), beside a deep
    still (G1), a 10-bit HEVC clip (G5), that clip over an H.264 one (G7), in
    an HLG project (G6, GEb), and flat shapes beside the still (GEc)."""
    closed = True
    hevc = ["-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p10le",
            "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v",
            "hvc1", "-b:v", "2M"]
    still = ["-f", "lavfi", "-i", "color=c=gray:size=64x64", "-frames:v", "1", "-pix_fmt",
             "rgb48be"]
    h264 = ["-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p",
            "-c:v", "h264_videotoolbox", "-b:v", "2M"]
    # (the rows that want it, name, the shapes, media in front, media at the back, output)
    plans = [
        ({"G0", "G3", "GEa", "GEd"}, "shape", [(SHAPE_563, None)], None, None, None),
        ({"GV"}, "shapeh264", [(SHAPE_563, None)], ("gvh264.mov", h264), None, None),
        ({"G1"}, "shapestill", [(SHAPE_563, None)], ("gstill16.png", still), None, None),
        ({"G5"}, "shapehevc", [(SHAPE_563, None)], ("ghevc10.mov", hevc), None, None),
        ({"G7"}, "shapereread", [(SHAPE_563, None)], ("ghevc10b.mov", hevc), ("gh264.mov", h264),
         None),
        ({"G6", "GEb"}, "shapehlg", [(SHAPE_563, None)], None, None, "hlg"),
        ({"GEc"}, "shapeflat", FLAT_SHAPES, ("gstill16b.png", still), None, None),
    ]
    for wanted, name, shapes, front, back, output in plans:
        if not selected & wanted:
            continue
        doc = Doc(client, name)
        made, why = (True, "") if doc.ok else (False, doc.why)
        for shape, video in shapes:
            if made:
                made, why = doc.shape_clip(shape, video)
        if made and output:
            got = doc.call("set_canvas", output=output)
            made, why = got["ok"], got.get("error", "")
        if made and front:
            made, why = doc.media_clip(fixture(*front))
        if made and back:
            made, why = doc.media_clip(fixture(*back), index=0)
        if not made:
            print(f"       {name} project: {why}", flush=True)
        elif name == "shape":
            if selected & {"G0", "GEa"}:
                files["G0"] = doc.frame(FILES["G0"])
            if "G0" in selected:
                files["G0h"] = doc.frame(FILES["G0h"])
            if "GEa" in selected:
                # Spec §11 PR-21: G0's PNG is deep, so the 8-bit path is read through the APNG door.
                files["GEa"] = doc.apng(FILES["GEa"])
            if "G3" in selected:
                files["G3"] = doc.export(FILES["G3"], preset="prores_422")
                files["G4"] = doc.export(FILES["G4"], preset="hevc_10bit")
            if "GEd" in selected:
                files["GEd"] = doc.export(FILES["GEd"], preset="h264")
        elif name == "shapehlg":
            if "G6" in selected:
                files["G6"] = doc.frame(FILES["G6"])
            if "GEb" in selected:
                files["GEb"] = doc.frame(FILES["GEb"])
        else:
            row = sorted(wanted)[0]
            files[row] = doc.frame(FILES[row])
        closed = doc.close() and closed
    if selected & {"GM", "GMg"}:
        closed = run_mattes(client, files) and closed
    if selected & {"GMc", "GMs", "GMe", "GMf", "GMr"}:
        closed = run_source_mattes(client, files) and closed
    return closed


def run_mattes(client, files):
    """Spec §11 PR-17's and PR-18's exports: a white card under `shape563` on a
    `luma` matte track (GM), and under a `band374` graphic clip on one (GMg),
    each only when its row is selected."""
    closed = True
    for row, name, module, source in [("GM", "shapematte", None, None),
                                      ("GMg", "bandmatte", "band374", BAND_JS)]:
        if row not in selected:
            continue
        doc = Doc(client, name, module, source)
        made, why = (True, "") if doc.ok else (False, doc.why)
        if made:
            # A new project's background is opaque black: read, not set (an identity is refused).
            ground = (doc.project().get("canvas") or {}).get("background")
            made, why = ground == [0, 0, 0, 1], f"canvas background {ground}"
        if made:
            made, why = doc.shape_clip(WHITE_CARD)
        if made and module is None:
            made, why = doc.shape_clip(SHAPE_563)
        elif made:
            made, why = ((False, "no new track") if doc.new_track() is None
                         else doc.clip(track=doc.track))
        if made:
            made, why = doc.luma_matte()
        if made:
            files[row] = doc.export(FILES[row], preset="prores_422")
        else:
            print(f"       {name} project: {why}", flush=True)
        closed = doc.close() and closed
    return closed


def run_source_mattes(client, files):
    """Spec §11 PR-19's projects (#597): precision_proof's 10-bit ramp clip and
    deep still, each as a `luma` matte over a white card (GMc, GMs, GMf) or a
    60 % grey one (GMe), and each placed plainly as its control (GMc0, GMs0,
    GMf0), each only when a row that reads it is selected."""
    closed = True
    clip, still = precision.ramp_clip(), precision.still16_png()
    # (name, the source, the card under it or None, [(row, file, preset or None for a frame)])
    plans = [("clipmatte", clip, WHITE_CARD, [("GMc", "GMc", "prores_422"), ("GMf", "GMf", None)]),
             ("clipplain", clip, None, [("GMc", "GMc0", "prores_422"),
                                        ("GMf GMr", "GMf0", None)]),
             ("stillmatte", still, WHITE_CARD, [("GMs", "GMs", "prores_422")]),
             ("stillplain", still, None, [("GMs", "GMs0", "prores_422")]),
             ("clipgrey", clip, GREY_CARD, [("GMe", "GMe", "h264")]),
             # Spec §11 PR-21: GMc's project over an 8-bit H.264 clip on a back-most track (GMr).
             ("clipmatteh264", clip, WHITE_CARD, [("GMr", "GMr", None)])]
    for name, source, card, outputs in plans:
        # An output is made when any row named in its first field is selected.
        outputs = [output for output in outputs if selected & set(output[0].split())]
        if not outputs:
            continue
        doc = Doc(client, name)
        made, why = (True, "") if doc.ok else (False, doc.why)
        if made:
            # A new project's background is opaque black: read, not set (an identity is refused).
            ground = (doc.project().get("canvas") or {}).get("background")
            made, why = ground == [0, 0, 0, 1], f"canvas background {ground}"
        if made and card is not None:
            made, why = doc.shape_clip(card)
        if made:
            made, why = doc.canvas_media(source)
        if made and card is not None:
            made, why = doc.luma_matte()
        if made and name == "clipmatteh264":
            made, why = doc.media_clip(fixture("gmrh264.mov", [
                "-f", "lavfi", "-i", "color=c=gray:size=256x144:rate=30:duration=1,format=yuv420p",
                "-c:v", "h264_videotoolbox", "-b:v", "2M"]), index=0)
        if not made:
            print(f"       {name} project: {why}", flush=True)
        for _, file, preset in outputs if made else []:
            files[file] = (doc.export(FILES[file], preset=preset) if preset
                           else doc.frame(FILES[file]))
        closed = doc.close() and closed
    return closed


def deep_frame(row, scope, path, exact_rule, e=None):
    """D1's rule over a rendered frame: a 16-bit PNG, ≥ 400 distinct G values
    along row 540, and (with `exact_rule`) each within 1/8 level of `e`
    (`band374`'s unless a function is given)."""
    e = e or exact
    picture = read_png(path)
    values = deep_row(picture)
    header = png_header(path) if path and Path(path).exists() else None
    if values is None:
        check(f"{row} {scope}: a 16-bit PNG", False,
              f"header {header}; read {picture is not None}")
        return
    distinct = len(set(values))
    worst = max(abs(v / 257.0 - e(x, 540)) for x, v in enumerate(values))
    levels, median, widest = runs(picture)
    good = distinct >= 400 and (not exact_rule or worst <= 0.125)
    check(f"{row} {scope}: a 16-bit PNG, row 540 x 0–800 G ≥ 400 distinct values"
          + (", each within 1/8 level of e" if exact_rule else ""), good,
          f"{distinct} distinct 16-bit values; worst |G − e| {worst:.4f} levels"
          f"{'' if exact_rule else ' (not scored: the frame is HLG)'}; rounded to 8 bits "
          f"{levels} levels, median run {median}, widest {widest}")


def score_deep(files, base):
    """PR-15's rows over this run's files and the base's (or None)."""
    def theirs(row):
        path = base / FILES[row] if base else None
        return path if path and path.exists() else None

    if "E1" in selected:
        verdicts = []
        for row in ["B1", "F1", "S1"]:
            here, there = read_png(files.get(row)), read_png(theirs(row))
            verdicts.append((row, same(here, there)))
        # Spec §11 PR-20: a `render_frame` PNG of a graphic is deep, so the 8-bit frame path is
        # read through the APNG door, against the base's `render_frame` PNG of the same frame.
        doors = []
        for row, door in [("B3", "B3a"), ("F2", "F2a")]:
            here, there = read_png(files.get(door)), read_png(theirs(row))
            verdicts.append((f"{door} = the base's {row}", same(here, there)))
            header = png_header(files[door]) if files.get(door) else None
            # Printed: the base's own APNG frame against its own PNG, when it has both.
            doors.append((door, header, same(read_png(theirs(door)), there)
                          if theirs(door) else "no base APNG"))
        check("E1 the 8-bit paths are the base's byte for byte: B1's, F1's and S1's sheets, and "
              "the APNG frames of B3's and F2's projects, decode equal to the base's sheets and "
              "its render_frame PNGs of those frames",
              all(ok for _, ok in verdicts),
              f"equal to the base's: {verdicts}\n       APNG header, and at the base its own "
              f"APNG frame equal to its PNG: {doors}")
    if "D1" in selected:
        deep_frame("D1", "render_frame of band374 beside a 16-bit PNG still", files.get("D1"), True)
    if "D3" in selected:
        here = movie_figures(files.get("B4a"), 0.5, True)
        then = movie_figures(theirs("B4a"), 0.5, True)
        ours, base_movie = (read_movie(files.get("B4a"), 0.5, True),
                            read_movie(theirs("B4a"), 0.5, True))
        error = pixel_error(ours) if ours else None
        was = pixel_error(base_movie) if base_movie else None
        good = (here is not None and then is not None and here[1] <= then[1] / 2
                and error <= was / 2 and here[0] <= 0.15 and increasing(here[3]))
        check("D3 the prores_422 export of the band374 clip, the frame at 0.5 s (16-bit decode): "
              "noise kept ≤ ½ the base's, RMS of G − e less its mean ≤ ½ the base's, banding RMS "
              "≤ 0.15, "
              "row-540 block means strictly increase", good,
              f"{shown(here)}\n       base: {shown(then)}\n       RMS of G − e "
              f"{'none' if error is None else f'{error:.4f}'}; base's "
              f"{'none' if was is None else f'{was:.4f}'}")
    if "D4" in selected:
        here = movie_figures(files.get("B4b"), 2.5, True)
        then = movie_figures(theirs("B4b"), 2.5, True)
        ours, base_movie = (read_movie(files.get("B4b"), 2.5, True),
                            read_movie(theirs("B4b"), 2.5, True))
        error = pixel_error(ours, 997.5) if ours else None
        was = pixel_error(base_movie, 997.5) if base_movie else None
        good = (here is not None and then is not None and here[0] <= 0.15
                and here[1] <= 0.85 * then[1])
        check("D4 the hevc_10bit export of the 5 s band374m clip, the frame at 2.5 s (16-bit "
              "decode): banding RMS ≤ 0.15, noise kept ≤ 0.85 × the base's", good,
              f"{shown(here)}\n       base: {shown(then)}\n       RMS of G − e (not scored) "
              f"{'none' if error is None else f'{error:.4f}'}; base's "
              f"{'none' if was is None else f'{was:.4f}'}")
    if "D5" in selected:
        deep_frame("D5", "render_frame of band374 beside a 10-bit HEVC clip", files.get("D5"), True)
    if "D7" in selected:
        deep_frame("D7", "render_frame of band374 beside a 10-bit HEVC clip over an H.264 clip",
                   files.get("D7"), True)
    if "D6" in selected:
        deep_frame("D6", "render_frame of band374 in an HLG project", files.get("D6"), False)


def read_jpeg(path):
    """A 1920×1080 JPEG decoded to rgb24, or None."""
    if path is None or not Path(path).exists():
        return None
    raw = ffmpeg_raw(path, "rgb24")
    if raw is None or len(raw) != W * H * 3:
        return None
    return Picture(W, H, 3, array.array("B", raw))


def shape_measure(picture):
    """PR-16's printed figures over an 8-bit frame of `shape563` (G0's until PR-21, GEa's APNG
    frame since)."""
    levels, median, widest = runs(picture)
    row = [picture.g(x, 540) for x in range(801)]
    differing = sum(1 for y in range(500, 581)
                    if [picture.g(x, y) for x in range(801)] != row)
    gaps = [picture.g(x, y) - shape_exact(x, y) for y in range(500, 581) for x in range(801)]
    rms = math.sqrt(sum(g * g for g in gaps) / len(gaps))
    monotonic = all(b >= a for a, b in zip(row, row[1:]))
    return (f"row 540 x 0–800 G: {len(set(row))} levels, median run {median}, widest {widest}, "
            f"{'non-decreasing' if monotonic else 'NOT monotonic'}; {differing} of 81 rows "
            f"(500–580) differ from row 540; RMS(G − e) {rms:.4f}, worst |G − e| "
            f"{max(abs(g) for g in gaps):.4f} levels; worst 16-px block bias "
            f"{block_bias(picture, shape_exact):.4f}")


def score_shapes(files, base, capturing):
    """PR-16's rows over this run's files and the base's (or None)."""
    def theirs(row):
        path = base / FILES[row] if base else None
        return path if path and path.exists() else None

    if "G0" in selected:
        # Spec §11 PR-21: a gradient shape is a deep source of a saved frame.
        deep_frame("G0", "render_frame of shape563 alone", files.get("G0"), True, shape_exact)
        size = png_bytes(files.get("G0"))
        print(f"  --   G0's PNG (NOT scored): {f'{size[3]:,} bytes' if size else 'not read'}; G0h, "
              f"the same frame as HEIC: bitsPerSample {sample_depth(files.get('G0h'))}",
              flush=True)
    if "G1" in selected:
        deep_frame("G1", "render_frame of shape563 beside a 16-bit PNG still", files.get("G1"),
                   True, shape_exact)
    if "G3" in selected:
        here = movie_figures(files.get("G3"), 0.5, True)
        then = movie_figures(theirs("G3"), 0.5, True)
        ours, base_movie = (read_movie(files.get("G3"), 0.5, True),
                            read_movie(theirs("G3"), 0.5, True))
        error = pixel_error(ours, e=shape_exact) if ours else None
        was = pixel_error(base_movie, e=shape_exact) if base_movie else None
        good = (here is not None and then is not None
                and error is not None and was is not None and here[1] <= then[1] / 2
                and error <= was / 2 and here[0] <= 0.15 and increasing(here[3]))
        check("G3 the prores_422 export of the shape563 clip, the frame at 0.5 s (16-bit decode): "
              "noise kept ≤ ½ the base's, RMS of G − e less its mean ≤ ½ the base's, banding RMS "
              "≤ 0.15, row-540 block means strictly increase", good,
              f"{shown(here)}\n       base: {shown(then)}\n       RMS of G − e "
              f"{'none' if error is None else f'{error:.4f}'}; base's "
              f"{'none' if was is None else f'{was:.4f}'}")
        tenbit = movie_figures(files.get("G4"), 0.5, True)
        before = movie_figures(theirs("G4"), 0.5, True)
        print(f"  --   G4 (NOT scored; PR-15's limit) the hevc_10bit export of the shape563 clip, "
              f"the frame at 0.5 s (16-bit decode): {shown(tenbit)}\n       base: {shown(before)}",
              flush=True)
        if capturing and then is not None and was is not None:
            cure = then[1] >= VERDICT_NOISE and was >= VERDICT_ERROR
            verdict = ("CURE: the 8-bit ramp carries at least a dithered graphic's noise and "
                       "error into a deep file" if cure else "RECORD ONLY: under what PR-15 cured")
            print(f"  --   #563 VERDICT on this capture's own prores_422 file: noise kept "
                  f"{then[1]:.4f} (PR-15's base graphic {VERDICT_NOISE}), RMS of G − e less its "
                  f"mean {was:.4f} ({VERDICT_ERROR}): {verdict}", flush=True)
    if "G5" in selected:
        deep_frame("G5", "render_frame of shape563 beside a 10-bit HEVC clip", files.get("G5"),
                   True, shape_exact)
    if "G7" in selected:
        deep_frame("G7", "render_frame of shape563 beside a 10-bit HEVC clip over an H.264 clip",
                   files.get("G7"), True, shape_exact)
    if "G6" in selected:
        deep_frame("G6", "render_frame of shape563 in an HLG project", files.get("G6"), False,
                   shape_exact)
    if "GV" in selected:
        deep_frame("GV", "render_frame of shape563 beside a 256×144 8-bit H.264 clip (no deep "
                   "source but the shape)", files.get("GV"), True, shape_exact)
    if "GEa" in selected:
        # Spec §11 PR-21: the APNG door's frame against the base's same file. Printed: the base's
        # own APNG frame against its own G0 PNG when that is 8-bit (a base before PR-21).
        here, there = read_png(files.get("GEa")), read_png(theirs("GEa"))
        header = png_header(files["GEa"]) if files.get("GEa") else None
        own = theirs("G0")
        door = (same(there, read_png(own)) if own and png_header(own)[2] == 8
                else "the base's G0 is not an 8-bit PNG" if own else "no base G0")
        check("GEa the apng export's frame of shape563 alone (an 8-bit door): an 8-bit PNG that "
              "decodes equal to the base's", same(here, there) and header is not None
              and header[2] == 8,
              f"read {here is not None}; base {there is not None}; header {header}; the base's "
              f"APNG frame equal to its own G0 PNG: {door}\n       PR-16's measurement of it: "
              + (shape_measure(here) if here is not None and here.scale == 1.0 else "not read"))
    if "GEb" in selected:
        here, there = read_jpeg(files.get("GEb")), read_jpeg(theirs("GEb"))
        check("GEb render_frame of shape563 in an HLG project as a JPEG (its SDR version): "
              "decodes equal to the base's", same(here, there),
              f"read {here is not None}; base {there is not None}")
    if "GEc" in selected:
        here, there = read_png(files.get("GEc")), read_png(theirs("GEc"))
        header = png_header(files["GEc"]) if files.get("GEc") else None
        check("GEc render_frame of flat shapes beside a 16-bit PNG still: a 16-bit PNG that "
              "decodes equal to the base's (a flat shape stays 8-bit in a deep frame)",
              same(here, there) and header is not None and header[2] == 16,
              f"read {here is not None}; base {there is not None}; header {header}")


def matte_shown(path, e):
    """A matte export's figures and their printed form against its exact coverage `e`."""
    figures = movie_figures(path, 0.5, True)
    movie = read_movie(path, 0.5, True)
    if figures is None or movie is None:
        return None, "not read"
    return figures, f"{shown(figures)}, RMS of G − m less its mean {pixel_error(movie, e=e):.4f}"


def score_mattes(files, base):
    """#588's rows (spec §11 PR-17) over this run's files and the base's (or None)."""
    def theirs(row):
        path = base / FILES[row] if base else None
        return path if path and path.exists() else None

    if "GEd" in selected:
        here, there = (read_movie(files.get("GEd"), 0.5, False),
                       read_movie(theirs("GEd"), 0.5, False))
        gap = "n/a"
        if here is not None and there is not None:
            gaps = [abs(a - b) for a, b in zip(here.samples[500 * W * 3:581 * W * 3],
                                               there.samples[500 * W * 3:581 * W * 3])]
            gap = f"worst {max(gaps)}, mean {sum(gaps) / len(gaps):.4f}"
        check("GEd the h264 export of the shape563 clip, the frame at 0.5 s (8-bit decode): "
              "decodes equal to the base's", same(here, there),
              f"read {here is not None}; base {there is not None}; |Δ| over rows 500–580: {gap}")
    if "GM" in selected:
        here, text = matte_shown(files.get("GM"), matte_exact)
        _, before = matte_shown(theirs("GM"), matte_exact)
        good = here is not None and here[0] <= MATTE_BOUND and increasing(here[3])
        check("GM the prores_422 export of a white card under shape563 on a luma matte track, the "
              f"frame at 0.5 s (16-bit decode): banding RMS ≤ {MATTE_BOUND}, row-540 block means "
              "strictly increase", good,
              f"{text}\n       base: {before}"
              + (f"\n       row-540 block means {[round(m, 2) for m in here[3]]}" if here else ""))
    if "GMg" in selected:
        # Spec §11 PR-18: GM's rule, with `band374` (a graphic) as the matte.
        here, text = matte_shown(files.get("GMg"), band_matte_exact)
        _, before = matte_shown(theirs("GMg"), band_matte_exact)
        good = here is not None and here[0] <= MATTE_BOUND and increasing(here[3])
        check("GMg the prores_422 export of a white card under a band374 graphic clip on a luma "
              f"matte track, the frame at 0.5 s (16-bit decode): banding RMS ≤ {MATTE_BOUND}, "
              "row-540 block means strictly increase", good,
              f"{text}\n       base: {before}"
              + (f"\n       row-540 block means {[round(m, 2) for m in here[3]]}" if here else ""))


def ramp_figures(path, picture):
    """GMc's, GMs's and GMf's printed figures of one decoded picture."""
    if picture is None:
        return "not read"
    levels, median, widest = runs(picture)
    size = Path(path).stat().st_size if path and Path(path).exists() else None
    return (f"banding RMS {banding(picture):.4f}, noise kept {noise(picture):.4f}, RMS of G − e "
            f"less its mean {pixel_error(picture, e=ramp_exact):.4f}, row 540 x 0–800 "
            f"{deep_distinct(picture)} distinct 16-bit greens, {levels} 8-bit levels at median "
            f"run {median}, widest {widest}, {size} bytes")


def score_source_mattes(files, base):
    """#597's rows (spec §11 PR-19) over this run's files and the base's (or None)."""
    def theirs(row):
        path = base / FILES[row] if base else None
        return path if path and path.exists() else None

    for row, control, title in [("GMc", "GMc0", "the 10-bit ProRes ramp clip"),
                                ("GMs", "GMs0", "the 16-bit PNG ramp still")]:
        if row not in selected:
            continue
        here = read_movie(files.get(row), 0.5, True)
        plain = read_movie(files.get(control), 0.5, True)
        before = read_movie(theirs(row), 0.5, True)
        kept, wanted = deep_distinct(here), deep_distinct(plain)
        good = (here is not None and kept is not None and wanted is not None
                and banding(here) <= MATTE_BOUND and increasing(block_means(here))
                and 2 * kept >= wanted)
        check(f"{row} the prores_422 export of a white card under {title} on a luma matte track, "
              f"the frame at 0.5 s (16-bit decode): banding RMS ≤ {MATTE_BOUND}, row-540 block "
              f"means strictly increase, row 540 at least half the distinct 16-bit greens of the "
              f"source placed plainly ({control})", good,
              f"{ramp_figures(files.get(row), here)}\n       {control}: "
              f"{ramp_figures(files.get(control), plain)}\n       base: "
              f"{ramp_figures(theirs(row), before)}"
              + (f"\n       row-540 block means {[round(m, 2) for m in block_means(here)]}"
                 if here else ""))
    if "GMe" in selected:
        here, there = (read_movie(files.get("GMe"), 0.5, False),
                       read_movie(theirs("GMe"), 0.5, False))
        gap = "n/a"
        if here is not None and there is not None:
            gaps = [abs(a - b) for a, b in zip(here.samples[500 * W * 3:581 * W * 3],
                                               there.samples[500 * W * 3:581 * W * 3])]
            gap = f"worst {max(gaps)}, mean {sum(gaps) / len(gaps):.4f}"
        check("GMe the h264 export of a 60 % grey card under the ramp clip on a luma matte track, "
              "the frame at 0.5 s (8-bit decode): decodes equal to the base's", same(here, there),
              f"read {here is not None}; base {there is not None}; |Δ| over rows 500–580: {gap}")
    if "GMf" in selected:
        here, plain = read_png(files.get("GMf")), read_png(files.get("GMf0"))
        header = png_header(files["GMf"]) if files.get("GMf") else None
        kept, wanted = deep_distinct(here), deep_distinct(plain)
        good = (kept is not None and wanted is not None and banding(here) <= MATTE_BOUND
                and 2 * kept >= wanted)
        check(f"GMf render_frame at 0.5 s of GMc's project: a 16-bit PNG, banding RMS ≤ "
              f"{MATTE_BOUND}, row 540 at least half the distinct 16-bit greens of the clip's own "
              "frame (GMf0)", good,
              f"header {header}; {ramp_figures(files.get('GMf'), here)}\n       GMf0: "
              f"{ramp_figures(files.get('GMf0'), plain)}")
    if "GMr" in selected:
        # Spec §11 PR-21: PR-14's re-read and its mark, which a matted frame over an 8-bit clip
        # (the generator answers it 8-bit) is now the one frame to reach.
        here, plain = read_png(files.get("GMr")), read_png(files.get("GMf0"))
        header = png_header(files["GMr"]) if files.get("GMr") else None
        kept, wanted = deep_distinct(here), deep_distinct(plain)
        good = (kept is not None and wanted is not None and banding(here) <= MATTE_BOUND
                and 2 * kept >= wanted)
        check(f"GMr render_frame at 0.5 s of GMc's project over an 8-bit H.264 clip on a back-most "
              f"track: a 16-bit PNG, banding RMS ≤ {MATTE_BOUND}, row 540 at least half the "
              "distinct 16-bit greens of the clip's own frame (GMf0)", good,
              f"header {header}; {ramp_figures(files.get('GMr'), here)}\n       GMf0: "
              f"{ramp_figures(files.get('GMf0'), plain)}")


def png_bytes(path):
    """(bit depth, width, height, bytes, base64 bytes) of a PNG, or None."""
    header = png_header(path) if path and Path(path).exists() else None
    if header is None:
        return None
    size = Path(path).stat().st_size
    return header[2], header[0], header[1], size, 4 * ((size + 2) // 3)


def sample_depth(path):
    """`sips -g bitsPerSample` of an image, or None."""
    if path is None or not Path(path).exists():
        return None
    got = bounded.run(["sips", "-g", "bitsPerSample", str(path)], TOOL_BOUND,
                      env=bounded.child_env())
    found = [line.split(":")[-1].strip() for line in got["stdout"].splitlines()
             if "bitsPerSample" in line]
    return found[0] if got["rc"] == 0 and found else None


def score_graphic_sources(files, base):
    """#566's rows (spec §11 PR-20) over this run's files and the base's (or None)."""
    def theirs(row):
        path = base / FILES[row] if base else None
        return path if path and path.exists() else None

    if "DG" in selected:
        deep_frame("DG", "render_frame at 0.5 s of band374 alone (B3's project)", files.get("B3"),
                   True)
        size = png_bytes(files.get("B3"))
        seconds = FRAME_SECONDS.get(FILES["B3"])
        print(f"  --   DG's PNG (NOT scored): {f'{size[3]:,} bytes' if size else 'not read'}, "
              f"render_frame {f'{seconds:.2f} s' if seconds is not None else 'not timed'}; DGh, "
              f"the same frame as HEIC: bitsPerSample {sample_depth(files.get('DGh'))}",
              flush=True)
    if "DGf" in selected:
        picture = read_png(files.get("F2"))
        header = png_header(files["F2"]) if files.get("F2") else None
        x0, y0, x1, y1 = ONE_COLOUR_RECT
        values = ({tuple(picture.samples[(y * picture.width + x) * 4 + c] for c in range(3))
                   for y in range(y0, y1) for x in range(x0, x1)}
                  if picture is not None and picture.scale == 257.0 else set())
        worst = max((abs(v / 257.0 - want) for value in values
                     for v, want in zip(value, (51, 102, 153))), default=None)
        check("DGf render_frame of a flat clip (F2's project): a 16-bit PNG whose one-colour "
              "gradient rect holds one RGB value, each channel within 1/8 level of (51, 102, 153)",
              header is not None and header[2] == 16 and len(values) == 1
              and worst is not None and worst <= 0.125,
              f"header {header}; the rect's distinct values {sorted(values)[:4]}"
              f"{' …' if len(values) > 4 else ''} ({len(values)}); worst |v/257 − level| "
              f"{'none' if worst is None else f'{worst:.4f}'}")
    if "DGv" in selected:
        deep_frame("DGv", "render_frame of band374 beside a 256×144 8-bit H.264 clip (no deep "
                   "source)", files.get("DGv"), True)
    if "DGo" in selected:
        on, off = (png_header(files[row]) if files.get(row) else None for row in ("DGo", "DGo2"))
        check("DGo a band374 clip from 0 to 1 s and a flat shape from 1 s: the frame at 0.5 s is a "
              "16-bit PNG and the frame at 1.5 s, which draws no graphic, an 8-bit PNG",
              on is not None and off is not None and on[2] == 16 and off[2] == 8,
              f"0.5 s header {on}; 1.5 s header {off}")
    if "DGj" in selected:
        here, there = read_jpeg(files.get("DGj")), read_jpeg(theirs("DGj"))
        check("DGj render_frame of band374 alone as a JPEG: decodes equal to the base's",
              same(here, there), f"read {here is not None}; base {there is not None}")
    if "DGs" in selected and files.get("DGsg") is not None:
        for key, title in [("DGsg", "an 8-bit H.264 cut of the iPhone clip under the flat graphic"),
                           ("DGss", "the same cut beside a 64×64 16-bit still"),
                           ("DGsi", "the iPhone clip itself (HEVC Main 10, HLG)")]:
            for suffix, scale in [("", "unscaled"), ("1280", "max_width 1280")]:
                size = png_bytes(files.get(key + suffix))
                shown_size = ("not read" if size is None else
                              f"{size[0]}-bit {size[1]}×{size[2]}, {size[3]:,} bytes, base64 "
                              f"{size[4]:,} ({'OVER' if size[4] > API_IMAGE_LIMIT else 'under'} "
                              f"{API_IMAGE_LIMIT:,})")
                print(f"  --   DGs (NOT scored) {title}, {scale}: {shown_size}; "
                      f"{block_shown(BLOCKS.get(key + suffix))}", flush=True)


def block_shown(got):
    """An image block's printed size: its type, its PNG depth, its base64 bytes beside the API's
    limit."""
    if not got or not got.get("ok"):
        return f"image block not read ({(got or {}).get('error', 'not asked')})"
    header = png_header(got["block"])
    return (f"image block {got['mime']}{f', {header[2]}-bit' if header else ''}, base64 "
            f"{got['b64']:,} ({'OVER' if got['b64'] > API_IMAGE_LIMIT else 'under'} "
            f"{API_IMAGE_LIMIT:,})")


def written_last(got):
    """Whether the text's last sentence names the file `got` wrote: "Written to <path>."."""
    text = got.get("text", "")
    head, _, tail = text.rpartition(" Written to ")
    return bool(head) and tail.endswith(".") and Path(tail[:-1]).resolve() == got["file"].resolve()


def within_a_level(deep_path, block_path):
    """(every sample of the 8-bit block within 1 level of the deep file's rounded to 8 bits, the
    worst gap, the samples compared) or (False, None, 0) when either does not read or the sizes
    differ."""
    deep, eight = read_png(deep_path), read_png(block_path)
    if (deep is None or eight is None or deep.scale != 257.0 or eight.scale != 1.0
            or (deep.width, deep.height) != (eight.width, eight.height)):
        return False, None, 0
    worst = max(abs(b - (v + 128) // 257) for v, b in zip(deep.samples, eight.samples))
    return worst <= 1, worst, len(eight.samples)


def score_blocks(files):
    """#604's rows (spec §11 PR-22) over `BLOCKS`."""
    if "BK1" in selected:
        got = BLOCKS.get("BK1") or {"ok": False, "error": "not run"}
        file = png_bytes(got["file"]) if got["ok"] else None
        block = png_header(got["block"]) if got["ok"] else None
        close, worst, count = (within_a_level(got["file"], got["block"]) if got["ok"]
                               else (False, None, 0))
        good = (got["ok"] and file is not None and file[0] == 16 and file[4] > API_IMAGE_LIMIT
                and got["mime"] == "image/png" and block is not None and block[2] == 8
                and block[:2] == file[1:3] and got["b64"] <= API_IMAGE_LIMIT and close
                and COPY_PNG in got["text"] and written_last(got))
        check(f"BK1 render_frame of 1080p footage under a graphic, default: the file a 16-bit PNG "
              f"past the API's {API_IMAGE_LIMIT:,} base64 bytes; the block an 8-bit PNG of its "
              "size within it, every sample within 1 level of the file's; the copy sentence, and "
              "the text still ends naming the file", good,
              (f"file {file[0]}-bit {file[1]}×{file[2]}, {file[3]:,} bytes, base64 {file[4]:,}; "
               f"{block_shown(got)} {block[0]}×{block[1]}; worst |block − file/257| {worst} over "
               f"{count:,} samples; copy sentence {COPY_PNG in got['text']}; written last "
               f"{written_last(got)}" if file and block else f"{got.get('error', 'not read')}"))
    if "BK2" in selected:
        got = BLOCKS.get("BK2") or {"ok": False, "error": "not run"}
        equal = got["ok"] and got["block"].read_bytes() == got["file"].read_bytes()
        check("BK2 the same with full_depth_image: true: the block is the file's bytes, "
              "image/png, and no copy sentence",
              equal and got["mime"] == "image/png" and COPY_SAID not in got["text"]
              and written_last(got),
              f"{block_shown(got)}; equal to the file {equal}" if got["ok"] else got["error"])
    if "BK3" in selected:
        got = BLOCKS.get("BK3") or {"ok": False, "error": "not run"}
        file = png_header(got["file"]) if got["ok"] else None
        equal = got["ok"] and got["block"].read_bytes() == got["file"].read_bytes()
        check("BK3 render_frame of the footage alone (an 8-bit frame), default: an 8-bit PNG whose "
              "block is the file's bytes, image/png, and no copy sentence",
              equal and file is not None and file[2] == 8 and got["mime"] == "image/png"
              and COPY_SAID not in got["text"] and written_last(got),
              f"file header {file}; {block_shown(got)}; equal to the file {equal}"
              if got["ok"] else got["error"])
    if "BK4" in selected:
        got = BLOCKS.get("BK4") or {"ok": False, "error": "not run"}
        full = BLOCKS.get("BK4f") or {"ok": False, "error": "not run"}
        depth = sample_depth(got["file"]) if got["ok"] else None
        block = png_header(got["block"]) if got["ok"] else None
        equal = full["ok"] and full["block"].read_bytes() == full["file"].read_bytes()
        good = (got["ok"] and depth == "10" and got["mime"] == "image/png" and block is not None
                and block[2] == 8 and COPY_HEIC in got["text"] and written_last(got)
                and equal and full["mime"] == "image/heic" and COPY_SAID not in full["text"])
        check("BK4 BK1's frame as HEIC: the file 10 bits a sample, its default block an 8-bit PNG "
              "with the HEIC copy sentence, and with full_depth_image: true an image/heic block "
              "that is the file's bytes", good,
              f"default: file bitsPerSample {depth}; {block_shown(got)}; copy sentence "
              f"{COPY_HEIC in got.get('text', '')}; full: {block_shown(full)}, equal to the file "
              f"{equal}" + ("" if got["ok"] and full["ok"]
                            else f"; {got.get('error', '')} {full.get('error', '')}"))
    if "BK5" in selected:
        got = BLOCKS.get("BK5") or {"ok": False, "error": "not run"}
        schema = BLOCKS.get("BK5schema") or {}
        refused = not got["ok"] and "full_depth_image must be true or false." in got["error"]
        check("BK5 full_depth_image: \"yes\" is refused naming the argument, and tools/list "
              "publishes full_depth_image as a boolean", refused and schema.get("type") == "boolean",
              f"answer {got.get('error') if not got['ok'] else 'ok'}; schema {schema}")
    if "BK6" in selected:
        # BK1's rule in the BT.2100 HLG space (#611), less its size premise: a graphic's frame
        # is small, and the limit is BK1's subject.
        got = BLOCKS.get("BK6") or {"ok": False, "error": "not run"}
        output = BLOCKS.get("BK6output")
        file = png_bytes(got["file"]) if got["ok"] else None
        block = png_header(got["block"]) if got["ok"] else None
        close, worst, count = (within_a_level(got["file"], got["block"]) if got["ok"]
                               else (False, None, 0))
        good = (got["ok"] and output == "hlg" and file is not None and file[0] == 16
                and got["mime"] == "image/png" and block is not None and block[2] == 8
                and block[:2] == file[1:3] and close and COPY_PNG in got["text"]
                and written_last(got))
        check("BK6 render_frame of an HLG project's band374 clip (D6's recipe), default: the "
              "canvas reads back hlg; the file a 16-bit PNG; the block an 8-bit PNG of its size, "
              "every sample within 1 level of the file's; the copy sentence, and the text still "
              "ends naming the file", good,
              (f"canvas output {output}; file {file[0]}-bit {file[1]}×{file[2]}, {file[3]:,} "
               f"bytes, base64 {file[4]:,}; {block_shown(got)} {block[0]}×{block[1]}; worst "
               f"|block − file/257| {worst} over {count:,} samples; copy "
               f"sentence {COPY_PNG in got['text']}; written last {written_last(got)}"
               if file and block else f"canvas output {output}; {got.get('error', 'not read')}"))
    for row, title, depth, mime, copy in [
            ("BKk", "a 3840×2160 frame of footage under a graphic", 16, "image/png", COPY_PNG),
            ("BKp", "the 3840×2160 footage alone (an 8-bit frame)", 8, "image/png", None),
            ("BKj", "a 3840×2160 noise still as a JPEG", None, "image/jpeg", None)]:
        if row in selected:
            scaled_row(row, title, BLOCKS.get(row) or {"ok": False, "error": "not run"}, depth,
                       mime, copy)
    if "BKd" in selected:
        tool = BLOCKS.get("BKdtool") or {"error": "not run"}
        properties = (tool.get("inputSchema") or {}).get("properties") or {}
        said = tool.get("description") or ""
        width = properties.get("max_width") or {}
        width_said = width.get("description") or ""
        deep_said = (properties.get("full_depth_image") or {}).get("description") or ""
        missing = [phrase for phrase in SIDES_SAID if phrase not in said]
        width_missing = [phrase for phrase in WIDTH_SAID if phrase not in width_said]
        old = [name for name, text in [("render_frame", said), ("max_width", width_said),
                                       ("full_depth_image", deep_said)]
               if OLD_ATTRIBUTION in text]
        bounds = (width.get("minimum"), width.get("maximum"))
        check("BKd tools/list: render_frame's description names the API's limits on an image "
              "(8000 px, 3000 px past more than 20 images, 2576 px, 10 MB, Amazon Bedrock) and "
              "max_width as the caller's control; max_width's names 8000, 3000 and 2576 px and "
              "that the height follows, its schema still 16…8192; none says \"Anthropic API's "
              "5 MB\"", bool(said) and not missing and not width_missing and not old
              and bounds == (16, 8192),
              f"description missing {missing}; max_width missing {width_missing}, bounds "
              f"{bounds}; \"{OLD_ATTRIBUTION}\" in {old}"
              + (f"; {tool['error']}" if "error" in tool else "")
              + f"\n       description: {said}\n       max_width: {width_said}"
              f"\n       full_depth_image: {deep_said}")


def image_size(path):
    """(width, height) of an image by `sips`, or None."""
    if path is None or not Path(path).exists():
        return None
    got = bounded.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)], TOOL_BOUND,
                      env=bounded.child_env())
    found = {line.split(":")[0].strip(): line.split(":")[-1].strip()
             for line in got["stdout"].splitlines() if ":" in line}
    try:
        return int(found["pixelWidth"]), int(found["pixelHeight"])
    except (KeyError, ValueError):
        return None


def thumb_gap(a, b):
    """The mean |Δ| in 8-bit levels between images `a` and `b`, each reduced by ffmpeg to `THUMB`
    as `rgb24` with area scaling, or None when either does not read."""
    def thumb(path):
        argv = ["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-frames:v", "1", "-vf",
                f"scale={THUMB[0]}:{THUMB[1]}:flags=area", "-f", "rawvideo", "-pix_fmt", "rgb24",
                "-"]
        try:
            raw = subprocess.run(argv, capture_output=True, timeout=TOOL_BOUND,
                                 env=bounded.child_env()).stdout
        except (OSError, subprocess.TimeoutExpired):
            return None
        return raw if raw and len(raw) == THUMB[0] * THUMB[1] * 3 else None

    one, other = thumb(a), thumb(b)
    if one is None or other is None:
        return None
    return sum(abs(x - y) for x, y in zip(one, other)) / len(one)


def scaled_row(row, title, got, depth, mime, copy):
    """Spec §11 PR-23's rule (#610) over a 3840×2160 frame whose unscaled block would pass the
    API's limit: the file untouched and over it (the premise, so the row cannot pass on an easy
    picture), `depth` its PNG bit depth (None: a JPEG, read by `sips`); the block `mime`, within
    the limit, smaller on both sides with the aspect kept; `copy`'s sentence (None: no copy
    sentence), then the scale sentence naming the block's size, then "Written to <path>." last;
    and the block the frame (`thumb_gap` ≤ `THUMB_BOUND`)."""
    if not got["ok"]:
        check(f"{row} {title}: the block scaled to fit", False, got.get("error", "not read"))
        return
    file_b64 = 4 * ((got["file"].stat().st_size + 2) // 3)
    file_header = png_header(got["file"]) if depth else None
    file_size = file_header[:2] if file_header else image_size(got["file"])
    file_ok = (file_size == (3840, 2160) and file_b64 > API_IMAGE_LIMIT
               and (depth is None or file_header[2] == depth))
    block_header = png_header(got["block"]) if mime == "image/png" else None
    size = block_header[:2] if block_header else image_size(got["block"])
    smaller = (size is not None and 0 < size[0] < 3840 and 0 < size[1] < 2160
               and abs(size[0] * 2160 - size[1] * 3840) <= 3840)
    block_ok = (got["mime"] == mime and got["b64"] <= API_IMAGE_LIMIT and smaller
                and (mime != "image/png" or (block_header is not None and block_header[2] == 8)))
    said = SCALE_SAID.format(w=size[0], h=size[1]) if size else None
    sentences = (said is not None and f"{copy + ' ' if copy else ''}{said} Written to " in got["text"]
                 and got["text"].count(SCALED_WORDS) == 1 and written_last(got)
                 and (copy is not None or COPY_SAID not in got["text"]))
    gap = thumb_gap(got["block"], got["file"])
    picture = gap is not None and gap <= THUMB_BOUND
    check(f"{row} {title}, default: the file untouched (3840×2160"
          f"{f', {depth}-bit' if depth else ''}) and its base64 over the API's {API_IMAGE_LIMIT:,} "
          f"bytes; the block {mime} within it, smaller with the aspect kept; "
          + ("the copy sentence, then " if copy else "no copy sentence; ")
          + "the scale sentence naming its size, and the text still ends naming the file; the "
          f"block is the frame (64×36 mean |Δ| ≤ {THUMB_BOUND})",
          file_ok and block_ok and sentences and picture,
          f"file {file_size} {f'{file_header[2]}-bit' if file_header else ''} "
          f"{got['file'].stat().st_size:,} bytes, base64 {file_b64:,}; {block_shown(got)}, "
          f"{size}; aspect |w·2160 − h·3840| "
          f"{abs(size[0] * 2160 - size[1] * 3840) if size else None}; sentences {sentences}; "
          f"written last {written_last(got)}; 64×36 mean |Δ| "
          f"{f'{gap:.3f}' if gap is not None else 'not read'}; seconds "
          f"{FRAME_SECONDS.get(got['file'].name, 0):.2f}\n       text: {got['text']}")


def score(files, control):
    """Every row but Z1, over this run's files and the control's (or None)."""
    def theirs(row):
        path = control / FILES[row] if control else None
        return path if path and path.exists() else None

    if selected & {"B1", "B2"}:
        here = cell(read_png(files.get("B1")))
        there = cell(read_png(theirs("B1")))
        band_rows("B1", here, there, "render_graphic band374 frame 0, the cell at scale 1")
    if "B3" in selected:
        # Since spec §11 PR-20 the APNG door's frame (0.48 s), against the control's PNG.
        band_rows("B3", read_png(files.get("B3a")), read_png(theirs("B3")),
                  "the apng export's frame at 0.48 s of a band374 clip")
    if "B4a" in selected:
        here = movie_figures(files.get("B4a"), 0.5, True)
        then = movie_figures(theirs("B4a"), 0.5, True)
        good = (here is not None and then is not None and here[0] <= then[0] / 2
                and increasing(here[3]))
        check("B4a a prores_422 export of the band374 clip, the frame at 0.5 s (16-bit decode): "
              "banding RMS ≤ ½ the control's, row-540 50-px block means strictly increase", good,
              f"{shown(here)}\n       control: {shown(then)}"
              + (f"\n       row-540 block means {[round(m, 2) for m in here[3]]}" if here else ""))
    if "B4b" in selected:
        here = movie_figures(files.get("B4b"), 2.5, True)
        then = movie_figures(theirs("B4b"), 2.5, True)
        good = here is not None and then is not None and here[0] <= 0.15 and here[0] < then[0]
        check("B4b a hevc_10bit export of the 5 s band374m clip, the frame at 2.5 s (16-bit "
              "decode): banding RMS ≤ 0.15 and under the control's", good,
              f"{shown(here)}\n       control: {shown(then)}")
    for row, title, project, _, seek in LIMITS:
        if ("B4a" if project == "band" else "B4b") not in selected:
            continue
        here = movie_figures(files.get(row), seek, False)
        then = movie_figures(theirs(row), seek, False)
        ratio = (f"{here[0] / then[0]:.3f}" if here and then and then[0] else "n/a")
        growth = (f"{100.0 * (here[4] - then[4]) / then[4]:+.1f} %" if here and then else "n/a")
        print(f"  --   {row} (NOT scored; PR-13's limit) {title}, 8-bit decode: {shown(here)}\n"
              f"       control: {shown(then)}\n       banding ratio {ratio}; file {growth}",
              flush=True)
    if "F1" in selected:
        here, there = read_png(files.get("F1")), read_png(theirs("F1"))
        one = tuple(round(here.at(*ONE_COLOUR_AT, c)) for c in range(4)) if here else None
        equal = same(here, there)
        check("F1 render_graphic flat: decoded RGBA equals the control's; the one-colour rect is "
              "exactly (51, 102, 153, 255)", equal and one == (51, 102, 153, 255),
              f"equal to the control's: {equal if there else 'no control'}; one-colour rect "
              f"{one}")
    if "F2" in selected:
        here, there = read_png(files.get("F2a")), read_png(theirs("F2"))
        check("F2 the apng export's frame of a flat clip: decoded RGBA equals the control's",
              same(here, there),
              f"read {here is not None}; control {there is not None}")
    if "S1" in selected:
        sheet, first = read_png(files.get("S1")), read_png(files.get("B1"))
        a, b, c = cell(sheet, 0), cell(sheet, 1), cell(first, 0)
        check("S1 render_graphic band374 frames [0, 30], max_width 8192: the two cells equal, and "
              "equal to B1's cell", same(a, b) and same(a, c),
              f"cell 0 == cell 1: {same(a, b)}; cell 0 == B1's: {same(a, c)}")


# ---- the mutants ----------------------------------------------------------------------

def copy_crate(names):
    tree_copy.remove_tree(str(MUTANT_DIR))
    MUTANT_DIR.mkdir(parents=True)
    for name in names:
        shutil.copytree(ROOT / name, MUTANT_DIR / name, ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "app", MUTANT_DIR / "app")


def run_mutant(name):
    edits, named = MUTANTS[name]
    print(f"#375 part 1 — the {name} MUTANT ({' '.join(named)} must FAIL)", flush=True)
    core = name == "core-unpatched"
    copy_crate(["graphic", "core"] if core else ["graphic"])
    if core:
        manifest = MUTANT_DIR / "core/Cargo.toml"
        text = manifest.read_text()
        if text.count(CORE_PATCH) != 1:
            print(f"mutant {name}: the control could not be performed — {CORE_PATCH!r} occurs "
                  f"{text.count(CORE_PATCH)} times in core/Cargo.toml")
            return 2
        manifest.write_text(text[:text.index(CORE_PATCH)].rstrip("\n") + "\n")
        argv = ["cargo", "test", "--release", "--offline", "--test", "graphic_ffi",
                "a_gradient_is_dithered"]
        folder, expected = MUTANT_DIR / "core", None
    else:
        for path, anchor, replacement in edits:
            target = MUTANT_DIR / path
            text = target.read_text()
            if text.count(anchor) != 1:
                print(f"mutant {name}: the control could not be performed — the anchor occurs "
                      f"{text.count(anchor)} times in {path}: {anchor!r}")
                return 2
            target.write_text(text.replace(anchor, replacement))
        deep = name in DEEP_MUTANTS
        argv = ["cargo", "test", "--release", "--test", "deep" if deep else "dither"]
        folder, expected = MUTANT_DIR / "graphic", "running 7 tests"
    got = bounded.run(argv, CARGO_BOUND, cwd=str(folder),
                      env=bounded.child_env({"CARGO_TARGET_DIR": str(TARGET)}))
    output = got["stdout"] + got["stderr"]
    BASE.mkdir(parents=True, exist_ok=True)
    (BASE / f"mutant-{name}.log").write_text(output)
    if core:
        # Spec §11 PR-15: without core's `[patch]` the staticlib does not build, naming the
        # vendored crate's door; that failure is the catch.
        caught = (not got["expired"] and got["rc"] not in (0, None)
                  and "with_deep_pixmaps" in output and "running 1 test" not in output)
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {name} — core without its "
              f"[patch] table {'does not build (with_deep_pixmaps is the vendored crate\'s)' if caught else 'built, or failed another way'} "
              f"(rc {got['rc']}, expired {got['expired']})")
        return 0 if caught else 1
    if got["expired"] or expected not in output:
        errors = [line for line in output.splitlines() if line.startswith("error")][:5]
        print(f"mutant {name}: the control could not be performed — the tests did not run "
              f"(rc {got['rc']}, expired {got['expired']}): {errors}")
        return 2
    for line in output.splitlines():
        if line.startswith("test ") and " ... " in line:
            print(f"  {line}")
    survived = [test for test in named if f"test {test} ... FAILED" not in output]
    caught = not survived
    print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {name} — {' '.join(named)} "
          f"{'all FAILED' if caught else 'did not all fail'} (survived: "
          f"{', '.join(survived) or 'none'})")
    return 0 if caught else 1


def run_app_mutant(name, base):
    """An app mutant (spec §11 PR-15): the tree copied, the anchor replaced,
    the Debug app built there and the named rows run against it, with its `KEPT_ROWS`,
    which must pass (#611)."""
    edits, named = APP_MUTANTS[name]
    kept = KEPT_ROWS.get(name, [])
    print(f"#374, #563 — the {name} APP MUTANT ({' '.join(named)} must FAIL"
          + (f"; {' '.join(kept)} must pass" if kept else "") + ")", flush=True)
    tree = BASE / f"app-mutant-{name}"
    made, why = tree_copy.make_copy(str(tree))
    if made is None:
        print(f"mutant {name}: the control could not be performed — the tree copy: {why}")
        return 2
    for path, anchor, replacement in edits:
        target = tree / path
        text = target.read_text()
        if text.count(anchor) != 1:
            print(f"mutant {name}: the control could not be performed — the anchor occurs "
                  f"{text.count(anchor)} times in {path}: {anchor!r}")
            return 2
        target.write_text(text.replace(anchor, replacement))
    app, why = tree_copy.build_app(str(tree), CARGO_BOUND,
                                   env=bounded.child_env({"RC_PROOF_APP": "debug"}))
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    got = bounded.run(
        [sys.executable, str(Path(__file__).resolve()), "--only",
         ",".join(named + kept + ["Z1"]), "--base", str(base)],
        CARGO_BOUND, cwd=str(ROOT), env=bounded.child_env({"RC_PROOF_APP": str(app)}))
    output = got["stdout"] + got["stderr"]
    (BASE / f"app-mutant-{name}.log").write_text(output)
    for line in output.splitlines():
        if line.startswith(("  ok ", "  FAIL")):
            print(f"  {line}")
    ran = [row for row in named + kept
           if f"  FAIL {row} " in output or f"  ok   {row} " in output]
    survived = [row for row in named if f"  FAIL {row} " not in output]
    broken = [row for row in kept if f"  ok   {row} " not in output]
    if len(ran) != len(named + kept):
        print(f"mutant {name}: the control could not be performed — rows {named + kept} did not "
              f"all run (rc {got['rc']}); see {BASE / f'app-mutant-{name}.log'}")
        return 2
    caught = not survived and not broken
    print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {name} — {' '.join(named)} "
          f"{'all FAILED' if not survived else 'did not all fail'} (survived: "
          f"{', '.join(survived) or 'none'})"
          + (f"; {' '.join(kept)} {'all passed' if not broken else 'did not all pass'} "
             f"(broken: {', '.join(broken) or 'none'})" if kept else ""))
    tree_copy.remove_tree(str(tree))
    return 0 if caught else 1


# ---- the run --------------------------------------------------------------------------

def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--control", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=list(MUTANTS))
    parser.add_argument("--base", default=None,
                        help="a capture made by the app before spec §11 PR-15 (E1, D3, D4) "
                             "or PR-16 (G3, GEa–GEd, GMe, DGj; GM, GMg, GMc and GMs print its "
                             "figures)")
    parser.add_argument("--app-mutant", choices=list(APP_MUTANTS))
    args = parser.parse_args()
    base = Path(args.base).resolve() if args.base else None
    if base is not None and not base.is_dir():
        print(f"instrument failure: no base folder at {base}")
        return 2
    if args.mutant:
        return run_mutant(args.mutant)
    if args.app_mutant:
        if base is None:
            print("an app mutant needs --base")
            return 2
        return run_app_mutant(args.app_mutant, base)
    if args.mode == "capture" and not args.folder:
        print("capture needs a folder")
        return 2
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    keep = (ROOT / args.folder).resolve() if args.mode == "capture" else None
    control = (ROOT / args.control).resolve() if args.control else None
    if control is not None and not control.is_dir():
        print(f"instrument failure: no control folder at {control}")
        return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    binary = proof_app.binary()
    print(f"#375 part 1 — graphic gradients dithered, spec §11 PR-13 ({args.mode or 'run'}, "
          f"{proof_app.config()} build {binary}; control {control or keep or 'none'})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    log = WORK / "instance.log"
    files = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            closed = run(launched.client, files)
        except Exception as error:  # a row that could not run is a failure
            import traceback
            traceback.print_exc()
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    files = {row: path for row, path in files.items() if path is not None}
    if keep is not None:
        keep.mkdir(parents=True, exist_ok=True)
        for path in files.values():
            shutil.copy2(path, keep / path.name)
        (keep / "capture.json").write_text(json.dumps(
            {"tree": str(ROOT), "config": proof_app.config(),
             "files": sorted(p.name for p in files.values())}, indent=1))
        print(f"  captured {len(files)} files into {keep}", flush=True)
    score(files, keep or control)
    score_deep(files, keep or base)
    score_shapes(files, keep or base, keep is not None)
    score_mattes(files, keep or base)
    score_source_mattes(files, keep or base)
    score_graphic_sources(files, keep or base)
    score_blocks(files)
    found = hdr.complaints(log)
    check("Z1 every project closed and the log holds no `Frame Job: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(hdr.tail(log)), flush=True)
    scored = [name for name in ROWS if name in rows]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if keep is not None:
        print(f"captured; on this tree FAILED: {[n for n in scored if not rows[n]]}")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
