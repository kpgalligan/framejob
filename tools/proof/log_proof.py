#!/usr/bin/env python3
"""Road map "grading-3", phase T3-2 (spec §11 GR-16) — camera log footage at
step 0, over MCP and a probe over `app/Sources`. Written before any product
edit, so the control is captured on the untouched tree.

    python3 tools/proof/log_proof.py [--app PATH] [--only L1,LP3,...]
    python3 tools/proof/log_proof.py capture DIR    # the CONTROL tree: L9's references, the rest shown failing
    python3 tools/proof/log_proof.py compare DIR [--only L1,...]
    python3 tools/proof/log_proof.py --mutant NAME [--control DIR]

hdr_proof.py's shape, and its decoding helpers (imported). Launches the app
`proof_app` picks (Debug unless `RC_PROOF_APP=release`) on a scratch socket
of its own and stops only that process. **The instance runs in a scratch
home**, `CFFIXED_USER_HOME=tools/proof/work/log/run/home`; every package, PNG
and export of a run is under `tools/proof/work/log/run/`, removed at the
start and at exit. The fixtures are made once under
`tools/proof/work/log/media/` and kept; `capture` copies L9's into
`DIR/media/`, and every later L9 reads them from there. No menu item is
performed and no default written. Every call is bounded (`CALL_BOUND`),
every ffmpeg and ffprobe too. Every project is closed (`close_project`,
discard). This script NEVER records the screen and spends nothing.

Fixtures (1024×128, 1 s, 10-bit ProRes 422 HQ; written by this script as raw
`yuv422p10le` and encoded by ffmpeg, each kept only when ffprobe reads what
it should — a refused fixture is its rows' FAIL, named): for each curve, rows
0–63 are its encode of the scene-linear ramp R = 1.2·X/1023 and rows 64–127
three patches (columns 0–341, 342–682, 683–1023) at the maker's own 0 / 18 /
90 % codes, chroma 512. S-Log3 and V-Log store the maker's code CV itself
(Y = round(1023·y(R)); patches 95/420/598 and 128/433/602); Apple Log stores
its normalized signal P in video range (Y = round(64 + 876·P); patches
196/492/661, the paper's 154/500/697 being P·1023), GR-16's code domains.
`slog3.mov` is tagged bt2020/bt709/bt2020nc (labels alone pick `sdrWide`),
`vlog.mov` untagged, `applelog.mov` and `applelog2.mov` the Apple Log ramp
relabelled by `applelog_writer.swift` (Apple Log; Apple Log 2 with `log2`),
and `green.mov` a whole-frame S-Log3 / S-Gamut3.Cine card (scene light 0.15,
0.35, 0.12; bt2020/bt709/bt2020nc), `green_m.mov` the same card tagged
bt2020nc alone. Two channel-distinct cubes, out = (0.7r +
0.2g + 0.1b², g², 0.5b + 0.3r): 17³ (LP3) and 33³ (L5); `tone.wav` and
`still.png` for L8's refusals. The oracle: the codes ffmpeg reads back from a
fixture, s = (Y − 64)/876 (through the bt2020nc matrix for the card), rounded
to half as the `rgba16Float` source holds it (`oracle_at`), then
GR-16's formula in Python (`log_convert`): y = codeScale·s + codeOffset, the
maker's inverse, × the exposure 0.42^2.4/0.18, the gamut's matrix (derived
here from the published chromaticities and D65), GR-15's lift, the shoulder
(knee 0.39, white 64·0.42^2.4), then L^(1/2.4).

Rows (projects are the fixture alone on a canvas its size, 30 fps):
- **LP1–LP4**: `log_probe.swift` over `app/Sources` (a probe that will not
  build is a scored FAIL of all four).
- **L1**: each fixture with its Camera Log set (`set_media_color`): the grey
  row every 8th column and every column of the first 32 (each curve's toe and
  break), the three patches, and the card (the chromatic fixture, which a
  gamut matrix moves) of `green.mov` and of `green_m.mov` (the same card
  tagged with its matrix alone, bt2020nc, primaries and transfer unknown —
  GRD-18's matrix-only camera file), at 0.5 s = the oracle ±1 at 8 bits.
- **L2**: `applelog.mov` imports with `media[].color` {log apple_log, gamut
  bt2020, detected true}, `applelog2.mov` with {apple_log2, apple_wide_gamut,
  detected true}; `slog3.mov` with none.
- **L3**: `green.mov` (Camera Log set) over a magenta canvas, keyed (tolerance
  0.05, softness 0.1, spill 0) with the oracle's converted green: magenta ±8
  at the card; keyed with the log green: the card stays (= the unkeyed render
  ±8).
- **L4**: Color's four (saturation −0.5, brightness 0.1) on `slog3.mov` with
  Camera Log = the same on its own `prores_422` export placed alone, ±2 on the
  grey row and patches; and ≥ 10 levels from the same grade on the clip with
  Camera Log None.
- **L5**: Use LUT (`set_media_color {lut}`, the 33³ cube) on `slog3.mov`,
  `green.mov` and `green_m.mov` = `ffmpeg lut3d=…:interp=trilinear` of the
  same file ±2, sampled at `slog3.mov`'s grey row and patches and at the
  card.
- **L6**: reversed `slog3.mov` and `applelog.mov` clips (Camera Log set) at
  0.5 s: the media's conversion of the reverse intermediate's OWN codes (Y
  moved by −1, 0, +1, widened by 1 — hdr_proof's H4 envelope) at every
  sample; = forward ±2 wherever the intermediate's code is the file's within
  1 (the lossy HEVC Main 10 reverse moves the ramp's first column by three
  codes, seven levels through the toe); and ≥ 10 levels from the
  unconverted render.
- **L7**: `slog3.mov` with Camera Log and a `warm` look: `render_frame
  {ungraded: true}` byte-equal to the look-less render, ≥ 10 levels from
  Camera Log None.
- **L8**: every refusal of `set_media_color` by its sentence (and the four
  `Err`s); `undo` restores `color`; a `paste` payload carrying the media and
  its LUT row lands both remapped, without the LUT row lands no `color`;
  `consolidate_media` keeps `color` and `lut`; `remove_media` of the LUT
  refused, then cleared with `with_clips`; a `scope` is an `Err`.
- **L9** (STOP; `compare DIR` and mutants): each fixture alone with no Camera
  Log (`applelog` and `applelog2`, detected on the tree, set to None)
  rendered at 0.5 s byte-equal to DIR's PNGs. hdr_proof's H1 and H1m are the
  other half, run by that script. Since issue batch B102 (spec §11 PR-11)
  `render_frame` labels every frame BT.709, so a DIR captured before B102
  fails L9 on labels alone (`frame_label_proof.py same-pixels DIR NEW` shows
  the pixels equal).
- **L10** (issue batch B95, spec §11 GR-22): `slog3_fr.mov`, `slog3_vr.mov`
  and `vlog_fr.mov` with Camera Log at 0.5 s, L1's grey-row points and the
  patches = the oracle at each file's OWN decoded codes ±1 at 8 bits, the code
  domain by its range flag: a full-range file decodes s = Y/1023 (and
  (C − 512)/1023) and S-Log3 and V-Log take y = s; a video-range one is
  GR-16's.
- **L11** (B95): `applelog_fr.mov` with `{log: apple_log}` set by hand = the
  oracle at (1, 0) ±1, a guard row (Apple Log is (1, 0) in both ranges; it
  passes on the control).
- **L12** (B95): a reversed `slog3_fr.mov` clip with Camera Log: L6's envelope
  at the video-range intermediate's own codes under the media's full-range
  domain at every sample, and ≥ 10 levels at the 0 % patch from the same
  envelope under the video domain.
- **L13** (issue batch B98, #289): the odd-size range fixtures through the
  product, no Camera Log: each alone at 0.5 s forward, then reversed
  (`set_reversed`, the intermediate kept, L12's way). Per fixture it prints
  the file's shape, the intermediate's codec, pix_fmt, size and range, `toe`'s
  worst |Y₁₅ − expected| over `toe_points()` (expected in the intermediate's
  own range flag, `expected_y`) and where, column 0's file → intermediate
  code, and the reversed render's worst `spread` from the forward one over
  `samples()`. A fixture is REACHED when it was kept, imported, both renders
  decoded and the intermediate exists and decoded; a REACHED fixture HOLDS
  when its intermediate is `prores` `yuv422p10le` at exactly 1024×129, its
  toe worst is ≤ HOLD_BOUND (1) and its spread ≤ 2 (fixed before the run).
  L13 passes when the four odd fixtures (pairs `slog3_fr_odd`/`slog3_vr_odd`
  and `slog3_fr_vp9`/`slog3_vr_vp9`) are all REACHED and each not in
  `L13_OPEN` HOLDS (a fixture there is printed beside its issue; empty since
  issue batch B99, which closed the VP9 pair's #291). One not
  REACHED is an instrument failure, named in REFUSED. `slog3_fr_422` (the
  even HEVC 4:2:2 file: the HEVC branch, #280) is printed and not scored.
- **L14** (issue batch B99, #291, spec §11 GR-23): `slog3_fr_vp9e.mp4`,
  `slog3_vr_vp9e.mp4` and `slog3_fr_webm.webm` (the last imported through
  `ContainerRewrap`) with S-Log3 set at 0.5 s, scored as L10: L1's grey-row
  points and the patches = the oracle at the file's own decoded codes ±1 at
  8 bits, the code domain by the file's range flag — step 0's read of a VP9
  track's `vpcC` range bit. From B99 to B102 the bound was 2: the same codes
  rendered from VP9 and from HEVC parted by up to 0.88 of a level
  untransformed and 1.25 under S-Log3, which issue batch B102's
  `composition-gap` placed in the generator, whose image of the VP9 file is
  8-bit where the HEVC file's is 16-bit. Since issue batch B103 (#294, spec
  §11 PR-12) such a frame is read through export's reader, and the bound is
  1 again.
- **L15** (issue batch B101, #293; a probe row, no instance): `av1_range_probe.swift`
  over `app/Sources` reads each AV1 fixture's first format description — the
  `FullRangeVideo` key, the `av1C` and `colr` atoms, `av1C`'s first 8 bytes,
  the extension keys — and answers `CompositionBuilder.isFullRange`: the MP4s
  as they are, the WebMs through the built-in rewrap's writer
  (`ContainerRewrapWriter.write`, the precheck skipped: it refuses AV1
  without hardware decode). Each `SYNTHETIC_AV1` record, written field by
  field by `av1c()` (the AV1 Bitstream spec's §5.5), is `av1_fr.mp4`'s first
  compressed sample re-described with it and written as a one-sample `.mov`.
  No picture is decoded (AV1 does not decode on an M1/M2). L15 passes when
  every full-range item answers true, every video-range item false and every
  synthetic record its own `color_range`, but the two profile 2 range-1
  records, which answer false. It passed on the untouched tree (B101's
  control): AVFoundation sets the key from `av1C` itself in profiles 0 and 1,
  so no product code landed, and L15 stays as a guard with no mutant. B101's
  fix pass added two full-range profile 2 records (12 and 10 bits): profile 2
  gets no key and answers false, which the owner accepted as a known limit
  (2026-10-14, spec §11 GR-23, #293), so both are scored False and a change
  in AVFoundation's answer fails L15.
- **L16** (issue batch B103, #294, spec §11 PR-12; a probe row, no instance):
  `deep_video_probe.swift` over `app/Sources` reads each file's first format
  description — its media subtype, its `BitsPerComponent` extension, its
  `vpcC` record's first 8 bytes — and answers `DeepVideoFrame.isDeep`:
  true for `slog3_fr_vp9e.mp4`, `slog3_vr_vp9e.mp4`, the odd
  `slog3_fr_vp9.mp4` and `slog3_fr_webm.webm` (rewrapped by
  `ContainerRewrap.rewrap`, its precheck included), false for
  `vp9_8bit.mp4`, `slog3_fr.mov` (HEVC Main 10), `slog3_fr_422.mov` (HEVC
  Rext) and `slog3.mov` (ProRes 422 HQ). A probe that does not build is the
  row's FAIL (the control's answer).
- **L17** (B103): `slog3_fr_vp9e.mp4`, `slog3_vr_vp9e.mp4` and
  `slog3_fr_webm.webm` alone, no Camera Log, at 0.5 s, and the mixed project
  (`vp9_8bit.mp4` at 0, `slog3_fr_vp9e.mp4` at 1 s on one track) at 1.5 s:
  each `render_frame` PNG has IHDR bit depth 16. Unscored, it prints the
  depth of `slog3_fr.mov`, `slog3_fr_422.mov`, `slog3.mov` and
  `vp9_8bit.mp4` alone — the generator's depth per codec.
- **L18** (B103; L9's modes: `capture DIR`, `compare DIR`, mutants): the
  frames PR-12 leaves to the generator — `slog3_fr.mov` alone,
  `vp9_8bit.mp4` alone and the mixed project at 0.5 s as PNGs, and
  `slog3_fr_vp9e.mp4` alone as `format: "jpeg"` — byte-equal to DIR's.
  `capture` copies their media into `DIR/media/`, each extension kept, and
  every later L18 reads them from there.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Frame Job: ` line.

B95's fixtures (1024×128, 1 s, HEVC Main 10 4:2:0, libx265 lossless, `.mov`
`hvc1`): the curve's ramp and patches stored as the code 1023·y (Apple's P as
1023·P), chroma 512. `slog3_fr.mov` flagged full range (`pc`) and tagged
bt2020/bt709/bt2020nc, `slog3_vr.mov` the same codes flagged video range
(`tv`), `vlog_fr.mov` and `applelog_fr.mov` full range and untagged. The range
and the tags are given to ffmpeg's INPUT as well as its output (given to the
output alone, ffmpeg converts the codes at encode), and each is kept only when
ffprobe reads its range and tags and `source_yuv` reads back the written code
at column 512 of the grey row and at the 18 % patch; a refused one is its
rows' FAIL, naming the code read. B98's (#289, L13) are written the same
way, each by its `RANGE_SHAPES` row (size, pix_fmt, encoder, codec, profile,
extension; a name not there is B95's): `slog3_fr_odd.mov` (`pc`) and
`slog3_vr_odd.mov` (`tv`), 1024×129 `yuv422p10le` HEVC Rext (libx265
lossless `main422-10`, `hvc1`; 4:2:0 HEVC cannot hold an odd height), tagged
as `slog3_fr`; `slog3_fr_vp9.mp4` (`pc`) and `slog3_vr_vp9.mp4` (`tv`),
1024×129 `yuv420p10le` VP9 Profile 2 (libvpx-vp9 lossless), their tags
printed and not required; and `slog3_fr_422.mov`, 1024×128 as
`slog3_fr_odd`. B99's (#291, L14) are the VP9 pair at 1024×128,
`slog3_fr_vp9e.mp4` (`pc`) and `slog3_vr_vp9e.mp4` (`tv`), and
`slog3_fr_webm.webm`, the same full-range VP9 stream in WebM, its tags
printed and not required. B101's (#293, L15) are `AV1_FIXTURES`: one 64×64
1 s lavfi grey frame through libsvtav1 `yuv420p10le`, `av1_fr.mp4` (`pc`,
`-write_colr`), `av1_fr_colr.mp4` (`pc`, `+write_colr`), `av1_vr.mp4` (`tv`,
`-write_colr`), `av1_fr_webm.webm` (`pc`) and `av1_vr_webm.webm` (`tv`), each
kept only when ffprobe reads `av1` and its range and the file holds a `colr`
box exactly when `+write_colr`. Each is wanted with its codec, profile, pix_fmt and size,
and read back as above. B103's (#294, L16–L18) is `vp9_8bit.mp4`: 1 s of
lavfi `testsrc2` at 1024×128, 30 fps, libvpx-vp9 lossless Profile 0
`yuv420p`, kept only when ffprobe reads `vp9`, `Profile 0`, `yuv420p` and
1024×128. Mutants: `full-range-ignored` (L10, L12),
`apple-log-rescaled` (L11), `range-from-reverse` (L12), B98's
`odd-range-ignored` (L13: `Intermediate.pixelFormat(fullRange:)` answers the
video-range `x422` whatever the flag, spec §11 PR-10), and B99's
`vp9-range-ignored` (L13, L14: `isFullRange`'s fallback answers false in
place of `vp9FullRange(of:)`) and `vpcc-wrong-byte` (L13, L14: the bit read
from byte 7, the colour primaries, in place of byte 6, spec §11 GR-23).
B103's (#294, spec §11 PR-12; each run with `--only` its rows and Z1, the
"also" rows printed, not required): `vp9-deep-never` (L14, L16, L17:
`DeepVideoFrame.isDeep` answers false), `vp9-depth-eight` (L16, L18 also:
the depth test is `>= 8`), `vpcc-depth-nibble` (L14, L16, L17: the depth
read as byte 6's low nibble, the chroma and range bits), `vp9-track-wide`
(L18: `shows` counts the composition track by any description it lists, not
its segment at the frame time) and `vp9-jpeg-deep` (L18: `render_frame`
passes `keepsDepth: true` for JPEG too). `isDeep`'s VP9 subtype guard has no
mutant: no fixture but VP9 carries a `vpcC` atom (L16 prints each file's), so
removing it changes no answer.

    python3 tools/proof/log_proof.py reverse-variants [--variant base,rate2,...]

`reverse-variants` (issue batch B96, #280) launches no app. For each of
`REVERSE_VARIANTS`, in order — `base` (none), `x422` (`.hevcMain10` fed
`x422`, 4 bytes a pixel), `main422` (and HEVC Main 4:2:2 10), `rate2`,
`rate4`, `rate8` (`bits` × k AFTER its clamps, at most 240 Mbps), `quality`
(`AVVideoQualityKey` 1.0 for the rate), `prores422` (every size ProRes
422), `prores422hq` (and its codec 422 HQ), each one edit to the plain
`.hevcMain10` path of `ReverseRenderer.swift` — it copies the tree
(`tree_copy.make_copy` → `WORK/variant-<name>`, each anchor asserted once),
builds `reverse_probe.swift` over the copy's `app/Sources` and reverses
`slog3`, `applelog`, `slog3_fr`, `detail_1080` and `detail_2160`. It prints
the intermediate's codec/profile/pix_fmt; each detail fixture's bytes and
MB (10⁶ bytes) per minute beside Apple's published ProRes 422 / 422 HQ
rates (Apple ProRes White Paper, 29.97 fps); the ratio to `base`'s bytes;
and, for each log fixture, the worst |Y₁₅ − expected| over samples()' 131
points and grey-row columns 0–31, where, and column 0's codes file →
intermediate (expected: the file's Y; for `slog3_fr`, round(64 +
876·Y/1023), GR-22). A variant HOLDS when every log fixture's worst is ≤ 1,
and QUALIFIES when it holds and both ratios are ≤ 2.0 (fixed before the
run); the choice is the qualifier with the smallest 2160 ratio, a tie within
5 % to the earlier. The detail fixtures (`MEDIA/detail_1080.mov`,
`detail_2160.mov`): 2 s of `testsrc2` with `noise=alls=6:allf=t+u`,
`prores_ks -profile:v 3`, `yuv422p10le`, untagged, kept only when ffprobe
reads that, the size and 2 s — the temporal grain stops an average-rate
encoder from undershooting, so a ratio there reads as a rate ratio. Exit 0
when every reverse completed; an unbuilt or failed variant is printed by
name.

    python3 tools/proof/log_proof.py decode-gap

`decode-gap` (issue batch B101, #294) launches no app. `decode_gap_probe.swift`,
built over `app/Sources`, calls `DecoderSupport.enable()` and reads the first
frame of `slog3_fr.mov`, `slog3_vr.mov` (HEVC) and `slog3_fr_vp9e.mp4`,
`slog3_vr_vp9e.mp4` (VP9) through `AVAssetReaderTrackOutput` at each of
`x420`, `xf20`, `64RGBAHalf`, `128RGBAFloat` and `64RGBALE`, at
`sample_points()` and the grey row's first 32 columns. It prints each
file's biplanar codes against the codes it was written with (its own range:
`xf20` for `pc`, `x420` for `tv`), and per RGB format VP9 against HEVC of the
same codes and range in 8-bit levels (1/255). The verdict, B101's rule:
**decoder** when VP9's own-range codes differ from the written ones at a point
where HEVC's equal them; else **conversion** when VP9's `64RGBAHalf` is more
than 0.5 of a level from HEVC's (naming any other format within 0.5); else
**neither**. A reader error at `x420`, `xf20` or `64RGBAHalf` is an
instrument failure: exit 1 and no verdict; one at `128RGBAFloat` or
`64RGBALE` is printed. B101's run: **neither** — every own-range code exact
and VP9's `64RGBAHalf` equal to HEVC's at every point (0.000 levels).

    python3 tools/proof/log_proof.py composition-gap

`composition-gap` (issue batch B102, #294) launches the app once to make its
packages, stops it, then builds `composition_gap_probe.swift` over
`app/Sources` (`DecoderSupport.enable()` first) beside the tree's
`Compositor.metal` as `default.metallib`. Each GAP_FIXTURES file is
placed alone on a W×H 30 fps canvas, once with Camera Log None and once with
S-Log3 (`set_media_color`, RANGE_SETTINGS), saved (`Doc.save`) and closed.
The probe reads each package's frame at T over `gap_points()` at three
stages: `tap`, the first source frame handed to a probe-local compositor
(the built configuration with only `customVideoCompositorClass` swapped; the
built class's `sourcePixelBufferAttributes`, `canConformColorOfSourceFrames`
and `supportsHDRSourceFrames` copied); `reader`, an
`AVAssetReaderVideoCompositionOutput` over the built composition at
`Compositor.outputPixelFormat`; and `generator`, `Exporter.renderFrame` drawn
in its image's own space. Per GAP_PAIRS pair and setting it prints VP9
against HEVC's worst |Δ| in 8-bit levels at each stage and where, and each
side's compositor class, track labels and tap format, size and attachments.
The verdict, fixed before the run (GAP_BOUND 0.5), names the first stage
that parts: the tap parts (or its formats differ): **source frames**; else
the reader: **compositor**; else the generator: **generator**; else **not
reproduced**. Exit 0 with a verdict; 1 when a stage could not be read; 2 when
the instrument could not run.

`capture DIR` records L9's references (`DIR/l9-*.png`, `DIR/media/`) and runs
the other rows, which must FAIL on the control. `--mutant NAME` builds a COPY
of the tree (`tree_copy.make_copy`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it (L9 against
`--control`, default tools/proof/work/t3-2/ctl), the probe built over the
copy's `app/Sources`. MUTANT PASS when every named row FAILED; every other
row that failed is printed. Exit 0 when every scored row passed (a mutant:
caught); 1 when one failed (a mutant: survived); 2 when the control could
not be performed.
"""

import argparse
import atexit
import json
import math
import shutil
import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import hdr_proof as hdr  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/log"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CONTROL = "tools/proof/work/t3-2/ctl"
PROBE = ROOT / "tools/proof/log_probe.swift"
REVERSE_PROBE = ROOT / "tools/proof/reverse_probe.swift"
WRITER = ROOT / "tools/proof/applelog_writer.swift"
CALL_BOUND = 300
BUILD_BOUND = 1500
REVERSE_BOUND = 300
SEC = 600_000
T = SEC // 2
W, H = 1024, 128
GREY_ROW, PATCH_ROW = 32, 96
PATCH_X = (170, 512, 853)
RMAX = 1.2
# GR-16's display transform (T3-2's append): 18 % grey encodes to 0.42.
MID_GREY = 0.42
EXPOSURE = MID_GREY ** 2.4 / 0.18
LOG_WHITE = 64 * MID_GREY ** 2.4
KNEE, DISPLAY_GAMMA = 0.39, 2.4
VIDEO_SCALE, VIDEO_OFFSET = 876 / 1023, 64 / 1023
# The makers' constants (GR-16's append).
APPLE = dict(r0=-0.05641088, rt=0.01, c=47.28711236, b=0.00964052, g=0.08550479, d=0.69336945)
SLOG3_BREAK = 171.2102946929
VLOG = dict(cut1=0.01, cut2=0.181, b=0.00873, c=0.241514, d=0.598206)
# Published chromaticities (x, y) of R, G, B; every white D65.
PRIMARIES = {"bt709": ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060)),
             "bt2020": ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046)),
             "s_gamut3_cine": ((0.766, 0.275), (0.225, 0.800), (0.089, -0.087)),
             "s_gamut3": ((0.730, 0.280), (0.140, 0.855), (0.100, -0.050)),
             "v_gamut": ((0.730, 0.280), (0.165, 0.840), (0.100, -0.030)),
             "apple_wide_gamut": ((0.725, 0.301), (0.221, 0.814), (0.068, -0.076))}
D65 = (0.3127, 0.3290)
LUMA709 = (0.2126, 0.7152, 0.0722)
GAMUTS = {"apple_log": ["bt2020"], "apple_log2": ["apple_wide_gamut"],
          "slog3": ["s_gamut3_cine", "s_gamut3"], "vlog": ["v_gamut"]}
CODE = {"apple_log": (1.0, 0.0), "apple_log2": (1.0, 0.0),
        "slog3": (VIDEO_SCALE, VIDEO_OFFSET), "vlog": (VIDEO_SCALE, VIDEO_OFFSET)}
# The makers' 0 / 18 / 90 % codes, as STORED (Apple's P in video range).
PATCHES = {"slog3": (95, 420, 598), "vlog": (128, 433, 602),
           "apple_log": (196, 492, 661), "apple_log2": (196, 492, 661)}
REFLECTANCE = (0.0, 0.18, 0.90)
GREEN_LIGHT = (0.15, 0.35, 0.12)
# name: (curve, the file's tags (primaries, transfer, matrix) or None, writer mode)
FIXTURES = {"slog3": ("slog3", ("bt2020", "bt709", "bt2020nc"), None),
            "vlog": ("vlog", None, None),
            "applelog": ("apple_log", ("bt709", "bt709", "bt709"), "log"),
            "applelog2": ("apple_log2", ("bt709", "bt709", "bt709"), "log2")}
SETTINGS = {"slog3": {"log": "slog3", "gamut": "s_gamut3_cine"}, "vlog": {"log": "vlog"},
            "applelog": {"log": "apple_log"}, "applelog2": {"log": "apple_log2"},
            "green": {"log": "slog3", "gamut": "s_gamut3_cine"},
            "green_m": {"log": "slog3", "gamut": "s_gamut3_cine"}}
L9_FIXTURES = ["slog3", "vlog", "applelog", "applelog2", "green"]
ROWS = ["LP1", "LP2", "LP3", "LP4", "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10",
        "L11", "L12", "L13", "L14", "L15", "L16", "L17", "L18", "Z1"]
LP_ROWS = {"LP1", "LP2", "LP3", "LP4"}
# The rows a probe answers with no instance (B101 adds L15, B103 L16).
PROBE_ROWS = LP_ROWS | {"L15", "L16"}
# B95 (spec §11 GR-22): HEVC Main 10 4:2:0 fixtures (libx265, lossless) flagged
# full (`pc`) or video (`tv`) range, the curve's signal stored as the 10-bit
# code 1023·y (Apple's P as 1023·P). name: (curve, range, tags or None).
RANGE_FIXTURES = {"slog3_fr": ("slog3", "pc", ("bt2020", "bt709", "bt2020nc")),
                  "slog3_vr": ("slog3", "tv", ("bt2020", "bt709", "bt2020nc")),
                  "vlog_fr": ("vlog", "pc", None),
                  "applelog_fr": ("apple_log", "pc", None),
                  # B98 (#289), L13's: odd-size twins of each range, and the
                  # even HEVC 4:2:2 file (the HEVC branch, printed only).
                  "slog3_fr_odd": ("slog3", "pc", ("bt2020", "bt709", "bt2020nc")),
                  "slog3_vr_odd": ("slog3", "tv", ("bt2020", "bt709", "bt2020nc")),
                  "slog3_fr_vp9": ("slog3", "pc", None),
                  "slog3_vr_vp9": ("slog3", "tv", None),
                  "slog3_fr_422": ("slog3", "pc", ("bt2020", "bt709", "bt2020nc")),
                  # B99 (#291), L14's: the VP9 pair at an even size, and the
                  # full-range one in WebM (the `ContainerRewrap` route).
                  "slog3_fr_vp9e": ("slog3", "pc", None),
                  "slog3_vr_vp9e": ("slog3", "tv", None),
                  "slog3_fr_webm": ("slog3", "pc", None)}
RANGE_SETTINGS = {"slog3_fr": SETTINGS["slog3"], "slog3_vr": SETTINGS["slog3"],
                  "vlog_fr": SETTINGS["vlog"], "applelog_fr": {"log": "apple_log"},
                  "slog3_fr_vp9e": SETTINGS["slog3"], "slog3_vr_vp9e": SETTINGS["slog3"],
                  "slog3_fr_webm": SETTINGS["slog3"]}
# B98 (#289): a range fixture's shape, (width, height, pix_fmt, encoder argv,
# codec_name, profile, extension); a name not here is RANGE_DEFAULT, B95's.
X265 = ["-c:v", "libx265", "-x265-params", "lossless=1:log-level=error"]
RANGE_DEFAULT = (W, H, "yuv420p10le", [*X265, "-profile:v", "main10", "-tag:v", "hvc1"],
                 "hevc", "Main 10", ".mov")
ODD_H = 129
HEVC422 = ("yuv422p10le", [*X265, "-profile:v", "main422-10", "-tag:v", "hvc1"], "hevc", "Rext",
           ".mov")
VP9 = ("yuv420p10le", ["-c:v", "libvpx-vp9", "-lossless", "1", "-profile:v", "2"], "vp9",
       "Profile 2", ".mp4")
RANGE_SHAPES = {"slog3_fr_odd": (W, ODD_H, *HEVC422), "slog3_vr_odd": (W, ODD_H, *HEVC422),
                "slog3_fr_vp9": (W, ODD_H, *VP9), "slog3_vr_vp9": (W, ODD_H, *VP9),
                "slog3_fr_422": (W, H, *HEVC422),
                "slog3_fr_vp9e": (W, H, *VP9), "slog3_vr_vp9e": (W, H, *VP9),
                "slog3_fr_webm": (W, H, *VP9[:4], ".webm")}
# The VP9 fixtures' tags are printed, not required (their range is).
TAGS_PRINTED = {"slog3_fr_vp9", "slog3_vr_vp9", "slog3_fr_vp9e", "slog3_vr_vp9e",
                "slog3_fr_webm"}
# L13 (B98, #289): the odd fixtures scored, in pairs (full range, its
# video-range twin); `slog3_fr_422` printed only. L13_OPEN: fixture → the
# issue a range-independent or unfixed pair was filed as; such a fixture is
# scored on REACHED alone, its hold figures printed beside the reference.
L13_PAIRS = (("slog3_fr_odd", "slog3_vr_odd"), ("slog3_fr_vp9", "slog3_vr_vp9"))
L13_PRINTED = ("slog3_fr_422",)
# Empty since B99 (#291, spec §11 GR-23): B98's VP9 pair was here because an
# MP4's VP9 track carries no `FullRangeVideo` extension, so GR-22's flag read
# it as video range (measured after PR-10: toe 90, spread 28); the flag now
# reads the track's `vpcC` range bit, and the pair is scored.
L13_OPEN: dict[str, str] = {}
L13_SPREAD = 2
# The read-back points: one ramp column on GREY_ROW and the 18 % patch.
READBACK_X = 512
RANGE_CHECKED = {}
INPUT_SWIFT = "app/Sources/InputConversions.swift"
STAGE_SWIFT = "app/Sources/Compositor+Input.swift"
SOURCES_SWIFT = "app/Sources/Compositor+Sources.swift"
COLOR_SWIFT = "app/Sources/MediaImporter+Color.swift"
SHADER = "app/Resources/Shaders/Compositor.metal"
BUILDER_SWIFT = "app/Sources/CompositionBuilder.swift"
RANGE_SWIFT = "app/Sources/CompositionBuilder+SourceRange.swift"
# B101 (#293, L15): AV1 fixtures, each one 64×64 1 s lavfi grey frame
# (libsvtav1, yuv420p10le). name: (range flag, `-movflags` value or None,
# container). A fixture is kept only when ffprobe reads `av1` and its range
# and the file holds a `colr` box exactly when `+write_colr`.
AV1_FIXTURES = {"av1_fr": ("pc", "-write_colr", ".mp4"),
                "av1_fr_colr": ("pc", "+write_colr", ".mp4"),
                "av1_vr": ("tv", "-write_colr", ".mp4"),
                "av1_fr_webm": ("pc", None, ".webm"),
                "av1_vr_webm": ("tv", None, ".webm")}
AV1_PROBE = ROOT / "tools/proof/av1_range_probe.swift"
# B101 (#294): `decode-gap`'s probe, fixtures, formats and verdict bound.
GAP_PROBE = ROOT / "tools/proof/decode_gap_probe.swift"
GAP_FIXTURES = ("slog3_fr", "slog3_vr", "slog3_fr_vp9e", "slog3_vr_vp9e")
GAP_PAIRS = (("slog3_fr", "slog3_fr_vp9e"), ("slog3_vr", "slog3_vr_vp9e"))
GAP_FORMATS = ("x420", "xf20", "64RGBAHalf", "128RGBAFloat", "64RGBALE")
GAP_REQUIRED = ("x420", "xf20", "64RGBAHalf")
GAP_BOUND = 0.5
# B102 (#294): `composition-gap`'s probe, its two settings and its stages in order.
COMPOSITION_PROBE = ROOT / "tools/proof/composition_gap_probe.swift"
GAP_SETTINGS = ("none", "slog3")
GAP_STAGES = (("tap", "source frames"), ("reader", "compositor"), ("generator", "generator"))
# B103 (#294, spec §11 PR-12): the 8-bit VP9 file (lavfi testsrc2, libvpx-vp9
# lossless Profile 0, yuv420p), L16's probe and its items (label → kind,
# whether `DeepVideoFrame.isDeep` must answer true), L17's deep renders and
# its printed codecs, and the mixed project (`vp9_8bit` at 0, `slog3_fr_vp9e`
# at 1 s on one track).
VP9_8BIT = "vp9_8bit"
DEEP_PROBE = ROOT / "tools/proof/deep_video_probe.swift"
L16_ITEMS = {"slog3_fr_vp9e": ("file", True), "slog3_vr_vp9e": ("file", True),
             "slog3_fr_vp9": ("file", True), "slog3_fr_webm": ("webm", True),
             VP9_8BIT: ("file", False), "slog3_fr": ("file", False),
             "slog3_fr_422": ("file", False), "slog3": ("file", False)}
L17_DEEP = ("slog3_fr_vp9e", "slog3_vr_vp9e", "slog3_fr_webm")
L17_PRINTED = ("slog3_fr", "slog3_fr_422", "slog3", VP9_8BIT)
MIXED = (VP9_8BIT, "slog3_fr_vp9e")
DEEP_SWIFT = "app/Sources/DeepVideoFrame.swift"
RENDER_SWIFT = "app/Sources/AgentServer+Render.swift"
# name: ([(file, anchor, replacement), …], the rows that must fail).
MUTANTS = {
    "source-unconverted": ([(SOURCES_SWIFT,
                             "                let texture = inputs.converted(trackID: id) ?? "
                             "texture(from: buffer, live: &live)\n",
                             "                let texture = texture(from: buffer, live: &live)\n")],
                           ["L1", "L3", "L4"]),
    "slog3-breakpoint": ([(SHADER, "constant float kSlog3Break = 171.2102946929;\n",
                           "constant float kSlog3Break = 181.0;\n")], ["LP3", "L1"]),
    "cine-as-709": ([(INPUT_SWIFT, "        case .sGamut3Cine: self = .sGamut3Cine\n",
                      "        case .sGamut3Cine: self = .bt709\n")], ["LP2", "L1", "L3"]),
    "detection-ignores-label": ([(COLOR_SWIFT,
                                  "    static func detectedColor(_ descriptions: "
                                  "[CMFormatDescription]) -> MediaColor? {\n",
                                  "    static func detectedColor(_ descriptions: "
                                  "[CMFormatDescription]) -> MediaColor? {\n"
                                  "        if !descriptions.isEmpty { return nil }\n")], ["L2"]),
    "ungraded-drops-input": ([("core/src/recipe.rs", "            input,\n",
                               "            input: if ungraded { Value::Null } else { input },\n")],
                             ["L7"]),
    "lut-no-half-texel": ([(SHADER,
                            "    float3 coord = saturate(signal) * ((n - 1.0) / n) + 0.5 / n;\n",
                            "    float3 coord = saturate(signal);\n")], ["LP3", "L5"]),
    "plan-input-dropped": ([("core/src/plan.rs",
                             "                segment.insert(\"input\".to_string(), input);\n",
                             "")], ["L1"]),
    # hdr H-2 (spec §11 HD-13): the choice moved into `choose(input:buffer:output:)`.
    "labels-over-setting": ([(INPUT_SWIFT,
                              "        let chosen = input.flatMap(choose(input:)) ?? choose(for: "
                              "buffer)\n",
                              "        let chosen = choose(for: buffer) ?? input.flatMap(choose("
                              "input:))\n")], ["L1"]),
    # hdr H-1 (spec §11 HD-12): the clear keeps a PQ file's peak, so the anchor is
    # the line that clears the Camera Log through `without_camera_log`.
    "remove-lut-keeps-conversion": ([("core/src/lut.rs",
                                      "                row.color = row.color.and_then(|color| "
                                      "color.without_camera_log());\n", "")], ["L8"]),
    "log2-as-log": ([(COLOR_SWIFT,
                      "                return MediaColor(log: .appleLog2, gamut: .appleWideGamut, "
                      "detected: true)\n",
                      "                return MediaColor(log: .appleLog, gamut: .bt2020, "
                      "detected: true)\n")], ["L2"]),
    # B95 (spec §11 GR-22).
    "full-range-ignored": ([(INPUT_SWIFT,
                             "        case .slog3, .vlog: return fullRange ? (1, 0) : "
                             "(videoCodeScale, videoCodeOffset)\n",
                             "        case .slog3, .vlog: return (videoCodeScale, "
                             "videoCodeOffset)\n")], ["L10", "L12"]),
    "apple-log-rescaled": ([(INPUT_SWIFT,
                             "        case .appleLog, .appleLog2: return (1, 0)\n",
                             "        case .appleLog, .appleLog2:\n"
                             "            return fullRange ? (1023.0 / 876.0, -64.0 / 876.0) : "
                             "(1, 0)\n")], ["L11"]),
    # `reversedAssets` holds, per media, the reverse's intermediate a reversed
    # clip reads: the range is then read from the intermediate, not the media.
    "range-from-reverse": ([(BUILDER_SWIFT,
                             "        let fullRange = fullRangeMedia(plan: plan, urls: urls, "
                             "assets: &assets)\n",
                             "        let fullRange = fullRangeMedia(plan: plan, urls: urls, "
                             "assets: &reversedAssets)\n")], ["L12"]),
    # B98 (#289, spec §11 PR-10): the odd-size reverse reads video-range `x422`
    # whatever the media's range flag, as before PR-10.
    "odd-range-ignored": ([("app/Sources/ReverseRenderer.swift",
                            "                return kCVPixelFormatType_422YpCbCr10BiPlanarFullRange\n",
                            "                return pixelFormat\n")], ["L13"]),
    # B99 (#291, spec §11 GR-23): a VP9 track's `vpcC` range bit unread, then
    # read from the wrong byte (7, the colour primaries).
    "vp9-range-ignored": ([(RANGE_SWIFT,
                            "        return vp9FullRange(of: description) ?? false\n",
                            "        return false\n")], ["L13", "L14"]),
    "vpcc-wrong-byte": ([(RANGE_SWIFT,
                          "        return record[record.startIndex + 6] & 1 == 1\n",
                          "        return record[record.startIndex + 7] & 1 == 1\n")],
                        ["L13", "L14"]),
    # B103 (#294, spec §11 PR-12): `isDeep` never true; 8 bits counted deep;
    # the depth read from the low nibble (chroma and range, ≤ 7 for every
    # fixture); the composition track counted by any description it lists
    # instead of its segment at the frame time; JPEG asked to keep depth.
    "vp9-deep-never": ([(DEEP_SWIFT, "        return record[record.startIndex + 6] >> 4 > 8\n",
                         "        return false\n")], ["L14", "L16", "L17"]),
    "vp9-depth-eight": ([(DEEP_SWIFT, "        return record[record.startIndex + 6] >> 4 > 8\n",
                          "        return record[record.startIndex + 6] >> 4 >= 8\n")], ["L16"]),
    "vpcc-depth-nibble": ([(DEEP_SWIFT, "        return record[record.startIndex + 6] >> 4 > 8\n",
                            "        return record[record.startIndex + 6] & 0x0f > 8\n")],
                          ["L14", "L16", "L17"]),
    "vp9-track-wide": ([(DEEP_SWIFT,
                         "            if let shown = description(of: track, at: time), "
                         "isDeep(shown) { return true }\n",
                         "            if (CompositionBuilder.keyed(track, \"formatDescriptions\") "
                         "as? [CMFormatDescription] ?? []).contains(where: isDeep) "
                         "{ return true }\n")], ["L18"]),
    "vp9-jpeg-deep": ([(RENDER_SWIFT, "            graphics: graphics, keepsDepth: format.carriesDepth)\n",
                        "            graphics: graphics, keepsDepth: true)\n")], ["L18"]),
}
# B96 (#280): the reverse's intermediate variants, each one edit to the plain
# `.hevcMain10` path of ReverseRenderer.swift (`reverse-variants`). The rate
# variants scale `bits` AFTER its clamps: the log fixtures sit at the 2 Mbps
# floor, where scaling the 0.12 factor would leave rate2 a no-op.
REVERSER = "app/Sources/ReverseRenderer.swift"
X420_LINE = "            case .hevcMain10: return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange\n"
X420_BYTES = "            case .hevcMain10: return 3\n"
MAIN10_LINE = ("            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as "
               "String,\n")
RATE_LINE = "            AVVideoAverageBitRateKey: bits,\n"
INIT_LINE = ("            self = dimensions.width % 2 != 0 || dimensions.height % 2 != 0 ? "
             ".proRes422 : .hevcMain10\n")
PRORES_LINE = "                AVVideoCodecKey: AVVideoCodecType.proRes422,\n"
X422_EDITS = [(REVERSER, X420_LINE, X420_LINE.replace("420YpCbCr", "422YpCbCr")),
              (REVERSER, X420_BYTES, "            case .hevcMain10: return 4\n")]
PRORES_EDIT = (REVERSER, INIT_LINE, "            self = .proRes422\n")
REVERSE_VARIANTS = {
    "base": [],
    "x422": X422_EDITS,
    "main422": X422_EDITS + [(REVERSER, MAIN10_LINE,
                              MAIN10_LINE.replace("Main10_AutoLevel", "Main42210_AutoLevel"))],
    **{f"rate{k}": [(REVERSER, RATE_LINE,
                     f"            AVVideoAverageBitRateKey: min(bits * {k}, 240_000_000),\n")]
       for k in (2, 4, 8)},
    "quality": [(REVERSER, RATE_LINE, "            AVVideoQualityKey: 1.0,\n")],
    "prores422": [PRORES_EDIT],
    "prores422hq": [PRORES_EDIT, (REVERSER, PRORES_LINE,
                                  PRORES_LINE.replace("proRes422,", "proRes422HQ,"))],
}
# The log fixtures each variant reverses, and the cost fixtures: 2 s of grain
# detail, 10-bit ProRes 422 HQ, untagged. The temporal grain stops an
# average-rate encoder from undershooting, so a ratio there reads as a rate
# ratio.
VARIANT_LOGS = ["slog3", "applelog", "slog3_fr"]
DETAIL = {"detail_1080": (1920, 1080), "detail_2160": (3840, 2160)}
DETAIL_SECONDS = 2
# Apple's published target rates (Apple ProRes White Paper, its 29.97 fps
# table), Mbit/s: ProRes 422 and 422 HQ — the size estimate's source.
APPLE_PRORES = {"detail_1080": (117, 176), "detail_2160": (471, 707)}
# Fixed before any run (the spec): a variant HOLDS when every log fixture's
# worst |Y₁₅ − expected| is ≤ 1, and QUALIFIES when it holds and both detail
# ratios to `base` are ≤ 2.0; the choice is the qualifier with the smallest
# 2160 ratio, a tie within 5 % going to the earlier one.
HOLD_BOUND = 1
RATIO_BOUND = 2.0
TIE = 0.05
rows = {}
selected = set(ROWS)
REFUSED = {}


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    mark = "  ok   " if good else "  FAIL "
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


attempt, reply, code8, close_to = hdr.attempt, hdr.reply, hdr.code8, hdr.close_to
mat_mul, mat_vec, mat_inv = hdr.mat_mul, hdr.mat_vec, hdr.mat_inv


# ---- the oracle -----------------------------------------------------------------

def npm(name):
    """RGB → XYZ for `name`'s primaries and D65 (the standard derivation)."""
    columns = [[x / y, 1.0, (1 - x - y) / y] for x, y in PRIMARIES[name]]
    p = [[columns[j][i] for j in range(3)] for i in range(3)]
    xw, yw = D65
    s = mat_vec(mat_inv(p), [xw / yw, 1.0, (1 - xw - yw) / yw])
    return [[p[i][j] * s[j] for j in range(3)] for i in range(3)]


def to709(name):
    return mat_mul(mat_inv(npm("bt709")), npm(name))


def encode_curve(curve, r):
    """The maker's encode: scene reflection → its signal (y = CV/1023, or Apple's P)."""
    if curve in ("apple_log", "apple_log2"):
        a = APPLE
        if r >= a["rt"]:
            return a["g"] * math.log2(r + a["b"]) + a["d"]
        return a["c"] * (r - a["r0"]) ** 2 if r >= a["r0"] else 0.0
    if curve == "slog3":
        if r >= 0.01125:
            return (420 + 261.5 * math.log10((r + 0.01) / 0.19)) / 1023
        return (r * (SLOG3_BREAK - 95) / 0.01125 + 95) / 1023
    v = VLOG
    return 5.6 * r + 0.125 if r < v["cut1"] else v["c"] * math.log10(r + v["b"]) + v["d"]


def decode_curve(curve, y):
    """The maker's inverse: signal → scene reflection."""
    if curve in ("apple_log", "apple_log2"):
        a = APPLE
        pt = a["c"] * (a["rt"] - a["r0"]) ** 2
        if y < 0:
            return a["r0"]
        if y < pt:
            return math.sqrt(y / a["c"]) + a["r0"]
        return 2 ** ((y - a["d"]) / a["g"]) - a["b"]
    if curve == "slog3":
        if y >= SLOG3_BREAK / 1023:
            return 10 ** ((y * 1023 - 420) / 261.5) * 0.19 - 0.01
        return (y * 1023 - 95) * 0.01125 / (SLOG3_BREAK - 95)
    v = VLOG
    return (y - 0.125) / 5.6 if y < v["cut2"] else 10 ** ((y - v["d"]) / v["c"]) - v["b"]


def shoulder(m, white):
    if m <= KNEE:
        return m
    if m >= white:
        return 1.0
    t, tw = (m - KNEE) / (1 - KNEE), (white - KNEE) / (1 - KNEE)
    return KNEE + (1 - KNEE) * t * (1 + t / (tw * tw)) / (1 + t)


def display(curve, gamut, light):
    """Scene light (reflection, the camera gamut) → encoded BT.709."""
    linear = mat_vec(to709(gamut), [c * EXPOSURE for c in light])
    out = list(linear)
    low = min(out)
    if low < 0:
        y = sum(w * c for w, c in zip(LUMA709, out))
        out = [0.0] * 3 if y <= 0 else [y + (c - y) * y / (y - low) for c in out]
    top = max(out)
    if top > KNEE:
        out = [c * shoulder(top, LOG_WHITE) / top for c in out]
    return [max(c, 0.0) ** (1 / DISPLAY_GAMMA) for c in out]


def log_convert(curve, gamut, rgb):
    """GR-16's step 0 on one straight decoded signal s (per channel)."""
    scale, offset = CODE[curve]
    return display(curve, gamut, [decode_curve(curve, c * scale + offset) for c in rgb])


def stored_code(curve, r):
    """The fixture's 10-bit Y for scene reflection `r` (GR-16's code domains)."""
    y = encode_curve(curve, r)
    if curve in ("apple_log", "apple_log2"):
        return min(1023, max(0, round(64 + 876 * y)))
    return min(1023, max(0, round(1023 * y)))


def signal(code):
    return (code - 64) / 876


def lut_function(r, g, b):
    return (0.7 * r + 0.2 * g + 0.1 * b * b, g * g, 0.5 * b + 0.3 * r)


def cube_text(size):
    step = size - 1
    lines = [f"LUT_3D_SIZE {size}"]
    for b in range(size):
        for g in range(size):
            for r in range(size):
                lines.append(" ".join(f"{v:.6f}" for v in lut_function(r / step, g / step,
                                                                        b / step)))
    return "\n".join(lines) + "\n"


def trilinear(size, rgb):
    """The lattice (as written: six decimals, then half) at `rgb`, trilinear
    between lattice points at i/(size − 1), the input clamped to [0, 1]."""
    def at(i, j, k):
        step = size - 1
        return [hdr.half(float(f"{v:.6f}")) for v in lut_function(i / step, j / step, k / step)]
    p = [min(max(c, 0.0), 1.0) * (size - 1) for c in rgb]
    i0 = [min(int(math.floor(c)), size - 2) for c in p]
    f = [c - i for c, i in zip(p, i0)]
    out = [0.0, 0.0, 0.0]
    for dr in (0, 1):
        for dg in (0, 1):
            for db in (0, 1):
                w = ((f[0] if dr else 1 - f[0]) * (f[1] if dg else 1 - f[1])
                     * (f[2] if db else 1 - f[2]))
                v = at(i0[0] + dr, i0[1] + dg, i0[2] + db)
                out = [o + w * c for o, c in zip(out, v)]
    return out


# ---- fixtures -------------------------------------------------------------------

def raw_ramp(curve):
    """One yuv422p10le frame of `curve`'s ramp and patches."""
    ramp = [stored_code(curve, RMAX * x / (W - 1)) for x in range(W)]
    patches = PATCHES[curve]
    luma = []
    for y in range(H):
        luma += ramp if y < 64 else [patches[min(2, x * 3 // W)] for x in range(W)]
    chroma = [512] * (W // 2 * H)
    return struct.pack(f"<{len(luma) + 2 * len(chroma)}H", *luma, *chroma, *chroma)


def green_codes():
    """The card's (Y, Cb, Cr): S-Log3's CV per channel of GREEN_LIGHT, as the
    decoded signal s = (CV − 64)/876, through the bt2020nc matrix."""
    s = [(1023 * encode_curve("slog3", c) - 64) / 876 for c in GREEN_LIGHT]
    kr, kb = hdr.KR_KB["bt2020nc"]
    yy = kr * s[0] + (1 - kr - kb) * s[1] + kb * s[2]
    pb, pr = (s[2] - yy) / (2 * (1 - kb)), (s[0] - yy) / (2 * (1 - kr))
    return round(64 + 876 * yy), round(512 + 896 * pb), round(512 + 896 * pr)


def raw_green():
    y, cb, cr = green_codes()
    n, c = W * H, W // 2 * H
    return struct.pack(f"<{n + 2 * c}H", *([y] * n), *([cb] * c), *([cr] * c))


def encode(name, raw, tagset):
    """`raw` (one frame) looped to 1 s of ProRes 422 HQ with `tagset`'s tags
    (None: the bitstream's `unknown`, no `colr`; a None entry: that tag left
    `unknown`, the others written)."""
    out = MEDIA / f"{name}.mov"
    if out.exists():
        return out
    MEDIA.mkdir(parents=True, exist_ok=True)
    source = MEDIA / f"{name}.yuv"
    source.write_bytes(raw)
    bsf, colr = "", []
    if tagset is not None:
        pairs = [(key, flag, value) for (key, flag), value in
                 zip((("color_primaries", "-color_primaries"), ("color_trc", "-color_trc"),
                      ("colorspace", "-colorspace")), tagset) if value is not None]
        bsf = "prores_metadata=" + ":".join(f"{key}={value}" for key, _, value in pairs)
        colr = [part for _, flag, value in pairs for part in (flag, value)] \
            + ["-movflags", "+write_colr"]
    plain = MEDIA / f"{name}-plain.mov"
    made = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt",
                        "yuv422p10le", "-s", f"{W}x{H}", "-r", "30", "-stream_loop", "29",
                        "-i", str(source), "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt",
                        "yuv422p10le", "-color_primaries", "unknown", "-color_trc", "unknown",
                        "-colorspace", "unknown", str(plain)], 300)
    source.unlink(missing_ok=True)
    if made["rc"] == 0 and tagset is None:
        # The plain encode is already untagged (ffprobe: unknown ×3); the
        # bsf's `unknown` would write 0, which ffprobe reads as gbr/reserved.
        plain.rename(out)
    elif made["rc"] == 0:
        # Re-tagged by stream copy, as hdr_proof.py's `retag` does.
        made = bounded.run(["ffmpeg", "-v", "error", "-y", "-i", str(plain), "-c", "copy",
                            "-bsf:v", bsf, *colr, str(out)], 120)
    plain.unlink(missing_ok=True)
    if made["rc"] != 0 or not out.exists():
        REFUSED[name] = f"ffmpeg {name}: rc {made['rc']} {made['stderr'][-300:]}"
        out.unlink(missing_ok=True)
        return None
    return out


def checked(name, out, want):
    """`out` kept only when ffprobe reads every (key, value) of `want`."""
    if out is None:
        REFUSED[name] = REFUSED.get(name) or f"{name} was not made"
        return None
    probe = hdr.stream(out)
    wrong = {k: probe.get(k) for k, v in want.items()
             if probe.get(k, "unknown" if v == "unknown" else None) != v}
    if wrong:
        REFUSED[name] = f"{out.name} refused: ffprobe read {wrong}, want {want}"
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        return None
    return out


def relabel(name, source, mode):
    """`source` relabelled Apple Log (`mode` log) or Apple Log 2 (log2) by
    applelog_writer.swift; a writer that will not build or refuses is the
    fixture's FAIL."""
    out = MEDIA / f"{name}.mov"
    if out.exists():
        return out
    writer = BASE / "applelog-writer" / "applelog_writer"
    try:
        swift_build.build(sources=[WRITER], output=writer, timeout=BUILD_BOUND)
    except swift_build.SwiftBuildFailed as failure:
        REFUSED[name] = f"applelog_writer did not build: {str(failure)[:300]}"
        return None
    argv = [str(writer), str(source), str(out)] + (["log2"] if mode == "log2" else [])
    made = bounded.run(argv, 120)
    print(f"       applelog_writer {mode}: {(made['stdout'] + made['stderr']).strip()[-200:]}",
          flush=True)
    if made["rc"] != 0 or not out.exists():
        REFUSED[name] = f"applelog_writer {mode} exited {made['rc']}"
        out.unlink(missing_ok=True)
        return None
    return out


def fixture(name):
    """`name`'s file under MEDIA, made when missing; None when refused."""
    if name in RANGE_FIXTURES:
        return range_fixture(name)
    if name in FIXTURES:
        curve, tagset, mode = FIXTURES[name]
        made = encode(f"{name}-ramp" if mode else name, raw_ramp(curve), tagset)
        if mode:
            made = relabel(name, made, mode) if made else None
            want = {"color_space": "bt2020nc", "color_transfer": "unknown"}
            if mode == "log":
                want["color_primaries"] = "bt2020"
            return checked(name, made, want)
        if tagset is None:
            kept = checked(name, made, {"codec_name": "prores", "pix_fmt": "yuv422p10le"})
            probe = hdr.stream(kept) if kept else {}
            if kept and any(probe.get(k, "unknown") != "unknown" for k in
                            ("color_primaries", "color_transfer", "color_space")):
                REFUSED[name] = f"{name}.mov refused: ffprobe read {hdr.tags(probe)}"
                kept.unlink()
                return None
            return kept
        primaries, transfer, matrix = tagset
        return checked(name, made, {"pix_fmt": "yuv422p10le", "color_primaries": primaries,
                                    "color_transfer": transfer, "color_space": matrix})
    if name == "green":
        return checked(name, encode("green", raw_green(), ("bt2020", "bt709", "bt2020nc")),
                       {"pix_fmt": "yuv422p10le", "color_primaries": "bt2020",
                        "color_transfer": "bt709", "color_space": "bt2020nc"})
    if name == "green_m":
        # The same card tagged with its matrix alone (GRD-18: how a real
        # camera file may arrive), primaries and transfer left unknown.
        return checked(name, encode("green_m", raw_green(), (None, None, "bt2020nc")),
                       {"pix_fmt": "yuv422p10le", "color_primaries": "unknown",
                        "color_transfer": "unknown", "color_space": "bt2020nc"})
    if name == VP9_8BIT:
        return vp9_8bit_fixture()
    if name in ("lut17", "lut33"):
        out = MEDIA / f"{name}.cube"
        if not out.exists():
            MEDIA.mkdir(parents=True, exist_ok=True)
            out.write_text(cube_text(int(name[3:])))
        return out
    if name in ("tone", "still"):
        out = MEDIA / ("tone.wav" if name == "tone" else "still.png")
        if not out.exists():
            MEDIA.mkdir(parents=True, exist_ok=True)
            source = ["sine=frequency=440:duration=1"] if name == "tone" \
                else ["color=c=gray:size=64x64", "-frames:v", "1"]
            bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", *source, str(out)],
                        60)
        if not out.exists():
            REFUSED[name] = f"ffmpeg did not make {out.name}"
            return None
        return out
    raise ValueError(name)


def range_code(curve, r):
    """A range fixture's stored 10-bit code: 1023·y (Apple's 1023·P)."""
    return min(1023, max(0, round(1023 * encode_curve(curve, r))))


def raw_range(curve, width=W, height=H, sub_x=2, sub_y=2):
    """One 10-bit planar frame (chroma subsampled by `sub_x`, `sub_y`, sized
    by ceil) of `curve`'s ramp (rows below 64) and patches (the rest) as
    range_code stores them: (bytes, the ramp's codes, the three patches'
    codes)."""
    ramp = [range_code(curve, RMAX * x / (width - 1)) for x in range(width)]
    patches = [range_code(curve, r) for r in REFLECTANCE]
    luma = []
    for y in range(height):
        luma += ramp if y < 64 else [patches[min(2, x * 3 // width)] for x in range(width)]
    chroma = [512] * (-(-width // sub_x) * -(-height // sub_y))
    return struct.pack(f"<{len(luma) + 2 * len(chroma)}H", *luma, *chroma, *chroma), ramp, patches


def range_stream(path):
    """ffprobe's codec, profile, pix_fmt, size, range and tags of `path`'s
    video."""
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt,width,height,color_range,color_space,"
                       "color_transfer,color_primaries", "-of", "json", str(path)], 60)
    try:
        return json.loads(ran["stdout"])["streams"][0]
    except (ValueError, KeyError, IndexError):
        return {}


def range_fixture(name):
    """A RANGE_FIXTURES file, kept only when ffprobe reads its range (and its
    tags, or none) and `source_yuv` reads back the written code at one ramp
    point and one patch; else None, REFUSED[name] naming the code read. The
    range and the tags are given to the INPUT as well as the output: given to
    the output alone, ffmpeg converts the codes at encode (B95's
    objection). A RANGE_SHAPES name (B98) is written at its size, pix_fmt,
    encoder and extension, and wanted with its codec, profile and size."""
    if name in RANGE_CHECKED:
        return RANGE_CHECKED[name]
    curve, flag, tagset = RANGE_FIXTURES[name]
    width, height, pix_fmt, encoder, codec, profile, extension = \
        RANGE_SHAPES.get(name, RANGE_DEFAULT)
    sub_x, sub_y = (1, 1) if "444" in pix_fmt else (2, 1) if "422" in pix_fmt else (2, 2)
    raw, ramp, patches = raw_range(curve, width, height, sub_x, sub_y)
    out = MEDIA / f"{name}{extension}"
    tags = [] if tagset is None else ["-color_primaries", tagset[0], "-color_trc", tagset[1],
                                      "-colorspace", tagset[2]]
    if not out.exists():
        MEDIA.mkdir(parents=True, exist_ok=True)
        source = MEDIA / f"{name}.yuv"
        source.write_bytes(raw)
        # `-pix_fmt` sits after the codec's first pair, where B95's argv had it.
        made = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt",
                            pix_fmt, "-s", f"{width}x{height}", "-r", "30", "-color_range", flag,
                            *tags, "-stream_loop", "29", "-i", str(source), *encoder[:4],
                            "-pix_fmt", pix_fmt, *encoder[4:], "-color_range", flag, *tags,
                            str(out)], 300)
        source.unlink(missing_ok=True)
        if made["rc"] != 0 or not out.exists():
            REFUSED[name] = f"ffmpeg {name}: rc {made['rc']} {made['stderr'][-300:]}"
            out.unlink(missing_ok=True)
            RANGE_CHECKED[name] = None
            return None
    probe = range_stream(out)
    want = {"codec_name": codec, "profile": profile, "pix_fmt": pix_fmt, "color_range": flag}
    if name in RANGE_SHAPES:
        want.update({"width": width, "height": height})
    if tagset is not None:
        want.update({"color_primaries": tagset[0], "color_transfer": tagset[1],
                     "color_space": tagset[2]})
    wrong = {k: probe.get(k) for k, v in want.items() if probe.get(k) != v}
    if tagset is None and name not in TAGS_PRINTED:
        wrong.update({k: probe.get(k) for k in ("color_primaries", "color_transfer",
                                                 "color_space")
                      if probe.get(k, "unknown") != "unknown"})
    yuv = None if wrong else source_yuv(out, height)
    read = (yuv.codes(READBACK_X, GREY_ROW)[0], yuv.codes(PATCH_X[1], PATCH_ROW)[0]) \
        if yuv else None
    written = (ramp[READBACK_X], patches[1])
    if wrong or read != written:
        REFUSED[name] = (f"{out.name} refused: ffprobe read {wrong or 'as wanted'}; read back Y "
                         f"{read} at ({READBACK_X}, {GREY_ROW}) and ({PATCH_X[1]}, {PATCH_ROW}), "
                         f"written {written}")
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        RANGE_CHECKED[name] = None
        return None
    print(f"       {out.name} kept: {probe.get('codec_name')} {probe.get('profile')} "
          f"{probe.get('pix_fmt')} {probe.get('width')}×{probe.get('height')}, {hdr.tags(probe)} "
          f"range {probe.get('color_range')}, read back Y {read} = written", flush=True)
    RANGE_CHECKED[name] = out
    return out


def media_extension(name):
    """The extension `fixture(name)` writes: a range fixture's by its shape,
    `vp9_8bit`'s `.mp4`, every other `.mov`."""
    if name in RANGE_FIXTURES:
        return RANGE_SHAPES.get(name, RANGE_DEFAULT)[6]
    return ".mp4" if name == VP9_8BIT else ".mov"


def l9_media(name, control):
    """L9's (and L18's) fixture: DIR's copy when DIR holds one (compare,
    mutants), else MEDIA's (capture copies it into DIR, its extension kept)."""
    if control is not None:
        copy = control / "media" / f"{name}{media_extension(name)}"
        if copy.exists():
            return copy
        REFUSED[name] = f"{copy} is missing from the control"
        return None
    return fixture(name)


# ---- the documents --------------------------------------------------------------

class Doc(hdr.Doc):
    """hdr_proof's document, its files under this script's WORK."""

    def __init__(self, client, name, width=W, height=H):
        self.client, self.width, self.height = client, width, height
        self.path = WORK / f"{name}.framejob"
        self.made = attempt(client, "new_project", {"path": str(self.path)})["ok"]
        self.call("set_canvas", width=width, height=height, fps=[30, 1])
        c = self.project().get("canvas") or {}
        self.ok = self.made and c.get("width") == width and c.get("height") == height
        self.why = None if self.ok else "the project or its canvas was not made"
        self._media = {}

    def media_id(self, path):
        """`path` imported once; its media id."""
        if path not in self._media:
            got = self.call("import_media", path=str(path))
            self._media[path] = reply(got).get("media")
            if self._media[path] is None:
                self.ok, self.why = False, f"import {Path(path).name}: {got.get('error')}"
        return self._media[path]

    def place(self, path, at=0):
        """`path` imported once and placed on the first track at `at`, its
        Camera Log left as import wrote it; the clip id."""
        media = self.media_id(path)
        if media is None:
            return None
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=self.track(), media=media, at=at)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not got["ok"] or len(new) != 1:
            self.ok, self.why = False, f"add_clip {Path(path).name}: {got.get('error')}"
            return None
        return new[0]

    def row(self, media):
        return next((m for m in self.project().get("media") or [] if m.get("id") == media), {})

    def color(self, media, color):
        return self.call("set_media_color", media=media, color=color)

    def render(self, tag, t=T, **extra):
        out = WORK / f"{tag}.png"
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=t, path=str(out), **extra)
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def export(self, tag):
        out = WORK / f"{tag}.mov"
        out.unlink(missing_ok=True)
        got = self.call("export", preset="prores_422", path=str(out), size="document")
        if not (got["ok"] and out.exists()):
            print(f"       export {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def save(self, name):
        path = WORK / f"{name}.framejob"
        got = self.call("save_project", path=str(path))
        if got["ok"]:
            self.path = path
        return path if got["ok"] else None


def wait_reverse(doc, tag):
    folder = Path(doc.path) / "cache" / "reversed"
    deadline = time.monotonic() + REVERSE_BOUND
    while True:
        files = sorted(folder.glob("*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob("*.partial"))
        if files and not partial:
            got = doc.call("snapshot_ui", window="sheet", path=str(WORK / f"{tag}-sheet.png"))
            if not got["ok"] and "no sheet attached" in got.get("error", ""):
                return files, None
        if time.monotonic() > deadline:
            doc.call("cancel_sheet")
            return files, f"the reverse did not finish within {REVERSE_BOUND} s"
        time.sleep(0.25)


def frame(png):
    f = hdr.Frame(png, W, H) if png else None
    return f if f and f.ok else None


def sample_points():
    """The grey row's every 8th column and the three patch centres."""
    return [(x, GREY_ROW) for x in range(0, W, 8)] + [(x, PATCH_ROW) for x in PATCH_X]


def samples(png_frame):
    """The render's 8-bit values at sample_points(): [(x, y, rgb8)]."""
    return [(x, y, png_frame.px8(x, y)) for x, y in sample_points()]


def source_yuv(path, height=H):
    got = hdr.yuv_frames(path, W, height)
    return got[0] if got else None


def oracle_at(curve, gamut, yuv, x, y, matrix="bt2020nc"):
    """The oracle at a pixel, its decoded signal rounded to half first: step 0
    reads an `rgba16Float` source (hdr_probe.swift's P3 rounds its inputs the
    same way), and next to black the display transform is steep enough that
    the rounding alone is a level (S-Log3's 95: 0 unrounded, 0.84 rounded)."""
    s = [hdr.half(c) for c in hdr.rgb_of(*yuv.codes(x, y), matrix)]
    return [code8(c) for c in log_convert(curve, gamut, s)]


def spread(a, b):
    return max(abs(p - q) for p, q in zip(a, b))


# ---- L1, L2 ---------------------------------------------------------------------

def scene(client, name, tag, color, extra=None):
    """`name` alone (Camera Log `color`, or None for none / cleared), with
    `extra(doc, clip)` applied, rendered at T: (Frame, Doc closed?, why)."""
    path = fixture(name)
    if path is None:
        return None, f"{name} refused: {REFUSED.get(name)}"
    doc = Doc(client, tag)
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    set_to = doc.color(media, color) if clip is not None else {"ok": False}
    why = None if set_to["ok"] else f"set_media_color: {set_to.get('error')}"
    if extra and clip is not None:
        why = extra(doc, clip) or why
    png = doc.render(tag) if clip is not None else None
    doc.close()
    got = frame(png)
    return got, (why or doc.why or ("no render" if got is None else None))


def run_l1(client):
    misses, worst = [], {}
    for name in ("slog3", "vlog", "applelog", "applelog2", "green", "green_m"):
        curve = SETTINGS[name]["log"]
        got, why = scene(client, name, f"l1-{name}", SETTINGS[name])
        yuv = source_yuv(fixture(name)) if fixture(name) else None
        if got is None or yuv is None or why:
            misses.append(f"{name}: {why or 'no decode'}")
            continue
        gamut = SETTINGS[name].get("gamut") or GAMUTS[curve][0]
        if name in ("green", "green_m"):
            # The chromatic card: a grey row cannot see a gamut matrix.
            # `green_m` is the card tagged with its matrix alone, scored
            # against its own decode as every fixture is.
            points = [(x, y, got.px8(x, y)) for x, y in ((W // 2, H // 2), (100, 20),
                                                          (900, 110))]
        else:
            # Every 8th column and the three patches, and every column of the
            # first 32: each curve's toe and break sit in them (S-Log3's break,
            # code 171.2, falls between columns 9 and 10).
            points = samples(got) + [(x, GREY_ROW, got.px8(x, GREY_ROW))
                                     for x in range(32) if x % 8]
        gaps = [(x, y, v, oracle_at(curve, gamut, yuv, x, y)) for x, y, v in points]
        worst[name] = max(spread(v, o) for _, _, v, o in gaps)
        bad = [(x, y, v, o) for x, y, v, o in gaps if spread(v, o) > 1]
        if bad:
            misses.append(f"{name}: {len(bad)} samples off, e.g. {bad[:3]}")
        patches = [o for x, y, v, o in gaps if y == PATCH_ROW]
        print(f"       {name}: oracle patches {patches}, render "
              f"{[v for x, y, v, o in gaps if y == PATCH_ROW]}", flush=True)
    check("L1 each fixture with its Camera Log set: the grey row every 8th column and every "
          "column of the first 32 (the toes and breaks), the three makers' patches, and "
          "green.mov's S-Log3 / S-Gamut3.Cine card, fully tagged and tagged with its matrix "
          "alone (green_m.mov), at 0.5 s = the oracle ±1 at 8 bits",
          not misses,
          f"worst {worst}; {misses}")


def run_l2(client):
    want = {"applelog": {"log": "apple_log", "gamut": "bt2020", "detected": True},
            "applelog2": {"log": "apple_log2", "gamut": "apple_wide_gamut", "detected": True},
            "slog3": None}
    doc = Doc(client, "l2")
    got = {}
    for name in want:
        path = fixture(name)
        media = doc.media_id(path) if path and doc.ok else None
        got[name] = doc.row(media).get("color") if media is not None else "not imported"
    doc.close()
    check("L2 applelog.mov imports with color {apple_log, bt2020, detected}, applelog2.mov with "
          "{apple_log2, apple_wide_gamut, detected}, slog3.mov with none",
          got == want, f"got {got}")


# ---- L3, L4, L5 -----------------------------------------------------------------

def card_oracle():
    y, cb, cr = green_codes()
    s = hdr.rgb_of(y, cb, cr, "bt2020nc")
    return log_convert("slog3", "s_gamut3_cine", s), s


def card(png_frame):
    return png_frame.px8(W // 2, H // 2)


def run_l3(client):
    converted, log_green = card_oracle()
    path = fixture("green")
    if path is None:
        check("L3 the key sees converted values", False, REFUSED.get("green"))
        return
    shown = {}
    for tag, key in (("plain", None), ("converted", converted), ("log", log_green)):
        doc = Doc(client, f"l3-{tag}")
        doc.call("set_canvas", background=[1, 0, 1, 1])
        clip = doc.place(path) if doc.ok else None
        set_to = doc.color(doc._media.get(path), SETTINGS["green"]) if clip else {"ok": False}
        keyed = doc.call("set_video", clips=[clip], patch={"chroma": {
            "key": [round(c, 6) for c in key], "tolerance": 0.05, "softness": 0.1,
            "spill": 0}}) if key and clip else {"ok": True}
        got = frame(doc.render(f"l3-{tag}")) if set_to["ok"] and keyed["ok"] else None
        doc.close()
        shown[tag] = card(got) if got else None
    good = (shown["converted"] is not None and close_to(shown["converted"], [255, 0, 255], 8)
            and shown["log"] is not None and shown["plain"] is not None
            and close_to(shown["log"], shown["plain"], 8))
    check("L3 green.mov (Camera Log S-Log3 / S-Gamut3.Cine) over magenta, keyed (tolerance "
          "0.05) with the oracle's converted green, shows magenta ±8 at the card; keyed with the "
          "log green the card stays (= the unkeyed render ±8)", good,
          f"converted key {[round(c, 4) for c in converted]} → {shown['converted']}; log key "
          f"{[round(c, 4) for c in log_green]} → {shown['log']}; unkeyed {shown['plain']} "
          f"(oracle {[code8(c) for c in converted]})")


def run_l4(client):
    grade = {"color": {"saturation": -0.5, "brightness": 0.1}}
    path = fixture("slog3")
    if path is None:
        check("L4 Color's four act on converted values", False, REFUSED.get("slog3"))
        return

    def graded(doc, clip):
        got = doc.call("set_video", clips=[clip], patch=grade)
        return None if got["ok"] else f"set_video: {got.get('error')}"
    a, why_a = scene(client, "slog3", "l4-graded", SETTINGS["slog3"], graded)
    raw, why_raw = scene(client, "slog3", "l4-unconverted", None, graded)
    doc = Doc(client, "l4-export")
    clip = doc.place(path) if doc.ok else None
    set_to = doc.color(doc._media.get(path), SETTINGS["slog3"]) if clip else {"ok": False}
    exported = doc.export("l4-plain") if set_to["ok"] else None
    doc.close()
    b = None
    if exported:
        ref = Doc(client, "l4-ref")
        ref_clip = ref.place(exported) if ref.ok else None
        if ref_clip is not None and graded(ref, ref_clip) is None:
            b = frame(ref.render("l4-ref"))
        ref.close()
    if a is None or b is None or raw is None:
        check("L4 Color's four act on converted values", False,
              f"graded {why_a}; unconverted {why_raw}; export {exported}; ref {b}")
        return
    sa, sb, sr = samples(a), samples(b), samples(raw)
    gap = max(spread(p[2], q[2]) for p, q in zip(sa, sb))
    apart = max(spread(p[2], q[2]) for p, q in zip(sa, sr))
    check("L4 Color's four (saturation −0.5, brightness 0.1) on slog3.mov with Camera Log = the "
          "same on its own prores_422 export placed alone ±2, and ≥ 10 levels from the same "
          "grade with Camera Log None", gap <= 2 and apart >= 10,
          f"max |Δ| to the export's {gap}; to the unconverted grade {apart}")


def lut3d_reference(path, cube):
    """ffmpeg's trilinear lut3d of `path`'s first frame (limited range, the
    bt2020 matrix), as an rgb48le Frame-like reader."""
    out = WORK / f"lut3d-{path.stem}.png"
    made = bounded.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-frames:v", "1", "-vf",
                        "scale=in_color_matrix=bt2020:in_range=tv:out_range=pc,format=rgb48le,"
                        f"lut3d=file={cube}:interp=trilinear", str(out)], 120)
    return frame(out) if made["rc"] == 0 and out.exists() else None


def run_l5(client):
    cube = fixture("lut33")
    misses, worst = [], {}
    for name in ("slog3", "green", "green_m"):
        path = fixture(name)
        if path is None:
            misses.append(f"{name}: {REFUSED.get(name)}")
            continue
        doc = Doc(client, f"l5-{name}")
        clip = doc.place(path) if doc.ok else None
        lut = doc.media_id(cube) if clip is not None else None
        set_to = doc.color(doc._media.get(path), {"lut": lut}) if lut is not None \
            else {"ok": False}
        got = frame(doc.render(f"l5-{name}")) if set_to["ok"] else None
        doc.close()
        want = lut3d_reference(path, cube)
        if got is None or want is None:
            misses.append(f"{name}: render {got is not None} ({set_to.get('error')}), "
                          f"ffmpeg {want is not None}")
            continue
        points = ([(x, y) for x, y, _ in samples(got)] if name == "slog3"
                  else [(W // 2, H // 2), (100, 20), (900, 110)])
        gaps = [(x, y, got.px8(x, y), want.px8(x, y)) for x, y in points]
        worst[name] = max(spread(g, w) for _, _, g, w in gaps)
        bad = [g for g in gaps if spread(g[2], g[3]) > 2]
        if bad:
            misses.append(f"{name}: {len(bad)} off, e.g. {bad[:3]}")
    check("L5 Use LUT (a channel-distinct 33³ cube as the media's conversion) on slog3.mov, "
          "green.mov and green_m.mov = ffmpeg lut3d trilinear of the same file ±2 at the grey "
          "row, the patches and the card", not misses, f"worst {worst}; {misses}")


# ---- L6, L7 ---------------------------------------------------------------------

def run_l6(client):
    misses, figures = [], {}
    for name in ("slog3", "applelog"):
        forward, why_f = scene(client, name, f"l6-{name}-fwd", SETTINGS[name])
        unconverted, why_u = scene(client, name, f"l6-{name}-none", None)

        made = {}

        def reverse(doc, clip, tag=f"l6-{name}-rev"):
            got = doc.call("set_reversed", clip=clip, reversed=True)
            if not got["ok"]:
                return f"set_reversed: {got.get('error')}"
            files, late = wait_reverse(doc, tag)
            if files:
                kept = WORK / f"{tag}-intermediate.mov"
                shutil.copy2(files[0], kept)
                made["file"] = kept
            return late
        backward, why_b = scene(client, name, f"l6-{name}-rev", SETTINGS[name], reverse)
        if forward is None or backward is None or unconverted is None:
            misses.append(f"{name}: forward {why_f}; reversed {why_b}; unconverted {why_u}")
            continue
        sf, sb, su = samples(forward), samples(backward), samples(unconverted)
        source = source_yuv(fixture(name))
        middle = hdr.yuv_frames(made["file"], W, H, 16) if made.get("file") else None
        if source is None or middle is None:
            misses.append(f"{name}: the file or the reverse's intermediate did not decode")
            continue
        # The reverse is a lossy HEVC Main 10 intermediate (PR P2-2): where its
        # code is the file's within 1 the two renders must agree; everywhere,
        # the reversed render must be the media's conversion of the
        # intermediate's OWN codes — what "follows its media" claims.
        curve = FIXTURES[name][0]
        gamut = SETTINGS[name].get("gamut") or GAMUTS[curve][0]
        same, moved, off = [], [], []
        for (x, y, fwd), (_, _, back) in zip(sf, sb):
            a, b = source.codes(x, y)[0], middle[15].codes(x, y)[0]
            (same if abs(a - b) <= 1 else moved).append(spread(fwd, back))
            # hdr_proof's H4/H5 envelope: the oracle at the intermediate's
            # codes with Y moved by −1, 0 and +1, widened by 1 level — a
            # lossy frame's own code is known to a code, and next to black a
            # code is several levels.
            luma, cb, cr = middle[15].codes(x, y)
            outs = [[code8(c) for c in log_convert(
                curve, gamut, [hdr.half(v) for v in hdr.rgb_of(luma + d, cb, cr, "bt2020nc")])]
                for d in (-1, 0, 1)]
            low = [min(o[i] for o in outs) - 1 for i in range(3)]
            high = [max(o[i] for o in outs) + 1 for i in range(3)]
            if not all(lo <= v <= hi for v, lo, hi in zip(back, low, high)):
                off.append(((x, y), back, (low, high), a, b))
        apart = max(spread(p[2], q[2]) for p, q in zip(sb, su))
        gap = max(same) if same else None
        figures[name] = {"forward gap where the codes agree": gap,
                         "samples whose intermediate code moved": len(moved),
                         "their gaps": moved[:6], "apart": apart}
        if gap is None or gap > 2 or off or apart < 10:
            misses.append(f"{name}: forward gap {gap}; off the oracle of the intermediate "
                          f"{off[:4]}; apart {apart}")
    check("L6 reversed slog3.mov and applelog.mov clips with Camera Log at 0.5 s: the media's "
          "conversion of the reverse's own codes (Y ±1, widened by 1) at every sample, = "
          "forward ±2 wherever the "
          "intermediate's code is the file's within 1, and ≥ 10 levels from the unconverted "
          "render", not misses, f"{figures}; {misses}")


def run_l7(client):
    path = fixture("slog3")
    if path is None:
        check("L7 Show Ungraded keeps the conversion", False, REFUSED.get("slog3"))
        return
    unconverted, why_u = scene(client, "slog3", "l7-none", None)
    doc = Doc(client, "l7")
    clip = doc.place(path) if doc.ok else None
    set_to = doc.color(doc._media.get(path), SETTINGS["slog3"]) if clip else {"ok": False}
    plain = doc.render("l7-plain") if set_to["ok"] else None
    looked = doc.call("set_video", clips=[clip], patch={"look": {"kind": "warm"}}) \
        if plain else {"ok": False}
    graded = doc.render("l7-warm") if looked["ok"] else None
    ungraded = doc.render("l7-ungraded", ungraded=True) if looked["ok"] else None
    doc.close()
    if not (plain and graded and ungraded and unconverted):
        check("L7 Show Ungraded keeps the conversion", False,
              f"{set_to.get('error')} {looked.get('error')} {why_u}")
        return
    same = ungraded.read_bytes() == plain.read_bytes()
    look_shows = graded.read_bytes() != plain.read_bytes()
    apart = max(spread(p[2], q[2]) for p, q in zip(samples(frame(ungraded)),
                                                   samples(unconverted)))
    check("L7 slog3.mov with Camera Log and a warm look: render_frame {ungraded: true} is "
          "byte-equal to the look-less render, and ≥ 10 levels from Camera Log None",
          same and look_shows and apart >= 10,
          f"ungraded == look-less {same}; the look changes the render {look_shows}; apart {apart}")


# ---- L8 -------------------------------------------------------------------------

def refused_with(got, sentence):
    return (not got["ok"]) and sentence in got.get("error", "")


def run_l8(client):
    misses = []
    paths = {n: fixture(n) for n in ("slog3", "vlog", "tone", "still", "lut33", "lut17")}
    if any(p is None for p in paths.values()):
        check("L8 the refusals, undo, paste, consolidate, remove", False, f"fixtures {paths}")
        return
    doc = Doc(client, "l8")
    clip = doc.place(paths["slog3"]) if doc.ok else None
    video = doc._media.get(paths["slog3"])
    audio, image = doc.media_id(paths["tone"]), doc.media_id(paths["still"])
    lut, other = doc.media_id(paths["lut33"]), doc.media_id(paths["vlog"])
    cases = [
        (99999, {"log": "slog3"}, "no media with id 99999"),
        (video, 5, "color must be a json object or null, not"),
        (video, {"log": "slog3", "foo": 1}, "unknown key \"foo\" in color"),
        (video, {"log": "clog3"}, "unknown variant `clog3`"),
        (audio, {"log": "slog3"},
         f"media {audio} is an audio file; Camera Log is a setting on a video file"),
        (image, {"log": "slog3"},
         f"media {image} is an image; Camera Log is a setting on a video file"),
        (lut, {"log": "slog3"}, f"media {lut} is a LUT; Camera Log is a setting on a video file"),
        (video, {}, "color needs log or lut; null clears it"),
        (video, {"gamut": "bt2020"}, "color needs log or lut; null clears it"),
        (video, {"log": "slog3", "lut": lut}, "color takes log or lut, not both"),
        (video, {"lut": lut, "gamut": "bt2020"}, "color.gamut goes with log"),
        (video, {"log": "slog3", "gamut": "v_gamut"},
         "slog3 takes gamut s_gamut3_cine or s_gamut3, not v_gamut"),
        (video, {"log": "apple_log", "gamut": "apple_wide_gamut"},
         "apple_log takes gamut bt2020, not apple_wide_gamut"),
        (video, {"lut": 99999}, "color.lut 99999 is not a media of this project"),
        (video, {"lut": other}, f"color.lut {other} is a video media, not a lut"),
        (video, {"log": "slog3", "detected": True}, "color.detected is written by import, not set"),
    ]
    for media, color, sentence in cases:
        got = doc.color(media, color)
        if not refused_with(got, sentence):
            misses.append(f"{color} on {media}: {got.get('error') if not got['ok'] else 'applied'}"
                          f" (want …{sentence}…)")
    set_to = doc.color(video, {"log": "slog3"})
    stored = doc.row(video).get("color")
    undone = doc.call("undo")
    after_undo = doc.row(video).get("color")
    redone = doc.call("redo")
    after_redo = doc.row(video).get("color")
    if not (set_to["ok"] and stored == {"log": "slog3", "gamut": "s_gamut3_cine"}
            and undone["ok"] and after_undo is None and redone["ok"] and after_redo == stored):
        misses.append(f"set/undo/redo: stored {stored}, undone {after_undo}, redone {after_redo}"
                      f" {set_to.get('error')}")
    cleared = doc.color(video, None)
    if not (cleared["ok"] and doc.row(video).get("color") is None):
        misses.append(f"null did not clear: {cleared.get('error')}")
    again = doc.color(video, None)
    if not refused_with(again, "Camera Log made no change"):
        misses.append(f"null on none: {again} (an identity: no change, no undo step)")
    # A scope is an Err.
    nested = doc.call("nest", clips=[clip]) if clip is not None else {"ok": False}
    nests = doc.project().get("nests") or []
    if nested["ok"] and nests:
        scoped = doc.call("set_media_color", media=video, color={"log": "slog3"},
                          scope=nests[0]["id"])
        if not refused_with(scoped, "set_media_color has no meaning inside nest"):
            misses.append(f"scope: {scoped}")
    else:
        misses.append(f"nest: {nested.get('error')}")
    # The conversion LUT: paste, consolidate, remove.
    on_vlog = doc.color(other, {"lut": lut})
    vclip = doc.place(paths["vlog"], at=SEC) if on_vlog["ok"] else None
    project = doc.project()
    copied = next((dict(c) for c in project.get("clips") or [] if c.get("id") == vclip), None)
    rows_by_id = {m["id"]: m for m in project.get("media") or []}
    if copied is None:
        misses.append(f"paste source: {on_vlog.get('error')} clip {vclip}")
    else:
        copied["track"] = 0
        for tag, carried in (("with", [other, lut]), ("without", [other])):
            target = Doc(client, f"l8-paste-{tag}")
            target.media_id(paths["lut17"])  # one row first, so the pasted ids move
            pasted = target.call("paste", at=0, payload={
                "clips": [copied], "media": [rows_by_id[i] for i in carried]})
            by_path = {m.get("path"): m for m in target.project().get("media") or []}
            row = by_path.get(str(paths["vlog"])) or {}
            local_lut = (by_path.get(str(paths["lut33"])) or {}).get("id")
            target.close()
            if tag == "with":
                good = pasted["ok"] and local_lut is not None and local_lut != lut \
                    and row.get("color") == {"lut": local_lut}
            else:
                good = pasted["ok"] and local_lut is None and row.get("color") is None
            if not good:
                misses.append(f"paste {tag} the LUT row: {pasted.get('error')}; row {row}; "
                              f"lut here {local_lut}")
    saved = doc.save("l8-saved")
    consolidated = doc.call("consolidate_media") if saved else {"ok": False}
    after = doc.row(other)
    lut_row = doc.row(lut)
    if not (consolidated["ok"] and after.get("color") == {"lut": lut}
            and lut_row.get("kind") == "lut" and str(saved) in str(after.get("path", ""))):
        misses.append(f"consolidate: {consolidated.get('error')}; row {after}; lut {lut_row}")
    removed = doc.call("remove_media", media=lut)
    if not refused_with(removed, f"media {lut} is the Camera Log of media {other}; pass "
                                 "with_clips: true to remove it and clear it"):
        misses.append(f"remove refused: {removed}")
    forced = doc.call("remove_media", media=lut, with_clips=True)
    if not (forced["ok"] and not doc.row(lut) and doc.row(other).get("color") is None):
        misses.append(f"remove with_clips: {forced.get('error')}; row {doc.row(other)}")
    doc.close()
    check("L8 every set_media_color refusal by its sentence (and the four Errs); undo restores "
          "color; paste with the LUT row lands both remapped, without it lands no color; "
          "consolidate keeps color and lut; remove_media of the LUT refused, then cleared with "
          "with_clips; a scope is an Err", not misses, "; ".join(misses))


# ---- L10, L11, L12 (B95, spec §11 GR-22) --------------------------------------

def code_domain(curve, full):
    """GR-22's code domain: S-Log3 and V-Log by the file's range flag, Apple
    Log (1, 0) in both."""
    if full or curve in ("apple_log", "apple_log2"):
        return 1.0, 0.0
    return VIDEO_SCALE, VIDEO_OFFSET


def rgb_full(luma, cb, cr, matrix):
    """10-bit full-range codes → R'G'B': s = Y/1023, (C − 512)/1023."""
    kr, kb = hdr.KR_KB[matrix]
    yy, pb, pr = luma / 1023, (cb - 512) / 1023, (cr - 512) / 1023
    r = yy + 2 * (1 - kr) * pr
    b = yy + 2 * (1 - kb) * pb
    g = (yy - kr * r - kb * b) / (1 - kr - kb)
    return [r, g, b]


def range_oracle(curve, gamut, codes, full_decode, domain, matrix="bt2020nc"):
    """The 8-bit oracle at one pixel's codes: decoded in the file's range,
    rounded to half (`oracle_at`'s reason), then y = scale·s + offset under
    `domain` and GR-16's formula."""
    rgb = rgb_full(*codes, matrix) if full_decode else hdr.rgb_of(*codes, matrix)
    scale, offset = domain
    signal_ = [hdr.half(c) for c in rgb]
    return [code8(c) for c in display(curve, gamut, [decode_curve(curve, c * scale + offset)
                                                     for c in signal_])]


def range_rows(client, row, names, bound=1):
    """Each of `names` with its Camera Log at 0.5 s against the oracle at its
    OWN decoded codes, in its range, with the domain by its flag, within
    `bound` levels at 8 bits: (misses, worst). The 0 % patch's render, its
    oracle and its video-domain oracle are printed, not returned."""
    misses, worst, figures = [], {}, {}
    for name in names:
        curve, flag, _ = RANGE_FIXTURES[name]
        full = flag == "pc"
        got, why = scene(client, name, f"{row.lower()}-{name}", RANGE_SETTINGS[name])
        path = fixture(name)
        yuv = source_yuv(path) if path else None
        if got is None or yuv is None or why:
            misses.append(f"{name}: {why or REFUSED.get(name) or 'no decode'}")
            continue
        gamut = RANGE_SETTINGS[name].get("gamut") or GAMUTS[curve][0]
        points = samples(got) + [(x, GREY_ROW, got.px8(x, GREY_ROW)) for x in range(32) if x % 8]
        gaps = [(x, y, v, range_oracle(curve, gamut, yuv.codes(x, y), full,
                                       code_domain(curve, full))) for x, y, v in points]
        worst[name] = max(spread(v, o) for _, _, v, o in gaps)
        bad = [(x, y, v, o) for x, y, v, o in gaps if spread(v, o) > bound]
        if bad:
            misses.append(f"{name}: {len(bad)} samples off, e.g. {bad[:3]}")
        x0 = PATCH_X[0]
        figures[name] = {"0% patch render": got.px8(x0, PATCH_ROW),
                         "oracle": range_oracle(curve, gamut, yuv.codes(x0, PATCH_ROW), full,
                                                code_domain(curve, full)),
                         "video-domain oracle": range_oracle(
                             curve, gamut, yuv.codes(x0, PATCH_ROW), full,
                             (VIDEO_SCALE, VIDEO_OFFSET))}
        print(f"       {name} ({flag}): worst {worst[name]}; {figures[name]}", flush=True)
    return misses, worst


def run_l10(client):
    misses, worst = range_rows(client, "L10", ("slog3_fr", "slog3_vr", "vlog_fr"))
    check("L10 slog3_fr.mov, slog3_vr.mov and vlog_fr.mov (HEVC Main 10, flagged full, video, "
          "full range) with Camera Log at 0.5 s: L1's grey-row points and the patches = the "
          "oracle at the file's own decoded codes ±1 at 8 bits, the code domain by the range "
          "flag (GR-22)", not misses, f"worst {worst}; {misses}")


def run_l14(client):
    # Bound 1, L10's, since issue batch B103 (#294, spec §11 PR-12). From B99
    # to B102 it was 2: the same codes rendered from VP9 and from HEVC parted
    # by up to 0.88 of a level with no Camera Log and 1.25 under S-Log3
    # (B99's measurement). B101's `decode-gap` placed the gap after the
    # reader, and B102's `composition-gap` in the generator, whose image of a
    # VP9 file is 8-bit where an HEVC file's is 16-bit; PR-12 reads a frame
    # showing a deep VP9 track through export's reader instead. A range
    # misread is 28 levels off, so the bound tells the two apart either way;
    # `bound` stays a parameter of range_rows.
    misses, worst = range_rows(client, "L14", ("slog3_fr_vp9e", "slog3_vr_vp9e", "slog3_fr_webm"),
                               bound=1)
    check("L14 slog3_fr_vp9e.mp4, slog3_vr_vp9e.mp4 and slog3_fr_webm.webm (VP9 Profile 2, "
          "flagged full, video, full range; the WebM rewrapped) with S-Log3 at 0.5 s: L1's "
          "grey-row points and the patches = the oracle at the file's own decoded codes ±1 at "
          "8 bits (the frame read through export's reader, PR-12, #294), the code domain by "
          "the range flag (GR-23: a VP9 track's `vpcC` bit)",
          not misses, f"worst {worst}; {misses}")


def run_l11(client):
    misses, worst = range_rows(client, "L11", ("applelog_fr",))
    check("L11 applelog_fr.mov (Apple Log's P as 1023·P, flagged full range) with {log: "
          "apple_log} = the oracle at (1, 0) ±1 at 8 bits (a guard row: Apple Log is (1, 0) in "
          "both ranges)", not misses, f"worst {worst}; {misses}")


def range_envelope(curve, gamut, codes, domain):
    """L6's envelope at a video-range intermediate's codes (Y moved by −1, 0,
    +1, widened by 1 level) under `domain`: (low, high)."""
    luma, cb, cr = codes
    outs = [range_oracle(curve, gamut, (luma + d, cb, cr), False, domain) for d in (-1, 0, 1)]
    return ([min(o[i] for o in outs) - 1 for i in range(3)],
            [max(o[i] for o in outs) + 1 for i in range(3)])


L12_TITLE = ("L12 a reversed slog3_fr.mov clip with Camera Log at 0.5 s: L6's envelope at the "
             "intermediate's own codes under the media's full-range domain (1, 0) at every "
             "sample, and ≥ 10 levels at the 0 % patch from the same envelope under the video "
             "domain")


def run_l12(client):
    name = "slog3_fr"
    curve = RANGE_FIXTURES[name][0]
    gamut = RANGE_SETTINGS[name]["gamut"]
    made = {}

    def reverse(doc, clip, tag="l12-rev"):
        got = doc.call("set_reversed", clip=clip, reversed=True)
        if not got["ok"]:
            return f"set_reversed: {got.get('error')}"
        files, late = wait_reverse(doc, tag)
        if files:
            kept = WORK / f"{tag}-intermediate.mov"
            shutil.copy2(files[0], kept)
            made["file"] = kept
        return late
    backward, why = scene(client, name, "l12-rev", RANGE_SETTINGS[name], reverse)
    middle = hdr.yuv_frames(made["file"], W, H, 16) if made.get("file") else None
    source = source_yuv(fixture(name)) if fixture(name) else None
    if backward is None or middle is None or source is None or why:
        check(L12_TITLE, False,
              f"{why}; intermediate {made.get('file')}; decoded {middle is not None}")
        return
    full = code_domain(curve, True)
    off = []
    for x, y, back in samples(backward):
        low, high = range_envelope(curve, gamut, middle[15].codes(x, y), full)
        if not all(lo <= v <= hi for v, lo, hi in zip(back, low, high)):
            off.append(((x, y), back, (low, high), middle[15].codes(x, y)[0]))
    x0 = PATCH_X[0]
    back0 = backward.px8(x0, PATCH_ROW)
    vlow, vhigh = range_envelope(curve, gamut, middle[15].codes(x0, PATCH_ROW),
                                 (VIDEO_SCALE, VIDEO_OFFSET))
    apart = max(max(lo - v, v - hi) for v, lo, hi in zip(back0, vlow, vhigh))
    probe = range_stream(made["file"])
    codes = {f"({x}, {y})": (source.codes(x, y)[0], middle[15].codes(x, y)[0])
             for x, y in ((x0, PATCH_ROW), (PATCH_X[1], PATCH_ROW), (READBACK_X, GREY_ROW))}
    check(L12_TITLE,
          not off and apart >= 10,
          f"off {len(off)}, e.g. {off[:4]}; 0 % patch {back0}, video-domain envelope "
          f"{(vlow, vhigh)}, apart {apart}; intermediate {probe.get('codec_name')} "
          f"{probe.get('pix_fmt')} range {probe.get('color_range')}; Y file → intermediate "
          f"{codes}")


# ---- L13 (B98, #289) ------------------------------------------------------------

L13_TITLE = ("L13 odd-size full-range sources reversed through the product (no Camera Log, "
             "0.5 s): each odd fixture REACHED, and each not in L13_OPEN HOLDS — a ProRes 422 "
             f"yuv422p10le intermediate at exactly {W}×{ODD_H}, toe worst ≤ {HOLD_BOUND} in the "
             f"intermediate's own range, the reversed render within {L13_SPREAD} of the forward "
             "one at every sample")


def l13_fixture(client, name):
    """One L13 fixture forward and reversed: its figures, with `reached` and
    `holds`, and `why` when it was not reached."""
    width, height = RANGE_SHAPES[name][:2]
    path = fixture(name)
    if path is None:
        return {"reached": False, "why": f"refused: {REFUSED.get(name)}"}
    probe = range_stream(path)
    made = {}

    def reverse(doc, clip, tag=f"l13-{name}-rev"):
        got = doc.call("set_reversed", clip=clip, reversed=True)
        if not got["ok"]:
            made["late"] = f"set_reversed: {got.get('error')}"
            return made["late"]
        files, late = wait_reverse(doc, tag)
        made["late"] = late
        if files:
            kept = WORK / f"{tag}-intermediate.mov"
            shutil.copy2(files[0], kept)
            made["file"] = kept
        return late
    forward, why_f = scene(client, name, f"l13-{name}-fwd", None)
    backward, why_b = scene(client, name, f"l13-{name}-rev", None, reverse)
    middle = hdr.yuv_frames(made["file"], W, height, 16) if made.get("file") else None
    figures = {"file": f"{probe.get('codec_name')} {probe.get('profile')} "
                       f"{probe.get('pix_fmt')} {probe.get('width')}×{probe.get('height')} "
                       f"range {probe.get('color_range')} tags {hdr.tags(probe)}"}
    if forward is None or backward is None or middle is None or made.get("late"):
        return {**figures, "reached": False,
                "why": f"forward {why_f}; reversed {why_b}; reverse {made.get('late')}; "
                       f"intermediate {made.get('file')} decoded {middle is not None}"}
    inter = range_stream(made["file"])
    worst, where, column0 = toe(name, made["file"], height)
    gap = max(spread(f[2], b[2]) for f, b in zip(samples(forward), samples(backward)))
    shape = (inter.get("codec_name"), inter.get("pix_fmt"), inter.get("width"),
             inter.get("height"))
    holds = (shape == ("prores", "yuv422p10le", width, height)
             and worst is not None and worst <= HOLD_BOUND and gap <= L13_SPREAD)
    return {**figures, "reached": True, "holds": holds,
            "intermediate": f"{shape[0]} {shape[1]} {shape[2]}×{shape[3]} range "
                            f"{inter.get('color_range')}",
            "toe": f"worst {worst} at {where}, column 0 file → intermediate {column0}",
            "spread": gap}


def run_l13(client):
    """L13 (issue batch B98, #289): each odd fixture and `slog3_fr_422`
    forward and reversed with no Camera Log; REACHED and HOLDS as the
    module's docstring says."""
    results, failed = {}, []
    for name in [n for pair in L13_PAIRS for n in pair] + list(L13_PRINTED):
        got = l13_fixture(client, name)
        results[name] = got
        scored = name not in L13_PRINTED
        open_ = L13_OPEN.get(name)
        verdict = ("not reached" if not got["reached"] else "holds" if got["holds"]
                   else "does not hold")
        print(f"       {name} ({'scored' if scored and not open_ else open_ or 'printed only'}): "
              f"{verdict}; {got}", flush=True)
        if not scored:
            continue
        if not got["reached"]:
            REFUSED[name] = f"L13 not reached: {got['why']}"
            failed.append(f"{name} not reached")
        elif not got["holds"] and not open_:
            failed.append(f"{name} does not hold")
    pairs = {f"{fr}/{vr}": (results[fr].get("holds"), results[vr].get("holds"))
             for fr, vr in L13_PAIRS}
    check(L13_TITLE, not failed, f"pairs (full, video) hold {pairs}; failed {failed or 'none'}")


# ---- L15 (B101, #293) -----------------------------------------------------------

def av1_fixture(name):
    """An AV1_FIXTURES file under MEDIA, made when missing; the path, or None
    with REFUSED[name] saying why."""
    if name in RANGE_CHECKED:
        return RANGE_CHECKED[name]
    flag, movflags, extension = AV1_FIXTURES[name]
    out = MEDIA / f"{name}{extension}"
    if not out.exists():
        MEDIA.mkdir(parents=True, exist_ok=True)
        flags = ["-movflags", movflags] if movflags else []
        made = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            "color=c=gray:size=64x64:rate=30:duration=1", "-c:v", "libsvtav1",
                            "-pix_fmt", "yuv420p10le", "-color_range", flag, *flags, str(out)],
                           120, env=bounded.child_env({"SVT_LOG": "1"}))
        if made["rc"] != 0 or not out.exists():
            REFUSED[name] = f"ffmpeg {name}: rc {made['rc']} {made['stderr'][-300:]}"
            out.unlink(missing_ok=True)
            RANGE_CHECKED[name] = None
            return None
    probe = range_stream(out)
    colr = b"colr" in out.read_bytes()
    wrong = {k: probe.get(k) for k, v in (("codec_name", "av1"), ("color_range", flag))
             if probe.get(k) != v}
    if wrong or colr != (movflags == "+write_colr"):
        REFUSED[name] = (f"{out.name} refused: ffprobe read {wrong or 'as wanted'}; colr box "
                         f"{colr}, wanted {movflags == '+write_colr'}")
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        RANGE_CHECKED[name] = None
        return None
    RANGE_CHECKED[name] = out
    return out


class BitWriter:
    """The AV1 bitstream's f(n) and uvlc(), most significant bit first."""

    def __init__(self):
        self.bits = []

    def f(self, value, n):
        self.bits += [(value >> i) & 1 for i in range(n - 1, -1, -1)]

    def uvlc(self, value):
        """value + 1 = 2^z + v: z zeros, a one, then v in z bits (§4.10.3)."""
        z = (value + 1).bit_length() - 1
        self.f(0, z)
        self.f(1, 1)
        self.f(value + 1 - (1 << z), z)

    def payload(self):
        """The bits with trailing_bits(): a one, then zeros to a byte."""
        bits = self.bits + [1]
        bits += [0] * (-len(bits) % 8)
        return bytes(int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8))


def leb128(value):
    out = bytearray()
    while True:
        byte, value = value & 0x7F, value >> 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def av1c(profile=0, reduced=False, timing=None, model=None, delay=False, points=((0, 8, 0),),
         frame_id=False, order_hint=False, choose_sct=True, force_sct=1, high=True,
         twelve=False, mono=False, colours=(1, 1, 1), full=1):
    """An `av1C` record (marker 1, version 1) whose configOBUs are one
    sequence header OBU with `obu_has_size_field` and a leb128 size, written
    field by field as the AV1 Bitstream spec's §5.5 reads them. `timing`:
    (num_units_in_display_tick, time_scale, num_ticks_per_picture_minus_1 or
    None for equal_picture_interval 0); `model`: buffer_delay_length_minus_1
    + 1, or None for no decoder model; `points`: (operating_point_idc,
    seq_level_idx, decoder_model_present_for_this_op); `colours`: (primaries,
    transfer, matrix) or None for no colour description; `full`: the
    color_range bit, where one is written."""
    w = BitWriter()
    w.f(profile, 3)
    w.f(int(reduced), 1)  # still_picture, set with reduced_still_picture_header
    w.f(int(reduced), 1)
    if reduced:
        w.f(points[0][1], 5)
    else:
        w.f(int(timing is not None), 1)
        if timing is not None:
            tick, scale, ticks = timing
            w.f(tick, 32)
            w.f(scale, 32)
            w.f(int(ticks is not None), 1)
            if ticks is not None:
                w.uvlc(ticks)
            w.f(int(model is not None), 1)
            if model is not None:
                w.f(model - 1, 5)
                w.f(1001, 32)  # num_units_in_decoding_tick
                w.f(31, 5)  # buffer_removal_time_length_minus_1
                w.f(31, 5)  # frame_presentation_time_length_minus_1
        w.f(int(delay), 1)
        w.f(len(points) - 1, 5)
        for idc, level, present in points:
            w.f(idc, 12)
            w.f(level, 5)
            if level > 7:
                w.f(1, 1)  # seq_tier
            if model is not None:
                w.f(present, 1)
                if present:
                    w.f(300, model)  # decoder_buffer_delay
                    w.f(600, model)  # encoder_buffer_delay
                    w.f(1, 1)  # low_delay_mode_flag
            if delay:
                w.f(1, 1)  # initial_display_delay_present_for_this_op
                w.f(9, 4)
    w.f(5, 4)  # frame_width_bits_minus_1
    w.f(5, 4)
    w.f(63, 6)  # max_frame_width_minus_1: 64×64
    w.f(63, 6)
    if not reduced:
        w.f(int(frame_id), 1)
        if frame_id:
            w.f(5, 4)  # delta_frame_id_length_minus_2
            w.f(2, 3)  # additional_frame_id_length_minus_1
    w.f(0b011, 3)  # use_128x128_superblock, enable_filter_intra, enable_intra_edge_filter
    if not reduced:
        w.f(0b1111, 4)  # interintra, masked compound, warped motion, dual filter
        w.f(int(order_hint), 1)
        if order_hint:
            w.f(0b11, 2)  # enable_jnt_comp, enable_ref_frame_mvs
        w.f(int(choose_sct), 1)
        if not choose_sct:
            w.f(force_sct, 1)
        if choose_sct or force_sct:
            w.f(0, 1)  # seq_choose_integer_mv
            w.f(1, 1)  # seq_force_integer_mv
        if order_hint:
            w.f(6, 3)  # order_hint_bits_minus_1
    w.f(0b011, 3)  # enable_superres, enable_cdef, enable_restoration
    # color_config (§5.5.2)
    w.f(int(high), 1)
    if profile == 2 and high:
        w.f(int(twelve), 1)
    if profile != 1:
        w.f(int(mono), 1)
    w.f(int(colours is not None), 1)
    for value in colours or ():
        w.f(value, 8)
    if mono:
        sub = (1, 1)
        w.f(full, 1)
    elif colours == (1, 13, 0):
        sub = (0, 0)  # color_range implied 1: no bit
    else:
        w.f(full, 1)
        sub = (1, 1) if profile == 0 or twelve else (0, 0) if profile == 1 else (1, 0)
        if profile == 2 and twelve:
            w.f(1, 1)  # subsampling_x
            w.f(1, 1)  # subsampling_y
        if sub == (1, 1):
            w.f(0, 2)  # chroma_sample_position
    if not mono:
        w.f(0, 1)  # separate_uv_delta_q
    w.f(0, 1)  # film_grain_params_present
    payload = w.payload()
    tier = int(points[0][1] > 7)
    head = bytes([0x81, profile << 5 | points[0][1],
                  tier << 7 | int(high) << 6 | int(twelve) << 5 | int(mono) << 4
                  | sub[0] << 3 | sub[1] << 2, 0])
    return (head + bytes([0x0A]) + leb128(len(payload)) + payload).hex()


# (label, av1C hex, the color_range it carries). Each one differs from its
# neighbours in the branch it takes through §5.5; the timing case's
# num_ticks_per_picture_minus_1 1000 is a 19-bit uvlc, so a mis-sized read
# moves every later field.
SYNTHETIC_AV1 = [
    ("range 1", av1c(full=1), True),
    ("range 0", av1c(full=0), False),
    ("timing, decoder model, two operating points", av1c(
        timing=(1001, 30000, 1000), model=10, points=((0x103, 9, 1), (0x101, 4, 0)), full=1),
     True),
    ("initial_display_delay_present", av1c(delay=True, full=1), True),
    ("reduced_still_picture_header", av1c(reduced=True, full=1), True),
    ("mono_chrome", av1c(mono=True, full=1), True),
    ("profile 1, (1, 13, 0): range implied 1", av1c(profile=1, high=False, colours=(1, 13, 0)),
     True),
    ("profile 2, 12-bit", av1c(profile=2, twelve=True, full=0), False),
    # accepted limit (owner, 2026-10-14; spec §11 GR-23, #293): profile 2 gets no
    # FullRangeVideo key, so a full-range one reads as video range
    ("profile 2, 12-bit, range 1", av1c(profile=2, twelve=True, full=1), False),
    ("profile 2, 10-bit, range 1", av1c(profile=2, full=1), False),
    ("frame ids, order hint, screen content forced", av1c(
        frame_id=True, order_hint=True, choose_sct=False, force_sct=1, full=0), False),
    ("no colour description", av1c(colours=None, full=1), True),
]
# L15_OPEN: synthetic label → why its isFullRange is printed beside its
# expectation and not scored (it is still scored on being answered). Empty:
# the two profile 2 range-1 records B101's fix pass added are scored at their
# accepted answer, false (owner, 2026-10-14; spec §11 GR-23, #293), so a
# change in AVFoundation's answer fails L15.
L15_OPEN: dict[str, str] = {}

L15_TITLE = ("L15 AV1 (issue batch B101, #293): each fixture's first format description "
             "read (the FullRangeVideo key, the av1C and colr atoms) and isFullRange = its "
             "range flag (the MP4s as is, the WebMs through the built-in rewrap), and each "
             "synthetic av1C answers its color_range (profile 2 scored at its accepted limit, false)")


def run_l15(sources):
    """L15: the probe over `sources`, on the AV1 fixtures and SYNTHETIC_AV1."""
    items, want, misses, open_ = [], {}, [], {}
    for name, (flag, _, extension) in AV1_FIXTURES.items():
        path = av1_fixture(name)
        if path is None:
            misses.append(f"{name}: {REFUSED.get(name)}")
            continue
        items.append({"label": name, "kind": "webm" if extension == ".webm" else "file",
                      "path": str(path)})
        want[name] = flag == "pc"
    base = av1_fixture("av1_fr")
    if base is not None:
        for label, record, expected in SYNTHETIC_AV1:
            items.append({"label": f"synthetic {label}", "kind": "record", "record": record})
            want[f"synthetic {label}"] = expected
            if label in L15_OPEN:
                open_[f"synthetic {label}"] = L15_OPEN[label]
    binary, why = build_probe(sources, name="av1_range_probe", probe=AV1_PROBE)
    if binary is None:
        check(L15_TITLE, False, f"the probe did not build: {why}")
        return
    request, answer = WORK / "av1-probe.json", WORK / "av1-probe-answer.json"
    answer.unlink(missing_ok=True)
    request.write_text(json.dumps({"scratch": str(WORK / "av1-scratch"), "base": str(base),
                                   "items": items}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = {a["label"]: a for a in json.loads(answer.read_text())["items"]}
    except (OSError, ValueError, KeyError):
        answered = {}
        misses.append(f"no answer (rc {ran['rc']}, expired {ran['expired']}): "
                      f"{(ran['stdout'] + ran['stderr']).strip()[-300:]}")
    for label, expected in want.items():
        got = answered.get(label)
        if got is None:
            misses.append(f"{label}: not answered")
            continue
        if "error" in got:
            print(f"       {label}: error {got['error']}", flush=True)
            misses.append(f"{label}: {got['error']}")
            continue
        print(f"       {label}: key {got['key']}, av1C {got['av1C']} (head {got['head']}), colr "
              f"atom {got['colr']}, atoms {got['atoms']}, extensions {got['extensions']}; "
              f"isFullRange {got['fullRange']}, want {expected}"
              f"{'; ' + open_[label] if label in open_ else ''}", flush=True)
        if got["fullRange"] != expected and label not in open_:
            misses.append(f"{label}: isFullRange {got['fullRange']}, want {expected}")
    check(L15_TITLE, not misses, f"{len(want)} items; misses {misses or 'none'}; "
          f"open {sorted(open_) or 'none'}")


# ---- L16, L17, L18 (B103, #294, spec §11 PR-12) --------------------------------

def vp9_8bit_fixture():
    """`MEDIA/vp9_8bit.mp4`: 1 s of lavfi `testsrc2` at W×H and 30 fps through
    libvpx-vp9 lossless Profile 0, `yuv420p`; kept only when ffprobe reads
    `vp9`, `Profile 0`, `yuv420p` and W×H; else None, REFUSED naming what it
    read."""
    name = VP9_8BIT
    if name in RANGE_CHECKED:
        return RANGE_CHECKED[name]
    out = MEDIA / f"{name}.mp4"
    if not out.exists():
        MEDIA.mkdir(parents=True, exist_ok=True)
        made = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            f"testsrc2=size={W}x{H}:rate=30:duration=1", "-c:v", "libvpx-vp9",
                            "-lossless", "1", "-profile:v", "0", "-pix_fmt", "yuv420p", str(out)],
                           300)
        if made["rc"] != 0 or not out.exists():
            REFUSED[name] = f"ffmpeg {name}: rc {made['rc']} {made['stderr'][-300:]}"
            out.unlink(missing_ok=True)
            RANGE_CHECKED[name] = None
            return None
    probe = range_stream(out)
    want = {"codec_name": "vp9", "profile": "Profile 0", "pix_fmt": "yuv420p", "width": W,
            "height": H}
    wrong = {k: probe.get(k) for k, v in want.items() if probe.get(k) != v}
    if wrong:
        REFUSED[name] = f"{out.name} refused: ffprobe read {wrong}"
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        RANGE_CHECKED[name] = None
        return None
    RANGE_CHECKED[name] = out
    return out


def png_depth(path):
    """A PNG's IHDR bit depth, or None."""
    data = Path(path).read_bytes()[:25] if path else b""
    return data[24] if len(data) == 25 and data[:8] == b"\x89PNG\r\n\x1a\n" else None


def placed_render(client, tag, paths, t=T, jpeg=False):
    """`paths` placed on one track 1 s apart (the first at 0), any Camera Log
    import detected cleared (L9's way), rendered at `t` as a PNG, or a JPEG
    (`format: "jpeg"`): (the file or None, why, closed)."""
    doc = Doc(client, tag)
    for index, path in enumerate(paths):
        clip = doc.place(path, at=index * SEC) if doc.ok else None
        if clip is None:
            break
        media = doc._media.get(path)
        if doc.row(media).get("color") is not None:
            doc.color(media, None)
    out = None
    if doc.ok and not jpeg:
        out = doc.render(tag, t=t)
    elif doc.ok:
        out = WORK / f"{tag}.jpg"
        out.unlink(missing_ok=True)
        got = doc.call("render_frame", t=t, path=str(out), format="jpeg")
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            out = None
    closed = doc.close()
    return out, (doc.why or (None if out else "no render")), closed


L16_TITLE = ("L16 (issue batch B103, #294, spec §11 PR-12; a probe row): DeepVideoFrame.isDeep "
             "over each file's first format description is true for the 10-bit VP9 files "
             "(slog3_fr_vp9e, slog3_vr_vp9e, the odd slog3_fr_vp9, the WebM rewrapped) and false "
             "for 8-bit VP9, HEVC Main 10, HEVC Rext and ProRes 422 HQ")


def run_l16(sources):
    """L16: `deep_video_probe.swift` over `sources`, on L16_ITEMS."""
    items, want, misses = [], {}, []
    for name, (kind, deep) in L16_ITEMS.items():
        path = fixture(name)
        if path is None:
            misses.append(f"{name}: {REFUSED.get(name)}")
            continue
        items.append({"label": name, "kind": kind, "path": str(path)})
        want[name] = deep
    binary, why = build_probe(sources, name="deep_video_probe", probe=DEEP_PROBE)
    if binary is None:
        check(L16_TITLE, False, f"the probe did not build: {why}")
        return
    request, answer = WORK / "deep-probe.json", WORK / "deep-probe-answer.json"
    answer.unlink(missing_ok=True)
    request.write_text(json.dumps({"scratch": str(WORK / "deep-scratch"), "items": items}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = {a["label"]: a for a in json.loads(answer.read_text())["items"]}
    except (OSError, ValueError, KeyError):
        answered = {}
        misses.append(f"no answer (rc {ran['rc']}, expired {ran['expired']}): "
                      f"{(ran['stdout'] + ran['stderr']).strip()[-300:]}")
    for label, expected in want.items():
        got = answered.get(label)
        if got is None:
            misses.append(f"{label}: not answered")
            continue
        if "error" in got:
            print(f"       {label}: error {got['error']}", flush=True)
            misses.append(f"{label}: {got['error']}")
            continue
        print(f"       {label} ({L16_ITEMS[label][0]}): subtype {got['subtype']}, "
              f"bitsPerComponent {got['bitsPerComponent']}, vpcC {got['vpcC']}; deep "
              f"{got['deep']}, want {expected}", flush=True)
        if got["deep"] != expected:
            misses.append(f"{label}: deep {got['deep']}, want {expected}")
    check(L16_TITLE, not misses, f"{len(want)} items; misses {misses or 'none'}")


def run_l17(client, state):
    """L17: the deep VP9 renders' PNG bit depth (16), alone and in the mixed
    project at T + 1 s; the other codecs' printed, not scored."""
    misses, depths = [], {}
    for name in (*L17_DEEP, *L17_PRINTED):
        path = fixture(name)
        if path is None:
            depths[name] = None
            misses.append(f"{name}: {REFUSED.get(name)}")
            continue
        png, why, state[f"l17_{name}_closed"] = placed_render(client, f"l17-{name}", [path])
        depths[name] = png_depth(png)
        if why:
            misses.append(f"{name}: {why}")
    paths = [fixture(name) for name in MIXED]
    mixed = "mixed at 1.5 s"
    if None in paths:
        depths[mixed] = None
        misses.append(f"{mixed}: a fixture was refused")
    else:
        png, why, state["l17_mixed_closed"] = placed_render(client, "l17-mixed", paths,
                                                            t=T + SEC)
        depths[mixed] = png_depth(png)
        if why:
            misses.append(f"{mixed}: {why}")
    print(f"       PNG bit depth, scored: "
          f"{ {k: depths[k] for k in (*L17_DEEP, mixed)} }; printed (the generator's per "
          f"codec): { {k: depths[k] for k in L17_PRINTED} }", flush=True)
    shallow = [k for k in (*L17_DEEP, mixed) if depths.get(k) != 16]
    check("L17 (issue batch B103, #294, spec §11 PR-12) slog3_fr_vp9e.mp4, slog3_vr_vp9e.mp4 and "
          "slog3_fr_webm.webm alone, and the mixed project (vp9_8bit.mp4 at 0, slog3_fr_vp9e.mp4 "
          "at 1 s) at 1.5 s, no Camera Log: render_frame writes a PNG of IHDR bit depth 16",
          not shallow and not misses, f"not 16: {shallow or 'none'}; misses {misses or 'none'}")


# L18's renders: (tag, fixtures placed 1 s apart, time, JPEG?).
L18_CASES = (("l18-slog3_fr", ("slog3_fr",), T, False),
             ("l18-vp9_8bit", (VP9_8BIT,), T, False),
             ("l18-mixed", MIXED, T, False),
             ("l18-slog3_fr_vp9e-jpeg", ("slog3_fr_vp9e",), T, True))


def run_l18(client, mode, control, state):
    """L18 (L9's modes): the frames PR-12 leaves to the generator, byte-equal
    to DIR's."""
    misses, captured = [], 0
    for tag, names, t, jpeg in L18_CASES:
        paths = [l9_media(name, None if mode == "capture" else control) for name in names]
        if None in paths:
            misses.append(f"{tag}: {[REFUSED.get(n) for n in names]}")
            continue
        if mode == "capture":
            (control / "media").mkdir(parents=True, exist_ok=True)
            for path in paths:
                shutil.copy2(path, control / "media" / path.name)
        out, why, state[f"{tag}_closed"] = placed_render(client, tag, paths, t=t, jpeg=jpeg)
        if out is None:
            misses.append(f"{tag}: {why}")
            continue
        want = control / out.name
        if mode == "capture":
            shutil.copy2(out, want)
            captured += 1
            print(f"       {tag}: captured {out.stat().st_size} bytes"
                  f"{'' if jpeg else f', PNG depth {png_depth(out)}'}", flush=True)
        elif not want.exists():
            misses.append(f"{tag}: no control file")
        elif out.read_bytes() != want.read_bytes():
            misses.append(f"{tag}: bytes differ ({out.stat().st_size} against "
                          f"{want.stat().st_size}"
                          f"{'' if jpeg else f'; PNG depth {png_depth(out)} against {png_depth(want)}'})")
        else:
            print(f"       {tag}: byte-identical ({out.stat().st_size} bytes)", flush=True)
    if mode == "capture":
        print(f"  L18 references captured for {captured} of {len(L18_CASES)} frames "
              f"{misses or ''}", flush=True)
        state["capture_ok"] = state.get("capture_ok", True) and not misses
        return
    check(f"L18 (issue batch B103, #294, spec §11 PR-12) slog3_fr.mov alone, vp9_8bit.mp4 alone "
          f"and the mixed project at 0.5 s (PNG), and slog3_fr_vp9e.mp4 alone as JPEG, render "
          f"byte-identical to {control.name}'s", not misses, f"{misses}")


# ---- L9 -------------------------------------------------------------------------

def run_l9(client, mode, control, state):
    misses, captured = [], 0
    for name in L9_FIXTURES:
        path = l9_media(name, None if mode == "capture" else control)
        if path is None:
            misses.append(f"{name}: {REFUSED.get(name)}")
            continue
        if mode == "capture":
            (control / "media").mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, control / "media" / path.name)
        doc = Doc(client, f"l9-{name}")
        clip = doc.place(path) if doc.ok else None
        media = doc._media.get(path)
        if clip is not None and doc.row(media).get("color") is not None:
            doc.color(media, None)
        png = doc.render(f"l9-{name}") if clip is not None else None
        state[f"l9_{name}_closed"] = doc.close()
        if png is None:
            misses.append(f"{name}: {doc.why or 'no render'}")
            continue
        want = control / f"l9-{name}.png"
        if mode == "capture":
            shutil.copy2(png, want)
            captured += 1
        elif not want.exists():
            misses.append(f"{name}: no control PNG")
        elif png.read_bytes() != want.read_bytes():
            a, b = hdr.Frame(png, W, H), hdr.Frame(want, W, H)
            differ = sum(1 for x, y in zip(a.values, b.values) if x != y)
            misses.append(f"{name}: PNG bytes differ ({differ} 16-bit samples differ)")
    if mode == "capture":
        print(f"  L9 references captured for {captured} of {len(L9_FIXTURES)} fixtures "
              f"{misses or ''}", flush=True)
        state["capture_ok"] = not misses
        return
    check(f"L9 (STOP) {len(L9_FIXTURES)} fixtures with no Camera Log (applelog and applelog2 set "
          f"to None) render byte-identical to {control.name}'s", not misses, f"{misses}")


# ---- LP1–LP4 --------------------------------------------------------------------

def build_probe(sources, name="log_probe", probe=PROBE):
    """`probe` (`log_probe.swift`, or B96's `reverse_probe.swift`) as
    `main.swift` over `sources` (an `app/Sources`). (binary, None) or (None,
    why)."""
    folder = WORK / name
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(probe.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / name, defines=["FRAMEJOB_DEV_TOOLS"],
                                  timeout=BUILD_BOUND)
    except swift_build.SwiftBuildFailed as error:
        return None, f"{error} {error.diagnostics[:6]}"
    return built.binary, None


def probe_request(shader):
    pairings = []
    for curve, gamuts in GAMUTS.items():
        swift = {"apple_log": "apple_log", "apple_log2": "apple_log2", "slog3": "slog3",
                 "vlog": "vlog"}[curve]
        name = {"bt2020": "bt2020", "apple_wide_gamut": "appleWideGamut",
                "s_gamut3_cine": "sGamut3Cine", "s_gamut3": "sGamut3", "v_gamut": "vGamut"}
        for gamut in gamuts:
            pairings.append([{"log": curve, "gamut": gamut}, f"log({swift},{name[gamut]})"])
        pairings.append([{"log": curve}, f"log({swift},{name[gamuts[0]]})"])
    pairings += [[{"lut": 12}, "lut(12)"], [{}, "nil"]]
    steps = [-0.02 + 1.1 * i / 1023 for i in range(1024)]
    seed = 0x5eed_0f16
    triples = []
    for _ in range(512):
        triple = []
        for _ in range(3):
            seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
            triple.append((seed >> 11) / 2 ** 53 * 1.05 - 0.02)
        triples.append(triple)
    p3 = []
    for curve, gamut in (("apple_log", "bt2020"), ("slog3", "s_gamut3_cine"),
                         ("slog3", "s_gamut3"), ("vlog", "v_gamut"),
                         ("apple_log2", "apple_wide_gamut")):
        inputs = [[hdr.half(c) for c in rgb] for rgb in [[g, g, g] for g in steps] + triples]
        p3.append({"label": f"{curve}/{gamut}", "log": curve, "gamut": gamut, "inputs": inputs,
                   "outputs": [log_convert(curve, gamut, rgb) for rgb in inputs],
                   "premultiplied": True})
        # The makers' codes: the pass must decode each to its reflectance ±0.005.
        scale, offset = CODE[curve]
        codes, outs, bounds = [], [], []
        for code, r in zip(PATCHES[curve], REFLECTANCE):
            s = hdr.half(signal(code))
            codes.append([s, s, s])
            want = display(curve, gamut, [r] * 3)
            lo = display(curve, gamut, [r - 0.005] * 3)[1]
            hi = display(curve, gamut, [r + 0.005] * 3)[1]
            outs.append(want)
            bounds.append(max(abs(hi - want[1]), abs(want[1] - lo), 1e-4))
        p3.append({"label": f"{curve} makers' codes", "log": curve, "gamut": gamut,
                   "inputs": codes, "outputs": outs, "bounds": bounds})
    grid = [[(i + 0.37) / 9.4, (j + 0.11) / 9.2, (k + 0.73) / 9.6]
            for i in range(9) for j in range(9) for k in range(9)]
    grid = [[hdr.half(c) for c in rgb] for rgb in grid]
    p3.append({"label": "lut 17³", "lut": 7, "inputs": grid,
               "outputs": [trilinear(17, rgb) for rgb in grid], "premultiplied": True})
    return {"shader": str(shader), "pairings": pairings, "cube": str(fixture("lut17")),
            "matrices": {g: to709(g) for g in PRIMARIES if g != "bt709"}, "p3": p3,
            "constants": {"logMidGrey": MID_GREY, "logExposure": EXPOSURE,
                          "logWhite": LOG_WHITE, "shoulderKnee": KNEE,
                          "displayGamma": DISPLAY_GAMMA, "videoCodeScale": VIDEO_SCALE,
                          "videoCodeOffset": VIDEO_OFFSET, "kindAppleLog": 5, "kindSlog3": 6,
                          "kindVlog": 7, "kindLUT": 8}}


def run_probe(sources):
    binary, why = build_probe(sources)
    if binary is None:
        for name in sorted(LP_ROWS & selected):
            check(f"{name} the probe builds over app/Sources", False, why)
        return
    request, answer = WORK / "log-probe.json", WORK / "log-probe-answer.json"
    answer.unlink(missing_ok=True)
    shader = Path(sources).parent / "Resources/Shaders/Compositor.metal"
    request.write_text(json.dumps(probe_request(shader)))
    ran = bounded.run([str(binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(LP_ROWS & selected):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], row.get("detail", ""))


# ---- reverse-variants (issue batch B96, #280) ----------------------------------

def detail_fixture(name):
    """A DETAIL file under MEDIA, made when missing: 2 s of `testsrc2` with
    temporal grain, ProRes 422 HQ, untagged; kept only when ffprobe reads
    prores / yuv422p10le, its size and 2 s."""
    width, height = DETAIL[name]
    out = MEDIA / f"{name}.mov"
    if not out.exists():
        MEDIA.mkdir(parents=True, exist_ok=True)
        made = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            f"testsrc2=size={width}x{height}:rate=30:duration={DETAIL_SECONDS},"
                            "noise=alls=6:allf=t+u,format=yuv422p10le", "-c:v", "prores_ks",
                            "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-color_primaries",
                            "unknown", "-color_trc", "unknown", "-colorspace", "unknown",
                            str(out)], 600)
        if made["rc"] != 0 or not out.exists():
            REFUSED[name] = f"ffmpeg {name}: rc {made['rc']} {made['stderr'][-300:]}"
            out.unlink(missing_ok=True)
            return None
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,pix_fmt,width,height,duration", "-of", "json",
                       str(out)], 60)
    try:
        probe = json.loads(ran["stdout"])["streams"][0]
    except (ValueError, KeyError, IndexError):
        probe = {}
    good = (probe.get("codec_name") == "prores" and probe.get("pix_fmt") == "yuv422p10le"
            and (probe.get("width"), probe.get("height")) == (width, height)
            and abs(float(probe.get("duration") or 0) - DETAIL_SECONDS) < 0.05)
    if not good:
        REFUSED[name] = f"{out.name} refused: ffprobe read {probe}"
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        return None
    print(f"       {out.name} kept: {probe}", flush=True)
    return out


def variant_copy(variant):
    """The tree copied to WORK/variant-<name> with the variant's edits, each
    anchor asserted to occur exactly once: (copy, None) or (None, why)."""
    made, reason = tree_copy.make_copy(str(WORK / f"variant-{variant}"))
    if made is None:
        return None, reason
    copy = Path(made)
    for path, anchor, replacement in REVERSE_VARIANTS[variant]:
        target = copy / path
        if not target.resolve().is_relative_to(WORK):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    return copy, None


def run_reverse(binary, source, out, extra=()):
    """`reverse_probe SOURCE DEST JSON [extra]`: (its JSON answer, the
    intermediate's ffprobe codec/profile/pix_fmt/range)."""
    out.parent.mkdir(parents=True, exist_ok=True)
    answer = out.with_suffix(".json")
    answer.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(source), str(out), str(answer), *extra], REVERSE_BOUND,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        got = json.loads(answer.read_text())
    except (OSError, ValueError):
        got = {"ok": False, "error": f"no answer (rc {ran['rc']}, expired {ran['expired']}): "
                                     f"{(ran['stdout'] + ran['stderr']).strip()[-300:]}"}
    return got, (range_stream(out) if got.get("ok") and out.exists() else {})


def expected_y(name, code, intermediate_range="tv"):
    """The intermediate's expected Y for the file's Y `code`: the code itself
    when the file's range flag is the intermediate's; a full-range file's
    video-range code in a video-range intermediate (GR-22); a video-range
    file's full-range code, clamped, in a full-range one."""
    file_range = RANGE_FIXTURES.get(name, (0, "tv"))[1]
    if file_range == intermediate_range:
        return code
    if file_range == "pc":
        return round(64 + 876 * code / 1023)
    return min(1023, max(0, round((code - 64) * 1023 / 876)))


def toe_points():
    """sample_points() and the grey row's columns 0–31."""
    return sample_points() + [(x, GREY_ROW) for x in range(32) if x % 8]


def toe(name, intermediate, height=H):
    """(worst |Y₁₅ − expected|, where, column 0's (file Y, intermediate Y))
    of `intermediate` against the log fixture `name`, or (None, why, None);
    the expected code in the intermediate's own range flag."""
    source = source_yuv(fixture(name), height) if fixture(name) else None
    middle = hdr.yuv_frames(intermediate, W, height, 16)
    if source is None or middle is None:
        return None, f"{name}: the file or the intermediate did not decode", None
    within = "pc" if range_stream(intermediate).get("color_range") == "pc" else "tv"
    gaps = [(abs(middle[15].codes(x, y)[0]
                 - expected_y(name, source.codes(x, y)[0], within)), (x, y))
            for x, y in toe_points()]
    worst, where = max(gaps)
    return worst, where, (source.codes(0, GREY_ROW)[0], middle[15].codes(0, GREY_ROW)[0])


def stream_text(probe):
    return f"{probe.get('codec_name')}/{probe.get('profile')}/{probe.get('pix_fmt')}"


def mb_per_minute(size):
    return size / DETAIL_SECONDS * 60 / 1e6


def apple_note(name):
    a, hq = APPLE_PRORES[name]
    return (f"Apple's published ProRes 422 / 422 HQ at {name[7:]}p29.97: {a} / {hq} Mbit/s = "
            f"{a * 60 / 8:.0f} / {hq * 60 / 8:.0f} MB/min")


def run_variants(names):
    """`reverse-variants`: each variant built and run on the log and detail
    fixtures; the table printed. Exit 0 when every reverse completed."""
    print(f"B96 reverse-variants — {', '.join(names)}; launches no app", flush=True)
    logs = {n: fixture(n) for n in VARIANT_LOGS}
    details = {n: detail_fixture(n) for n in DETAIL}
    missing = [n for n, p in {**logs, **details}.items() if p is None]
    if missing:
        print(f"instrument failure: fixtures refused {missing}: {REFUSED}")
        return 2
    results, failed = {}, []
    for variant in names:
        print(f"\n  variant {variant}: {len(REVERSE_VARIANTS[variant])} edit(s)", flush=True)
        copy, why = variant_copy(variant)
        binary = None
        if copy is not None:
            binary, why = build_probe(copy / "app/Sources", f"reverse_probe_{variant}",
                                      REVERSE_PROBE)
        if binary is None:
            print(f"    UNBUILT {variant}: {why}", flush=True)
            failed.append(f"{variant} (unbuilt)")
            continue
        got = {"bytes": {}, "toe": {}, "stream": None}
        for name, path in {**logs, **details}.items():
            out = WORK / f"variant-{variant}-out" / f"{name}.mov"
            answer, probe = run_reverse(binary, path, out)
            if not answer.get("ok"):
                print(f"    FAILED {variant} on {name}: {answer.get('error')}", flush=True)
                failed.append(f"{variant} on {name}")
                continue
            if name in DETAIL:
                got["bytes"][name] = answer["bytes"]
                got["stream"] = got["stream"] or stream_text(probe)
                print(f"    {name}: {stream_text(probe)} range {probe.get('color_range')}, "
                      f"{answer['bytes']} bytes, {mb_per_minute(answer['bytes']):.0f} MB/min, "
                      f"{answer.get('seconds', 0):.1f} s ({apple_note(name)})", flush=True)
            else:
                worst, where, column0 = toe(name, out)
                got["toe"][name] = worst
                print(f"    {name}: {stream_text(probe)} range {probe.get('color_range')}; worst "
                      f"|Y15 − expected| {worst} at {where}; column 0 file → intermediate "
                      f"{column0}", flush=True)
            out.unlink(missing_ok=True)
        results[variant] = got
    base = results.get("base", {}).get("bytes", {})
    print("\n  variant      stream                          holds  MB/min 1080  MB/min 2160  "
          "ratio 1080  ratio 2160  qualifies", flush=True)
    qualifiers = []
    for variant, got in results.items():
        toes = [got["toe"].get(n) for n in VARIANT_LOGS]
        holds = all(v is not None and v <= HOLD_BOUND for v in toes)
        sizes = [got["bytes"].get(n) for n in DETAIL]
        ratios = [s / base[n] if s and base.get(n) else None for s, n in zip(sizes, DETAIL)]
        qualifies = holds and all(r is not None and r <= RATIO_BOUND for r in ratios)
        if qualifies:
            qualifiers.append((variant, ratios[1]))
        cells = [f"{mb_per_minute(s):11.0f}" if s else f"{'—':>11}" for s in sizes] + \
            [f"{r:10.2f}" if r is not None else f"{'—':>10}" for r in ratios]
        print(f"  {variant:<12} {str(got['stream']):<31} {'yes' if holds else 'no':<6} "
              f"{'  '.join(cells)}  {'yes' if qualifies else 'no'}   (worst toe {toes})",
              flush=True)
    if qualifiers:
        smallest = min(r for _, r in qualifiers)
        choice = next(v for v, r in qualifiers if r <= smallest * (1 + TIE))
        print(f"  the choice by B96's rule: {choice}", flush=True)
    else:
        print("  no variant qualifies (branch Q)", flush=True)
    if failed:
        print(f"  unbuilt or failed: {', '.join(failed)}", flush=True)
    return 0 if not failed else 1


# ---- decode-gap (issue batch B101, #294) ----------------------------------------

def gap_points():
    """sample_points() and every column of the grey row's first 32."""
    return list(dict.fromkeys(sample_points() + [(x, GREY_ROW) for x in range(32)]))


def written_codes(name):
    """The (Y, Cb, Cr) a GAP_FIXTURES file was written with at gap_points()."""
    _, ramp, patches = raw_range(RANGE_FIXTURES[name][0])
    return {(x, y): (ramp[x] if y < 64 else patches[min(2, x * 3 // W)], 512, 512)
            for x, y in gap_points()}


def levels(a, b, points):
    """The largest |a − b| over `points` and R, G, B, in 8-bit levels (1/255),
    and where."""
    return max((max(abs(p - q) for p, q in zip(a[pt], b[pt])) * 255, pt) for pt in points)


def run_decode_gap():
    """`decode-gap`: the four fixtures' first frames at each GAP_FORMATS
    format, through `decode_gap_probe.swift`; the figures and the verdict
    (B101's rule, in the module's docstring). Exit 0 with a verdict line; 1,
    and no verdict, when a GAP_REQUIRED read failed; 2 when the instrument
    could not run."""
    print(f"B101 decode-gap — {', '.join(GAP_FIXTURES)} at {', '.join(GAP_FORMATS)}; launches "
          "no app", flush=True)
    paths = {n: fixture(n) for n in GAP_FIXTURES}
    missing = [n for n, p in paths.items() if p is None]
    if missing:
        print(f"instrument failure: fixtures refused {missing}: {REFUSED}")
        return 2
    binary, why = build_probe(ROOT / "app/Sources", name="decode_gap_probe", probe=GAP_PROBE)
    if binary is None:
        print(f"instrument failure: the probe did not build: {why}")
        return 2
    points = gap_points()
    request, answer = WORK / "gap-probe.json", WORK / "gap-probe-answer.json"
    answer.unlink(missing_ok=True)
    request.write_text(json.dumps({
        "fixtures": [{"name": n, "path": str(p)} for n, p in paths.items()],
        "formats": list(GAP_FORMATS), "points": [list(p) for p in points]}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        print(f"instrument failure: no answer (rc {ran['rc']}, expired {ran['expired']}): "
              f"{(ran['stdout'] + ran['stderr']).strip()[-300:]}")
        return 2
    got, errors = {}, {}
    for row in answered:
        key = (row["fixture"], row["format"])
        if "error" in row:
            errors[key] = row["error"]
        else:
            got[key] = {(x, y): tuple(v) for x, y, v in row["values"]}
    for (name, fmt), error in errors.items():
        print(f"  {name} at {fmt}: reader error {error}", flush=True)
    unread = [(n, f) for n in GAP_FIXTURES for f in GAP_REQUIRED if (n, f) not in got]
    if unread:
        print(f"instrument failure: no read at {unread}; no verdict")
        return 1
    print("\n  biplanar codes against the written ones (Y, Cb, Cr):", flush=True)
    exact = {}
    for name in GAP_FIXTURES:
        own = "xf20" if RANGE_FIXTURES[name][1] == "pc" else "x420"
        written = written_codes(name)
        for fmt in ("x420", "xf20"):
            values = got[(name, fmt)]
            off = [(pt, values[pt], written[pt]) for pt in points if values[pt] != written[pt]]
            worst = max((abs(v[0] - w[0]) for _, v, w in off), default=0)
            if fmt == own:
                exact[name] = {pt for pt in points if values[pt] == written[pt]}
            print(f"    {name} {fmt}{' (its own range)' if fmt == own else ''}: {len(off)} of "
                  f"{len(points)} points differ, worst |ΔY| {worst}; e.g. {off[:3]}", flush=True)
    decoder = [(vp9, pt) for hevc, vp9 in GAP_PAIRS for pt in points
               if pt in exact[hevc] and pt not in exact[vp9]]
    print("\n  RGB, VP9 against HEVC of the same codes and range (8-bit levels):", flush=True)
    rgb = [f for f in GAP_FORMATS if f not in ("x420", "xf20")]
    gaps = {}
    for hevc, vp9 in GAP_PAIRS:
        for fmt in rgb:
            if (vp9, fmt) not in got or (hevc, fmt) not in got:
                print(f"    {vp9} vs {hevc} at {fmt}: not read", flush=True)
                continue
            gaps[(vp9, fmt)] = levels(got[(vp9, fmt)], got[(hevc, fmt)], points)
            half_vs = levels(got[(vp9, fmt)], got[(hevc, "64RGBAHalf")], points)
            hevc_vs = levels(got[(hevc, fmt)], got[(hevc, "64RGBAHalf")], points)
            print(f"    {vp9} vs {hevc} at {fmt}: max {gaps[(vp9, fmt)][0]:.3f} at "
                  f"{gaps[(vp9, fmt)][1]}; VP9 {fmt} vs HEVC 64RGBAHalf {half_vs[0]:.3f}; HEVC "
                  f"{fmt} vs its 64RGBAHalf {hevc_vs[0]:.3f}", flush=True)
            at = gaps[(vp9, fmt)][1]
            print(f"      at {at}: VP9 {[round(c * 255, 3) for c in got[(vp9, fmt)][at]]}, "
                  f"HEVC {[round(c * 255, 3) for c in got[(hevc, fmt)][at]]}", flush=True)
    half_gap = max(gaps[(vp9, "64RGBAHalf")][0] for _, vp9 in GAP_PAIRS)
    if decoder:
        verdict = (f"decoder — VP9's own-range biplanar codes differ from the written ones at "
                   f"{len(decoder)} point(s) where HEVC's equal them, e.g. {decoder[:3]}")
    elif half_gap > GAP_BOUND:
        better = [f for f in rgb if f != "64RGBAHalf"
                  and all((vp9, f) in gaps and gaps[(vp9, f)][0] <= GAP_BOUND
                          for _, vp9 in GAP_PAIRS)]
        verdict = (f"conversion — VP9's biplanar codes are exact, its 64RGBAHalf is "
                   f"{half_gap:.3f} levels from HEVC's; "
                   + (f"{', '.join(better)} bring(s) it within {GAP_BOUND} (PR-2's "
                      "sourcePixelFormat; not changed here)" if better else
                      f"no other format brings it within {GAP_BOUND}: an accepted limit"))
    else:
        verdict = (f"neither — VP9's biplanar codes are exact and its 64RGBAHalf is within "
                   f"{GAP_BOUND} of HEVC's ({half_gap:.3f})")
    print(f"\n  verdict: {verdict}", flush=True)
    return 0


# ---- composition-gap (issue batch B102, #294) -----------------------------------

def gap_packages(binary):
    """Each GAP_FIXTURES file alone, with each GAP_SETTINGS, saved and closed on
    an instance of its own, stopped before the probe runs: ({(name, setting):
    package}, why or None)."""
    paths = {n: fixture(n) for n in GAP_FIXTURES}
    missing = [n for n, p in paths.items() if p is None]
    if missing:
        return {}, f"fixtures refused {missing}: {REFUSED}"
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    packages, closed = {}, True
    try:
        if launched.client is None:
            return {}, f"the app did not listen at {launched.socket_path}"
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        for name, path in paths.items():
            for setting in GAP_SETTINGS:
                tag = f"cg-{name}-{setting}"
                doc = Doc(launched.client, tag)
                clip = doc.place(path) if doc.ok else None
                media = doc._media.get(path)
                color = None if setting == "none" else RANGE_SETTINGS[name]
                why = None
                if clip is not None and (color is not None
                                         or doc.row(media).get("color") is not None):
                    set_to = doc.color(media, color)
                    why = None if set_to["ok"] else f"set_media_color: {set_to.get('error')}"
                saved = doc.save(f"{tag}-saved") if clip is not None and not why else None
                closed = doc.close() and closed
                packages[(name, setting)] = saved
                if saved is None:
                    print(f"  {tag}: not saved ({why or doc.why})", flush=True)
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = hdr.complaints(log)
    print(f"  instance stopped; every project closed {closed}; complaints {found or 'none'}",
          flush=True)
    if found or not closed:
        return {}, f"closed {closed}; complaints {found}"
    return packages, None


def run_composition_gap(binary):
    """`composition-gap`: the figures and the verdict (the module's docstring)."""
    print(f"B102 composition-gap — {', '.join(GAP_FIXTURES)} with Camera Log None and S-Log3, "
          f"read at {', '.join(s for s, _ in GAP_STAGES)} ({proof_app.config()} build {binary})",
          flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    packages, why = gap_packages(binary)
    if why or any(p is None for p in packages.values()):
        print(f"instrument failure: {why or 'a package was not saved'}")
        return 2
    probe, why = build_probe(ROOT / "app/Sources", name="composition_gap_probe",
                             probe=COMPOSITION_PROBE)
    if probe is None:
        print(f"instrument failure: the probe did not build: {why}")
        return 2
    # The compositor's shaders beside the binary, as hdr_proof.build_probe
    # puts them: a bare binary's main bundle is its folder.
    resources = ROOT / "app/Resources"
    air, library = probe.parent / "Compositor.air", probe.parent / "default.metallib"
    shutil.copy2(resources / "Blank.mp4", probe.parent / "Blank.mp4")
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c",
                        str(resources / "Shaders/Compositor.metal"), "-o", str(air)], 300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o", str(library)],
                           300)
    if step["rc"] != 0 or not library.exists():
        print(f"instrument failure: the shader did not build: {step['stderr'][-400:]}")
        return 2
    points = gap_points()
    request, answer = WORK / "cg-probe.json", WORK / "cg-probe-answer.json"
    answer.unlink(missing_ok=True)
    request.write_text(json.dumps({
        "frames": [{"tag": f"{n}|{s}", "package": str(p), "tick": T}
                   for (n, s), p in packages.items()],
        "points": [list(p) for p in points]}))
    ran = bounded.run([str(probe), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = {r["tag"]: r for r in json.loads(answer.read_text())["rows"]}
    except (OSError, ValueError, KeyError):
        print(f"instrument failure: no answer (rc {ran['rc']}, expired {ran['expired']}): "
              f"{(ran['stdout'] + ran['stderr']).strip()[-300:]}")
        return 2
    unread, parted = [], []
    for hevc, vp9 in GAP_PAIRS:
        for setting in GAP_SETTINGS:
            sides = {n: answered.get(f"{n}|{setting}") or {} for n in (hevc, vp9)}
            print(f"\n  {vp9} against {hevc}, Camera Log {setting}:", flush=True)
            for name, row in sides.items():
                tap = row.get("tap") or {}
                print(f"    {name}: compositor {row.get('compositor')}; track {row.get('track')}; "
                      f"tap {tap.get('format')} {tap.get('width')}×{tap.get('height')} "
                      f"attachments {tap.get('attachments')}"
                      + (f"; error {row.get('error') or tap.get('error')}"
                         if row.get("error") or tap.get("error") else "")
                      + f"; generator {(row.get('generator') or {}).get('space')} "
                      f"{(row.get('generator') or {}).get('bits')}-bit", flush=True)
            first = None
            for stage, verdict in GAP_STAGES:
                a = (sides[vp9].get(stage) or {}).get("values")
                b = (sides[hevc].get(stage) or {}).get("values")
                if stage == "tap" and (sides[vp9].get("tap") or {}).get("format") != \
                        (sides[hevc].get("tap") or {}).get("format"):
                    print(f"    {stage}: formats differ", flush=True)
                    first = first or verdict
                    continue
                if not a or not b:
                    print(f"    {stage}: not read (VP9 "
                          f"{(sides[vp9].get(stage) or {}).get('error', 'no values')}; HEVC "
                          f"{(sides[hevc].get(stage) or {}).get('error', 'no values')})",
                          flush=True)
                    unread.append(f"{vp9}/{hevc} {setting} {stage}")
                    continue
                va = {(x, y): tuple(v) for x, y, v in a}
                vb = {(x, y): tuple(v) for x, y, v in b}
                worst, at = levels(va, vb, points)
                print(f"    {stage}: worst |Δ| {worst:.3f} levels at {at} (VP9 "
                      f"{[round(c * 255, 3) for c in va[at]]}, HEVC "
                      f"{[round(c * 255, 3) for c in vb[at]]})", flush=True)
                if worst > GAP_BOUND and first is None:
                    first = verdict
            print(f"    first stage past {GAP_BOUND}: {first or 'none'}", flush=True)
            if first:
                parted.append((next(i for i, (_, v) in enumerate(GAP_STAGES) if v == first),
                               first, f"{vp9}/{hevc} {setting}"))
    if unread:
        print(f"\n  not read: {unread}; no verdict")
        return 1
    if parted:
        earliest = min(parted)[1]
        where = [w for _, v, w in parted if v == earliest]
        verdict = f"{earliest} — VP9 and HEVC part first there, in {where}"
    else:
        verdict = f"not reproduced — every stage within {GAP_BOUND} for every pair and setting"
    print(f"\n  verdict: {verdict}", flush=True)
    return 0


# ---- the run --------------------------------------------------------------------

def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    for path, anchor, replacement in edits:
        target = copy / path
        if target.is_symlink() or not target.resolve().is_relative_to(WORK):
            # A core file is a symlink into the tree: the copy gets its own core.
            if path.startswith("core/"):
                core = copy / "core"
                if core.is_symlink():
                    core.unlink()
                    shutil.copytree(ROOT / "core", core, symlinks=True,
                                    ignore=shutil.ignore_patterns("target"))
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


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?",
                        choices=["capture", "compare", "reverse-variants", "decode-gap",
                                 "composition-gap"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--control", default=CONTROL)
    parser.add_argument("--variant", help="reverse-variants: comma-separated variants to run")
    args = parser.parse_args()
    if args.mode == "reverse-variants":
        names = [n.strip() for n in (args.variant or ",".join(REVERSE_VARIANTS)).split(",")
                 if n.strip()]
        unknown = [n for n in names if n not in REVERSE_VARIANTS]
        if unknown:
            print(f"unknown variants: {unknown}")
            return 2
        remove_work()
        atexit.register(remove_work)
        HOME.mkdir(parents=True)
        return run_variants([n for n in REVERSE_VARIANTS if n in names])
    if args.mode == "decode-gap":
        remove_work()
        atexit.register(remove_work)
        HOME.mkdir(parents=True)
        return run_decode_gap()
    if args.mode == "composition-gap":
        remove_work()
        atexit.register(remove_work)
        HOME.mkdir(parents=True)
        binary = Path(args.app) if args.app else proof_app.binary()
        return run_composition_gap(proof_app.executable(binary) if binary.suffix == ".app"
                                   else binary)
    if args.mode and not args.folder:
        print(f"{args.mode} needs a folder")
        return 2
    control = (ROOT / (args.folder or args.control)).resolve()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mode == "capture":
        control.mkdir(parents=True, exist_ok=True)
    if args.mode is None and not args.mutant:
        selected -= {"L9", "L18"}
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][1] if args.mutant else []
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading-3 T3-2 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
    else:
        print(f"grading-3 T3-2 — camera log over MCP ({args.mode or 'run'}, {config} build "
              f"{binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    state = {}
    closed = True
    log = WORK / "instance.log"
    needs_instance = bool(selected - PROBE_ROWS - {"Z1"})
    if needs_instance:
        launched = mcp.launch(str(binary), [],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                print(f"instrument failure: the app did not listen at {launched.socket_path}")
                return 2
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            client = launched.client
            try:
                if "L9" in selected and args.mode in ("capture", "compare") or (
                        "L9" in selected and args.mutant):
                    run_l9(client, args.mode, control, state)
                if "L18" in selected and (args.mode in ("capture", "compare") or args.mutant):
                    run_l18(client, args.mode, control, state)
                if "L17" in selected:
                    run_l17(client, state)
                for name, run in (("L1", run_l1), ("L2", run_l2), ("L3", run_l3),
                                  ("L4", run_l4), ("L5", run_l5), ("L6", run_l6),
                                  ("L7", run_l7), ("L8", run_l8), ("L10", run_l10),
                                  ("L11", run_l11), ("L12", run_l12), ("L13", run_l13),
                                  ("L14", run_l14)):
                    if name in selected:
                        run(client)
            except Exception as error:  # a row that could not run is a failure
                import traceback
                traceback.print_exc()
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
                closed = False
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    if selected & LP_ROWS:
        run_probe(sources)
    if "L15" in selected:
        run_l15(sources)
    if "L16" in selected:
        run_l16(sources)
    found = hdr.complaints(log) if needs_instance else []
    closed = closed and all(v for k, v in state.items() if k.endswith("closed"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Frame Job: ` "
          "line", closed and not found and not REFUSED,
          f"closed {closed}; refused {REFUSED or 'none'}; complaints {found}")
    if needs_instance:
        print(f"  {log.name} tail:\n    " + "\n    ".join(hdr.tail(log)), flush=True)
    if args.mode == "capture":
        (control / "capture.json").write_text(json.dumps({"tree": str(ROOT), "config": config},
                                                         indent=1))
        shown = [n for n in ROWS if n in rows and n not in ("L9", "L18", "Z1")]
        failing = [n for n in shown if not rows[n]]
        print(f"captured into {args.folder}; on the control FAILED: {failing} (passed, so not "
              f"discriminating: {[n for n in shown if rows[n]]})")
        return 0 if rows.get("Z1") and state.get("capture_ok") else 1
    scored = [name for name in ROWS if name in rows]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}")
            return 2
        survived = [name for name in named if rows.get(name)]
        others = [name for name in scored if not rows.get(name) and name not in named]
        caught = not survived
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy (survived: {', '.join(survived) or 'none'}; other rows failed: "
              f"{', '.join(others) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
