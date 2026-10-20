#!/usr/bin/env python3
"""Road map "grading-3", phase T3-1 (spec §11 GR-15) — honest sources and
Frame Job's own HDR→SDR at step 0, over MCP and two probes over `app/Sources`.
Written before any product edit, so the control is captured on the untouched
tree. T3-3 (the close) added H1a, H7 and TI's export wall time, measuring two
of GR-15's unmeasured claims; the product was not edited for them.

    python3 tools/proof/hdr_proof.py [--app PATH] [--only H1a,H2,H7,...] [--control DIR]
    python3 tools/proof/hdr_proof.py capture DIR [--only H1,H7i,Z1]   # the CONTROL tree: H1's
                                                    # and H7i's references, H2–H6 shown
    python3 tools/proof/hdr_proof.py compare DIR [--only H1,...]
    python3 tools/proof/hdr_proof.py --measure      # TI, TH and TO: 4K costs (Release figures)
    python3 tools/proof/hdr_proof.py --mutant NAME [--control DIR]

curves_proof.py's shape. Launches the app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`) on a scratch socket of its own and stops only that
process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/hdr/run/home`; every package, PNG and
export of a run is under `tools/proof/work/hdr/run/`, removed at the start and
at exit. The fixtures are made once under `tools/proof/work/hdr/media/` and
kept; `capture` copies H1's into `DIR/media/`, and every later run reads H1's
from there, so the control and the tree draw the same bytes (a VideoToolbox
encode is not repeatable). No default is written: `--measure` passes
`-FrameJobCompositorTiming YES` as a launch argument, and the only menu items
performed (hdr H-3's DM and DX) are View ▸ Show SDR Version and File ▸ Export…,
neither of which persists anything (the sheet is read and cancelled, never
committed). Every
call is bounded (`CALL_BOUND`), every ffmpeg and ffprobe too. Every project is
closed (`close_project`, discard). This script NEVER records the screen.

Fixtures (each kept only when ffprobe reads what it should; a refused fixture
is its row's FAIL, named): `base.mov`, the road map's ramp — 1024×128, 1 s,
10-bit ProRes 422 HQ, the grey ramp on rows 0–63 (Y = 64 + X·876/1023, Cb =
Cr = 512; read on row 32) over the chroma ramp on rows 64–127 (Cb rising
112→912, Cr falling 912→112; read on row 96) — re-tagged by stream copy with
`prores_metadata` and the container's `colr` (`+write_colr`) as `bt709`,
`hlg` (bt2020/arib-std-b67/bt2020nc), `pq` (bt2020/smpte2084/bt2020nc),
`b2020_709` (bt2020/bt709/bt2020nc), `p3_709` (smpte432/bt709/bt709), and
`untagged` (the bsf's `unknown`, no `colr`); by `hevc_videotoolbox` Main 10
from it, `hlg_hevc.mov` (the HLG tags), `srgb.mov` (bt709/iec61966-2-1/bt709)
and `b2020_2020.mov` (bt2020/bt2020-10/bt2020nc); 640×360 1 s `testsrc2`
movies — H.264 BT.709 and untagged, HEVC 8-bit tagged with the matrix only,
ProRes 4444 with an alpha ramp — an 8-bit PNG of it, and container_import_proof
.py's P1 VP9 WebM (the BT.709 H.264 and the ProRes 4444 through
`bt709_fixture.make`, issue #292: `setparams` on the input and the tags on the
output, kept — a cached file too — only when ffprobe reads bt709 ×3 and the
first frame reads back against its own graph); `applelog.mov`, `bt709.mov`
relabelled Apple Log by `applelog_writer.swift` (ffprobe
`bt2020nc/unknown/bt2020`, the label read back); and, for TI only, 4K 4 s
ProRes twins of the ramp, HLG and BT.709.
For H1a: `hevc_alpha.mov`, 640×360 1 s `testsrc2` with an alpha ramp through
`hevc_videotoolbox` from `bgra`, BT.709-tagged by `setparams` (the `-color_*`
flags alone do not stick from `bgra`). For H7's family (rewritten in hdr H-1,
#281): the ramp as raw 4:2:0 10-bit planes through the **x265 CLI**
(`--lossless`, the PQ tags in its VUI; ffmpeg 9.0.2's libx265 wrapper no
longer writes the mastering display with these values), muxed by ffmpeg's
stream copy as `hvc1` — `pq_plain.mov` with no metadata, and with SEI 137
(`--master-display G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)
L(<max>,50)`) and SEI 144 (`--max-cll`): `pq_hdr10` (40000000; 4000,400),
`pq_hdr10_600` (6000000; 600,200), `pq_hdr10_cll` (40000000; 1000,400) and
`pq_hdr10_display` (20000000; no CLL) — and through `hdr10_writer.swift`
(AVAssetWriter's explicit `MasteringDisplayColorVolume` and
`ContentLightLevelInfo`, every sample copied): `pq_desc_600` (over pq_plain:
6000000; 600,200) and `pq_both` (over pq_hdr10, its SEI still 4,000: 600). No
x265 on the host refuses each by name.
The oracle: the codes ffmpeg reads back from a fixture, through the matrix
its tags name (limited range), then this script's own formula with GR-15's
numbers (`convert`), the matrices derived here from the published
chromaticities and D65 (`to709`).

Rows (projects are the fixture alone on a canvas its size, 30 fps):
- **H1** (STOP; `compare DIR` and mutants): every SDR fixture (`bt709`,
  `untagged`, both H.264, the matrix-only HEVC, the PNG, the ProRes 4444, the
  WebM), `srgb.mov`, `applelog.mov` and the BT.709 ramp reversed
  (`set_reversed`): `render_frame` at 0 and 0.5 s byte-identical to DIR's PNGs,
  and `hdr_pick_probe.swift`'s picks at three points at 0.5 s equal to DIR's.
  R0's `rec_tags.mov` joins it when the selector's arm for its tags is nil.
- **H1a** (T3-3; GR-15's "ProRes 4444 with alpha, the WebM rewrap, the
  HEVC-with-alpha path" in a converting composition): prores4444 | hlg |
  hevc_alpha | webm, 1 s each on one 640×360 track, saved; at 0.5 s into
  each non-HLG clip the tree probe's PNG bytes and picks equal the base
  tree's (716720c, a version-18 copy, as H1m). CONTROL: at the HLG clip the
  tree's PNG differs from the base's (the composition converts).
- **H2**: the HLG, PQ and HLG HEVC ramps alone, and BT.709 | HLG | BT.709 (1 s
  each): each `prores_422` export's first frame of the HDR clip equals its
  frame +5 on the grey row (every 8th column) ±1, and `render_frame` at both
  ticks equals the export there ±1 (the first-frame flash; a parity row).
- **H3**: the HLG and PQ grey rows at 0.5 s, every 8th column, = the oracle ±1
  at 8 bits; and Apple's six measured points (HLG 0.25/0.5/0.75/1.0 → 0.215/
  0.384/0.604/1.0, PQ 0.5/0.75 → 0.719/1.0), read off the render at those
  signals, within 3/255 (GR-15's bound, written before measuring).
- **H4**: the HLG chroma row: every even column whose source chroma (max − min
  of R'G'B') is ≥ 0.05 and whose converted linear colour (after the matrix,
  before the lift) leaves [0, 1]³ — at least 20 of them, counted on the
  oracle (a CONTROL on the fixture) — and the column nearest the brief's
  patch (0.42, 0.84, 1.17): the render's hue in linear BT.709 opponent space
  (p = r − g, q = (r + g)/2 − b, atan2(q, p)) within 2° of the oracle's
  pre-lift colour, and its values = the oracle ±2.
- **H5**: `b2020_709`, `p3_709`, `b2020_2020` at 0.5 s: the grey row = the
  signal ±1, the chroma row (every 8th even column) = the oracle ±2.
- **H6**: `hdr_pick_probe.swift` on the HLG ramp over a magenta canvas
  background: the eyedropper's pick at (256, 96) at 0.5 s equals the
  `prores_422` export's pixel there (frame 15) ±2; keyed with the probe's key
  (`set_video` chroma, tolerance 0.05), the export shows magenta there ±8.
- **H7** (CONTROL; rewritten in hdr H-1 for #281, spec §11 HD-12): ffprobe's
  first-frame side data names each SEI fixture's own values (`max_luminance=
  <max>/10000`, `max_content=<MaxCLL>`; x265 writes MaxCLL 0 for
  pq_hdr10_display, measured), none on `pq_plain`; its stream side data names
  each writer fixture's description values, and pq_both's first frame still
  pq_hdr10's 4,000; and `hdr10_writer` read both extensions back.
- **H7d**: `get_project`'s `media[0].color.pq` after import: `{}` on
  pq_plain, `{file 4000, from max_cll}`, `{600, max_cll}`, `{1000, max_cll}`,
  `{2000, mastering_display}`, `{600, max_cll}` on pq_desc_600 and on pq_both
  (the description over the SEI); `{}` on the ProRes `pq` retag; no `pq` on
  `hlg` or `bt709`.
- **H7i**: pq_plain's and pq_hdr10_cll's renders at 0.5 s byte-equal DIR's
  pq_plain PNG (`capture DIR --only H7i,Z1` on the tree before the phase's
  code writes `DIR/h7-pq_plain.png` and copies both files into `DIR/media/`,
  which the run reads), and the grey row (every 8th column) = the oracle at
  1,000 ±1.
- **H7p**: pq_hdr10_600's, pq_hdr10_display's, pq_hdr10's and pq_desc_600's
  grey rows = the oracle at the file's peak (600, 2000, 4000, 600) ±1; at PQ
  0.70 (`render_at`) the 600/1000/2000/4000 files within ±1 of
  255.0/246.9/243.5/242.8 (the road map's computed table); pq_desc_600's PNG
  bytes = pq_hdr10_600's.
- **H7o** on pq_hdr10: `set_media_color {peak: 1000}` renders pq_plain's
  bytes and stores `{4000, max_cll, peak 1000}`; `undo` brings the 4,000
  render back; `{peak: 100}` renders `{peak: 203}`'s bytes (the white held at
  1); `null` keeps `{4000, max_cll}` and the 4,000 render.
- **H7r**: refused, each in its own sentence: a peak on `hlg` and on `bt709`
  ("media N is not a PQ file; only a PQ file takes a peak"), 0 and 10001
  ("color.peak must be 1–10000 cd/m², not N"), `{pq: {file: 1}}` ("color.pq
  is read from the file at import, not set").
  Printed, unscored: Apple's reading of each file (`hdr_pick_probe.swift`'s
  `plain` request, as H1w's oracle) at the grey row every 64th column, and
  each one's worst |Δ| against `pq_plain`'s.
- **R0** (GR-15's owed check; NEVER records the screen, never searches the
  disk): ffprobe reads the labels of the newest-by-name `Screen Recording
  *.mov` in `~/Movies/Frame Job Recordings/` (that folder only, read-only,
  labels only: its pixels are never imported, rendered or copied), the
  selector's arm for them (`arm`, Approach 3's table) is printed, and
  `rec_tags.mov` — the ramp as `srgb.mov` is made, carrying exactly those
  three tags — joins H1 (arm nil) or H5 (`sdrWide`). No such file: "no
  recording on disk; GRD-16", scored nothing.
- **TI** (`--measure`, mutants): the 4K HLG twin placed twice (8 s) exported
  `prores_422` on an instance of its own, then the BT.709 twin on another;
  every compositor timing line (`[framejob] compositor: … over 120 frames, N
  input passes`) reports 120 passes for HLG and 0 for BT.709, at least two
  lines each; the averages, their difference, each export's wall time
  (`time.monotonic()` around the `export` call, recorded, not scored) and the
  host state are printed.
- **P1–P8**: `hdr_probe.swift` over `app/Sources` (a probe that will not build
  is a scored FAIL of all eight). P5 (hdr H-1): `pqShoulderWhite` (1000/203
  bit-exact with no peak, 1 at 100 and 203, peak/203 above), `MediaColor`'s
  stored and `input` shapes and its two dictionaries, `setMediaColor` sending
  null for an empty dictionary, and a converted marker omitting a nil `peak`.
  P6 (hdr H-2): `liftSDR` against Core Graphics drawing each 10-bit Core Media
  709 grey into a 16-bit-float `itur_2100_HLG` bitmap ±1/1023 and
  `unliftSDR(liftSDR(x)) = x` ±1/1023; `choose(input:buffer:output:)`'s table
  (SDR today's, HLG: HLG BT.2020 nil and no arm `.sdr`); a 16-bit HLG frame's
  pick at its code values ±1/255 and the HLG eyedropper's key = `unliftedPick`
  ±2/255.
- **HS…HX** (hdr H-2, #277, spec §11 HD-2, HD-3, HD-13 — the HLG working
  space): each project set to HLG by `set_canvas {output}`; every row reads the
  16-bit PNG as value/65535 against this script's HD-13 oracles (`lift`,
  `unlift`, `pq_hlg`, `eetf`, `hlg_matrix`, `log_hlg`) every 64th column,
  inside the oracle's ±1-code envelope widened by 1/1023 (`env16`) unless a
  row says otherwise. HS the bt709, untagged and srgb ramps → the lift (the
  sRGB-EOTF twin for srgb); HH hlg and hlg_hevc = their own signal, `hlg_p3`
  (smpte432/arib-std-b67) = the matrix in scene light on both rows; HP
  pq_plain → PQ→HLG at 1,000 cd/m², pq_hdr10 (4,000) through BT.2390's EETF and
  on it wherever it parts from the clip by > 3 levels (every 8th column, ≥ 4);
  HT (640×360) a white title = 0.7500, a 50 % grey title, 8-bit grey PNG and
  grey shape (each drawn 128/255) = the bt709 recording at 128/255 and its
  lift, a [0.5, 0.5, 0.5, 1] background = 0.5059, each ±1/1023; HL bt709 as
  S-Log3 → the log oracle, 18 % grey at 0.380; HW saturation −1 on the chroma
  row → BT.2020 luma of the lifted colour, exposure +1 on the grey row →
  OETF(min(2·invOETF(v), 1)); HK `green_709` over a 50 % background keyed in
  SDR at the green its render reads, then switched: the left the lifted
  background 0.5059, the right the lift of the SDR grey ±1/1023; HM a luma
  matte (two shapes nested on the matte track) over bt709: left the lifted
  ramp, right 0.5·lift + 0.5·0.5059 ±2/1023; HF the PNG 16-bit with `cICP`
  9/18/0/1 and an `iCCP` named ITUR_2100_HLG, the HEIC 10-bit as BT.2100 HLG
  (`sips`), a JPEG written as the SDR version and not labelled HLG (hdr H-3;
  H-2 refused it); HX `hevc_10bit` and `prores_422` tagged
  bt2020nc/arib-std-b67/bt2020 with no Dolby Vision configuration or RPU,
  `h264` written as the SDR version, tagged bt709 ×3 (hdr H-3; H-2 refused
  it), `gif` and `audio_wav` written.
- **DT…DX** (hdr H-3, #277, spec §11 HD-4, HD-5, HD-7, HD-14 — the
  deliverables): 16-bit PNGs read as value/65535 against HD-14 (a)'s
  `sdr_version` (scene light, display light at γ 1.2, × 1000/203, BT.2020 →
  BT.709, GR-15's gamut lift and shoulder at knee 0.9 to 1000/203, Core Media
  709's encode with its toe) and (d)'s `pq_version`; every bounded row prints
  its largest miss. DT every video row of an HLG project (the hlg ramp) at its
  default and each accepted `dynamic_range`: bt709 ×3 for the SDR version,
  bt2020nc/arib-std-b67/bt2020 for hlg, bt2020nc/smpte2084/bt2020 for pq, the
  result's `dynamic_range` naming it, no DOVI record or RPU on any HEVC file,
  gif and apng written; DP prores_422, prores_4444 and hevc_10bit at pq: each
  file's side data (P3-D65, min 50/10000, max 10000000/10000, MaxCLL 1000,
  MaxFALL 0) and prores_422's decoded grey row = the PQ oracle ±2/1023; DV
  `render_frame {sdr_version}` of the ramp = the oracle ±1/255 every 64th
  column, a white title 248.4/255, a 0.42 title 107.1/255 and HLG 0.50
  125.7/255, each ±1, the PNG labelled as an SDR project's frame; DI the bt709
  ramp in an HLG project, sdr_version = its SDR render ±1/255 at or below SDR
  0.9477, the shoulder oracle above; DE `h264` (default) frame 15 = the
  sdr_version render ±2/255 (decoded 8-bit, at 50 Mbit/s: the encoder's own
  rate put the grey row's chroma 2.7/255 off) and `prores_422 {sdr}` ±1/255, and
  a JPEG `render_frame` = the sdr_version PNG ±1/255, labelled as it; DR four
  refusals by sentence; DS an SDR project's `sdr_version` PNG and JPEG
  byte-identical to without and its `{dynamic_range: "sdr"}` h264 settings
  equal; DM View ▸ Show SDR Version (it writes no default, so it is performed
  here) shows the "SDR Version" tag, leaves an un-optioned `render_frame`
  byte-identical, and hides the tag when performed again; DX on instances of
  its own (scratch homes, `screens.py`'s PINS and `FrameJobExportChoice` as
  `<string>{"preset_id":…}</string>` launch arguments, as hevc_alpha_proof's
  E3): File ▸ Export… in an HLG project shows "Dynamic Range:" with the popup
  on HDR (HLG) (pinned hevc_10bit) and SDR version (pinned h264); an SDR
  project's sheet has no such row; `cancel_sheet` closes each. The layout dump
  carries no enabled state, so DX reads the popup's title only.
- **TO** (`--measure`): TH's 4K fixture placed twice as an HLG project,
  `prores_422` at hlg and at sdr, each on its own instance: the frame times
  printed against C0's 0.21 ms (REASONED); scored only on the two files' tags.
- **P7**: `hdr_probe.swift`'s `OutputTransform.compositionColour` table,
  `Playback.previewComposition` recolouring a hand-built HLG composition by
  `sdrVersion` (an SDR one never, the same object at Full), `OutputUniforms`
  16 bytes, `sdrKnee` 0.9, `uniforms(for:)`, the two HDR10 blobs, and
  `RecipeOptions.json` / `delivering` / `forFrame`.
- **TH** (`--measure`): TI's 4K BT.709 twin on two tracks (the upper at scale
  0.5) and a title, 8 s, `prores_422`, as an SDR and as an HLG project, each on
  its own instance: 0 and 240 input passes per 120 frames (scored), the frame
  times printed against PR-1's 8 ms.
- **SI…SP** (hdr H-4, #277, spec §11 HD-8, HD-15 — the scopes): SI every H1 SDR
  scene at 0.5 s, `render_frame` with the four scopes and with `{vectorscope,
  vectorscope_zoom: 4}`: each JSON byte-identical to DIR's `si/` and the text (WORK's
  path spelled `<work>`) equal (`capture` writes them; a plain run, `compare` and
  `--only` compare); SW HLG projects of the hlg ramp (identity) and the bt709 ramp (the
  lift): every waveform column's levels holding more than 8 px within ±1 of round(255·
  Y′₂₀₂₀) of the oracle's saturated R′G′B′ at the pixel's codes ±1 (both ways), every
  level within ±1 of the PNG's own pixels (the render's row 64, where the chroma half
  begins, is off the oracle and printed), the parade's channels the same, the histogram's
  planes the waveform's and the parade's column sums exactly, CONTROL ≥ 50 chroma-row
  columns where Rec. 709 and BT.2020 levels part by > 2; SV the `hlg_bars` fixture
  (960×128 ProRes 422 HQ, BT.2111's six 75 % bars as BT.2020-NCL limited-range codes
  computed here, 160 px each, re-tagged HLG as `hlg` is): the six fullest non-centre bins
  each ±1 of one bar's BT.2020 bin, the JSON's targets this script's bins, null at ×2 off
  the plot, the skin line the lifted patch through BT.2020 ±0.05°, CONTROL ≥ 4 bars whose
  Rec. 709 and BT.2020 bins part by ≥ 2; SS the HLG JSON's `signal`, `scale` (the nits
  recomputed here) and `matrix`, and the four sentences and the ×2 one; SD
  `{sdr_version, waveform, vectorscope}` with no `signal` or `scale`, matrix Rec. 709, the
  waveform ±1 of Rec. 709 levels of its PNG, a JPEG's scopes with no `signal`,
  `{ungraded, waveform}` with exposure +1 on the clip `signal` "hlg" at SW's hlg oracle;
  SP View ▸ Scopes on the hlg ramp, paused, through `snapshot_ui`: the captions "HLG ·
  cd/m²" over "Rec. 2100 HLG" and the top readouts within 0.2 of `render_frame`'s; View ▸
  Show SDR Version turns both captions "Rec. 709 · encoded" at `{sdr_version}`'s readouts
  (CONTROL: > 1 point from the HLG ones); off again the HLG captions, kept under View ▸
  Show Ungraded; an SDR project's "Rec. 709 · encoded". The View items performed —
  Scopes, Show SDR Version, Show Ungraded — persist nothing.
- **P8** (hdr H-4): `hdr_probe.swift`'s `ScopeSignal` (its init table, ticks, labels,
  captions, uniforms), `targets(for: .sdr)` bit-equal to `targets`, `targets(for: .hlg)`
  BT.2020's, the traces' SDR JSON with no `signal`/`scale` and HLG JSON with both; and
  `WaveformTraceView` (248×200), `ParadeView` (600×200) and `VectorscopeView` (512×512 at
  ×1 and ×2) cached to bitmaps in a borderless offscreen window, an HLG trace beside the
  same with `signal: .sdr`: a dashed well row at 75 % in HLG only (every parade well), the
  target boxes' corners and the skin line lit for the trace's signal, CONTROL ≥ 4 targets
  whose HLG and SDR boxes part by ≥ 4 pt with no SDR box where the HLG one is, and the SDR
  bitmap unlit on the HLG skin ray.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Frame Job: ` line.

Issue batch B102 (spec §11 PR-11): `render_frame` labels every frame BT.709
at the write, so a DIR captured before B102 fails H1 on labels alone (its
PNGs' `sRGB` chunks are `iCCP` now; `frame_label_proof.py same-pixels DIR
NEW` shows the pixels equal). The mutant `relabel-in-renderframe` (H1)
applies the label inside `Exporter.renderFrame` instead, which moves the
eyedropper's picks; it runs against a capture made after PR-11.

H1a, the H7 family, the H-2 rows, the H-3 rows and the H-4 rows run in a plain run,
`compare` and `--only`; never under `capture`'s default selection, `--measure` or a
mutant's default selection; hdr H-1's five, H-2's twelve, H-3's seven and H-4's nine
mutants run with `--only <their rows>,Z1` (SI also runs under `capture --only`, writing
DIR's references). `capture --only`
captures just the rows named, keeping an earlier capture's H1 record.
`capture DIR` records H1's references (`DIR/h1-*.png`, `DIR/media/`,
`DIR/capture.json` with the picks and the reverse's digest) and runs H2–H6 and
R0, which must FAIL on the control (each discriminates). `--mutant NAME`
builds a COPY of the tree (`tree_copy.make_copy`), applies its edits (each
anchor asserted to occur exactly once), builds it by the copy's own `make
app-debug` (`make app` under `RC_PROOF_APP=release`) and runs every row on it
(H1 against `--control`, default tools/proof/work/t3-1/ctl), the probes built
over the copy's `app/Sources`. MUTANT PASS when every named row FAILED; every
other row that failed is printed.
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed (a
mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import bt709_fixture  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import reference_build  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/hdr"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CONTROL = "tools/proof/work/t3-1/ctl"
PICK_PROBE = ROOT / "tools/proof/hdr_pick_probe.swift"
MATH_PROBE = ROOT / "tools/proof/hdr_probe.swift"
WRITER = ROOT / "tools/proof/applelog_writer.swift"
HDR10_WRITER = ROOT / "tools/proof/hdr10_writer.swift"
RECORDINGS = Path.home() / "Movies" / "Frame Job Recordings"
CALL_BOUND = 300
BUILD_BOUND = 1500
REVERSE_BOUND = 300
SEC = 600_000
FRAME = SEC // 30
T = SEC // 2
W, H = 1024, 128
GREY_ROW, CHROMA_ROW = 32, 96
SW, SH = 640, 360
BASE_FILTER = ("color=c=black:size=1024x128:rate=30:duration=1,format=yuv422p10le,"
               "geq=lum='64+X*876/(W-1)':cb='if(lt(Y,64),512,112+X*800/(W-1))':"
               "cr='if(lt(Y,64),512,912-X*800/(W-1))'")
# name: (primaries, transfer, matrix) for prores_metadata and colr; None = untagged.
RETAGS = {"bt709": ("bt709", "bt709", "bt709"),
          "untagged": None,
          "hlg": ("bt2020", "arib-std-b67", "bt2020nc"),
          "pq": ("bt2020", "smpte2084", "bt2020nc"),
          "b2020_709": ("bt2020", "bt709", "bt2020nc"),
          "p3_709": ("smpte432", "bt709", "bt709"),
          # hdr H-2's HH: HLG over P3 D65 (spec §11 HD-13 (d)).
          "hlg_p3": ("smpte432", "arib-std-b67", "bt2020nc")}
HEVC10 = {"hlg_hevc": ("bt2020", "arib-std-b67", "bt2020nc"),
          "srgb": ("bt709", "iec61966-2-1", "bt709"),
          "b2020_2020": ("bt2020", "bt2020-10", "bt2020nc"),
          "p3srgb": ("smpte432", "iec61966-2-1", "bt709")}
# GR-15's numbers (spec §11 GR-15, T3-1's append) and the standards' constants.
HLG_GAMMA, HLG_GAIN, KNEE, HLG_WHITE = 0.96, 1.07, 0.39, 1.07
PQ_REFERENCE, PQ_WHITE, DISPLAY_GAMMA = 203.0, 1000.0, 2.4
# The gamma of Core Media's BT.709 profile (`curv` 502/256): the sRGB arm's encode
# is its inverse (GR-15 as amended, M7).
CM709_GAMMA = 502 / 256
HLG_A = 0.17883277
HLG_B = 1 - 4 * HLG_A
HLG_C = 0.5 - HLG_A * math.log(4 * HLG_A)
PQ_M1, PQ_M2 = 2610 / 16384, 2523 / 4096 * 128
PQ_C1, PQ_C2, PQ_C3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32
# Published chromaticities (x, y) of R, G, B, and D65.
PRIMARIES = {"bt709": ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060)),
             "bt2020": ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046)),
             "p3d65": ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060))}
D65 = (0.3127, 0.3290)
LUMA2020 = (0.2627, 0.6780, 0.0593)
LUMA709 = (0.2126, 0.7152, 0.0722)
KR_KB = {"bt709": (0.2126, 0.0722), "bt2020nc": (0.2627, 0.0593)}
APPLE = {"hlg": [(0.25, 0.215), (0.5, 0.384), (0.75, 0.604), (1.0, 1.0)],
         "pq": [(0.5, 0.719), (0.75, 1.0)]}
APPLE_BOUND = 3
PATCH = (0.42, 0.84, 1.17)
TIMING = re.compile(r"\[framejob\] compositor: ([\d.]+) ms average, ([\d.]+) ms worst over 120 "
                    r"frames(?:, (\d+) input passes)?")
# H1's SDR fixtures: (name, canvas width, height).
H1_FIXTURES = [("bt709", W, H), ("untagged", W, H), ("h264_709", SW, SH),
               ("h264_untagged", SW, SH), ("hevc8_matrix", SW, SH), ("still8", SW, SH),
               ("prores4444", SW, SH), ("webm", SW, SH), ("srgb", W, H), ("applelog", W, H)]
H1_SUFFIX = {"still8": ".png", "webm": ".webm"}
PICK_POINTS = {(W, H): [[256.5, 32.5], [512.5, 96.5], [900.5, 100.5]],
               (SW, SH): [[320.5, 180.5], [100.5, 60.5], [540.5, 300.5]]}
ROWS = ["H1", "H1m", "H1a", "H1s", "H1w", "H2", "H3", "H4", "H5", "H6", "H7", "H7d", "H7i",
        "H7p", "H7o", "H7r", "HS", "HH", "HP", "HT", "HL", "HW", "HK", "HM", "HF", "HX", "DT",
        "DP", "DV", "DI", "DE", "DR", "DS", "DM", "DX", "SI", "SW", "SV", "SS", "SD", "SP", "R0",
        "TI", "TH", "TO", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "Z1"]
# H7's family (hdr H-1, #281, spec §11 HD-6, HD-12): PQ ramps whose HDR10 static
# metadata sits in the HEVC stream's SEI (the x265 CLI, muxed by ffmpeg's stream copy;
# ffmpeg 9.0.2's libx265 wrapper no longer writes the mastering display with these
# values) or in the sample description (hdr10_writer.swift, AVAssetWriter's explicit keys).
X265_DISPLAY = "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)"
# name: (the mastering display's maximum in x265's 0.0001 cd/m² or None, (MaxCLL, MaxFALL)
# or None), each written by x265 as SEI 137 and 144.
SEI_FIXTURES = {"pq_plain": (None, None), "pq_hdr10": (40000000, (4000, 400)),
                "pq_hdr10_600": (6000000, (600, 200)), "pq_hdr10_cll": (40000000, (1000, 400)),
                "pq_hdr10_display": (20000000, None)}
# name: (the SEI fixture whose samples it copies, the maximum, MaxCLL, MaxFALL) in the
# sample description; pq_both keeps pq_hdr10's SEI (4,000) under a 600 description.
DESC_FIXTURES = {"pq_desc_600": ("pq_plain", 6000000, 600, 200),
                 "pq_both": ("pq_hdr10", 6000000, 600, 200)}
H7_FIXTURES = list(SEI_FIXTURES) + list(DESC_FIXTURES)
# H7d: what import stores as `media.color.pq` (HD-12: the description first, else the
# SEI; MaxCLL when non-zero, else the mastering maximum rounded to whole cd/m²).
H7_READS = {"pq_plain": {}, "pq_hdr10": {"file": 4000, "from": "max_cll"},
            "pq_hdr10_600": {"file": 600, "from": "max_cll"},
            "pq_hdr10_cll": {"file": 1000, "from": "max_cll"},
            "pq_hdr10_display": {"file": 2000, "from": "mastering_display"},
            "pq_desc_600": {"file": 600, "from": "max_cll"},
            "pq_both": {"file": 600, "from": "max_cll"}}
# H7p: each peak's fixture, and the computed level at PQ 0.70 (620.9 cd/m²; the road
# map's table, hdr_math.py §4, re-run in H-0).
PEAK_FIXTURES = {600: "pq_hdr10_600", 1000: "pq_hdr10_cll", 2000: "pq_hdr10_display",
                 4000: "pq_hdr10"}
AT_070 = {600: 255.0, 1000: 246.9, 2000: 243.5, 4000: 242.8}
H7_ROWS = {"H7", "H7d", "H7i", "H7p", "H7o", "H7r"}
# hdr H-2 (#277, spec §11 HD-2, HD-3, HD-13): the HLG working space's rows, and the
# numbers its oracles use (HD-13 (a)–(e)); every row reads 16-bit PNGs as value/65535,
# and a 10-bit level is the tolerance unless the row names another.
H2_ROWS = {"HS", "HH", "HP", "HT", "HL", "HW", "HK", "HM", "HF", "HX"}
LEVEL = 1 / 1023
HLG_NOMINAL_GAMMA = 1.2
LIFT_SCALE = PQ_REFERENCE / PQ_WHITE
LOG_HLG_EXPOSURE = 0.38 * 0.38 / 3 / 0.18
SLOG3_BREAK = 171.2102946929
# Core Graphics draws Core Media 709's γ curve with a slope limit of 16: its decode is
# max(s/16, s^γ) (measured in H-2, `hdr_probe.swift` P6), and so is the lift's.
CM709_TOE = 16.0
# hdr H-3 (#277, spec §11 HD-4, HD-5, HD-7, HD-14): the deliverables' rows and numbers.
# The SDR version's knee and white (HD-14 (a)), and the SDR grey at the knee, below which
# the version is the round trip; the video rows, the three that carry HDR, the tags each
# picture is written with, HD-5's HDR10 side data as ffprobe names it, and the menu item.
H3_ROWS = {"DT", "DP", "DV", "DI", "DE", "DR", "DS", "DM", "DX"}
SDR_KNEE = 0.9
SDR_WHITE = PQ_WHITE / PQ_REFERENCE
SDR_KNEE_GREY = 0.9477
VIDEO_ROWS = ["h264", "hevc", "hevc_10bit", "hevc_alpha", "prores_422", "prores_4444", "gif",
              "apng"]
HDR_ROWS = ["hevc_10bit", "prores_422", "prores_4444"]
PICTURE_TAGS = {"sdr": "bt709/bt709/bt709", "hlg": "bt2020nc/arib-std-b67/bt2020",
                "pq": "bt2020nc/smpte2084/bt2020"}
HDR10_SIDE = {"red_x": "34000/50000", "red_y": "16000/50000", "green_x": "13250/50000",
              "green_y": "34500/50000", "blue_x": "7500/50000", "blue_y": "3000/50000",
              "white_point_x": "15635/50000", "white_point_y": "16450/50000",
              "min_luminance": "50/10000", "max_luminance": "10000000/10000",
              "max_content": "1000", "max_average": "0"}
SDR_VERSION_MENU = ["View", "Show SDR Version"]
DE_H264_BITRATE = 50_000_000
# hdr H-4 (#277, spec §11 HD-8, HD-15): the scopes' rows. SI holds every SDR project's scope
# JSON and sentences to DIR's; the rest read an HLG project's.
H4_ROWS = {"SI", "SW", "SV", "SS", "SD", "SP"}
SCOPE_KINDS = ["waveform", "parade", "vectorscope", "histogram"]
SCOPES_ALL = {kind: True for kind in SCOPE_KINDS}
SCOPES_MENU = ["View", "Scopes"]
UNGRADED_MENU = ["View", "Show Ungraded"]
# SV's fixture: BT.2111's six 75 % bars as BT.2020 HLG values, 160 px each, tagged HLG.
HLG_BARS = [("R", (0.75, 0.0, 0.0)), ("Mg", (0.75, 0.0, 0.75)), ("B", (0.0, 0.0, 0.75)),
            ("Cy", (0.0, 0.75, 0.75)), ("G", (0.0, 0.75, 0.0)), ("Yl", (0.75, 0.75, 0.0))]
BARS_W, BARS_H, BAR_W = 960, 128, 160
SKIN_PATCH = (194 / 255, 150 / 255, 130 / 255)
PANEL_WAIT = 20
SDR_CAPTION = "Rec. 709 · encoded"


BASE_COMMIT = "716720c"
BASE_TREE = BASE / f"base-{BASE_COMMIT}"
INPUT_SWIFT = "app/Sources/InputConversions.swift"
STAGE_SWIFT = "app/Sources/Compositor+Input.swift"
COMPOSITOR = "app/Sources/Compositor.swift"
BUILDER = "app/Sources/CompositionBuilder.swift"
SHADER = "app/Resources/Shaders/Compositor.metal"
HDR10_RS = "core/src/hdr10.rs"
SOURCES_SWIFT = "app/Sources/Compositor+Sources.swift"
RENDERER_SWIFT = "app/Sources/MetalRenderer.swift"
OUTPUT_SWIFT = "app/Sources/OutputTransform.swift"
RANGE_RS = "core/src/dynamic_range.rs"
EXPORT_RS = "core/src/export.rs"
EXPORTER_SWIFT = "app/Sources/Exporter.swift"
OPTIONS_SWIFT = "app/Sources/RecipeOptions.swift"
PREVIEW_SWIFT = "app/Sources/Playback+PreviewQuality.swift"
WRITER_SWIFT = "app/Sources/FrameWriter.swift"
SETTINGS_SWIFT = "app/Sources/ExporterWriter+Settings.swift"
SCOPE_SHADER = "app/Resources/Shaders/Waveform.metal"
SIGNAL_SWIFT = "app/Sources/ScopeSignal.swift"
VECTORSCOPE_SWIFT = "app/Sources/VectorscopeView.swift"
P_ROWS = {"P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8"}
RECORDS = {"R0"}
# name: ([(file, anchor, replacement), …], the rows that must fail).
MUTANTS = {
    "no-conform": ([(STAGE_SWIFT, "    override var canConformColorOfSourceFrames: Bool { true }\n",
                     "    override var canConformColorOfSourceFrames: Bool { false }\n")],
                   ["H2", "H3"]),
    "hlg-branch-moved": ([(SHADER, "    return select(high, low, v <= 0.5);\n",
                           "    return select(high, low, v <= 0.45);\n")], ["P3"]),
    "matrix-transposed": ([(INPUT_SWIFT, "        return simd_float3x3(rows: rows)\n",
                            "        return simd_float3x3(columns: (rows[0], rows[1], rows[2]))\n")],
                          ["H3", "H5", "H1w", "P2", "P3"]),
    "shoulder-dropped": ([(SHADER, "    return l * (s / m);\n", "    return min(l, 1.0);\n")],
                         ["H3", "H4", "P3"]),
    "lift-dropped": ([(SHADER, "    return y <= 0.0 ? float3(0.0) : y + (l - y) * (y / (y - low));\n",
                       "    return max(l, 0.0);\n")], ["H4", "P3"]),
    # Re-pinned in hdr H-3: an SDR project's colour is `OutputTransform.compositionColour`'s
    # first arm, a converting composition's BT.709 dropped.
    "no-composition-color": ([(OUTPUT_SWIFT, "            return converts\n",
                               "            return false\n")], ["H2", "H3", "H1m"]),
    "select-by-primaries": ([(INPUT_SWIFT, "        guard logTransfer == nil else { return nil }\n",
                              "        if let wide = wide(primaries) { return wide }\n")],
                            ["H1", "P1"]),
    "convert-everywhere": ([(BUILDER, "        let converts = hlg || convertsSources(videoTracks) "
                                      "|| plan.convertsMedia\n",
                             "        let converts = true\n")], ["H1", "H1m"]),
    "conform-everywhere": ([
        (COMPOSITOR, "    var canConformColorOfSourceFrames: Bool { false }\n",
         "    var canConformColorOfSourceFrames: Bool { true }\n"),
        (COMPOSITOR, "    var supportsHDRSourceFrames: Bool { false }\n",
         "    var supportsHDRSourceFrames: Bool { true }\n")], ["H1m"]),
    "srgb-arm-dropped": ([(INPUT_SWIFT, "        default: return .srgb(.bt709)\n",
                           "        default: return nil\n")], ["H1s", "P1"]),
    "srgb-starts-conversion": ([(INPUT_SWIFT,
                                 "    var startsConversion: Bool { self != .srgb(.bt709) }\n",
                                 "    var startsConversion: Bool { true }\n")], ["H1", "P1"]),
    "srgb-wide-as-sdrwide": ([(INPUT_SWIFT,
                               "        case Label.primaries2020: return .srgb(.bt2020)\n"
                               "        case Label.p3D65: return .srgb(.p3D65)\n",
                               "        case Label.primaries2020: return .sdrWide(.bt2020)\n"
                               "        case Label.p3D65: return .sdrWide(.p3D65)\n")],
                             ["H1w", "P1"]),
    # B102 (spec §11 PR-11): the BT.709 label applied inside `Exporter.renderFrame`
    # instead of at the write, so the eyedropper reads a relabelled frame. Run
    # with `--control` a capture made after PR-11 (B102's `hdr-after`).
    "relabel-in-renderframe": ([("app/Sources/Exporter.swift",
                                 "        return RenderedFrame(image: image, graphics: "
                                 "GraphicRegistry.shared.reports(for: key))\n",
                                 "        return RenderedFrame(image: image.map(FrameWriter.labelled), "
                                 "graphics: GraphicRegistry.shared.reports(for: key))\n")],
                               ["H1"]),
    # hdr H-1 (#281, spec §11 HD-12): each run with `--only <its rows>,Z1` and `--control`
    # the capture of H7i made on the tree before the phase's code.
    "peak-ignored": ([(INPUT_SWIFT,
                       "            uniforms.white = InputConversions.pqShoulderWhite(peak: peak)\n",
                       "            uniforms.white = InputConversions.pqShoulderWhite(peak: nil)\n")],
                     ["H7p", "H7o"]),
    "mastering-over-cll": ([(HDR10_RS,
                             "    content_light\n"
                             "        .map(|cll| found(cll, PeakSource::MaxCll))\n"
                             "        .or_else(|| mastering.map(|max| found(max, "
                             "PeakSource::MasteringDisplay)))\n",
                             "    mastering\n"
                             "        .map(|max| found(max, PeakSource::MasteringDisplay))\n"
                             "        .or_else(|| content_light.map(|cll| found(cll, "
                             "PeakSource::MaxCll)))\n")], ["H7d", "H7i"]),
    "sei-unparsed": ([(HDR10_RS, "    let (mastering, light) = sei_payloads(sample, nal_length_size);\n",
                       "    let (mastering, light) = (None, None);\n")], ["H7d", "H7p"]),
    "unknown-not-1000": ([(INPUT_SWIFT, "        let nits = peak.map { Float($0) } ?? pqWhite\n",
                           "        let nits = peak.map { Float($0) } ?? 4000\n")],
                         ["H7i", "P5"]),
    "peak-below-knee": ([(INPUT_SWIFT,
                          "        return max(nits, pqReferenceWhite) / pqReferenceWhite\n",
                          "        return nits / pqReferenceWhite\n")], ["H7o", "P5"]),
    # hdr H-2 (#277, spec §11 HD-13): one per decision, each run with `--only <its
    # rows>,Z1` and `--control` the capture made on the tree before the phase's code.
    # The SDR arm: a BT.709 or untagged source left unlifted in an HLG project.
    "sdr-not-lifted": ([(INPUT_SWIFT, "        case nil: return .sdr\n",
                         "        case nil: return nil\n")], ["HS", "HT"]),
    # Layers: text sampled as drawn, not lifted.
    "title-not-lifted": ([(SOURCES_SWIFT,
                           "            guard let rendered = renderers.text(props, hash: hash, "
                           "reveal: reveal)\n            else { return .absent }\n"
                           "            return lifting(rendered.texture, rendered.size)\n",
                           "            guard let rendered = renderers.text(props, hash: hash, "
                           "reveal: reveal)\n            else { return .absent }\n"
                           "            return .textured(\n                rendered.texture, "
                           "rendered.size, premultiplied: true, orientation: 0)\n")], ["HT"]),
    # The background cleared to its SDR colour.
    "background-not-lifted": ([(RENDERER_SWIFT,
                                "            buffer: buffer, target: target, clear: "
                                "clearColor(background(canvas)),\n",
                                "            buffer: buffer, target: target, clear: "
                                "clearColor(canvas.background),\n")], ["HT"]),
    # The grade's weights: Rec. 709's in an HLG project too.
    "709-weights-in-hlg": ([(SHADER,
                             "    return hlgOutput > 0.5 ? kLuma2020 : float3(0.2126, 0.7152, "
                             "0.0722);\n",
                             "    return float3(0.2126, 0.7152, 0.0722);\n")], ["HW"]),
    # Tone's transfer: the sRGB pair in an HLG project too.
    "srgb-tone-in-hlg": ([(SHADER,
                           "    float3 lin = (hlg ? hlgInverseOETF(saturate(rgb)) : "
                           "gradeDecode(rgb))\n        * exp2(u.exposure) * gains;\n"
                           "    rgb = hlg ? hlgOETF(saturate(lin)) : gradeEncode(lin);\n",
                           "    float3 lin = gradeDecode(rgb) * exp2(u.exposure) * gains;\n"
                           "    rgb = gradeEncode(lin);\n")], ["HW"]),
    # PQ above 1,000 cd/m² clipped, not through BT.2390's EETF.
    "pq-no-eetf": ([(SHADER,
                     "        float3 s = u.eetfSourcePQ > 0.0 ? pqEETF(signal, u) : signal;\n",
                     "        float3 s = signal;\n")], ["HP"]),
    # Frames: an HLG frame relabelled BT.709 at the write.
    "frame-labelled-709": ([(WRITER_SWIFT, "        if isHLG(image) { return image }\n", "")],
                           ["HF"]),
    # Camera log: the SDR arms' ending (the lift) in place of scene light's.
    "log-to-sdr-in-hlg": ([(SHADER,
                            "        return hlgOETF(max(inputMatrix(u, r * u.exposure), "
                            "0.0));\n",
                            "        return hlgOETF(hlgInverseOOTF(\n            max(inputMatrix("
                            "u, r * u.exposure), 0.0) * u.liftScale, u.ootfGamma));\n")],
                          ["HL"]),
    # Dolby Vision: the insertion-mode key dropped.
    "dv-left-on": ([(SETTINGS_SWIFT,
                     "            compression[kVTCompressionPropertyKey_HDRMetadataInsertionMode "
                     "as String] =\n                kVTHDRMetadataInsertionMode_None\n", "")],
                   ["HX"]),
    # The pick: an HLG frame read through ColorSync's tone mapping.
    "pick-tone-mapped": ([(WRITER_SWIFT,
                           "        guard isHLG(image), let srgb = CGColorSpace(name: "
                           "CGColorSpace.sRGB) else { return image }\n"
                           "        return image.copy(colorSpace: srgb) ?? image\n",
                           "        return image\n")], ["P6"]),
    # hdr H-3 (#277, spec §11 HD-14): one per decision, each run with `--only <its
    # rows>,Z1` and `--control` the capture made on the tree before the phase's code.
    # The export override never read: every row at its default.
    "range-ignored": ([(EXPORT_RS,
                        "        let picture = self.deliverable(preset, dynamic_range(overrides)?)?;\n",
                        "        let picture = self.deliverable(preset, None)?;\n"
                        "        let _ = dynamic_range;\n")], ["DP", "DR"]),
    # The output pass's SDR arm on GR-15's HLG constants (γ 0.96, gain 1.07, knee 0.39,
    # white 1.07, BT.1886's encode) instead of the inverse of the lift.
    "sdr-via-gr15": ([(SHADER,
                       "        float3 l = inputShoulder(inputLift(kBT2020ToBT709 * (display * "
                       "kHlgPeakOverSDRWhite)),\n"
                       "                                 u.knee, kHlgPeakOverSDRWhite);\n"
                       "        l = max(l, 0.0);\n"
                       "        rgb = min(l * kCoreMedia709Toe, pow(l, 1.0 / kCoreMedia709Gamma));\n",
                       "        float3 light = ys > 1e-6 ? 1.07 * scene * pow(ys, 0.96 - 1.0) : "
                       "float3(0.0);\n"
                       "        float3 l = inputShoulder(inputLift(kBT2020ToBT709 * light), 0.39, "
                       "1.07);\n"
                       "        rgb = pow(max(l, 0.0), 1.0 / 2.4);\n")], ["DV", "DI"]),
    # HDR10's two keys dropped: VideoToolbox's Auto metadata, and none on ProRes.
    "pq-auto-metadata": ([(SETTINGS_SWIFT,
                           "        [\n"
                           "            kVTCompressionPropertyKey_MasteringDisplayColorVolume as "
                           "String:\n"
                           "                OutputTransform.masteringDisplay,\n"
                           "            kVTCompressionPropertyKey_ContentLightLevelInfo as String:\n"
                           "                OutputTransform.contentLightLevel,\n"
                           "        ]\n",
                           "        [:]\n")], ["DP"]),
    # An 8-bit row of an HLG project written as HLG, not its SDR version.
    "8bit-row-hlg": ([(RANGE_RS, "            None => Ok(Some(DynamicRange::Sdr)),\n",
                       "            None => Ok(Some(DynamicRange::Hlg)),\n")],
                     ["DT", "DE", "HX"]),
    # The export draws the asked options, not its settings' picture: the SDR version only
    # ever in the preview.
    "sdr-version-preview-only": ([(EXPORTER_SWIFT,
                                   "        RecipeSource.shared.setOptions(options.delivering("
                                   "settings), for: key)\n",
                                   "        RecipeSource.shared.setOptions(options, for: key)\n")],
                                 ["DE"]),
    # A JPEG of an HLG project drawn as HLG (and so refused by FrameWriter's guard).
    "jpeg-not-sdr-version": ([(OPTIONS_SWIFT,
                               "        guard format == .jpeg, output == .hlg else { return self }\n",
                               "        guard format == .jpeg, output == .hlg, format != .jpeg else "
                               "{ return self }\n")], ["DE", "HF"]),
    # The preview's composition kept HLG whatever Show SDR Version says.
    "preview-keeps-hlg": ([(PREVIEW_SWIFT,
                            "                hlg: true, converts: true, range: sdrVersion ? .sdr : "
                            ".hlg)\n",
                            "                hlg: true, converts: true, range: .hlg)\n")], ["P7"]),
    # The chroma key's distance on the working (lifted) colour.
    "key-not-unlifted": ([(SHADER,
                           "        float d = distance(u.hlgOutput > 0.5 ? saturate(hlgUnliftSDR("
                           "rgb)) : rgb, key);\n",
                           "        float d = distance(rgb, key);\n")], ["HK"]),
    # The matte resolve's luma on the lifted composite.
    "matte-not-unlifted": ([(SHADER,
                             "    if (u.hlgOutput > 0.5) {\n        // An HLG project (spec §11 "
                             "HD-13 (h)): Rec. 709 luma of the un-lifted,\n",
                             "    if (false) {\n        // An HLG project (spec §11 "
                             "HD-13 (h)): Rec. 709 luma of the un-lifted,\n")], ["HM"]),
    # hdr H-4 (#277, spec §11 HD-8, HD-15): one per decision, each run with `--only <its
    # rows>,Z1` and `--control` the capture made on the tree before the phase's code.
    # The shader's HLG waveform and vectorscope on Rec. 709's constants.
    "scope-709-in-hlg": ([
        (SCOPE_SHADER, "        level = min(255u, uint(dot(rgb, kLuma2020Weights) * 255.0 + 0.5));\n",
         "        level = min(255u, uint(dot(rgb, kLumaWeights) * 255.0 + 0.5));\n"),
        (SCOPE_SHADER, "        int2 raw = signal == 1u ? chromaBins2020(",
         "        int2 raw = signal == 1u ? chromaBins(")], ["SW", "SV"]),
    # The histogram's HLG Y′ on Rec. 709's weights.
    "histogram-709-in-hlg": ([(SCOPE_SHADER,
                               "            levels.w = scopeLevel(dot(rgb, kLuma2020Weights));\n",
                               "            levels.w = scopeLevel(dot(rgb, kLumaWeights));\n")],
                             ["SW"]),
    # Reference white at 100 %, not 75 %: the JSON's and the dashed line's.
    "ref-line-at-100": ([(SIGNAL_SWIFT, "        case .hlg: return 75\n",
                          "        case .hlg: return 100\n")], ["SS", "P8"]),
    # The SDR version's frames read as HLG.
    "sdr-version-read-as-hlg": ([(SIGNAL_SWIFT,
                                  "        self = output == .hlg && dynamicRange != .sdr ? .hlg : "
                                  ".sdr\n",
                                  "        self = output == .hlg ? .hlg : .sdr\n")],
                                ["SD", "SP"]),
    # The panel's frames offered as SDR whatever their canvas.
    "tap-signal-dropped": ([(COMPOSITOR, "                signal: ScopeSignal(canvas: recipe?.canvas))\n",
                             "                signal: .sdr)\n")], ["SP"]),
    # render_frame's scopes read as SDR in an HLG project.
    "render-scopes-sdr": ([("app/Sources/AgentServer+Render.swift",
                            "            let signal = ScopeSignal(output: output, dynamicRange: "
                            "options.dynamicRange)\n",
                            "            let signal = ScopeSignal.sdr\n")], ["SW", "SV", "SS"]),
    # An SDR trace's JSON naming its signal.
    "sdr-json-names-scale": ([(SIGNAL_SWIFT, "        case .sdr: return [:]\n",
                               "        case .sdr: return [\"signal\": rawValue]\n")],
                             ["SI", "P8"]),
    # The vectorscope view drawing Rec. 709's targets and skin line in HLG.
    "vectorscope-view-709-targets": ([
        (VECTORSCOPE_SWIFT, "VectorscopeTrace.skinLineDegrees(for: signal) * .pi / 180",
         "VectorscopeTrace.skinLineDegrees(for: .sdr) * .pi / 180"),
        (VECTORSCOPE_SWIFT, "for target in VectorscopeTrace.targets(for: signal) {",
         "for target in VectorscopeTrace.targets(for: .sdr) {")], ["P8"]),
    # The parade's wells drawing SDR's graticule in HLG.
    "parade-graticule-sdr": ([("app/Sources/ParadeView.swift",
                               "labelsIn: index == 0 ? bounds : nil, signal: signal)",
                               "labelsIn: index == 0 ? bounds : nil)")], ["P8"]),
}
rows = {}
selected = set(ROWS)
REFUSED = {}


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
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


# ---- the oracle -----------------------------------------------------------------

def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def mat_inv(m):
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]


def npm(name):
    """RGB → XYZ for `name`'s primaries and D65 (the standard derivation)."""
    columns = [[x / y, 1.0, (1 - x - y) / y] for x, y in PRIMARIES[name]]
    p = [[columns[j][i] for j in range(3)] for i in range(3)]
    xw, yw = D65
    s = mat_vec(mat_inv(p), [xw / yw, 1.0, (1 - xw - yw) / yw])
    return [[p[i][j] * s[j] for j in range(3)] for i in range(3)]


def to709(name):
    """Linear `name` RGB → linear BT.709 RGB."""
    return mat_mul(mat_inv(npm("bt709")), npm(name))


def hlg_inverse(v):
    v = max(v, 0.0)
    return v * v / 3 if v <= 0.5 else (math.exp((v - HLG_C) / HLG_A) + HLG_B) / 12


def pq_eotf(v):
    p = min(max(v, 0.0), 1.0) ** (1 / PQ_M2)
    return (max(p - PQ_C1, 0.0) / (PQ_C2 - PQ_C3 * p)) ** (1 / PQ_M1)


def shoulder(m, white):
    if m <= KNEE:
        return m
    if m >= white:
        return 1.0
    t, tw = (m - KNEE) / (1 - KNEE), (white - KNEE) / (1 - KNEE)
    return KNEE + (1 - KNEE) * t * (1 + t / (tw * tw)) / (1 + t)


def convert(kind, primaries, rgb, peak=PQ_WHITE):
    """GR-15's step 0 on one straight R'G'B' signal: (the encoded output, the
    linear BT.709 colour before the lift). `kind` is hlg, pq, sdr (wide-gamut
    SDR) or srgb (the sRGB arm: IEC 61966-2-1's EOTF, the matrix, the inverse
    of Core Media's 709 gamma). `peak` is a PQ file's peak in cd/m² (spec §11
    HD-12: the shoulder's white max(peak, 203)/203; 1,000 when unknown)."""
    m = to709(primaries)
    if kind == "srgb":
        light = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                 for c in (max(v, 0.0) for v in rgb)]
        linear = mat_vec(m, light)
        return [max(c, 0.0) ** (1 / CM709_GAMMA) for c in linear], linear
    if kind == "sdr":
        linear = mat_vec(m, [max(c, 0.0) ** DISPLAY_GAMMA for c in rgb])
        return [max(c, 0.0) ** (1 / DISPLAY_GAMMA) for c in linear], linear
    if kind == "hlg":
        e = [hlg_inverse(c) for c in rgb]
        ys = sum(w * c for w, c in zip(LUMA2020, e))
        light = [HLG_GAIN * c * ys ** (HLG_GAMMA - 1) if ys > 1e-6 else 0.0 for c in e]
        white = HLG_WHITE
    else:
        light = [pq_eotf(c) * 10000 / PQ_REFERENCE for c in rgb]
        white = max(peak, PQ_REFERENCE) / PQ_REFERENCE
    linear = mat_vec(m, light)
    out = list(linear)
    low = min(out)
    if low < 0:
        y = sum(w * c for w, c in zip(LUMA709, out))
        out = [0.0] * 3 if y <= 0 else [y + (c - y) * y / (y - low) for c in out]
    top = max(out)
    if top > KNEE:
        out = [c * shoulder(top, white) / top for c in out]
    return [max(c, 0.0) ** (1 / DISPLAY_GAMMA) for c in out], linear


def code8(value):
    return round(255 * min(max(value, 0.0), 1.0))


def hue(rgb):
    p = rgb[0] - rgb[1]
    q = (rgb[0] + rgb[1]) / 2 - rgb[2]
    return math.degrees(math.atan2(q, p))


def hue_gap(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


# ---- the selector's table, mirrored (Approach 3) for R0 ------------------------

def arm(primaries, transfer):
    """The arm `InputConversion.choose` gives ffprobe's names; None = identity."""
    gamut = {"bt2020": "bt2020", "smpte432": "p3d65", "bt709": "bt709"}
    if transfer in ("arib-std-b67", "smpte2084"):
        kind = "hlg" if transfer == "arib-std-b67" else "pq"
        return f"{kind}({gamut.get(primaries, 'bt2020')})"
    if transfer == "iec61966-2-1":
        return f"srgb({gamut.get(primaries, 'bt709')})"
    if transfer in ("bt709", "bt2020-10", "bt2020-12") and primaries in ("bt2020", "smpte432"):
        return f"sdrWide({gamut[primaries]})"
    return None


# ---- fixtures -------------------------------------------------------------------

def ffmpeg_make(out, argv, seconds=600):
    if out.exists():
        return out
    MEDIA.mkdir(parents=True, exist_ok=True)
    made = bounded.run(["ffmpeg", "-v", "error", "-y", *argv, str(out)], seconds)
    if made["rc"] != 0 or not out.exists():
        print(f"       ffmpeg {out.name}: rc {made['rc']} {made['stderr'][-300:]}", flush=True)
        out.unlink(missing_ok=True)
        return None
    return out


def stream(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt,width,height,color_space,"
                       "color_transfer,color_primaries", "-of", "json", str(path)], 60)
    try:
        return json.loads(ran["stdout"])["streams"][0]
    except (ValueError, KeyError, IndexError):
        return {}


def tags(probe):
    return "/".join(str(probe.get(k, "-")) for k in ("color_space", "color_transfer",
                                                     "color_primaries"))


def checked(name, out, want):
    """`out` kept only when ffprobe reads every (key, value) of `want`; else
    None, REFUSED[name] saying why, and the file removed."""
    if out is None:
        REFUSED[name] = REFUSED.get(name) or f"{name} was not made"
        return None
    probe = stream(out)
    wrong = {k: probe.get(k) for k, v in want.items()
             if probe.get(k, "unknown" if v == "unknown" else None) != v}
    if wrong:
        REFUSED[name] = f"{out.name} refused: ffprobe read {wrong}, want {want}"
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        return None
    return out


def base():
    return checked("base", ffmpeg_make(MEDIA / "base.mov", [
        "-f", "lavfi", "-i", BASE_FILTER, "-c:v", "prores_ks", "-profile:v", "3",
        "-pix_fmt", "yuv422p10le"]), {"codec_name": "prores", "pix_fmt": "yuv422p10le",
                                      "width": W, "height": H})


def retag(name):
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    tagset = RETAGS[name]
    if tagset is None:
        bsf, colr = "prores_metadata=color_primaries=unknown:color_trc=unknown:colorspace=unknown", []
        want = {"codec_name": "prores"}
    else:
        primaries, transfer, matrix = tagset
        bsf = (f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:"
               f"colorspace={matrix}")
        colr = ["-color_primaries", primaries, "-color_trc", transfer, "-colorspace", matrix,
                "-movflags", "+write_colr"]
        want = {"color_primaries": primaries, "color_transfer": transfer, "color_space": matrix}
    out = MEDIA / f"{name}.mov"
    made = ffmpeg_make(out, ["-i", str(source), "-c", "copy", "-bsf:v", bsf, *colr], 120)
    kept = checked(name, made, want)
    if kept is not None and tagset is None:
        probe = stream(kept)
        known = {"bt709", "bt2020", "smpte432", "arib-std-b67", "smpte2084", "bt2020nc",
                 "iec61966-2-1", "bt2020-10"}
        if any(probe.get(k) in known for k in
               ("color_primaries", "color_transfer", "color_space")):
            REFUSED[name] = f"untagged.mov refused: ffprobe read {tags(probe)}"
            kept.unlink()
            return None
    return kept


def hevc10(name, tagset, out=None):
    """The ramp through `hevc_videotoolbox` Main 10 with `tagset`'s three tags
    (None for one ffprobe reads as absent), as precision's ramp10_hlg is made."""
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    primaries, transfer, matrix = tagset
    params, flags, want = [], [], {"codec_name": "hevc", "profile": "Main 10",
                                   "pix_fmt": "yuv420p10le"}
    for key, flag, value in (("color_primaries", "-color_primaries", primaries),
                             ("color_trc", "-color_trc", transfer),
                             ("colorspace", "-colorspace", matrix)):
        if value not in (None, "unknown"):
            params.append(f"{key}={value}")
            flags += [flag, value]
    want.update({k: v for k, v in (("color_primaries", primaries),
                                   ("color_transfer", transfer), ("color_space", matrix))
                 if v not in (None, "unknown")})
    vf = "format=yuv420p10le" + (",setparams=" + ":".join(params) if params else "")
    made = ffmpeg_make(out or MEDIA / f"{name}.mov", [
        "-i", str(source), "-vf", vf, "-c:v", "hevc_videotoolbox", "-profile:v", "main10",
        "-pix_fmt", "p010le", "-tag:v", "hvc1", "-b:v", "20M", *flags], 300)
    return checked(name, made, want)


def testsrc(name, extra, want, suffix=".mov", source="testsrc2"):
    return checked(name, ffmpeg_make(MEDIA / f"{name}{suffix}", [
        "-f", "lavfi", "-i", f"{source}=size={SW}x{SH}:rate=30:duration=1", *extra], 300), want)


def bt709(name, suffix, vf, codec, want, pix_fmt):
    """A 640×360 1 s `testsrc2` BT.709 fixture through `bt709_fixture.make`
    (issue #292): `vf`, ending in its SETPARAMS, on the input, the tags on
    the output; kept, a cached file too, only when ffprobe reads `want` and
    bt709 ×3 and the first frame reads back against its own graph; else None,
    REFUSED[name] the maker's reason."""
    made, why = bt709_fixture.make(MEDIA / f"{name}{suffix}", [
        "-f", "lavfi", "-i", f"testsrc2=size={SW}x{SH}:rate=30:duration=1", "-vf", vf],
        codec, want, pix_fmt, 300)
    if made is None:
        REFUSED[name] = why
    return made


def applelog():
    out = MEDIA / "applelog.mov"
    if not out.exists():
        source = retag("bt709")
        if source is None:
            REFUSED["applelog"] = REFUSED.get("bt709")
            return None
        writer = BASE / "applelog-writer" / "applelog_writer"
        try:
            swift_build.build(sources=[WRITER], output=writer, timeout=BUILD_BOUND)
        except swift_build.SwiftBuildFailed as failure:
            REFUSED["applelog"] = f"applelog_writer did not build: {str(failure)[:300]}"
            return None
        made = bounded.run([str(writer), str(source), str(out)], 120)
        print(f"       applelog_writer: {(made['stdout'] + made['stderr']).strip()[-200:]}",
              flush=True)
        if made["rc"] != 0 or not out.exists():
            REFUSED["applelog"] = f"applelog_writer exited {made['rc']}"
            out.unlink(missing_ok=True)
            return None
    return checked("applelog", out, {"color_space": "bt2020nc", "color_transfer": "unknown",
                                     "color_primaries": "bt2020"})


def fixture(name):
    """`name`'s file under MEDIA, made when missing; None when refused."""
    if name in RETAGS:
        return retag(name)
    if name in HEVC10:
        return hevc10(name, HEVC10[name])
    if name == "applelog":
        return applelog()
    if name == "h264_709":
        return bt709(name, ".mp4", bt709_fixture.SETPARAMS,
                     ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18"],
                     {"codec_name": "h264", "pix_fmt": "yuv420p", "width": SW, "height": SH},
                     "yuv420p")
    if name == "h264_untagged":
        return testsrc(name, ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18"],
                       {"codec_name": "h264"}, ".mp4")
    if name == "hevc8_matrix":
        made = testsrc(name, ["-vf", "format=yuv420p,setparams=colorspace=bt709",
                              "-c:v", "hevc_videotoolbox", "-profile:v", "main", "-tag:v",
                              "hvc1", "-b:v", "8M", "-colorspace", "bt709"],
                       {"codec_name": "hevc", "pix_fmt": "yuv420p", "color_space": "bt709"})
        probe = stream(made) if made else {}
        if made and (probe.get("color_primaries", "unknown") != "unknown"
                     or probe.get("color_transfer", "unknown") != "unknown"):
            REFUSED[name] = f"hevc8_matrix refused: ffprobe read {tags(probe)}"
            made.unlink()
            return None
        return made
    if name == "still8":
        return checked(name, ffmpeg_make(MEDIA / "still8.png", [
            "-f", "lavfi", "-i", f"testsrc2=size={SW}x{SH}:rate=1:duration=1", "-frames:v", "1",
            "-pix_fmt", "rgb24"]), {"pix_fmt": "rgb24"})
    if name == "prores4444":
        return bt709(name, ".mov", "format=yuva444p10le,geq=lum='lum(X,Y)':cb='cb(X,Y)':"
                     f"cr='cr(X,Y)':a='X*1023/(W-1)',{bt709_fixture.SETPARAMS}",
                     ["-c:v", "prores_ks", "-profile:v", "4", "-pix_fmt", "yuva444p10le"],
                     {"codec_name": "prores", "pix_fmt": "yuva444p12le"}, "yuv444p10le")
    if name == "webm":
        return checked(name, ffmpeg_make(MEDIA / "webm.webm", [
            "-f", "lavfi", "-i", f"testsrc2=size={SW}x{SH}:rate=30:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2",
            "-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p", "-b:v", "500k", "-c:a", "libopus"]),
            {"codec_name": "vp9"})
    if name == "hevc_alpha":
        return testsrc(name, ["-vf", "format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
                              "a='255*X/(W-1)',setparams=color_primaries=bt709:color_trc=bt709:"
                              "colorspace=bt709", "-c:v", "hevc_videotoolbox", "-alpha_quality",
                              "0.75", "-pix_fmt", "bgra", "-tag:v", "hvc1", "-b:v", "8M"],
                       {"codec_name": "hevc", "color_transfer": "bt709",
                        "color_primaries": "bt709"})
    if name in SEI_FIXTURES:
        return pq_x265(name)
    if name in DESC_FIXTURES:
        return pq_described(name)
    if name in ("hlg4k", "bt709_4k"):
        return four_k(name)
    if name == "green_709":
        return green_709()
    if name == "grey8":
        return grey_png()
    if name == "hlg_bars":
        return hlg_bars()
    if name in MEDIA_REC:
        return MEDIA_REC[name]
    raise ValueError(name)


def pq_raw():
    """The ramp as raw 4:2:0 10-bit planes, x265's input (made once, kept)."""
    source = base()
    if source is None:
        return None
    return ffmpeg_make(MEDIA / "ramp420p10.yuv", [
        "-i", str(source), "-vf", "format=yuv420p10le", "-f", "rawvideo",
        "-pix_fmt", "yuv420p10le"], 120)


def pq_x265(name):
    """H7's SEI fixtures (hdr H-1): the ramp through the x265 CLI, lossless, 4:2:0
    10-bit, PQ-tagged in its VUI, with SEI_FIXTURES' HDR10 static metadata as SEI 137
    and 144, then muxed by ffmpeg's stream copy (`hvc1`, 30 frames at k/30 s). Refused
    by name when x265 is not installed."""
    out = MEDIA / f"{name}.mov"
    if not out.exists():
        x265 = shutil.which("x265")
        if x265 is None:
            REFUSED[name] = f"{name} refused: the x265 CLI is not installed (`which x265`)"
            return None
        raw = pq_raw()
        if raw is None:
            REFUSED[name] = REFUSED.get("base") or "ramp420p10.yuv was not made"
            return None
        maximum, cll = SEI_FIXTURES[name]
        hevc = MEDIA / f"{name}.hevc"
        argv = [x265, "--input", str(raw), "--input-res", f"{W}x{H}", "--fps", "30",
                "--input-csp", "i420", "--input-depth", "10", "--output-depth", "10",
                "--lossless", "--colorprim", "bt2020", "--transfer", "smpte2084",
                "--colormatrix", "bt2020nc", "--log-level", "error"]
        if maximum is not None:
            argv += ["--master-display", f"{X265_DISPLAY}L({maximum},50)"]
        if cll is not None:
            argv += ["--max-cll", f"{cll[0]},{cll[1]}"]
        made = bounded.run(argv + ["-o", str(hevc)], 300)
        if made["rc"] != 0 or not hevc.exists():
            REFUSED[name] = f"x265 {name}: rc {made['rc']} {made['stderr'][-300:]}"
            hevc.unlink(missing_ok=True)
            return None
        # `-framerate` and `make_zero`: the stream's frames at k/30 from 0 with no edit
        # list (`-r 30` alone started them at -0.08 s under an edit list, which put
        # hdr10_writer's copies off the 1/30 grid).
        muxed = ffmpeg_make(out, ["-framerate", "30", "-i", str(hevc), "-c", "copy", "-tag:v",
                                  "hvc1", "-avoid_negative_ts", "make_zero"], 120)
        hevc.unlink(missing_ok=True)
        if muxed is None:
            REFUSED[name] = f"ffmpeg did not mux {name}.mov"
            return None
    return checked(name, out, {"codec_name": "hevc", "pix_fmt": "yuv420p10le",
                               "color_primaries": "bt2020", "color_transfer": "smpte2084",
                               "color_space": "bt2020nc"})


def pq_described(name):
    """H7's sample-description fixtures (hdr H-1): an SEI fixture's samples copied by
    hdr10_writer.swift under a description carrying DESC_FIXTURES' two extensions.
    The writer's own line is kept in WRITTEN; it exits 0 only when both read back."""
    out = MEDIA / f"{name}.mov"
    over, maximum, cll, fall = DESC_FIXTURES[name]
    if not out.exists():
        source = pq_x265(over)
        if source is None:
            REFUSED[name] = REFUSED.get(over)
            return None
        writer = BASE / "hdr10-writer" / "hdr10_writer"
        try:
            swift_build.build(sources=[HDR10_WRITER], output=writer, timeout=BUILD_BOUND)
        except swift_build.SwiftBuildFailed as failure:
            REFUSED[name] = f"hdr10_writer did not build: {str(failure)[:300]}"
            return None
        made = bounded.run([str(writer), str(source), str(out), str(maximum), str(cll),
                            str(fall)], 120)
        WRITTEN[name] = (made["rc"], (made["stdout"] + made["stderr"]).strip()[-300:])
        print(f"       hdr10_writer {name}: {WRITTEN[name][1]}", flush=True)
        if made["rc"] != 0 or not out.exists():
            REFUSED[name] = f"hdr10_writer exited {made['rc']} for {name}"
            out.unlink(missing_ok=True)
            return None
    return checked(name, out, {"codec_name": "hevc", "pix_fmt": "yuv420p10le",
                               "color_transfer": "smpte2084"})


def four_k(name):
    """TI's 4K 4 s ProRes twins: the ramp scaled up, looped, re-tagged."""
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    plain = ffmpeg_make(MEDIA / "ramp4k.mov", [
        "-stream_loop", "3", "-i", str(source), "-vf", "scale=3840:2160:flags=bilinear",
        "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"], 600)
    if plain is None:
        REFUSED[name] = "ffmpeg did not make ramp4k.mov"
        return None
    primaries, transfer, matrix = RETAGS["hlg" if name == "hlg4k" else "bt709"]
    made = ffmpeg_make(MEDIA / f"{name}.mov", [
        "-i", str(plain), "-c", "copy", "-bsf:v",
        f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:colorspace={matrix}",
        "-color_primaries", primaries, "-color_trc", transfer, "-colorspace", matrix,
        "-movflags", "+write_colr"], 120)
    return checked(name, made, {"width": 3840, "height": 2160, "color_transfer": transfer})


def h1_file(name):
    """H1's fixture's file name in `DIR/media/`."""
    return name + H1_SUFFIX.get(name, ".mp4" if name.startswith("h264") else ".mov")


def h1_media(name, control):
    """H1's fixture: DIR's copy when DIR holds one (compare, mutants), else
    MEDIA's (capture copies it into DIR)."""
    if control is not None:
        copy = control / "media" / h1_file(name)
        if copy.exists():
            return copy
        REFUSED[name] = f"{copy} is missing from the control"
        return None
    return fixture(name)


# ---- decoding -------------------------------------------------------------------

def decode(path, pix_fmt, frames=1, extra=()):
    argv = ["ffmpeg", "-v", "error", "-i", str(path), *extra]
    if frames is not None:
        argv += ["-frames:v", str(frames)]
    try:
        raw = subprocess.run(argv + ["-f", "rawvideo", "-pix_fmt", pix_fmt, "-"],
                             capture_output=True, timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw or None


class Yuv:
    """One frame's 10-bit planes: Y at (x, y), chroma at its subsampled site."""

    def __init__(self, raw, width, height, sub_x, sub_y):
        n = width * height
        cw, ch = -(-width // sub_x), -(-height // sub_y)
        values = struct.unpack(f"<{n + 2 * cw * ch}H", raw[:2 * (n + 2 * cw * ch)])
        self.y, self.cb, self.cr = values[:n], values[n:n + cw * ch], values[n + cw * ch:]
        self.width, self.cw, self.sx, self.sy = width, cw, sub_x, sub_y

    def codes(self, x, y):
        c = (y // self.sy) * self.cw + x // self.sx
        return self.y[y * self.width + x], self.cb[c], self.cr[c]

    def rgb(self, x, y, matrix):
        """Limited-range R'G'B' (unclamped) through `matrix`'s Kr, Kb."""
        return rgb_of(*self.codes(x, y), matrix)


def rgb_of(luma, cb, cr, matrix):
    """10-bit limited-range codes → R'G'B' (unclamped) through `matrix`'s Kr, Kb."""
    kr, kb = KR_KB[matrix]
    yy, pb, pr = (luma - 64) / 876, (cb - 512) / 896, (cr - 512) / 896
    r = yy + 2 * (1 - kr) * pr
    b = yy + 2 * (1 - kb) * pb
    g = (yy - kr * r - kb * b) / (1 - kr - kb)
    return [r, g, b]


def envelope(kind, primaries, codes, matrix):
    """H4/H5's bound: per channel, the 8-bit range of the oracle evaluated at
    the fixture's Y', Cb and Cr codes each moved by −1, 0, +1 (27 evaluations),
    widened by 1 level. (low, high) triples."""
    luma, cb, cr = codes
    outs = [[code8(c) for c in convert(kind, primaries,
                                       rgb_of(luma + a, cb + b, cr + c, matrix))[0]]
            for a in (-1, 0, 1) for b in (-1, 0, 1) for c in (-1, 0, 1)]
    return ([min(o[i] for o in outs) - 1 for i in range(3)],
            [max(o[i] for o in outs) + 1 for i in range(3)])


def inside(got, bounds):
    low, high = bounds
    return all(lo <= g <= hi for g, lo, hi in zip(got, low, high))


def yuv_frames(path, width, height, count=1):
    """The first `count` frames of a 4:2:2 or 4:2:0 10-bit file as Yuv, or None."""
    probe = stream(path)
    fmt = "yuv420p10le" if "420" in probe.get("pix_fmt", "") else "yuv422p10le"
    sub_y = 2 if fmt == "yuv420p10le" else 1
    raw = decode(path, fmt, count)
    size = 2 * (width * height + 2 * -(-width // 2) * -(-height // sub_y))
    if not raw or len(raw) < size * count:
        return None
    return [Yuv(raw[i * size:(i + 1) * size], width, height, 2, sub_y) for i in range(count)]


class Frame:
    """A render_frame PNG decoded at 16 bits (`rgb48le`)."""

    def __init__(self, path, width, height):
        raw = decode(path, "rgb48le")
        self.ok = bool(raw) and len(raw) >= width * height * 6
        self.values = struct.unpack(f"<{width * height * 3}H", raw[:width * height * 6]) \
            if self.ok else ()
        self.width, self.path = width, path

    def px(self, x, y):
        at = (y * self.width + x) * 3
        return [v / 65535 for v in self.values[at:at + 3]]

    def px8(self, x, y):
        return [round(v * 65535 / 257) for v in self.px(x, y)]


def close_to(a, b, tolerance):
    return all(abs(x - y) <= tolerance for x, y in zip(a, b))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:16]


# ---- the documents --------------------------------------------------------------

class Doc:
    def __init__(self, client, name, width, height):
        self.client, self.width, self.height = client, width, height
        self.path = WORK / f"{name}.framejob"
        self.made = attempt(client, "new_project", {"path": str(self.path)})["ok"]
        self.call("set_canvas", width=width, height=height, fps=[30, 1])
        c = self.project().get("canvas") or {}
        self.ok = self.made and c.get("width") == width and c.get("height") == height
        self.why = None if self.ok else "the project or its canvas was not made"

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def track(self):
        return (self.project().get("tracks") or [{}])[0].get("id")

    def place(self, path, at=0):
        """`path` imported (once) and placed on the first track at `at`; the clip id."""
        media = getattr(self, "_media", {})
        if path not in media:
            got = self.call("import_media", path=str(path))
            media[path] = reply(got).get("media")
            if media[path] is None:
                self.ok, self.why = False, f"import {Path(path).name}: {got.get('error')}"
            self._media = media
            # T3-2 (GR-16): an Apple-Log-labelled file is converted from import;
            # Camera Log ▸ None keeps every scene as T3-1 rendered it. Never
            # fires on the control, whose media carry no `color`.
            row = next((m for m in self.project().get("media") or []
                        if m.get("id") == media[path]), {})
            if row.get("color") is not None:
                self.call("set_media_color", media=media[path], color=None)
        if media[path] is None:
            return None
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=self.track(), media=media[path], at=at)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not got["ok"] or len(new) != 1:
            self.ok, self.why = False, f"add_clip {Path(path).name}: {got.get('error')}"
            return None
        return new[0]

    def place_tool(self, tool, **arguments):
        """One clip made by `tool` (`add_text_clip`, `add_shape_clip`, `add_clip`); its
        id, or None and the Doc failed."""
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not got["ok"] or len(new) != 1:
            self.ok, self.why = False, f"{tool}: {got.get('error')}"
            return None
        return new[0]

    def render(self, tag, t=T):
        out = WORK / f"{tag}.png"
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=t, path=str(out))
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

    def close(self):
        return attempt(self.client, "close_project",
                       {"project": str(self.path), "discard": True})["ok"]


def wait_reverse(doc, tag):
    """precision_proof.py's wait: `cache/reversed/*.mov` with no `.partial`
    and no sheet. (files, None) or (files, why)."""
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


# ---- the pick probe -------------------------------------------------------------

def build_probe(source, sources, name):
    """`source` as `main.swift` over `sources` (an `app/Sources`), beside that
    tree's `Compositor.metal` as `default.metallib` and `Blank.mp4`. (binary,
    None) or (None, why)."""
    folder = WORK / name
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(source.read_text())
    resources = Path(sources).parent / "Resources"
    shader = resources / "Shaders/Compositor.metal"
    air, library = folder / "Compositor.air", folder / "default.metallib"
    shutil.copy2(resources / "Blank.mp4", folder / "Blank.mp4")
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                       300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                            str(library)], 300)
    if step["rc"] != 0 or not library.exists():
        return None, f"the shader did not build: {step['stderr'][-400:]}"
    try:
        defines = reference_build.tree_defines(Path(sources).parents[1], ["FRAMEJOB_DEV_TOOLS"])
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / name, defines=defines, timeout=BUILD_BOUND)
    except swift_build.SwiftBuildFailed as error:
        return None, f"{error} {error.diagnostics[:6]}"
    return built.binary, None


def base_sources():
    """716720c's `app/Sources` (and `app/Resources`, and `app/Bridging`, whose
    name says which dev-tools flag the tree spells), by `git archive` into
    BASE_TREE, made once and kept; None and why when the archive fails."""
    sources = BASE_TREE / "app/Sources"
    if (sources / "Compositor.swift").exists() and (BASE_TREE / "app/Bridging").is_dir():
        return sources, None
    tree_copy.remove_tree(str(BASE_TREE)) if BASE_TREE.exists() else None
    BASE_TREE.mkdir(parents=True)
    archive = BASE / f"base-{BASE_COMMIT}.tar"
    made = bounded.run(["git", "-C", str(ROOT), "archive", "-o", str(archive), BASE_COMMIT,
                        "app/Sources", "app/Resources", "app/Bridging"], 120)
    if made["rc"] == 0:
        made = bounded.run(["tar", "-xf", str(archive), "-C", str(BASE_TREE)], 120)
    archive.unlink(missing_ok=True)
    if made["rc"] != 0 or not (sources / "Compositor.swift").exists():
        return None, f"git archive {BASE_COMMIT} failed: {made['stderr'][-300:]}"
    return sources, None


def base_copy(package):
    """A copy of `package` whose `project.json` says version 18 — the base tree
    (716720c) refuses a newer file, and every number up to 18 it reads — or
    None and why when the package's media carry `color` (T3-2, GR-16), which
    the base tree would drop, so its frame would not be the tree's."""
    source = Path(package)
    try:
        text = (source / "project.json").read_text()
        project = json.loads(text)
    except (OSError, ValueError) as error:
        return None, f"{source.name}: {error}"
    if any(m.get("color") is not None for m in project.get("media") or []):
        return None, f"{source.name}: a media carries color"
    copy = source.with_name(source.stem + "-v18.framejob")
    if copy.exists():
        shutil.rmtree(copy)
    shutil.copytree(source, copy)
    (copy / "project.json").write_text(re.sub(r'"version":\s*\d+', '"version": 18', text,
                                              count=1))
    return copy, None


def run_picks(sources, picks, name="hdr_pick_probe"):
    """`hdr_pick_probe.swift` built over `sources` (None: the base tree) over
    `picks`; {tag: answer row}, or {"error": why}."""
    if sources is None:
        sources, why = base_sources()
        name = "hdr_pick_probe_base"
        if sources is None:
            return {"error": why}
    binary, why = build_probe(PICK_PROBE, sources, name)
    if binary is None:
        return {"error": f"the pick probe ({name}) did not build: {why}"}
    request, answer = WORK / f"{name}.json", WORK / f"{name}-answer.json"
    answer.unlink(missing_ok=True)
    request.write_text(json.dumps({"picks": picks}))
    ran = bounded.run([str(binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        return {row["tag"]: row for row in json.loads(answer.read_text())["rows"]}
    except (OSError, ValueError, KeyError):
        return {"error": f"the pick probe answered nothing (rc {ran['rc']}): "
                         f"{(ran['stdout'] + ran['stderr'])[-400:]}"}


# ---- H1 -------------------------------------------------------------------------

def h1_scene(client, name, path, width, height, reverse=False):
    """`path` alone (reversed when asked), rendered at 0 and T and saved for the
    pick probe: {renders: {tick: png}, package, clip, reverse file} or a why."""
    doc = Doc(client, f"h1-{name}", width, height)
    clip = doc.place(path) if doc.ok else None
    files = []
    if reverse and clip is not None:
        doc.call("set_reversed", clip=clip, reversed=True)
        files, late = wait_reverse(doc, f"h1-{name}")
        if late:
            doc.ok, doc.why = False, late
    renders = {t: doc.render(f"h1-{name}-{t}", t) for t in (0, T)} if doc.ok else {}
    package = doc.save(f"h1-{name}-saved") if doc.ok else None
    closed = doc.close()
    good = doc.ok and clip is not None and all(renders.values()) and package is not None
    return {"renders": renders, "package": package, "clip": clip,
            "reverse": files[0] if files else None, "why": doc.why, "ok": good,
            "closed": closed, "size": (width, height)}


def run_h1(client, mode, control, sources, state, extra=()):
    """H1's scenes; capture writes DIR's references, compare holds the tree to them."""
    scenes = {}
    fixtures = list(H1_FIXTURES) + list(extra)
    for name, width, height in fixtures:
        path = h1_media(name, None if mode == "capture" else control)
        if path is None:
            scenes[name] = {"ok": False, "why": REFUSED.get(name), "closed": True}
            continue
        if mode == "capture":
            (control / "media").mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, control / "media" / h1_file(name))
        scenes[name] = h1_scene(client, name, path, width, height)
    ramp = h1_media("bt709", None if mode == "capture" else control)
    scenes["reversed"] = h1_scene(client, "reversed", ramp, W, H, reverse=True) if ramp \
        else {"ok": False, "why": REFUSED.get("bt709"), "closed": True}
    picks = [{"tag": name, "package": str(s["package"]), "tick": T, "clips": [s["clip"]],
              "points": PICK_POINTS[s["size"]]} for name, s in scenes.items() if s["ok"]]
    answered = run_picks(sources, picks) if picks else {"error": "no scene"}
    state["h1_closed"] = all(s.get("closed") for s in scenes.values())
    record = {"picks": {}, "reverse": None}
    if mode == "capture":
        for name, s in scenes.items():
            for t, png in (s.get("renders") or {}).items():
                if png:
                    shutil.copy2(png, control / f"h1-{name}-{t}.png")
            row = answered.get(name) or {}
            record["picks"][name] = row.get("picked")
        rev = scenes["reversed"].get("reverse")
        if rev:
            shutil.copy2(rev, control / "media" / "reversed-intermediate.mov")
            record["reverse"] = digest(rev)
        state["h1_record"] = record
        failed = [n for n, s in scenes.items() if not s["ok"]]
        print(f"  H1 references captured for {len(scenes) - len(failed)} scenes"
              f"{'; NOT for ' + str({n: scenes[n].get('why') for n in failed}) if failed else ''}"
              f"; picks {answered.get('error') or 'answered'}", flush=True)
        state["capture_ok"] = not failed and "error" not in answered
        return
    try:
        recorded = json.loads((control / "capture.json").read_text())
    except (OSError, ValueError):
        recorded = {}
    misses = []
    for name, s in scenes.items():
        if not s["ok"]:
            misses.append(f"{name}: {s.get('why')}")
            continue
        for t, png in s["renders"].items():
            want = control / f"h1-{name}-{t}.png"
            if not want.exists():
                misses.append(f"{name}@{t}: no control PNG")
            elif png.read_bytes() != want.read_bytes():
                a, b = Frame(png, *s["size"]), Frame(want, *s["size"])
                differ = sum(1 for x, y in zip(a.values, b.values) if x != y)
                misses.append(f"{name}@{t}: PNG bytes differ ({differ} of {len(a.values)} "
                              f"16-bit samples differ)")
        got = (answered.get(name) or {}).get("picked")
        want = (recorded.get("picks") or {}).get(name)
        if got is None or got != want:
            misses.append(f"{name}: pick {got} vs control {want} "
                          f"{answered.get('error', '')}")
    rev = scenes["reversed"].get("reverse")
    same_intermediate = rev is not None and digest(rev) == recorded.get("reverse")
    check(f"H1 (STOP) {len(scenes)} SDR scenes: render_frame at 0 and 0.5 s byte-identical to "
          f"{control.name}'s, and the eyedropper's picks equal",
          not misses, f"{misses or 'all equal'}; the reverse's intermediate "
          f"{'equals' if same_intermediate else 'differs from'} the control's "
          f"({digest(rev) if rev else None} vs {recorded.get('reverse')})")


# ---- H2 -------------------------------------------------------------------------

def export_rgb8(frames, index, x, y):
    return [code8(c) for c in frames[index].rgb(x, y, "bt709")]


def run_h2(client, state):
    hlg, pq, hevc, bt709 = (fixture(n) for n in ("hlg", "pq", "hlg_hevc", "bt709"))
    scenes = [("hlg", [hlg], 0), ("pq", [pq], 0), ("hlg_hevc", [hevc], 0),
              ("sequence", [bt709, hlg, bt709], 30)]
    misses, closed, figures = [], True, []
    for name, paths, first in scenes:
        if any(p is None for p in paths):
            misses.append(f"{name}: fixture refused ({REFUSED})")
            continue
        doc = Doc(client, f"h2-{name}", W, H)
        for i, path in enumerate(paths):
            doc.place(path, at=i * SEC)
        renders = [doc.render(f"h2-{name}-{k}", (first + k) * FRAME) for k in (0, 5)] \
            if doc.ok else [None, None]
        out = doc.export(f"h2-{name}") if doc.ok else None
        closed = doc.close() and closed
        frames = yuv_frames(out, W, H, first + 6) if out else None
        if not doc.ok or frames is None or not all(renders):
            misses.append(f"{name}: {doc.why or 'no export or render'}")
            continue
        drawn = [Frame(r, W, H) for r in renders]
        worst_flash, worst_parity = 0, 0
        for x in range(0, W, 8):
            a = export_rgb8(frames, first, x, GREY_ROW)
            b = export_rgb8(frames, first + 5, x, GREY_ROW)
            worst_flash = max(worst_flash, max(abs(p - q) for p, q in zip(a, b)))
            for k, e in ((0, a), (1, b)):
                r = drawn[k].px8(x, GREY_ROW)
                worst_parity = max(worst_parity, max(abs(p - q) for p, q in zip(r, e)))
        mid = W // 2
        figures.append(f"{name}: export frame {first} vs +5 max |Δ| {worst_flash}, render vs "
                       f"export max |Δ| {worst_parity}; at x={mid} export "
                       f"{export_rgb8(frames, first, mid, GREY_ROW)} / "
                       f"{export_rgb8(frames, first + 5, mid, GREY_ROW)}, render "
                       f"{drawn[0].px8(mid, GREY_ROW)} / {drawn[1].px8(mid, GREY_ROW)}")
        if worst_flash > 1 or worst_parity > 1:
            misses.append(name)
    state["h2_closed"] = closed
    check("H2 the HDR clip's first exported frame equals its frame +5 on the grey row ±1, and "
          "render_frame at both ticks equals the export ±1 (HLG, PQ, HLG HEVC, BT.709|HLG|BT.709)",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


# ---- H3, H4, H5: the conversion's values ----------------------------------------

def fixture_scene(client, name, t=T):
    """`name` alone at 1024×128 rendered at `t`: (Frame, the fixture's Yuv) or
    (None, why); the doc is closed."""
    path = fixture(name)
    if path is None:
        return None, f"{name} refused: {REFUSED.get(name)}"
    doc = Doc(client, f"v-{name}", W, H)
    doc.place(path) if doc.ok else None
    png = doc.render(f"v-{name}", t) if doc.ok else None
    closed = doc.close()
    source = yuv_frames(path, W, H)
    if png is None or source is None or not closed:
        return None, f"{name}: {doc.why or 'no render, no decode or not closed'}"
    frame = Frame(png, W, H)
    return (frame, source[0]) if frame.ok else (None, f"{name}: the PNG did not decode")


def render_at(frame, source, signal, matrix):
    """The render's encoded grey value at grey `signal`, interpolated between
    the two grey-row columns whose measured signals bracket it."""
    points = [(source.rgb(x, GREY_ROW, matrix)[1], frame.px(x, GREY_ROW)[1]) for x in range(W)]
    for (s0, v0), (s1, v1) in zip(points, points[1:]):
        if s0 <= signal <= s1 and s1 > s0:
            return v0 + (v1 - v0) * (signal - s0) / (s1 - s0)
    return points[-1][1] if signal >= points[-1][0] else points[0][1]


def run_h3(client, scenes):
    misses, figures = [], []
    for kind in ("hlg", "pq"):
        frame, source = scenes.get(kind) or (None, None)
        if frame is None:
            misses.append(f"{kind}: {source}")
            continue
        worst = 0
        for x in range(0, W, 8):
            rgb = source.rgb(x, GREY_ROW, "bt2020nc")
            want = [code8(c) for c in convert(kind, "bt2020", rgb)[0]]
            got = frame.px8(x, GREY_ROW)
            worst = max(worst, max(abs(a - b) for a, b in zip(got, want)))
            if not close_to(got, want, 1) and len(misses) < 12:
                misses.append(f"{kind} x={x} render {got} oracle {want}")
        apple = []
        for signal, target in APPLE[kind]:
            value = render_at(frame, source, signal, "bt2020nc")
            off = (value - target) * 255
            apple.append(f"{signal}→{value:.4f} ({off:+.2f})")
            if abs(off) > APPLE_BOUND:
                misses.append(f"{kind} Apple {signal}: {off:+.2f} levels")
        figures.append(f"{kind}: worst |Δ| against the oracle {worst} levels; Apple's points "
                       f"{', '.join(apple)}")
    check("H3 the HLG and PQ grey rows (every 8th column) = the oracle ±1 at 8 bits, and Apple's "
          "six points within 3/255", not misses,
          f"{misses[:12] or 'all within'}\n       " + "\n       ".join(figures))


def run_h4(scenes):
    frame, source = scenes.get("hlg") or (None, None)
    if frame is None:
        check("H4 the HLG chroma row is compressed, not clipped", False, f"{source}")
        return
    columns, nearest = [], None
    for x in range(0, W, 2):
        rgb = source.rgb(x, CHROMA_ROW, "bt2020nc")
        distance = sum((a - b) ** 2 for a, b in zip(rgb, PATCH))
        if nearest is None or distance < nearest[0]:
            nearest = (distance, x, rgb)
        out, linear = convert("hlg", "bt2020", rgb)
        if max(rgb) - min(rgb) >= 0.05 and (min(linear) < 0 or max(linear) > 1):
            columns.append(x)
    picked = sorted(set(columns) | {nearest[1]})
    misses, worst_hue, worst_value = [], 0.0, 0
    for x in picked:
        rgb = source.rgb(x, CHROMA_ROW, "bt2020nc")
        out, linear = convert("hlg", "bt2020", rgb)
        want = [code8(c) for c in out]
        bounds = envelope("hlg", "bt2020", source.codes(x, CHROMA_ROW), "bt2020nc")
        got = frame.px8(x, CHROMA_ROW)
        rendered = [c ** DISPLAY_GAMMA for c in frame.px(x, CHROMA_ROW)]
        gap = hue_gap(hue(rendered), hue(linear))
        worst_hue = max(worst_hue, gap)
        worst_value = max(worst_value, max(abs(a - b) for a, b in zip(got, want)))
        if (gap > 2 or not inside(got, bounds)) and len(misses) < 10:
            misses.append(f"x={x} render {got} oracle {want} envelope {bounds} hue gap "
                          f"{gap:.2f}°")
    _, px, prgb = nearest
    patch = f"the patch column x={px} (source {[round(c, 3) for c in prgb]}): render " \
            f"{frame.px8(px, CHROMA_ROW)}, oracle " \
            f"{[code8(c) for c in convert('hlg', 'bt2020', prgb)[0]]}"
    check(f"H4 the HLG chroma row: {len(columns)} columns (≥ 20, CONTROL) out of [0,1]³ after the "
          f"matrix, and the brief's patch: hue within 2°, values inside the oracle's ±1-code "
          f"envelope ±1 level",
          len(columns) >= 20 and not misses,
          f"{misses or 'all within'}; worst hue gap {worst_hue:.2f}°, worst |Δ| {worst_value}; "
          f"{patch}")


def run_h5(client, scenes, extra=None):
    names = [("b2020_709", "bt2020", "bt2020nc"), ("p3_709", "p3d65", "bt709"),
             ("b2020_2020", "bt2020", "bt2020nc")] + ([extra] if extra else [])
    misses, figures = [], []
    for name, primaries, matrix in names:
        frame, source = scenes.get(name) or (None, None)
        if frame is None:
            misses.append(f"{name}: {source}")
            continue
        grey_worst = chroma_worst = 0
        where, outside = None, []
        for x in range(0, W, 8):
            want = [code8(c) for c in source.rgb(x, GREY_ROW, matrix)]
            got = frame.px8(x, GREY_ROW)
            grey_worst = max(grey_worst, max(abs(a - b) for a, b in zip(got, want)))
            rgb = source.rgb(x, CHROMA_ROW, matrix)
            want = [code8(c) for c in convert("sdr", primaries, rgb)[0]]
            bounds = envelope("sdr", primaries, source.codes(x, CHROMA_ROW), matrix)
            got = frame.px8(x, CHROMA_ROW)
            gap = max(abs(a - b) for a, b in zip(got, want))
            if gap > chroma_worst:
                chroma_worst, where = gap, (x, got, want)
            if not inside(got, bounds):
                outside.append((x, got, bounds))
        mid = W // 2
        figures.append(f"{name}: grey worst |Δ| {grey_worst}, chroma worst |Δ| {chroma_worst} "
                       f"(x, render, oracle {where}); outside the envelope {outside[:3]}; "
                       f"grey at x={mid} {frame.px8(mid, GREY_ROW)} (signal "
                       f"{[code8(c) for c in source.rgb(mid, GREY_ROW, matrix)]})")
        if grey_worst > 1 or outside:
            misses.append(name)
    check("H5 the wide-gamut SDR files (BT.2020/BT.709, P3/BT.709, BT.2020/BT.2020-10): the grey "
          "row = the signal ±1, the chroma row inside the oracle's ±1-code envelope ±1 level",
          not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


# ---- H6 -------------------------------------------------------------------------

def run_h6(client, sources, state):
    """H6 (revision 2): the HLG ramp's pick against the pick of its own
    `prores_422` export placed alone (a BT.709 file, today's path), both
    through the tree probe, ±3; the keyed export magenta ±8; the base-tree
    probe must fail the pick half (the CONTROL)."""
    hlg = fixture("hlg")
    if hlg is None:
        check("H6 the eyedropper picks the colour the export keys on", False,
              f"hlg refused: {REFUSED.get('hlg')}")
        return
    doc = Doc(client, "h6", W, H)
    doc.call("set_canvas", background=[1, 0, 1, 1])
    clip = doc.place(hlg) if doc.ok else None
    package = doc.save("h6-saved") if doc.ok else None
    first = doc.export("h6-plain") if doc.ok else None
    ref = Doc(client, "h6-ref", W, H)
    ref_clip = ref.place(first) if ref.ok and first else None
    ref_package = ref.save("h6-ref-saved") if ref_clip is not None else None
    state["h6_ref_closed"] = ref.close()
    point = [[256.5, 96.5]]
    asks = [{"tag": "hlg", "package": str(package), "tick": T, "clips": [clip], "points": point},
            {"tag": "ref", "package": str(ref_package), "tick": T, "clips": [ref_clip],
             "points": point}] if package and ref_package else []
    tree = run_picks(sources, asks) if asks else {"error": "not saved"}
    copies = [base_copy(ask["package"]) for ask in asks]
    refused = [why for copy, why in copies if copy is None]
    older = [dict(ask, package=str(copy)) for ask, (copy, _) in zip(asks, copies)]
    base = ({"error": f"the base tree's copy: {'; '.join(refused)}"} if refused
            else run_picks(None, older)) if asks else {"error": "not saved"}

    def pick(answer, tag):
        got = ((answer.get(tag) or {}).get("picked") or [None])[0]
        return [code8(c) for c in got] if got else None
    key = ((tree.get("hlg") or {}).get("keys") or [None])[0]
    keyed = doc.call("set_video", clips=[clip], patch={"chroma": {
        "key": key, "tolerance": 0.05, "softness": 0.1, "spill": 0.5}}) if key else {"ok": False}
    second = doc.export("h6-keyed") if keyed["ok"] else None
    state["h6_closed"] = doc.close()
    keyed_frames = yuv_frames(second, W, H, 16) if second else None
    shown = export_rgb8(keyed_frames, 15, 256, CHROMA_ROW) if keyed_frames else None
    mine, theirs = pick(tree, "hlg"), pick(tree, "ref")
    base_mine, base_theirs = pick(base, "hlg"), pick(base, "ref")
    agrees = mine is not None and theirs is not None and close_to(mine, theirs, 3)
    control_fails = base_mine is not None and base_theirs is not None \
        and not close_to(base_mine, base_theirs, 3)
    good = agrees and shown is not None and close_to(shown, [255, 0, 255], 8) and control_fails
    check("H6 the eyedropper's pick at (256, 96) at 0.5 s on the HLG ramp equals the pick of its "
          "own prores_422 export placed alone ±3, keyed with it (tolerance 0.05) the export shows "
          "magenta there ±8, and the base tree fails the pick half (CONTROL)", good,
          f"tree picks HLG {mine} / its export {theirs} (key {key}); keyed export {shown}; "
          f"base-tree picks {base_mine} / {base_theirs} (fails: {control_fails}); "
          f"{tree.get('error', '')} {base.get('error', '')} {doc.why or ''} "
          f"keyed {keyed.get('error', 'ok')}")


# ---- H1m, H1s, H1w: mixed compositions and the sRGB arm --------------------------

def saved_scene(client, name, paths, width=W, height=H):
    """`paths` one after another (1 s each) on one track, saved; (package,
    clip ids, Doc) — the Doc still open."""
    doc = Doc(client, name, width, height)
    clips = [doc.place(path, at=i * SEC) for i, path in enumerate(paths)] if doc.ok else []
    package = doc.save(f"{name}-saved") if doc.ok and all(c is not None for c in clips) \
        else None
    return package, clips, doc


def run_h1m(client, control, sources, state):
    """H1m (STOP): two mixed projects, at ticks showing no converted source:
    the base-tree probe's and the tree probe's PNG bytes and picks equal. The
    base tree reads a version-18 copy of each package (`base_copy`, T3-2); a
    package whose media carry `color` is a FAIL."""
    names = {n: h1_media(n, control) for n in ("srgb", "bt709", "untagged", "applelog")}
    names["hlg"] = fixture("hlg")
    scenes = [("mix_sdr", ["srgb", "bt709", "untagged"], [T, SEC + T, 2 * SEC + T]),
              ("mix_hdr", ["untagged", "hlg", "bt709", "applelog"], [T, 2 * SEC + T, 3 * SEC + T])]
    misses, asks = [], {"tree": [], "base": []}
    for scene, members, ticks in scenes:
        if any(names[m] is None for m in members):
            misses.append(f"{scene}: a fixture is missing ({REFUSED})")
            continue
        package, clips, doc = saved_scene(client, f"h1m-{scene}", [names[m] for m in members])
        state[f"h1m_{scene}_closed"] = doc.close()
        if package is None:
            misses.append(f"{scene}: {doc.why or 'not saved'}")
            continue
        older, why = base_copy(package)
        if older is None:
            misses.append(f"{scene}: the base tree's copy: {why}")
            continue
        for tick in ticks:
            for which in asks:
                asks[which].append({"tag": f"{scene}@{tick}",
                                    "package": str(package if which == "tree" else older),
                                    "tick": tick, "clips": clips, "points": PICK_POINTS[(W, H)],
                                    "png": str(WORK / f"h1m-{which}-{scene}-{tick}.png")})
    tree = run_picks(sources, asks["tree"]) if asks["tree"] else {"error": "no scene"}
    base = run_picks(None, asks["base"]) if asks["base"] else {"error": "no scene"}
    for ask in asks["tree"]:
        tag = ask["tag"]
        a, b = tree.get(tag) or {}, base.get(tag) or {}
        pa, pb = Path(a.get("png") or "/nonexistent"), Path(b.get("png") or "/nonexistent")
        if not (pa.exists() and pb.exists()):
            misses.append(f"{tag}: no PNG ({a.get('error') or tree.get('error')} / "
                          f"{b.get('error') or base.get('error')})")
            continue
        if pa.read_bytes() != pb.read_bytes():
            fa, fb = Frame(pa, W, H), Frame(pb, W, H)
            differ = sum(1 for x, y in zip(fa.values, fb.values) if x != y)
            misses.append(f"{tag}: PNG bytes differ ({differ} 16-bit samples differ)")
        if a.get("picked") != b.get("picked"):
            misses.append(f"{tag}: picks {a.get('picked')} vs base {b.get('picked')}")
    check("H1m (STOP) srgb|bt709|untagged and untagged|hlg|bt709|applelog, at ticks showing no "
          "converted source: the tree's PNG bytes and picks equal the base tree's (716720c)",
          not misses and bool(asks["tree"]), f"{misses or 'all equal'}")


def run_h1a(client, sources, state):
    """H1a (T3-3): alpha and WebM sources in a converting composition —
    prores4444 | hlg | hevc_alpha | webm on one 640×360 track; at the ticks
    showing no HLG the tree probe's PNG bytes and picks equal the base tree's
    (a version-18 copy, as H1m); at the HLG tick the tree's PNG must differ
    from the base's (the CONTROL: the tree's composition converts)."""
    members = ["prores4444", "hlg", "hevc_alpha", "webm"]
    paths = [fixture(n) for n in members]
    name = "H1a prores4444|hlg|hevc_alpha|webm (640×360): at the non-HLG ticks the tree's PNG " \
           "bytes and picks equal the base tree's (716720c); at the HLG tick the PNGs differ " \
           "(CONTROL)"
    if any(path is None for path in paths):
        check(name, False, f"a fixture is missing: {[n for n, p in zip(members, paths) if p is None]} "
                           f"({REFUSED})")
        return
    package, clips, doc = saved_scene(client, "h1a-mix", paths, SW, SH)
    state["h1a_closed"] = doc.close()
    if package is None:
        check(name, False, f"not saved: {doc.why}")
        return
    older, why = base_copy(package)
    if older is None:
        check(name, False, f"the base tree's copy: {why}")
        return
    control_tick = SEC + T
    ticks = [T, control_tick, 2 * SEC + T, 3 * SEC + T]
    asks = {which: [{"tag": f"h1a@{tick}", "package": str(package if which == "tree" else older),
                     "tick": tick, "clips": clips, "points": PICK_POINTS[(SW, SH)],
                     "png": str(WORK / f"h1a-{which}-{tick}.png")} for tick in ticks]
            for which in ("tree", "base")}
    tree = run_picks(sources, asks["tree"])
    base = run_picks(None, asks["base"])
    misses, figures, control = [], [], None
    for tick in ticks:
        tag = f"h1a@{tick}"
        a, b = tree.get(tag) or {}, base.get(tag) or {}
        pa, pb = Path(a.get("png") or "/nonexistent"), Path(b.get("png") or "/nonexistent")
        if not (pa.exists() and pb.exists()):
            misses.append(f"{tag}: no PNG ({a.get('error') or tree.get('error')} / "
                          f"{b.get('error') or base.get('error')})")
            continue
        same = pa.read_bytes() == pb.read_bytes()
        differ = 0
        if not same:
            fa, fb = Frame(pa, SW, SH), Frame(pb, SW, SH)
            differ = sum(1 for x, y in zip(fa.values, fb.values) if x != y)
        figures.append(f"{tag}: PNG bytes {'equal' if same else f'differ ({differ} 16-bit samples)'}"
                       f"; picks tree {a.get('picked')} base {b.get('picked')}")
        if tick == control_tick:
            control = not same
            continue
        if not same:
            misses.append(f"{tag}: PNG bytes differ ({differ} 16-bit samples differ)")
        if a.get("picked") != b.get("picked"):
            misses.append(f"{tag}: picks {a.get('picked')} vs base {b.get('picked')}")
    if control is not True:
        misses.append(f"CONTROL h1a@{control_tick}: the HLG tick's PNGs "
                      f"{'are equal' if control is False else 'were not drawn'}")
    check(name, not misses, f"{misses or 'all equal, the control differs'}\n       "
          + "\n       ".join(figures))


# ---- H7 -------------------------------------------------------------------------

def side(path, entries):
    """What ffprobe reads as `path`'s HDR10 side data — `frame=side_data_list` on its
    first video frame (the HEVC stream's SEI) or `stream_side_data_list` (the sample
    description's `mdcv` and `clli`): {"mastering": max_luminance, "cll": max_content},
    None for each it does not name."""
    argv = ["ffprobe", "-v", "error", "-select_streams", "v:0"]
    if entries == "frame":
        argv += ["-read_intervals", "%+#1", "-show_frames", "-show_entries",
                 "frame=side_data_list"]
    else:
        argv += ["-show_entries", "stream_side_data_list"]
    ran = bounded.run(argv + [str(path)], 60)
    found = {"mastering": None, "cll": None}
    for line in ran["stdout"].splitlines():
        key, _, value = line.strip().partition("=")
        if key == "max_luminance":
            found["mastering"] = value
        elif key == "max_content":
            found["cll"] = value
    return found


def side_want(maximum, cll):
    """`side`'s answer for a maximum and a (MaxCLL, MaxFALL) pair. Measured in hdr H-1:
    given `--master-display` alone, x265 still writes SEI 144, as 0,0 (MaxCLL unknown)."""
    return {"mastering": f"{maximum}/10000" if maximum is not None else None,
            "cll": str(cll[0]) if cll is not None else ("0" if maximum is not None else None)}


def h7_control(paths):
    """H7's CONTROL readings: {name: (got, want)} — each SEI fixture's first frame
    against its own values; each writer fixture's stream side data against the
    description it was given, and pq_both's first frame still pq_hdr10's SEI."""
    readings = {}
    for n, path in paths.items():
        if path is None:
            continue
        if n in SEI_FIXTURES:
            readings[n] = (side(path, "frame"), side_want(*SEI_FIXTURES[n]))
        else:
            over, maximum, cll, fall = DESC_FIXTURES[n]
            readings[n] = (side(path, "stream"), side_want(maximum, (cll, fall)))
            if SEI_FIXTURES[over] != (None, None):
                readings[f"{n} frame"] = (side(path, "frame"), side_want(*SEI_FIXTURES[over]))
    return readings


def h7_media(name, control):
    """H7i's fixture: DIR's copy when DIR holds one (the capture made it), else MEDIA's."""
    if control is not None:
        copy = control / "media" / f"{name}.mov"
        if copy.exists():
            return copy
    return fixture(name)


def peak_scene(client, name, path):
    """`path` alone at 1024×128: what import stored as `color` and the render at T —
    {color, frame, source, png} or {why}; the doc is closed."""
    doc = Doc(client, f"p-{name}", W, H)
    doc.place(path) if doc.ok else None
    rows = doc.project().get("media") or [] if doc.ok else []
    color = rows[0].get("color") if rows else None
    png = doc.render(f"p-{name}") if doc.ok else None
    closed = doc.close()
    source = yuv_frames(path, W, H)
    frame = Frame(png, W, H) if png else None
    if frame is None or not frame.ok or source is None or not closed:
        return {"why": f"{name}: {doc.why or 'no render, no decode or not closed'}",
                "color": color, "closed": closed}
    return {"color": color, "frame": frame, "source": source[0], "png": png, "closed": closed}


def grey_misses(scene, peak, tag, misses):
    """H3's loop at `peak`: the grey row's every 8th column against the oracle ±1;
    the worst |Δ| in levels."""
    worst = 0
    for x in range(0, W, 8):
        rgb = scene["source"].rgb(x, GREY_ROW, "bt2020nc")
        want = [code8(c) for c in convert("pq", "bt2020", rgb, peak)[0]]
        got = scene["frame"].px8(x, GREY_ROW)
        worst = max(worst, max(abs(a - b) for a, b in zip(got, want)))
        if not close_to(got, want, 1) and len(misses) < 12:
            misses.append(f"{tag} x={x} render {got} oracle at {peak} {want}")
    return worst


def same_png(a, b):
    return a is not None and b is not None and Path(a).read_bytes() == Path(b).read_bytes()


def run_h7(client, mode, control, sources, state):
    """hdr H-1 (#281, spec §11 HD-12): H7 the fixtures' own metadata (CONTROL), H7d
    what import reads, H7i the unknown and 1,000 cd/m² files unchanged, H7p the peak
    placing the shoulder, H7o the override, H7r the three new refusals."""
    paths = {n: fixture(n) for n in H7_FIXTURES}
    for n in ("pq_plain", "pq_hdr10_cll"):
        paths[n] = h7_media(n, None if mode == "capture" else control) or paths[n]
    if mode == "capture":
        (control / "media").mkdir(parents=True, exist_ok=True)
        for n in ("pq_plain", "pq_hdr10_cll"):
            if paths[n] is not None:
                shutil.copy2(paths[n], control / "media" / f"{n}.mov")
    refused = {n: REFUSED.get(n) for n, p in paths.items() if p is None}
    state["h7_fixture"] = not refused
    # H7, a CONTROL: each SEI fixture's first frame names its own values, pq_plain
    # none, and the writer read both extensions back.
    readings = h7_control(paths)
    found = {n: got for n, (got, _) in readings.items()}
    wrong = {n: pair for n, pair in readings.items() if pair[0] != pair[1]}
    unwritten = {n: WRITTEN.get(n) for n in DESC_FIXTURES
                 if n in WRITTEN and WRITTEN[n][0] != 0}
    check("H7 CONTROL: ffprobe reads each SEI fixture's own HDR10 values on its first frame "
          "(none on pq_plain; MaxCLL 0 on pq_hdr10_display) and each writer fixture's in its "
          "stream side data, pq_both's first frame still 4,000; hdr10_writer read both "
          "description extensions back", not refused and not wrong and not unwritten,
          f"refused {refused or 'none'}; side data {found}; wrong {wrong or 'none'}; writer "
          f"{ {n: w[1] for n, w in WRITTEN.items()} or 'not run this time (fixtures kept)'}")
    if refused:
        for row in sorted(H7_ROWS - {"H7"}):
            check(f"{row} the fixtures were made", False, f"refused {refused}")
        return
    scenes = {n: peak_scene(client, n, paths[n]) for n in H7_FIXTURES}
    state["h7_closed"] = all(s.get("closed") for s in scenes.values())
    # H7d: what import stored.
    misses = []
    for n in H7_FIXTURES:
        got = (scenes[n].get("color") or {}).get("pq")
        if got != H7_READS[n]:
            misses.append(f"{n}: color {scenes[n].get('color')}, want pq {H7_READS[n]}")
    others = {}
    for n, want in (("pq", True), ("hlg", False), ("bt709", False)):
        doc = Doc(client, f"pd-{n}", W, H)
        doc.place(fixture(n)) if doc.ok else None
        rows = doc.project().get("media") or [] if doc.ok else []
        others[n] = rows[0].get("color") if rows else "not imported"
        state[f"h7_{n}_closed"] = doc.close()
        if want and (others[n] or {}).get("pq") != {}:
            misses.append(f"the ProRes pq retag: color {others[n]}, want pq {{}}")
        if not want and isinstance(others[n], dict) and "pq" in others[n]:
            misses.append(f"{n}: color {others[n]}, want no pq")
        if others[n] == "not imported":
            misses.append(f"{n} was not imported")
    check("H7d import stores color.pq: {} on pq_plain, {4000, max_cll}, {600, max_cll}, "
          "{1000, max_cll}, {2000, mastering_display}, {600, max_cll} on pq_desc_600 and on "
          "pq_both (the description over the SEI's 4,000); {} on the ProRes pq retag; none on "
          "hlg or bt709", not misses,
          f"{misses or 'all as read'}; read {[(n, (scenes[n].get('color') or {}).get('pq')) for n in H7_FIXTURES]}; "
          f"others {others}")
    # H7i: the unknown file and the 1,000 cd/m² file render as before.
    misses, figures = [], []
    want_png = control / "h7-pq_plain.png"
    for n in ("pq_plain", "pq_hdr10_cll"):
        scene = scenes[n]
        if "frame" not in scene:
            misses.append(scene["why"])
            continue
        worst = grey_misses(scene, 1000, n, misses)
        figures.append(f"{n}: worst |Δ| against the oracle at 1,000 {worst} levels")
        if mode == "capture":
            if n == "pq_plain":
                shutil.copy2(scene["png"], want_png)
        elif not want_png.exists():
            misses.append(f"{n}: no control PNG {want_png}")
        elif not same_png(scene["png"], want_png):
            misses.append(f"{n}: its render's PNG bytes differ from the control's pq_plain")
    check(f"H7i pq_plain and pq_hdr10_cll (MaxCLL 1,000) at 0.5 s: the render's PNG bytes equal "
          f"{control.name}'s pq_plain, and the grey row (every 8th column) = the oracle at 1,000 "
          f"±1", not misses, f"{misses or 'all equal'}; " + "; ".join(figures))
    # H7p: the peak places the shoulder.
    misses, figures = [], []
    for n, peak in [(PEAK_FIXTURES[p], p) for p in (600, 2000, 4000)] + [("pq_desc_600", 600)]:
        scene = scenes[n]
        if "frame" not in scene:
            misses.append(scene["why"])
            continue
        worst = grey_misses(scene, peak, n, misses)
        figures.append(f"{n}: worst |Δ| against the oracle at {peak} {worst} levels")
    for peak, n in PEAK_FIXTURES.items():
        scene = scenes[n]
        if "frame" not in scene:
            continue
        level = render_at(scene["frame"], scene["source"], 0.70, "bt2020nc") * 255
        figures.append(f"{n} at PQ 0.70: {level:.2f} (computed {AT_070[peak]})")
        if abs(level - AT_070[peak]) > 1:
            misses.append(f"{n} at PQ 0.70: {level:.2f}, computed {AT_070[peak]}")
    if not same_png(scenes["pq_desc_600"].get("png"), scenes["pq_hdr10_600"].get("png")):
        misses.append("pq_desc_600's render PNG bytes differ from pq_hdr10_600's")
    check("H7p the shoulder at the file's peak: pq_hdr10_600, pq_hdr10_display, pq_hdr10 and "
          "pq_desc_600's grey rows (every 8th column) = the oracle at 600/2000/4000/600 ±1; at "
          "PQ 0.70 the 600/1000/2000/4000 files within ±1 of 255.0/246.9/243.5/242.8; "
          "pq_desc_600's PNG bytes = pq_hdr10_600's", not misses,
          f"{misses or 'all within'}\n       " + "\n       ".join(figures))
    run_h7o(client, paths, scenes, state)
    run_h7r(client, paths, state)
    apple_reading(sources, paths, state)


def apple_reading(sources, paths, state):
    """Unscored (B96's, kept for #281): Apple's own reading of each fixture —
    `hdr_pick_probe.swift`'s `plain` request (H1w's oracle), an AVAssetImageGenerator
    frame with no composition — at the grey row every 64th column, and each one's worst
    |Δ| against pq_plain's: whether Apple's reading follows either route's metadata."""
    points = [[x + 0.5, GREY_ROW + 0.5] for x in range(0, W, 64)]
    apple = run_picks(sources, [{"tag": n, "plain": str(paths[n]), "tick": T, "clips": [],
                                 "points": points} for n in H7_FIXTURES])
    read = {}
    for n in H7_FIXTURES:
        got = (apple.get(n) or {}).get("picked")
        read[n] = [[code8(c) for c in one] if one else None for one in got] if got else None
    lines = [f"{n}: {read[n] if read[n] is not None else (apple.get(n) or {}).get('error') or apple.get('error') or 'not read'}"
             for n in H7_FIXTURES]
    for n in H7_FIXTURES[1:]:
        a, b = read.get("pq_plain"), read.get(n)
        if a is None or b is None or any(p is None or q is None for p, q in zip(a, b)):
            lines.append(f"{n} against pq_plain: not read")
            continue
        worst = max(max(abs(x - y) for x, y in zip(p, q)) for p, q in zip(a, b))
        lines.append(f"{n} against pq_plain: worst |Δ| {worst} levels")
    state["h7_apple"] = read
    print("  unscored: Apple's reading (x = 0, 64, …, 960)\n       " + "\n       ".join(lines),
          flush=True)


def run_h7o(client, paths, scenes, state):
    """H7o: the override on pq_hdr10, its undo, the knee, and null."""
    misses = []
    plain = scenes["pq_plain"].get("png")
    doc = Doc(client, "h7o", W, H)
    doc.place(paths["pq_hdr10"]) if doc.ok else None
    media = getattr(doc, "_media", {}).get(paths["pq_hdr10"])

    def pq():
        row = next((m for m in doc.project().get("media") or [] if m.get("id") == media), {})
        return (row.get("color") or {}).get("pq")

    def peak(color, tag):
        got = doc.call("set_media_color", media=media, color=color)
        if not got["ok"]:
            misses.append(f"set {color}: {got.get('error')}")
            return None
        return doc.render(f"h7o-{tag}")

    at4000 = doc.render("h7o-4000") if doc.ok else None
    at1000 = peak({"peak": 1000}, "1000")
    stored = pq()
    if not same_png(at1000, plain):
        misses.append("{peak: 1000}'s render differs from pq_plain's")
    if stored != {"file": 4000, "from": "max_cll", "peak": 1000}:
        misses.append(f"{{peak: 1000}} stored pq {stored}")
    # Undone only after an applied set, so a refused one never undoes the clip.
    undone = doc.call("undo") if at1000 is not None else {"ok": False, "error": "nothing set"}
    after_undo = doc.render("h7o-undone") if undone["ok"] else None
    if not (undone["ok"] and same_png(after_undo, at4000) and not same_png(at4000, plain)):
        misses.append(f"undo: {undone.get('error')}; the 4,000 render back "
                      f"{same_png(after_undo, at4000)}; it differs from pq_plain's "
                      f"{not same_png(at4000, plain)}")
    at100 = peak({"peak": 100}, "100")
    at203 = peak({"peak": 203}, "203")
    if not same_png(at100, at203):
        misses.append("{peak: 100}'s render differs from {peak: 203}'s (the white held at 1)")
    cleared = doc.call("set_media_color", media=media, color=None)
    after_null = pq()
    at_null = doc.render("h7o-null")
    if not (cleared["ok"] and after_null == {"file": 4000, "from": "max_cll"}
            and same_png(at_null, at4000)):
        misses.append(f"null: {cleared.get('error')}; pq {after_null}; the 4,000 render "
                      f"{same_png(at_null, at4000)}")
    state["h7o_closed"] = doc.close()
    check("H7o the override on pq_hdr10: {peak: 1000} renders pq_plain's bytes and stores "
          "{4000, max_cll, peak 1000}; undo brings the 4,000 render back; {peak: 100} renders "
          "{peak: 203}'s bytes; null keeps {4000, max_cll} and the 4,000 render", not misses,
          f"{misses or 'all as asked'}")


def run_h7r(client, paths, state):
    """H7r: the three new sentences, each a refusal."""
    misses = []
    doc = Doc(client, "h7r", W, H)
    ids = {}
    for index, (n, path) in enumerate((("hlg", fixture("hlg")), ("bt709", fixture("bt709")),
                                       ("pq_hdr10", paths["pq_hdr10"]))):
        doc.place(path, at=index * SEC) if doc.ok and path is not None else None
        ids[n] = getattr(doc, "_media", {}).get(path)
    cases = [(ids["hlg"], {"peak": 1000},
              f"media {ids['hlg']} is not a PQ file; only a PQ file takes a peak"),
             (ids["bt709"], {"peak": 1000},
              f"media {ids['bt709']} is not a PQ file; only a PQ file takes a peak"),
             (ids["pq_hdr10"], {"peak": 0}, "color.peak must be 1–10000 cd/m², not 0"),
             (ids["pq_hdr10"], {"peak": 10001}, "color.peak must be 1–10000 cd/m², not 10001"),
             (ids["pq_hdr10"], {"pq": {"file": 1}},
              "color.pq is read from the file at import, not set")]
    for media, color, sentence in cases:
        got = doc.call("set_media_color", media=media, color=color)
        want = f"was refused at set_media_color: {sentence}"
        if got["ok"] or want not in got.get("error", ""):
            misses.append(f"{color} on {media}: {got.get('error') if not got['ok'] else 'applied'}"
                          f" (want …{want}…)")
    state["h7r_closed"] = doc.close()
    check("H7r refused, each in its own sentence: a peak on hlg and on bt709 (not a PQ file), "
          "0 and 10001 (outside 1–10000), and {pq: {file: 1}} (read at import)", not misses,
          f"{misses or 'all refused'}")


def run_srgb_rows(client, control, sources, state):
    """H1s and H1w: the sRGB arm, BT.709 primaries in a converting composition
    and P3 D65 primaries alone."""
    srgb, hlg, p3 = h1_media("srgb", control), fixture("hlg"), fixture("p3srgb")
    plan = [("alone", [srgb]), ("mixed", [srgb, hlg]), ("p3", [p3])]
    made = {}
    for name, paths in plan:
        if any(path is None for path in paths):
            made[name] = None
            continue
        package, clips, doc = saved_scene(client, f"srgb-{name}", paths)
        exported = doc.export(f"srgb-{name}") if package else None
        state[f"srgb_{name}_closed"] = doc.close()
        made[name] = (package, clips, exported) if package and exported else None
    asks = [{"tag": n, "package": str(m[0]), "tick": T, "clips": m[1],
             "points": PICK_POINTS[(W, H)]} for n, m in made.items() if m]
    oracle_ask = [{"tag": "oracle", "plain": str(p3), "tick": T, "clips": [],
                   "points": PICK_POINTS[(W, H)]}] if p3 else []
    tree = run_picks(sources, asks + oracle_ask) if asks else {"error": "no scene"}
    base = run_picks(None, asks) if asks else {"error": "no scene"}

    def picks(answer, tag):
        got = (answer.get(tag) or {}).get("picked")
        return [[code8(c) for c in one] if one else None for one in got] if got else None

    def near(a, b, tolerance):
        return a is not None and b is not None and all(
            x is not None and y is not None and close_to(x, y, tolerance) for x, y in zip(a, b))
    frames = {n: (yuv_frames(m[2], W, H, 16) if m else None) for n, m in made.items()}

    # H1s
    alone, mixed = picks(tree, "alone"), picks(tree, "mixed")
    base_mixed = picks(base, "mixed")
    rows_ok, worst, mid = True, 0, None
    if frames.get("alone") and frames.get("mixed"):
        for row in (GREY_ROW, CHROMA_ROW):
            for x in range(0, W, 8):
                a = export_rgb8(frames["alone"], 15, x, row)
                b = export_rgb8(frames["mixed"], 15, x, row)
                worst = max(worst, max(abs(p - q) for p, q in zip(a, b)))
        mid = (export_rgb8(frames["alone"], 15, 512, GREY_ROW),
               export_rgb8(frames["mixed"], 15, 512, GREY_ROW))
        rows_ok = worst <= 6 and close_to(*mid, 1)
    else:
        rows_ok = False
    control = base_mixed is not None and alone is not None and not near(
        base_mixed[:1], alone[:1], 2)
    check("H1s srgb|hlg against srgb alone: the tree's picks at 0.5 s ±2, the prores_422 export's "
          "frame 15 rows (every 8th column) ±6 and ±1 at x=512 on the grey row; the base tree's "
          "grey pick fails (CONTROL)",
          near(mixed, alone, 2) and rows_ok and control,
          f"picks mixed {mixed} / alone {alone}; base-tree mixed {base_mixed} (fails: {control}); "
          f"export rows worst |Δ| {worst}, x=512 alone/mixed {mid}; "
          f"{tree.get('error', '')} {base.get('error', '')}")

    # H1w
    oracle, mine, base_p3 = picks(tree, "oracle"), picks(tree, "p3"), picks(base, "p3")
    grey = None
    if frames.get("p3") and frames.get("alone"):
        grey = (export_rgb8(frames["p3"], 15, 512, GREY_ROW),
                export_rgb8(frames["alone"], 15, 512, GREY_ROW))
    control_w = base_p3 is not None and oracle is not None and not near(base_p3[:1], oracle[:1], 2)
    check("H1w p3srgb.mov alone (smpte432/iec61966-2-1/bt709): the tree's picks at 0.5 s = Apple's "
          "reading of the file's own labels ±2, the export's grey at x=512 = srgb alone's ±1; "
          "the base tree's grey pick fails (CONTROL)",
          near(mine, oracle, 2) and grey is not None and close_to(*grey, 1) and control_w,
          f"picks tree {mine} / oracle {oracle}; base-tree {base_p3} (fails: {control_w}); "
          f"export grey x=512 p3/alone {grey}; refused {REFUSED.get('p3srgb', 'none')}")


# ---- R0 -------------------------------------------------------------------------

def run_r0(state):
    """The labels of the newest existing recording, never its pixels; the
    rec_tags fixture, and where it is scored."""
    found = sorted(RECORDINGS.glob("Screen Recording *.mov")) if RECORDINGS.is_dir() else []
    if not found:
        check("R0 no recording on disk; GRD-16", True, f"{RECORDINGS} holds none")
        return None
    newest = found[-1]
    probe = stream(newest)
    primaries = probe.get("color_primaries", "unknown")
    transfer = probe.get("color_transfer", "unknown")
    matrix = probe.get("color_space", "unknown")
    chosen = arm(primaries, transfer)
    out = MEDIA / f"rec_tags-{primaries}-{transfer}-{matrix}.mov"
    made = hevc10("rec_tags", (primaries, transfer, matrix), out)
    check(f"R0 the newest recording's labels (read only): {newest.name}: primaries {primaries}, "
          f"transfer {transfer}, matrix {matrix}; the selector's arm: {chosen or 'nil (identity)'}",
          True, f"codec {probe.get('codec_name')} {probe.get('pix_fmt')}; rec_tags.mov "
          f"{'made: ' + tags(stream(made)) if made else 'REFUSED: ' + str(REFUSED.get('rec_tags'))}"
          f"; scored under {'H1' if chosen in (None, 'srgb(bt709)') else 'H5' if chosen.startswith('sdrWide') else 'none'}")
    state["r0"] = {"file": newest.name, "tags": [primaries, transfer, matrix], "arm": chosen}
    if made is None:
        state["r0_fixture"] = False
        return None
    return {"path": made, "arm": chosen, "primaries": primaries, "matrix": matrix}


# ---- hdr H-2 (#277, spec §11 HD-2, HD-3, HD-13): the HLG working space ----------

def to2020(name):
    """Linear `name` RGB → linear BT.2020 RGB (derived here, as `to709`)."""
    return mat_mul(mat_inv(npm("bt2020")), npm(name))


def hlg_oetf(light):
    e = max(light, 0.0)
    return math.sqrt(3 * e) if e <= 1 / 12 else HLG_A * math.log(12 * e - HLG_B) + HLG_C


def inverse_ootf(display):
    """BT.2100's inverse OOTF at γ 1.2 on BT.2020 luminance (HD-13 (a))."""
    yd = sum(w * c for w, c in zip(LUMA2020, display))
    if yd <= 0:
        return [0.0, 0.0, 0.0]
    return [c * yd ** ((1 - HLG_NOMINAL_GAMMA) / HLG_NOMINAL_GAMMA) for c in display]


def srgb_eotf(c):
    c = max(c, 0.0)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lift(rgb, primaries="bt709", decode="cm709"):
    """HD-3's lift as HD-13 (a) computes it: Core Media 709's γ decode with its toe
    (or the sRGB EOTF), the matrix to BT.2020, × 203/1000, the inverse OOTF, the HLG
    OETF."""
    linear = [srgb_eotf(c) if decode == "srgb" else max(max(c, 0.0) / CM709_TOE,
                                                          max(c, 0.0) ** CM709_GAMMA)
              for c in rgb]
    display = [max(c, 0.0) * LIFT_SCALE for c in mat_vec(to2020(primaries), linear)]
    return [unit(hlg_oetf(c)) for c in inverse_ootf(display)]


def unlift(hlg):
    """The lift's inverse (HD-13 (h)), unclamped above 1."""
    scene = [hlg_inverse(c) for c in hlg]
    ys = sum(w * c for w, c in zip(LUMA2020, scene))
    display = [c * ys ** (HLG_NOMINAL_GAMMA - 1) for c in scene] if ys > 0 else [0.0] * 3
    linear = mat_vec(to709("bt2020"), [c / LIFT_SCALE for c in display])
    return [min(max(c, 0.0) * CM709_TOE, max(c, 0.0) ** (1 / CM709_GAMMA)) for c in linear]


def pq_signal(nits):
    y = (max(nits, 0.0) / 10000) ** PQ_M1
    return ((PQ_C1 + PQ_C2 * y) / (1 + PQ_C3 * y)) ** PQ_M2


def eetf(signal, peak):
    """BT.2390's EETF (HD-13 (c)): Lb 0, the target 1,000 cd/m², KS = 1.5·maxLum − 0.5,
    on the signal over the source's peak (held at 1)."""
    source = pq_signal(peak)
    max_lum = pq_signal(PQ_WHITE) / source
    ks = 1.5 * max_lum - 0.5
    e1 = min(min(max(signal, 0.0), 1.0) / source, 1.0)
    if e1 < ks:
        e2 = e1
    else:
        t = (e1 - ks) / (1 - ks)
        e2 = ((2 * t ** 3 - 3 * t ** 2 + 1) * ks + (t ** 3 - 2 * t ** 2 + t) * (1 - ks)
              + (-2 * t ** 3 + 3 * t ** 2) * max_lum)
    return min(e2, 1.0) * source


def pq_hlg(rgb, peak=None):
    """PQ → HLG at 1,000 cd/m² (HD-13 (c)), through the EETF when `peak` exceeds it."""
    signal = [eetf(c, peak) for c in rgb] if peak and peak > PQ_WHITE else list(rgb)
    display = [min(pq_eotf(c) * 10000 / PQ_WHITE, 1.0) for c in signal]
    return [unit(hlg_oetf(c)) for c in inverse_ootf([max(c, 0.0) for c in display])]


def hlg_matrix(rgb, primaries):
    """HLG over `primaries` → BT.2020 in scene light (HD-13 (d))."""
    scene = mat_vec(to2020(primaries), [hlg_inverse(c) for c in rgb])
    return [unit(hlg_oetf(max(c, 0.0))) for c in scene]


def slog3_reflection(y):
    """Sony's S-Log3 to scene reflection, y = code/1023 (the shader's constants)."""
    code = y * 1023
    if code >= SLOG3_BREAK:
        return 10 ** ((code - 420.0) / 261.5) * 0.19 - 0.01
    return (code - 95.0) * 0.01125 / (SLOG3_BREAK - 95.0)


def log_hlg(signal):
    """A video-range S-Log3 grey → HLG (HD-13 (e)): the code domain, the curve, the
    exposure 0.26741, the OETF, no shoulder."""
    y = signal * 876 / 1023 + 64 / 1023
    return unit(hlg_oetf(slog3_reflection(y) * LOG_HLG_EXPOSURE))


def levels(value):
    return value * 1023


def unit(value):
    """The layer stage's clamp (spec §11 PR-1): every oracle's output is in [0, 1]."""
    return min(max(value, 0.0), 1.0)


def env16(fn, codes, matrix):
    """The oracle `fn` of the R'G'B' at a fixture's Y', Cb and Cr codes each moved by
    −1, 0, +1, as H4's envelope, widened by one 10-bit level: (low, high) triples."""
    luma, cb, cr = codes
    outs = [fn(rgb_of(luma + a, cb + b, cr + c, matrix))
            for a in (-1, 0, 1) for b in (-1, 0, 1) for c in (-1, 0, 1)]
    return ([min(o[i] for o in outs) - LEVEL for i in range(3)],
            [max(o[i] for o in outs) + LEVEL for i in range(3)])


def hlg_doc(client, name, paths=(), width=W, height=H, background=None):
    """A project of `paths` one after another (1 s each), its canvas set to HLG
    (`set_canvas {output}` — the Dynamic Range popup is never pressed: the canvas
    checkbox beside it persists a default). The Doc, open."""
    doc = Doc(client, name, width, height)
    if background is not None and doc.ok:
        doc.call("set_canvas", background=background)
    for i, path in enumerate(paths):
        if path is None:
            doc.ok, doc.why = False, f"{name}: a fixture was refused ({REFUSED})"
        elif doc.ok:
            doc.place(path, at=i * SEC)
    if doc.ok:
        got = doc.call("set_canvas", output="hlg")
        if not got["ok"] or (doc.project().get("canvas") or {}).get("output") != "hlg":
            doc.ok, doc.why = False, f"{name}: set_canvas output: {got.get('error')}"
    return doc


def frame_of(doc, tag, width=W, height=H, t=T):
    png = doc.render(tag, t) if doc.ok else None
    frame = Frame(png, width, height) if png else None
    return frame if frame is not None and frame.ok else None


def grey_row_misses(frame, source, matrix, want, tag, misses, step=64):
    """The grey row every `step`th column inside the envelope of `want(R'G'B')` at the
    fixture's codes ±1 (`env16`), widened by one 10-bit level — the decoder's reading of
    a code is the uncertainty, as H4's and H5's envelopes hold. The worst |Δ| against the
    nominal oracle in 10-bit levels."""
    worst = 0.0
    for x in range(0, W, step):
        rgb = source.rgb(x, GREY_ROW, matrix)
        oracle = want(rgb)
        bounds = env16(want, source.codes(x, GREY_ROW), matrix)
        got = frame.px(x, GREY_ROW)
        gap = max(abs(a - b) for a, b in zip(got, oracle))
        worst = max(worst, gap)
        if not inside(got, bounds) and len(misses) < 12:
            misses.append(f"{tag} x={x} render {[round(v, 5) for v in got]} oracle "
                          f"{[round(v, 5) for v in oracle]} ({levels(gap):.2f} levels) envelope "
                          f"{[[round(v, 5) for v in b] for b in bounds]}")
    return levels(worst)


def run_hs(client, state):
    """HS: the BT.709, untagged and sRGB ramps in an HLG project → the lift."""
    misses, figures = [], []
    for name, decode in (("bt709", "cm709"), ("untagged", "cm709"), ("srgb", "srgb")):
        path = fixture(name)
        source = yuv_frames(path, W, H) if path else None
        doc = hlg_doc(client, f"hs-{name}", [path])
        frame = frame_of(doc, f"hs-{name}")
        state[f"hs_{name}_closed"] = doc.close()
        if frame is None or source is None:
            misses.append(f"{name}: {doc.why or 'no render or decode'}")
            continue
        worst = grey_row_misses(frame, source[0], "bt709",
                                lambda rgb, d=decode: lift(rgb, "bt709", d), name, misses)
        figures.append(f"{name}: worst |Δ| {worst:.3f} levels; at x=512 "
                       f"{round(frame.px(512, GREY_ROW)[1], 5)} (lift "
                       f"{round(lift(source[0].rgb(512, GREY_ROW, 'bt709'), 'bt709', decode)[1], 5)})")
    check("HS the bt709, untagged and srgb ramps in an HLG project: the grey row (every 64th "
          "column) = HD-3's lift (the sRGB-EOTF twin for srgb) inside the ±1-code envelope "
          "±1/1023", not misses,
          f"{misses or 'all within'}\n       " + "\n       ".join(figures))


def run_hh(client, state):
    """HH: HLG over BT.2020 unchanged; HLG over P3 matrixed in scene light."""
    misses, figures = [], []
    for name in ("hlg", "hlg_hevc"):
        path = fixture(name)
        source = yuv_frames(path, W, H) if path else None
        doc = hlg_doc(client, f"hh-{name}", [path])
        frame = frame_of(doc, f"hh-{name}")
        state[f"hh_{name}_closed"] = doc.close()
        if frame is None or source is None:
            misses.append(f"{name}: {doc.why or 'no render or decode'}")
            continue
        worst = grey_row_misses(frame, source[0], "bt2020nc", lambda rgb: rgb, name, misses)
        figures.append(f"{name}: grey row against its own signal worst {worst:.3f} levels")
    path = fixture("hlg_p3")
    source = yuv_frames(path, W, H) if path else None
    doc = hlg_doc(client, "hh-hlg_p3", [path])
    frame = frame_of(doc, "hh-hlg_p3")
    state["hh_hlg_p3_closed"] = doc.close()
    if frame is None or source is None:
        misses.append(f"hlg_p3: {doc.why or 'no render or decode'} {REFUSED.get('hlg_p3', '')}")
    else:
        worst = grey_row_misses(frame, source[0], "bt2020nc",
                                lambda rgb: hlg_matrix(rgb, "p3d65"), "hlg_p3", misses)
        outside, moved = [], 0
        for x in range(0, W, 64):
            codes = source[0].codes(x, CHROMA_ROW)
            bounds = env16(lambda rgb: hlg_matrix(rgb, "p3d65"), codes, "bt2020nc")
            got = frame.px(x, CHROMA_ROW)
            signal = source[0].rgb(x, CHROMA_ROW, "bt2020nc")
            moved += max(abs(a - b) for a, b in zip(hlg_matrix(signal, "p3d65"), signal)) > 4 * LEVEL
            if not inside(got, bounds):
                outside.append((x, [round(v, 4) for v in got],
                                [[round(v, 4) for v in b] for b in bounds]))
        if outside:
            misses.append(f"hlg_p3 chroma row outside the oracle's envelope: {outside[:3]}")
        if moved < 4:
            misses.append(f"CONTROL: the matrix moved only {moved} chroma columns by > 4 levels")
        figures.append(f"hlg_p3: grey worst {worst:.3f} levels; chroma {len(outside)} of "
                       f"{W // 64} columns outside, {moved} moved by > 4 levels (CONTROL)")
    check("HH hlg and hlg_hevc in an HLG project equal their source signal (the grey row, "
          "every 64th column, inside the ±1-code envelope ±1/1023); hlg_p3 (smpte432/"
          "arib-std-b67) = the matrix in scene light (the grey and chroma rows inside the same "
          "envelope)",
          not misses, f"{misses or 'all within'}\n       " + "\n       ".join(figures))


def run_hp(client, state):
    """HP: PQ → HLG at 1,000 cd/m², and pq_hdr10 (4,000) through BT.2390's EETF."""
    misses, figures = [], []
    for name, peak in (("pq_plain", None), ("pq_hdr10", 4000)):
        path = fixture(name)
        source = yuv_frames(path, W, H) if path else None
        doc = hlg_doc(client, f"hp-{name}", [path])
        frame = frame_of(doc, f"hp-{name}")
        state[f"hp_{name}_closed"] = doc.close()
        if frame is None or source is None:
            misses.append(f"{name}: {doc.why or 'no render or decode'}")
            continue
        worst = grey_row_misses(frame, source[0], "bt2020nc",
                                lambda rgb, p=peak: pq_hlg(rgb, p), name, misses)
        figures.append(f"{name}: worst |Δ| {worst:.3f} levels against PQ→HLG"
                       f"{' through the EETF at 4,000' if peak else ' at 1,000'}")
        if peak:
            # Every 8th column above 1,000 cd/m² where the two oracles part by more than
            # 3 levels: the render inside the EETF oracle's envelope there, so outside the
            # no-EETF one's (at least four such columns, a CONTROL on the fixture).
            parted = []
            for x in range(0, W, 8):
                rgb = source[0].rgb(x, GREY_ROW, "bt2020nc")
                apart = abs(pq_hlg(rgb, peak)[1] - pq_hlg(rgb)[1])
                if pq_eotf(rgb[1]) * 10000 <= PQ_WHITE or apart <= 3 * LEVEL:
                    continue
                bounds = env16(lambda c: pq_hlg(c, peak), source[0].codes(x, GREY_ROW),
                               "bt2020nc")
                got = frame.px(x, GREY_ROW)
                parted.append((x, round(levels(apart), 2), inside(got, bounds)))
            if len(parted) < 4 or not all(ok for _, _, ok in parted):
                misses.append(f"pq_hdr10 where the EETF parts from the clip: {parted}")
            figures.append(f"pq_hdr10 above 1,000 cd/m², every 8th column where the oracles part "
                           f"by > 3 levels: (x, levels apart, inside the EETF envelope) {parted}")
    check("HP pq_plain = PQ→HLG at 1,000 cd/m² and pq_hdr10 (4,000) = it through BT.2390's EETF "
          "(the grey row, every 64th column, inside the ±1-code envelope ±1/1023), and pq_hdr10 "
          "on the EETF where it parts from the no-EETF oracle by > 3 levels above 1,000 cd/m² "
          "(every 8th column, ≥ 4 columns)", not misses,
          f"{misses or 'all within'}\n       " + "\n       ".join(figures))


def grey_png():
    """HT's 8-bit grey still (128/255), 640×360, made once."""
    return checked("grey8", ffmpeg_make(MEDIA / "grey8.png", [
        "-f", "lavfi", "-i", f"color=c=0x808080:size={SW}x{SH}:rate=1:duration=1",
        "-frames:v", "1", "-pix_fmt", "rgb24"]), {"pix_fmt": "rgb24"})


def layer_scene(client, name, add, background=None):
    """A 640×360 project with one layer `add(doc, track)` puts on its track, rendered
    SDR then HLG: (SDR Frame, HLG Frame) or (None, why)."""
    doc = Doc(client, name, SW, SH)
    if background is not None and doc.ok:
        doc.call("set_canvas", background=background)
    made = add(doc, doc.track()) if doc.ok and add else True
    sdr = frame_of(doc, f"{name}-sdr", SW, SH) if made else None
    got = doc.call("set_canvas", output="hlg") if doc.ok else {"ok": False}
    hlg = frame_of(doc, f"{name}-hlg", SW, SH) if got["ok"] else None
    closed = doc.close()
    if sdr is None or hlg is None or not closed:
        return None, f"{name}: {doc.why or 'no render'} (made {made}, closed {closed})"
    return (sdr, hlg), None


def brightest(frame, width, height):
    """The largest green value of the frame (every 2nd pixel): a title's full-coverage
    interior over black."""
    return max(frame.px(x, y)[1] for y in range(0, height, 2) for x in range(0, width, 2))


def run_ht(client, state):
    """HT: a white title → 0.7500; a grey title, an 8-bit grey PNG still and a grey shape
    each equal the bt709 recording at the same SDR grey; a 50 % background → 0.5059.

    The same SDR grey is the layer's own 8-bit value, 128/255 (Core Graphics draws 0.5
    as 128, and the PNG holds 0x80). An SDR project's render of these layers is printed,
    not used: it comes through `AVAssetImageGenerator`, which reads 128/255 as 0.49999
    (measured in H-2), where an HLG project's frame is the reader's, the compositor's own
    values (HD-13 (i))."""
    misses, figures = [], []
    ramp_path = fixture("bt709")
    ramp_source = yuv_frames(ramp_path, W, H) if ramp_path else None
    doc = hlg_doc(client, "ht-ramp", [ramp_path])
    ramp = frame_of(doc, "ht-ramp")
    state["ht_ramp_closed"] = doc.close()
    if ramp is None or ramp_source is None:
        check("HT drawn layers lifted", False, f"the ramp: {doc.why}")
        return

    def text(color):
        return lambda d, track: d.place_tool(
            "add_text_clip", track=track, at=0, duration=2 * SEC,
            text={"content": "H", "size": 220, "color": color})

    def shape(fill, width, height):
        return lambda d, track: d.place_tool(
            "add_shape_clip", track=track, at=0, duration=2 * SEC,
            shape={"kind": "rectangle", "stroke": None, "width": width, "height": height,
                   "fill": fill})
    still = grey_png()
    grey = 128 / 255
    scenes = {
        "white title": (text([1, 1, 1, 1]), "max", None),
        "grey title": (text([0.5, 0.5, 0.5, 1]), "max", None),
        "grey still": ((lambda d, track: d.place(still)) if still else None, "centre", None),
        "grey shape": (shape([0.5, 0.5, 0.5, 1], 400, 200), "centre", None),
        # A clear 16 × 16 shape in the corner: an empty timeline draws no frame.
        "background": (shape([0, 0, 0, 0], 16, 16), "centre", [0.5, 0.5, 0.5, 1]),
    }
    for name, (add, read, background) in scenes.items():
        if add is None:
            misses.append(f"{name}: fixture refused {REFUSED.get('grey8')}")
            continue
        pair, why = layer_scene(client, "ht-" + name.replace(" ", "-"), add, background)
        state[f"ht_{name.replace(' ', '_')}_closed"] = why is None or "closed False" not in why
        if pair is None:
            misses.append(why)
            continue
        sdr, hlg = pair
        if read == "max":
            v_sdr, v_hlg = brightest(sdr, SW, SH), brightest(hlg, SW, SH)
        else:
            v_sdr, v_hlg = sdr.px(SW // 2, SH // 2)[1], hlg.px(SW // 2, SH // 2)[1]
        if name == "white title":
            ok = abs(v_hlg - 0.75) <= LEVEL
            figures.append(f"{name}: HLG {v_hlg:.5f} (want 0.7500 ±1/1023; SDR {v_sdr:.5f})")
        elif name == "background":
            got = hlg.px(SW // 2, SH // 2)
            ok = all(abs(v - 0.5059) <= LEVEL for v in got)
            figures.append(f"{name} [0.5, 0.5, 0.5, 1]: HLG {[round(v, 5) for v in got]} (want "
                           f"0.5059; the lift {lift([0.5] * 3)[1]:.5f}; SDR {v_sdr:.5f})")
        else:
            at = render_at(ramp, ramp_source[0], grey, "bt709")
            want = lift([grey] * 3)[1]
            ok = abs(v_hlg - at) <= LEVEL and abs(v_hlg - want) <= LEVEL
            figures.append(f"{name}: HLG {v_hlg:.5f}; the bt709 recording at 128/255 {at:.5f}; "
                           f"the lift {want:.5f} (SDR, unscored: {v_sdr:.5f})")
        if not ok:
            misses.append(name)
    check("HT in an HLG project a white text title = 0.7500 ±1/1023; a 50 % grey title, an "
          "8-bit grey PNG still and a 50 % grey shape (each 128/255 drawn) = the bt709 recording "
          "at 128/255 and the lift of it ±1/1023; a [0.5, 0.5, 0.5, 1] background = 0.5059 "
          "±1/1023", not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_hl(client, state):
    """HL: bt709 as S-Log3 in an HLG project → the log oracle; 18 % grey at 0.380."""
    misses, figures = [], []
    path = fixture("bt709")
    source = yuv_frames(path, W, H) if path else None
    doc = hlg_doc(client, "hl", [path])
    media = getattr(doc, "_media", {}).get(path)
    got = doc.call("set_media_color", media=media, color={"log": "slog3"}) if doc.ok \
        else {"ok": False, "error": doc.why}
    frame = frame_of(doc, "hl") if got["ok"] else None
    state["hl_closed"] = doc.close()
    if frame is None or source is None:
        misses.append(f"{doc.why or got.get('error') or 'no render or decode'}")
    else:
        worst = grey_row_misses(frame, source[0], "bt709", lambda rgb: [log_hlg(c) for c in rgb],
                                "slog3", misses)
        grey = (420 - 64) / 876
        at = render_at(frame, source[0], grey, "bt709")
        figures.append(f"worst |Δ| {worst:.3f} levels; 18 % grey (signal {grey:.4f}) renders "
                       f"{at:.4f} (oracle {log_hlg(grey):.4f})")
        if abs(at - 0.380) > LEVEL:
            misses.append(f"18 % grey at {at:.4f}, not 0.380")
    check("HL bt709 with set_media_color {log: slog3} in an HLG project: the grey row (every "
          "64th column) = the log oracle (×0.26741, the OETF, clipped at 1) inside the ±1-code "
          "envelope ±1/1023, 18 % grey at 0.380 ±1/1023",
          not misses, f"{misses or 'all within'}\n       " + "\n       ".join(figures))


def run_hw(client, state):
    """HW: saturation −1 → BT.2020 luma of the lifted colour; exposure +1 → HLG's
    scene light doubled."""
    misses, figures = [], []
    path = fixture("bt709")
    source = yuv_frames(path, W, H) if path else None
    doc = hlg_doc(client, "hw", [path])
    clip = (doc.project().get("clips") or [{}])[0].get("id") if doc.ok else None
    a = doc.call("set_video", clips=[clip], patch={"color": {"saturation": -1}}) if clip \
        else {"ok": False}
    grey = frame_of(doc, "hw-saturation") if a["ok"] else None
    b = doc.call("set_video", clips=[clip], patch={"color": {"saturation": 0, "exposure": 1}}) \
        if a["ok"] else {"ok": False}
    exposed = frame_of(doc, "hw-exposure") if b["ok"] else None
    state["hw_closed"] = doc.close()
    if grey is None or exposed is None or source is None:
        misses.append(f"{doc.why or a.get('error') or b.get('error') or 'no render or decode'}")
    else:
        def luma2020(rgb):
            y = sum(w * c for w, c in zip(LUMA2020, lift(rgb)))
            return [y] * 3
        outside, separated = [], 0
        for x in range(0, W, 64):
            codes = source[0].codes(x, CHROMA_ROW)
            bounds = env16(luma2020, codes, "bt709")
            got = grey.px(x, CHROMA_ROW)
            rgb = source[0].rgb(x, CHROMA_ROW, "bt709")
            y709 = sum(w * c for w, c in zip(LUMA709, lift(rgb)))
            separated += abs(y709 - luma2020(rgb)[0]) > 2 * LEVEL
            if not inside(got, bounds):
                outside.append((x, [round(v, 4) for v in got],
                                [[round(v, 4) for v in b] for b in bounds]))
        if outside:
            misses.append(f"saturation −1: {len(outside)} chroma columns outside the BT.2020 "
                          f"luma envelope {outside[:3]}")
        if separated < 4:
            misses.append(f"CONTROL: BT.709 and BT.2020 luma part by > 2 levels at only "
                          f"{separated} columns")
        worst = grey_row_misses(
            exposed, source[0], "bt709",
            lambda rgb: [hlg_oetf(min(2 * hlg_inverse(c), 1.0)) for c in lift(rgb)],
            "exposure +1", misses)
        figures.append(f"saturation −1: {len(outside)} of {W // 64} chroma columns outside, "
                       f"{separated} separating the weights by > 2 levels (CONTROL); exposure +1: "
                       f"worst |Δ| {worst:.3f} levels")
    check("HW in an HLG project: saturation −1 on the chroma row = BT.2020 luma of the lifted "
          "colour, exposure +1 on the grey row = OETF(min(2·invOETF(v), 1)), each inside the "
          "±1-code envelope ±1/1023", not misses,
          f"{misses or 'all within'}\n       " + "\n       ".join(figures))


GREEN_Y, GREEN_CB, GREEN_CR = 690, 167, 105  # BT.709 R'G'B' (0, 1, 0), 10-bit video range


def green_709():
    """HK's fixture: the left half code-value green, the right half 50 % grey, 1024×128,
    1 s, 10-bit ProRes 422 HQ, then tagged BT.709 by stream copy as `retag` tags (the
    encoder's own `-color_*` flags did not stick, measured), made once."""
    vf = (f"color=c=black:size={W}x{H}:rate=30:duration=1,format=yuv422p10le,"
          f"geq=lum='if(lt(X,W/2),{GREEN_Y},502)':cb='if(lt(X,W/2),{GREEN_CB},512)':"
          f"cr='if(lt(X,W/2),{GREEN_CR},512)'")
    plain = ffmpeg_make(MEDIA / "green_plain.mov", [
        "-f", "lavfi", "-i", vf, "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt",
        "yuv422p10le"])
    if plain is None:
        REFUSED["green_709"] = "ffmpeg did not make green_plain.mov"
        return None
    return checked("green_709", ffmpeg_make(MEDIA / "green_709.mov", [
        "-i", str(plain), "-c", "copy", "-bsf:v",
        "prores_metadata=color_primaries=bt709:color_trc=bt709:colorspace=bt709",
        "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
        "-movflags", "+write_colr"], 120),
        {"codec_name": "prores", "color_primaries": "bt709", "color_transfer": "bt709",
         "color_space": "bt709"})


def run_hk(client, state):
    """HK: a chroma key picked in SDR keeps keying after the switch to HLG."""
    misses, figures = [], []
    path = green_709()
    doc = Doc(client, "hk", W, H)
    if doc.ok:
        doc.call("set_canvas", background=[0.5, 0.5, 0.5, 1])
    clip = doc.place(path) if doc.ok and path else None
    left, right = (W // 4, H // 2), (3 * W // 4, H // 2)
    plain = frame_of(doc, "hk-plain") if clip else None
    key = [round(v, 5) for v in plain.px(*left)] if plain else None
    keyed = doc.call("set_video", clips=[clip], patch={"chroma": {
        "key": key, "tolerance": 0.1, "softness": 0.0, "spill": 0.0}}) if key else {"ok": False}
    sdr = frame_of(doc, "hk-sdr") if keyed["ok"] else None
    switched = doc.call("set_canvas", output="hlg") if sdr else {"ok": False}
    hlg = frame_of(doc, "hk-hlg") if switched["ok"] else None
    state["hk_closed"] = doc.close()
    if hlg is None or sdr is None:
        misses.append(f"{doc.why or keyed.get('error') or switched.get('error') or 'no render'}"
                      f" {REFUSED.get('green_709', '')}")
    else:
        grey = sdr.px(*right)
        want_right = lift(grey)
        got_left, got_right = hlg.px(*left), hlg.px(*right)
        figures.append(f"key {key}; SDR keyed: left {[round(v, 5) for v in sdr.px(*left)]} "
                       f"(CONTROL, the background 0.5), right {[round(v, 5) for v in grey]}; HLG: "
                       f"left {[round(v, 5) for v in got_left]} (want 0.5059), right "
                       f"{[round(v, 5) for v in got_right]} (want {[round(v, 5) for v in want_right]})")
        if not close_to(sdr.px(*left), [0.5] * 3, LEVEL):
            misses.append("CONTROL: the SDR key did not open the left half")
        if not close_to(got_left, [0.5059] * 3, LEVEL):
            misses.append("the HLG left half is not the lifted background")
        if not close_to(got_right, want_right, LEVEL):
            misses.append("the HLG right half is not the lift of the SDR grey")
    check("HK green_709 over a [0.5, 0.5, 0.5, 1] background, keyed (tolerance 0.1) at the green "
          "the SDR render reads: after set_canvas {output: hlg} the left half reads the lifted "
          "background 0.5059 and the right half the lift of the SDR render's grey, ±1/1023",
          not misses, f"{misses or 'all as wanted'}\n       " + "\n       ".join(figures))


def run_hm(client, state):
    """HM: a luma matte of a white and a 50 % grey shape over bt709 in an HLG project.

    A track holds no two clips at once, so the two shapes are drawn on two tracks and
    nested (`nest`), the emptied track removed (`remove_empty_tracks`), and the nest's
    track made the luma matte directly in front of the ramp's."""
    misses, figures = [], []
    path = fixture("bt709")
    source = yuv_frames(path, W, H) if path else None
    doc = Doc(client, "hm", W, H)
    if doc.ok:
        doc.call("set_canvas", background=[0.5, 0.5, 0.5, 1])
    clip = doc.place(path) if doc.ok and path else None
    shapes = []
    for x0, fill in ((0, [1, 1, 1, 1]), (W // 2, [0.5, 0.5, 0.5, 1])):
        added = doc.call("add_track") if clip else {"ok": False}
        tracks = doc.project().get("tracks") or [] if added["ok"] else []
        made = doc.place_tool("add_shape_clip", track=tracks[-1]["id"], at=0, duration=2 * SEC,
                              shape={"kind": "rectangle", "stroke": None, "width": W // 2,
                                     "height": H, "fill": fill}) if tracks else None
        moved = doc.call("set_video", clips=[made], patch={"x": x0 + W // 4 - W // 2, "y": 0}) \
            if made else {"ok": False}
        shapes.append(made if moved["ok"] else None)
    nested = doc.call("nest", clips=shapes) if all(shapes) else {"ok": False}
    pruned = doc.call("remove_empty_tracks") if nested["ok"] else {"ok": False}
    tracks = doc.project().get("tracks") or [] if pruned["ok"] else []
    front = tracks[-1]["id"] if len(tracks) == 2 else None
    matted = doc.call("set_track", track=front, matte="luma") if front else {"ok": False}
    switched = doc.call("set_canvas", output="hlg") if matted["ok"] else {"ok": False}
    frame = frame_of(doc, "hm") if switched["ok"] else None
    state["hm_closed"] = doc.close()
    if frame is None or source is None:
        misses.append(f"{doc.why or nested.get('error') or pruned.get('error') or matted.get('error') or switched.get('error') or 'not built'}"
                      f" (tracks {len(tracks)})")
    else:
        bg = lift([0.5] * 3)
        worst = {"left": 0.0, "right": 0.0}
        for x in range(0, W, 64):
            if abs(x - W // 2) < 8:
                continue
            ramp = lift(source[0].rgb(x, GREY_ROW, "bt709"))
            side = "left" if x < W // 2 else "right"
            want = ramp if side == "left" else [0.5 * r + 0.5 * b for r, b in zip(ramp, bg)]
            got = frame.px(x, GREY_ROW)
            gap = max(abs(a - b) for a, b in zip(got, want))
            worst[side] = max(worst[side], levels(gap))
            if gap > 2 * LEVEL and len(misses) < 12:
                misses.append(f"{side} x={x} render {[round(v, 5) for v in got]} want "
                              f"{[round(v, 5) for v in want]}")
        figures.append(f"worst |Δ| left (coverage 1) {worst['left']:.3f}, right (coverage 0.5) "
                       f"{worst['right']:.3f} levels")
    check("HM a luma matte track holding a white shape (left) and a 50 % grey shape (right) "
          "over bt709 in an HLG project: the left = the lifted ramp (coverage 1), the right = "
          "0.5·lift(ramp) + 0.5·0.5059, ±2/1023 (the grey row, every 64th column)", not misses,
          f"{misses or 'all within'}\n       " + "\n       ".join(figures))


def png_chunks(path):
    """`path`'s PNG chunks as [(type, data)], or [] when it is not a PNG."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return []
    chunks, at = [], 8
    while at + 8 <= len(data):
        size = struct.unpack(">I", data[at:at + 4])[0]
        chunks.append((data[at + 4:at + 8].decode("latin-1"), data[at + 8:at + 8 + size]))
        at += 12 + size
    return chunks


def run_hf(client, state):
    """HF: an HLG project's frames — a 16-bit PNG with cICP 9/18/0/1 and an iCCP named
    ITUR_2100_HLG, a 10-bit HEIC labelled ITUR_2100_HLG, and a JPEG written as the SDR
    version (hdr H-3, spec §11 HD-14 (e)), not labelled HLG."""
    misses, figures = [], []
    doc = hlg_doc(client, "hf", [fixture("bt709")])
    png = doc.render("hf") if doc.ok else None
    heic = WORK / "hf.heic"
    made = doc.call("render_frame", t=T, path=str(heic), format="heic") if doc.ok \
        else {"ok": False}
    jpeg_path = WORK / "hf.jpg"
    jpeg = doc.call("render_frame", t=T, path=str(jpeg_path), format="jpeg") if doc.ok \
        else {"ok": False}
    state["hf_closed"] = doc.close()
    if png is None:
        misses.append(f"no PNG: {doc.why}")
    else:
        chunks = dict((k, v) for k, v in reversed(png_chunks(png)))
        depth = chunks.get("IHDR", b"\0" * 9)[8]
        cicp = list(chunks.get("cICP", b""))
        name = chunks.get("iCCP", b"").split(b"\0")[0].decode("latin-1")
        figures.append(f"PNG: depth {depth}, cICP {cicp}, iCCP {name!r}, chunks "
                       f"{[k for k, _ in png_chunks(png)]}")
        if depth != 16 or cicp != [9, 18, 0, 1] or "ITUR_2100_HLG" not in name:
            misses.append("the PNG")
    if not made["ok"] or not heic.exists():
        misses.append(f"no HEIC: {made.get('error')}")
    else:
        read = bounded.run(["sips", "-g", "bitsPerSample", "-g", "profile", str(heic)], 60)
        figures.append(f"HEIC (sips): {' '.join(read['stdout'].split()[1:])}")
        # sips names a profile by its description: ITUR_2100_HLG's is "Rec. ITU-R BT.2100 HLG".
        if "bitsPerSample: 10" not in read["stdout"] or "BT.2100 HLG" not in read["stdout"]:
            misses.append("the HEIC")
    if not jpeg["ok"] or not jpeg_path.exists():
        misses.append(f"no JPEG: {jpeg.get('error')}")
    else:
        label = sips_profile(jpeg_path)
        figures.append(f"JPEG: written, profile {label!r}")
        if "HLG" in label or "2100" in label:
            misses.append("the JPEG is labelled HLG")
    check("HF an HLG project's render_frame: a 16-bit PNG with cICP 9/18/0/1 and an iCCP named "
          "ITUR_2100_HLG; a HEIC at 10 bits labelled ITUR_2100_HLG (sips: \"Rec. ITU-R BT.2100 "
          "HLG\"); a JPEG written as the SDR version, not labelled HLG",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_hx(client, state):
    """HX: an HLG project's 10-bit exports tagged HLG with no Dolby Vision; h264 its SDR
    version (bt709, hdr H-3); gif and audio_wav written."""
    misses, figures = [], []
    doc = hlg_doc(client, "hx", [fixture("bt709"), fixture("webm")])
    outs = {}
    for preset in ("hevc_10bit", "prores_422", "h264", "gif", "audio_wav"):
        base = WORK / f"hx-{preset}"
        got = doc.call("export", preset=preset, path=str(base), size="document") if doc.ok \
            else {"ok": False, "error": doc.why}
        files = sorted(WORK.glob(f"hx-{preset}.*"))
        outs[preset] = (got, files[0] if files else None)
    state["hx_closed"] = doc.close()
    for preset, want in (("hevc_10bit", PICTURE_TAGS["hlg"]), ("prores_422", PICTURE_TAGS["hlg"]),
                         ("h264", PICTURE_TAGS["sdr"])):
        got, path = outs[preset]
        probe = stream(path) if path else {}
        figures.append(f"{preset}: {tags(probe) if path else got.get('error')}")
        if not path or tags(probe) != want:
            misses.append(f"{preset}'s tags")
    got, path = outs["hevc_10bit"]
    if path:
        record, rpu = dovi(path)
        figures.append(f"hevc_10bit: DOVI configuration record {record}, Dolby Vision RPU {rpu}")
        if record or rpu:
            misses.append("Dolby Vision in the HEVC")
    for preset in ("gif", "audio_wav"):
        got, path = outs[preset]
        figures.append(f"{preset}: {path.name if path else got.get('error')}")
        if not got["ok"] or path is None:
            misses.append(f"{preset} was not written")
    check("HX an HLG project's hevc_10bit and prores_422 exports tagged bt2020nc/arib-std-b67/"
          "bt2020, the HEVC with no DOVI configuration record and no Dolby Vision RPU; h264 "
          "written as the SDR version, tagged bt709 ×3; gif and audio_wav written", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


# ---- hdr H-3 (#277, spec §11 HD-4, HD-5, HD-7, HD-14): the deliverables ----------

def sdr_version(hlg_rgb):
    """HD-14 (a)/(b)'s SDR version of one HLG R'G'B' (the output pass, `framejob_output_
    fragment`): scene light, display light (γ 1.2 on BT.2020 luminance), × 1000/203,
    BT.2020 → BT.709, GR-15's gamut lift, the shoulder at the knee reaching 1 at 1000/203,
    Core Media 709's encode with its toe."""
    scene = [hlg_inverse(unit(c)) for c in hlg_rgb]
    ys = sum(w * c for w, c in zip(LUMA2020, scene))
    display = [c * ys ** (HLG_NOMINAL_GAMMA - 1) for c in scene] if ys > 0 else [0.0] * 3
    lin = mat_vec(to709("bt2020"), [c * SDR_WHITE for c in display])
    low = min(lin)
    if low < 0:
        y = sum(w * c for w, c in zip(LUMA709, lin))
        lin = [0.0] * 3 if y <= 0 else [y + (c - y) * y / (y - low) for c in lin]
    top = max(lin)
    if top > SDR_KNEE:
        if top >= SDR_WHITE:
            s = 1.0
        else:
            t, tw = (top - SDR_KNEE) / (1 - SDR_KNEE), (SDR_WHITE - SDR_KNEE) / (1 - SDR_KNEE)
            s = SDR_KNEE + (1 - SDR_KNEE) * t * (1 + t / (tw * tw)) / (1 + t)
        lin = [c * s / top for c in lin]
    return [unit(min(max(c, 0.0) * CM709_TOE, max(c, 0.0) ** (1 / CM709_GAMMA))) for c in lin]


def pq_version(hlg_rgb):
    """HD-14 (d)'s PQ of one HLG R'G'B': display light at 1,000 cd/m² on ST 2084's scale."""
    scene = [hlg_inverse(unit(c)) for c in hlg_rgb]
    ys = sum(w * c for w, c in zip(LUMA2020, scene))
    display = [c * ys ** (HLG_NOMINAL_GAMMA - 1) for c in scene] if ys > 0 else [0.0] * 3
    return [unit(pq_signal(c * PQ_WHITE)) for c in display]


def render_opts(doc, tag, t=T, **options):
    """`render_frame` at `t` with `options` (`format`, `sdr_version`, …); (path, reply)."""
    suffix = {"jpeg": ".jpg", "heic": ".heic"}.get(options.get("format"), ".png")
    out = WORK / f"{tag}{suffix}"
    out.unlink(missing_ok=True)
    got = doc.call("render_frame", t=t, path=str(out), **options) if doc.ok \
        else {"ok": False, "error": doc.why}
    if not (got["ok"] and out.exists()):
        print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
        return None, got
    return out, got


def export_as(doc, tag, preset, **extra):
    """One `export` of `doc` as `preset` at its document size: (file or None, reply)."""
    base_path = WORK / tag

    def written():  # the export's file, never a package a document of that name made
        return sorted(f for f in WORK.glob(f"{tag}.*") if f.is_file())
    for stale in written():
        stale.unlink()
    got = doc.call("export", preset=preset, path=str(base_path), size="document", **extra) \
        if doc.ok else {"ok": False, "error": doc.why}
    files = written()
    return (files[0] if got["ok"] and files else None), got


def dovi(path):
    """(a DOVI configuration record in the stream, Dolby Vision RPU on its first 10
    frames) as ffprobe reads `path`."""
    streams = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                           "-show_entries", "stream_side_data_list", str(path)], 60)["stdout"]
    frames = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-read_intervals", "%+#10", "-show_frames", "-show_entries",
                          "frame=side_data_list", str(path)], 120)["stdout"]
    return "DOVI configuration record" in streams, "Dolby Vision RPU" in frames


def side_all(path):
    """Every `key=value` of `path`'s HDR10 side data: the stream's (the sample
    description's `mdcv` and `clli`), else its first frame's."""
    found = {}
    for entries in ("stream", "frame"):
        argv = ["ffprobe", "-v", "error", "-select_streams", "v:0"]
        argv += (["-show_entries", "stream_side_data_list"] if entries == "stream" else
                 ["-read_intervals", "%+#1", "-show_frames", "-show_entries",
                  "frame=side_data_list"])
        for line in bounded.run(argv + [str(path)], 60)["stdout"].splitlines():
            key, _, value = line.strip().partition("=")
            if key in HDR10_SIDE and key not in found:
                found[key] = value
        if all(k in found for k in HDR10_SIDE):
            break
    return found


def sips_profile(path):
    ran = bounded.run(["sips", "-g", "profile", str(path)], 60)["stdout"]
    return " ".join(ran.split("profile:", 1)[1].split()) if "profile:" in ran else ""


def png_label(path):
    """(cICP list, iCCP name) of a PNG."""
    chunks = dict((k, v) for k, v in reversed(png_chunks(path)))
    return list(chunks.get("cICP", b"")), \
        chunks.get("iCCP", b"").split(b"\0")[0].decode("latin-1")


def ramp_sdr_misses(frame, source, oracle, tag, bound, misses, step=64, matrix="bt2020nc"):
    """The grey row every `step`th column against `oracle(R'G'B')` within `bound`; the
    largest miss in levels of 255."""
    worst = 0.0
    for x in range(0, W, step):
        want = oracle(source.rgb(x, GREY_ROW, matrix))
        got = frame.px(x, GREY_ROW)
        gap = max(abs(a - b) for a, b in zip(got, want))
        worst = max(worst, gap)
        if gap > bound and len(misses) < 12:
            misses.append(f"{tag} x={x} got {[round(v, 5) for v in got]} want "
                          f"{[round(v, 5) for v in want]} ({gap * 255:.2f}/255)")
    return worst * 255


def code_column(source, code):
    """The first grey-row column whose luma code is `code`, or None."""
    return next((x for x in range(W) if source.codes(x, GREY_ROW)[0] == code), None)


def run_dt(client, state):
    """DT: every video row of an HLG project at its default and each accepted
    dynamic_range, tagged as the picture it writes; no Dolby Vision in any HEVC file."""
    misses, figures = [], []
    doc = hlg_doc(client, "dt", [fixture("hlg")])
    for preset in VIDEO_ROWS:
        ranges = [None, "hlg", "pq", "sdr"] if preset in HDR_ROWS else [None, "sdr"]
        for asked in ranges:
            tag = f"dt-{preset}-{asked or 'default'}"
            extra = {"dynamic_range": asked} if asked else {}
            path, got = export_as(doc, tag, preset, **extra)
            picture = asked or ("hlg" if preset in HDR_ROWS else "sdr")
            said = reply(got).get("dynamic_range")
            if path is None:
                misses.append(f"{tag}: {got.get('error', 'no file')}")
                continue
            if said != picture:
                misses.append(f"{tag}: the result's dynamic_range {said!r}, not {picture!r}")
            if preset in ("gif", "apng"):
                figures.append(f"{tag}: written ({path.stat().st_size} bytes)")
                continue
            read = tags(stream(path))
            line = f"{tag}: {read}"
            if read != PICTURE_TAGS[picture]:
                misses.append(f"{tag}: {read}, not {PICTURE_TAGS[picture]}")
            if preset.startswith("hevc"):
                record, rpu = dovi(path)
                line += f", DOVI record {record}, RPU {rpu}"
                if record or rpu:
                    misses.append(f"{tag}: Dolby Vision")
            figures.append(line)
    state["dt_closed"] = doc.close()
    check("DT every video row of an HLG project (the hlg ramp, 1 s) at its default and each "
          "accepted dynamic_range: bt709 ×3 for the SDR version, bt2020nc/arib-std-b67/bt2020 "
          "for hlg, bt2020nc/smpte2084/bt2020 for pq, the result naming it; no DOVI record or "
          "RPU in any HEVC file; gif and apng written", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_dp(client, state):
    """DP: the three 10-bit rows at pq carry HD-5's mastering display and content light
    level; prores_422's decoded grey row = the PQ oracle ±2/1023."""
    misses, figures = [], []
    path = fixture("hlg")
    source = yuv_frames(path, W, H) if path else None
    doc = hlg_doc(client, "dp", [path])
    outs = {preset: export_as(doc, f"dp-{preset}", preset, dynamic_range="pq")
            for preset in HDR_ROWS}
    state["dp_closed"] = doc.close()
    for preset, (out, got) in outs.items():
        if out is None:
            misses.append(f"{preset}: {got.get('error', 'no file')}")
            continue
        found = side_all(out)
        figures.append(f"{preset}: {tags(stream(out))}; side data {found}")
        wrong = {k: found.get(k) for k, v in HDR10_SIDE.items() if found.get(k) != v}
        if wrong:
            misses.append(f"{preset}: {wrong}")
    out = outs["prores_422"][0]
    frames = yuv_frames(out, W, H, 16) if out else None
    if frames is None or source is None:
        misses.append("prores_422's frames or the fixture did not decode")
    else:
        worst = 0.0
        for x in range(0, W, 8):
            want = pq_version(source[0].rgb(x, GREY_ROW, "bt2020nc"))
            got = frames[15].rgb(x, GREY_ROW, "bt2020nc")
            gap = max(abs(a - b) for a, b in zip(got, want))
            worst = max(worst, gap)
            if gap > 2 * LEVEL and len(misses) < 12:
                misses.append(f"prores_422 x={x} {[round(v, 5) for v in got]} want "
                              f"{[round(v, 5) for v in want]}")
        figures.append(f"prores_422's grey row against the PQ oracle: largest miss "
                       f"{levels(worst):.3f}/1023")
    check("DP prores_422, prores_4444 and hevc_10bit at pq: each file's side data P3-D65 "
          "(red 34000/50000 …, white 16450/50000), min_luminance=50/10000 max_luminance="
          "10000000/10000, max_content=1000 max_average=0; prores_422's decoded grey row = the "
          "PQ oracle ±2/1023", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_dv(client, state):
    """DV: render_frame {sdr_version} of the hlg ramp = the HD-14 (a) oracle; a white title
    248.4/255, a 0.42 title 107.1/255, HLG 0.50 125.7/255, each ±1; the PNG labelled BT.709
    as an SDR project's frame is."""
    misses, figures = [], []
    path = fixture("hlg")
    source = yuv_frames(path, W, H) if path else None
    doc = hlg_doc(client, "dv", [path])
    png, _ = render_opts(doc, "dv", sdr_version=True)
    state["dv_closed"] = doc.close()
    frame = Frame(png, W, H) if png else None
    if frame is None or not frame.ok or source is None:
        misses.append(f"the ramp: {doc.why or 'no render or decode'}")
    else:
        worst = ramp_sdr_misses(frame, source[0], sdr_version, "ramp", 1 / 255, misses)
        figures.append(f"the ramp against the oracle every 64th column: largest miss "
                       f"{worst:.3f}/255")
        x = code_column(source[0], 502)
        if x is None:
            misses.append("no column at HLG code 502 (0.50)")
        else:
            got = frame.px(x, GREY_ROW)[1] * 255
            figures.append(f"HLG 0.50 (x={x}): {got:.2f}/255 (want 125.7 ±1)")
            if abs(got - 125.7) > 1:
                misses.append("HLG 0.50")
        cicp, name = png_label(png)
        sdr = Doc(client, "dv-sdr", W, H)
        sdr.place(fixture("bt709")) if sdr.ok else None
        sdr_png, _ = render_opts(sdr, "dv-sdr")
        state["dv_sdr_closed"] = sdr.close()
        sdr_label = png_label(sdr_png) if sdr_png else None
        figures.append(f"the PNG: cICP {cicp}, iCCP {name!r}; an SDR project's: {sdr_label}")
        if (cicp, name) != sdr_label or "2100" in name or cicp[:2] == [9, 18]:
            misses.append("the PNG's label")
    for title, color, want in (("white title", [1, 1, 1, 1], 248.4),
                               ("0.42 title", [0.42, 0.42, 0.42, 1], 107.1)):
        tag = "dv-" + title.replace(" ", "-").replace(".", "")
        d = Doc(client, tag, SW, SH)
        if d.ok:
            d.place_tool("add_text_clip", track=d.track(), at=0, duration=2 * SEC,
                         text={"content": "H", "size": 220, "color": color})
            d.call("set_canvas", output="hlg")
        out, _ = render_opts(d, tag, sdr_version=True)
        state[f"{tag}_closed"] = d.close()
        f = Frame(out, SW, SH) if out else None
        if f is None or not f.ok:
            misses.append(f"{title}: {d.why or 'no render'}")
            continue
        got = brightest(f, SW, SH) * 255
        figures.append(f"{title}: {got:.2f}/255 (want {want} ±1)")
        if abs(got - want) > 1:
            misses.append(title)
    check("DV render_frame {sdr_version} of the hlg ramp = HD-14 (a)'s oracle ±1/255 every "
          "64th column; a white title 248.4/255, a 0.42 title 107.1/255 and HLG 0.50 125.7/255, "
          "each ±1; the PNG labelled as an SDR project's frame (BT.709), not HLG", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_di(client, state):
    """DI: the bt709 ramp in an HLG project drawn as its SDR version = the same ramp's SDR
    project render ±1/255 wherever SDR ≤ the knee's grey, and the shoulder oracle above."""
    misses, figures = [], []
    path = fixture("bt709")
    source = yuv_frames(path, W, H) if path else None
    sdr = Doc(client, "di-sdr", W, H)
    sdr.place(path) if sdr.ok and path else None
    plain, _ = render_opts(sdr, "di-sdr")
    state["di_sdr_closed"] = sdr.close()
    doc = hlg_doc(client, "di", [path])
    version, _ = render_opts(doc, "di", sdr_version=True)
    state["di_closed"] = doc.close()
    a = Frame(plain, W, H) if plain else None
    b = Frame(version, W, H) if version else None
    if a is None or b is None or not (a.ok and b.ok) or source is None:
        misses.append("a render or the fixture did not decode")
    else:
        below = above = 0.0
        counted = [0, 0]
        for x in range(0, W, 8):
            s = a.px(x, GREY_ROW)
            got = b.px(x, GREY_ROW)
            if max(s) <= SDR_KNEE_GREY:
                want, counted[0] = s, counted[0] + 1
            else:
                want, counted[1] = sdr_version(lift(source[0].rgb(x, GREY_ROW, "bt709"))), \
                    counted[1] + 1
            gap = max(abs(p - q) for p, q in zip(got, want))
            if max(s) <= SDR_KNEE_GREY:
                below = max(below, gap)
            else:
                above = max(above, gap)
            if gap > 1 / 255 and len(misses) < 12:
                misses.append(f"x={x} SDR {[round(v, 5) for v in s]} version "
                              f"{[round(v, 5) for v in got]} want {[round(v, 5) for v in want]}")
        figures.append(f"{counted[0]} columns at or below SDR {SDR_KNEE_GREY}: largest miss "
                       f"{below * 255:.3f}/255; {counted[1]} above, against the shoulder "
                       f"oracle: {above * 255:.3f}/255")
        if not all(counted):
            misses.append(f"columns below/above the knee {counted}")
    check("DI the bt709 ramp in an HLG project, sdr_version = its SDR project's render ±1/255 "
          "wherever SDR ≤ 0.9477, and the shoulder oracle above (every 8th column)", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_de(client, state):
    """DE: an h264 export (default) and a prores_422 {sdr} export of the hlg ramp, frame
    15, = render_frame {sdr_version} at 0.5 s (±2/255 decoded 8-bit, ±1/255 ProRes); a JPEG
    render_frame = the sdr_version PNG ±1/255, labelled as it."""
    misses, figures = [], []
    doc = hlg_doc(client, "de", [fixture("hlg")])
    png, _ = render_opts(doc, "de", sdr_version=True)
    jpeg, _ = render_opts(doc, "de-jpeg", format="jpeg")
    # The h264 export at the default dynamic range but a high rate (DE_H264_BITRATE): at the
    # encoder's own rate its chroma on the grey row reads 2.7/255 off at worst (measured on
    # the first run), which is compression, not the picture this row asks about.
    files = {"h264": export_as(doc, "de-h264", "h264", video_bitrate=DE_H264_BITRATE),
             "prores_422": export_as(doc, "de-prores", "prores_422", dynamic_range="sdr")}
    state["de_closed"] = doc.close()
    frame = Frame(png, W, H) if png else None
    if frame is None or not frame.ok:
        check("DE exports = the SDR version", False, f"no sdr_version render: {doc.why}")
        return
    for preset, bound in (("h264", 2 / 255), ("prores_422", 1 / 255)):
        out, got = files[preset]
        frames = yuv_frames(out, W, H, 16) if out else None
        if frames is None:
            misses.append(f"{preset}: {got.get('error', 'no frames')}")
            continue
        worst = 0.0
        for x in range(0, W, 8):
            e = frames[15].rgb(x, GREY_ROW, "bt709")
            r = frame.px(x, GREY_ROW)
            gap = max(abs(p - q) for p, q in zip(e, r))
            worst = max(worst, gap)
            if gap > bound and len(misses) < 12:
                misses.append(f"{preset} x={x} export {[round(v, 4) for v in e]} render "
                              f"{[round(v, 4) for v in r]}")
        figures.append(f"{preset} ({tags(stream(out))}) frame 15 against the render: largest "
                       f"miss {worst * 255:.3f}/255 (bound {bound * 255:.0f})")
    j = Frame(jpeg, W, H) if jpeg else None
    if j is None or not j.ok:
        misses.append("no JPEG")
    else:
        worst = max(max(abs(p - q) for p, q in zip(j.px(x, GREY_ROW), frame.px(x, GREY_ROW)))
                    for x in range(0, W, 8))
        label, want = sips_profile(jpeg), sips_profile(png)
        figures.append(f"JPEG against the PNG: largest miss {worst * 255:.3f}/255; profile "
                       f"{label!r} (the PNG's {want!r})")
        if worst > 1 / 255:
            misses.append("the JPEG's pixels")
        if label != want or "HLG" in label:
            misses.append("the JPEG's label")
    check("DE h264 (default) frame 15 = render_frame {sdr_version} at 0.5 s ±2/255 and "
          "prores_422 {sdr} frame 15 ±1/255 on the grey row every 8th column; a JPEG "
          "render_frame (no sdr_version) = the sdr_version PNG ±1/255, labelled as it",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_dr(client, state):
    """DR: the three refusals and the reader's, each by its sentence."""
    misses, figures = [], []
    hlg = hlg_doc(client, "dr-hlg", [fixture("hlg")])
    sdr = Doc(client, "dr-sdr", W, H)
    sdr.place(fixture("bt709")) if sdr.ok else None
    cases = [
        (hlg, "h264", "hlg", "h264 is 8-bit and writes the SDR version; export dynamic_range "
         "\"hlg\" as hevc_10bit, prores_422 or prores_4444"),
        (hlg, "gif", "pq", "gif is 8-bit and writes the SDR version; export dynamic_range "
         "\"pq\" as hevc_10bit, prores_422 or prores_4444"),
        (sdr, "hevc_10bit", "pq", "dynamic_range \"pq\" needs an HLG project; set_canvas "
         "output \"hlg\" first"),
        (hlg, "hevc_10bit", "bogus", "export dynamic_range must be \"hlg\", \"pq\" or "
         "\"sdr\", not \"bogus\""),
    ]
    for doc, preset, asked, sentence in cases:
        tag = f"dr-{preset}-{asked}"
        out, got = export_as(doc, tag, preset, dynamic_range=asked)
        figures.append(f"{preset} {{{asked}}}: {got.get('error', 'WRITTEN')}")
        if got["ok"] or out is not None or sentence not in got.get("error", ""):
            misses.append(f"{preset} {{{asked}}}")
    state["dr_hlg_closed"], state["dr_sdr_closed"] = hlg.close(), sdr.close()
    check("DR refused by sentence: h264 {hlg} and gif {pq} in an HLG project; hevc_10bit {pq} "
          "in an SDR project; {dynamic_range: \"bogus\"}", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_ds(client, state):
    """DS: an SDR project's render_frame {sdr_version: true} PNG and JPEG byte-identical to
    without; its {dynamic_range: "sdr"} h264 export's settings equal to without."""
    misses, figures = [], []
    doc = Doc(client, "ds", W, H)
    doc.place(fixture("bt709")) if doc.ok else None
    pairs = {}
    for fmt in ("png", "jpeg"):
        a, _ = render_opts(doc, f"ds-{fmt}-plain", format=fmt)
        b, _ = render_opts(doc, f"ds-{fmt}-sdr", format=fmt, sdr_version=True)
        pairs[fmt] = (a, b)
    plain_out, plain = export_as(doc, "ds-h264-plain", "h264")
    sdr_out, sdr = export_as(doc, "ds-h264-sdr", "h264", dynamic_range="sdr")
    state["ds_closed"] = doc.close()
    for fmt, (a, b) in pairs.items():
        same = a is not None and b is not None and a.read_bytes() == b.read_bytes()
        figures.append(f"{fmt}: {digest(a) if a else None} / {digest(b) if b else None}")
        if not same:
            misses.append(fmt)
    keep = lambda got: {k: v for k, v in reply(got).items() if k not in ("path", "bytes")}
    figures.append(f"h264 settings {keep(plain)} / {keep(sdr)}")
    if plain_out is None or sdr_out is None or keep(plain) != keep(sdr) or not keep(plain):
        misses.append("the h264 settings")
    check("DS an SDR project's render_frame {sdr_version: true} PNG and JPEG byte-identical to "
          "without; its {dynamic_range: \"sdr\"} h264 export's settings equal to without",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def editor_views(doc, tag):
    out = WORK / "snapshots" / f"{tag}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    got = reply(doc.call("snapshot_ui", window="editor", view="preview", path=str(out),
                         fill_preview=False))
    try:
        return json.loads(Path(got.get("layout_path", "")).read_text()).get("views", [])
    except (OSError, ValueError):
        return []


def sdr_tag_shown(views):
    tag = next((v for v in views if v.get("id") == "preview.sdrVersion"), None)
    return tag is not None and not tag.get("hidden", True) and tag.get("text") == "SDR Version"


def run_dm(client, state):
    """DM: View ▸ Show SDR Version on an HLG project shows its tag, leaves an un-optioned
    render_frame byte-identical, and performed again hides the tag."""
    misses, figures = [], []
    doc = hlg_doc(client, "dm", [fixture("hlg")])
    before, _ = render_opts(doc, "dm-before")
    on = doc.call("perform_menu_item", path=SDR_VERSION_MENU) if doc.ok else {"ok": False}
    shown = sdr_tag_shown(editor_views(doc, "dm-on"))
    during, _ = render_opts(doc, "dm-during")
    off = doc.call("perform_menu_item", path=SDR_VERSION_MENU) if doc.ok else {"ok": False}
    hidden = not sdr_tag_shown(editor_views(doc, "dm-off"))
    state["dm_closed"] = doc.close()
    same = before is not None and during is not None and before.read_bytes() == during.read_bytes()
    figures.append(f"menu on {on.get('error', 'ok')}, off {off.get('error', 'ok')}; tag shown "
                   f"{shown}, hidden after {hidden}; render {digest(before) if before else None}"
                   f" / {digest(during) if during else None}")
    if not (on["ok"] and off["ok"] and shown and hidden and same):
        misses.append("as above")
    check("DM View ▸ Show SDR Version on an HLG project: the editor's \"SDR Version\" tag shows, "
          "an un-optioned render_frame is byte-identical before and while it is on, and "
          "performing it again hides the tag", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def sheet_texts(client, doc, tag):
    """File ▸ Export… on `doc`, the sheet's visible texts and the title of the popup after
    "Dynamic Range:", then `cancel_sheet`. (texts, title, problem or None)."""
    menu = attempt(client, "perform_menu_item",
                   {"project": str(doc.path), "path": ["File", "Export…"]})
    if not menu["ok"]:
        return [], None, f"File ▸ Export…: {menu.get('error')}"
    try:
        out = WORK / "snapshots" / f"{tag}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        got = reply(attempt(client, "snapshot_ui",
                            {"window": "sheet", "project": str(doc.path), "path": str(out)}))
        views = json.loads(Path(got.get("layout_path", "")).read_text()).get("views", [])
    except (OSError, ValueError) as error:
        return [], None, f"snapshot_ui: {error}"
    finally:
        cancelled = attempt(client, "cancel_sheet", {"project": str(doc.path)})
    visible = [v for v in views if not v.get("hidden") and v.get("text")]
    at = next((v["i"] for v in visible if v["text"] == "Dynamic Range:"), None)
    title = next((v["text"] for v in visible
                  if at is not None and v.get("class") == "NSPopUpButton" and v["i"] > at), None)
    return [v["text"] for v in visible], title, \
        None if cancelled["ok"] else f"cancel_sheet: {cancelled.get('error')}"


def run_dx(binary):
    """DX: the export sheet on instances of its own, each pinned with `screens.py`'s PINS
    and the export choice: an HLG project's Dynamic Range row reads HDR (HLG) on
    hevc_10bit and SDR version on h264; an SDR project's sheet has no such row."""
    from screens import PINS
    misses, figures = [], []
    for preset, want in (("hevc_10bit", "HDR (HLG)"), ("h264", "SDR version")):
        folder = WORK / f"dx-{preset}"
        home = folder / "home"
        home.mkdir(parents=True)
        choice = json.dumps({"preset_id": preset}, separators=(",", ":"))
        arguments = []
        for key, value in PINS:
            arguments += [f"-{key}", f"<string>{choice}</string>"
                          if key == "FrameJobExportChoice" else value]
        log = folder / "instance.log"
        launched = mcp.launch(str(binary), arguments,
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(home)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                misses.append(f"{preset}: the instance did not listen")
                continue
            client = launched.client
            doc = hlg_doc(client, f"dx-{preset}-hlg", [fixture("hlg")])
            texts, title, problem = sheet_texts(client, doc, f"dx-{preset}-hlg")
            closed = doc.close()
            figures.append(f"{preset} pinned, HLG project: \"Dynamic Range:\" "
                           f"{'Dynamic Range:' in texts}, the popup {title!r}")
            if "Dynamic Range:" not in texts or title != want or problem or not closed:
                misses.append(f"{preset} HLG: {title!r} {problem or ''} closed {closed}")
            if preset == "hevc_10bit":
                sdr = Doc(client, f"dx-{preset}-sdr", W, H)
                sdr.place(fixture("bt709")) if sdr.ok else None
                texts, _, problem = sheet_texts(client, sdr, f"dx-{preset}-sdr")
                closed = sdr.close()
                format_shown = "HEVC 10-bit (MP4)" in texts
                figures.append(f"{preset} pinned, SDR project: \"Dynamic Range:\" "
                               f"{'Dynamic Range:' in texts}; the format shown {format_shown}")
                if "Dynamic Range:" in texts or not texts or problem or not closed:
                    misses.append(f"{preset} SDR: {problem or ''} closed {closed}")
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
        found = complaints(log)
        if found:
            misses.append(f"{preset}: complaints {found[:2]}")
    check("DX the export sheet (own instances, PINS and FrameJobExportChoice pinned): in an HLG "
          "project \"Dynamic Range:\" with the popup on HDR (HLG) when pinned to hevc_10bit and "
          "on SDR version when pinned to h264; no \"Dynamic Range:\" in an SDR project",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def run_to(binary):
    """TO (`--measure`): TH's 4K fixture placed twice (8 s) as an HLG project, exported
    prores_422 at hlg and at sdr, each on an instance of its own: the frame times printed
    against C0's 0.21 ms (REASONED); scored only on both files' tags."""
    figures, misses = [], []
    path = fixture("bt709_4k")
    averages_by = {}
    for asked in ("hlg", "sdr"):
        if path is None:
            misses.append(f"bt709_4k refused: {REFUSED.get('bt709_4k')}")
            break
        log = WORK / f"to-{asked}-instance.log"
        before = host_state()
        launched = mcp.launch(str(binary), ["-FrameJobCompositorTiming", "YES"],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        lines, out = [], None
        try:
            if launched.client is None:
                misses.append(f"{asked}: the instance did not listen")
                continue
            doc = Doc(launched.client, f"to-{asked}-project", 3840, 2160)
            doc.place(path, 0)
            doc.place(path, 4 * SEC)
            doc.call("set_canvas", output="hlg")
            start = log.stat().st_size if log.exists() else 0
            out, _ = export_as(doc, f"to-{asked}", "prores_422", dynamic_range=asked)
            time.sleep(1)
            with open(log, errors="replace") as handle:
                handle.seek(start)
                lines = TIMING.findall(handle.read())
            doc.close()
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
        averages = [float(a) for a, _, _ in lines]
        averages_by[asked] = averages
        read = tags(stream(out)) if out else None
        figures.append(f"{asked}: {read}; {len(lines)} timing lines, average ms {averages}, "
                       f"worst {[float(w) for _, w, _ in lines]}; host before {before}, after "
                       f"{host_state()}")
        if read != PICTURE_TAGS[asked]:
            misses.append(f"{asked}: {read}")
    if all(averages_by.get(k) for k in ("hlg", "sdr")):
        mean = {k: sum(v) / len(v) for k, v in averages_by.items()}
        figures.append(f"mean average hlg {mean['hlg']:.3f} ms, sdr {mean['sdr']:.3f} ms: the "
                       f"output pass {mean['sdr'] - mean['hlg']:+.3f} ms per 4K frame (C0's copy "
                       f"0.21 ms, REASONED; recorded, not scored)")
    check("TO the 4K HLG project's prores_422 at hlg and at sdr: tagged bt2020nc/arib-std-b67/"
          "bt2020 and bt709 ×3; the output pass's frame time recorded", not misses,
          f"{misses or 'as wanted'}\n       " + "\n       ".join(figures))


def run_th(binary):
    """TH (`--measure`): TI's 4K BT.709 twin on two tracks (the upper at scale 0.5) and a
    title, 8 s, exported prores_422 as an SDR project and as an HLG project, each on its
    own instance: 240 input passes per 120 frames in HLG and 0 in SDR (scored), the
    averages against PR-1's 8 ms (recorded)."""
    figures, misses = [], []
    path = fixture("bt709_4k")
    for output, want in (("sdr", 0), ("hlg", 240)):
        if path is None:
            misses.append(f"bt709_4k refused: {REFUSED.get('bt709_4k')}")
            break
        log = WORK / f"th-{output}.log"
        before = host_state()
        wall = None
        launched = mcp.launch(str(binary), ["-FrameJobCompositorTiming", "YES"],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        lines, out = [], None
        try:
            if launched.client is None:
                misses.append(f"{output}: the instance did not listen")
                continue
            doc = Doc(launched.client, f"th-{output}", 3840, 2160)
            doc.place(path, 0)
            doc.place(path, 4 * SEC)
            added = doc.call("add_track")
            tracks = doc.project().get("tracks") or [] if added["ok"] else []
            upper = tracks[-1]["id"] if len(tracks) == 2 else None
            for at in (0, 4 * SEC):
                made = doc.place_tool("add_clip", track=upper, media=doc._media.get(path),
                                      at=at) if upper else None
                if made:
                    doc.call("set_video", clips=[made], patch={"scale": 0.5})
            doc.call("add_track")
            tracks = doc.project().get("tracks") or []
            doc.place_tool("add_text_clip", track=tracks[-1]["id"], at=0, duration=8 * SEC,
                           text={"content": "Frame Job", "size": 160})
            if output == "hlg":
                doc.call("set_canvas", output="hlg")
            start = log.stat().st_size if log.exists() else 0
            started = time.monotonic()
            out = doc.export(f"th-{output}") if doc.ok else None
            wall = time.monotonic() - started
            time.sleep(1)
            with open(log, errors="replace") as handle:
                handle.seek(start)
                lines = TIMING.findall(handle.read())
            doc.close()
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
        found = [l for l in open(log, errors="replace") if "Frame Job: " in l]
        passes = [None if p == "" else int(p) for _, _, p in lines]
        averages = [float(a) for a, _, _ in lines]
        worst = [float(w) for _, w, _ in lines]
        figures.append(f"{output}: {len(lines)} lines, passes {passes}, average ms {averages}, "
                       f"worst {worst}; export wall s "
                       f"{'%.2f' % wall if wall is not None and out else None} (recorded, not "
                       f"scored); host before {before}; after {host_state()}")
        if averages:
            figures.append(f"{output} mean average {sum(averages) / len(averages):.3f} ms "
                           f"(PR-1's 7.38–7.585 ms; the budget 8 ms)")
        if out is None or len(lines) < 2 or any(p != want for p in passes) or found:
            misses.append(f"{output}: export {'ok' if out else 'missing'}, lines {len(lines)}, "
                          f"passes {passes}, complaints {found[:2]}")
    check("TH the 4K BT.709 twin on two tracks (the upper at scale 0.5) and a title: 240 input "
          "passes per 120 frames as an HLG project, 0 as an SDR one (≥ 2 lines each); the frame "
          "times recorded against PR-1's 8 ms", not misses,
          f"{misses or 'as wanted'}\n       " + "\n       ".join(figures))


# ---- TI -------------------------------------------------------------------------

def host_state():
    power = bounded.run(["pmset", "-g"], 30)["stdout"]
    mode = re.search(r"powermode\s+(\d+)", power)
    source = bounded.run(["pmset", "-g", "batt"], 30)["stdout"].splitlines()[:1]
    load = bounded.run(["sysctl", "-n", "vm.loadavg"], 30)["stdout"].strip()
    return f"powermode {mode.group(1) if mode else '?'}; {' '.join(source)}; loadavg {load}"


def run_ti(binary):
    figures, misses = [], []
    for name, want in (("hlg4k", 120), ("bt709_4k", 0)):
        path = fixture(name)
        if path is None:
            misses.append(f"{name} refused: {REFUSED.get(name)}")
            continue
        log = WORK / f"ti-{name}.log"
        before = host_state()
        wall = None
        launched = mcp.launch(str(binary), ["-FrameJobCompositorTiming", "YES"],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                misses.append(f"{name}: the instance did not listen")
                continue
            doc = Doc(launched.client, f"ti-{name}", 3840, 2160)
            doc.place(path, 0)
            doc.place(path, 4 * SEC)
            start = log.stat().st_size if log.exists() else 0
            started = time.monotonic()
            out = doc.export(f"ti-{name}") if doc.ok else None
            wall = time.monotonic() - started
            time.sleep(1)
            with open(log, errors="replace") as handle:
                handle.seek(start)
                lines = TIMING.findall(handle.read())
            doc.close()
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
        found = [l for l in open(log, errors="replace") if "Frame Job: " in l]
        passes = [None if p == "" else int(p) for _, _, p in lines]
        averages = [float(a) for a, _, _ in lines]
        worst = [float(w) for _, w, _ in lines]
        figures.append(f"{name}: {len(lines)} lines, passes {passes}, average ms "
                       f"{averages}, worst {worst}; export wall s "
                       f"{'%.2f' % wall if wall is not None and out else None} (recorded, not "
                       f"scored); host before {before}; after {host_state()}")
        if out is None or len(lines) < 2 or any(p != want for p in passes) or found:
            misses.append(f"{name}: export {'ok' if out else 'missing'}, lines {len(lines)}, "
                          f"passes {passes}, complaints {found[:2]}")
        else:
            figures.append(f"{name} mean average {sum(averages) / len(averages):.3f} ms")
    check("TI the 4K HLG twin's timing lines report 120 input passes per 120 frames and the "
          "BT.709 twin's 0 (≥ 2 lines each); the averages printed", not misses,
          f"{misses or 'as wanted'}\n       " + "\n       ".join(figures))


# ---- P1–P4 ----------------------------------------------------------------------

def run_math_probe(sources):
    if not MATH_PROBE.exists():
        for name in sorted(P_ROWS & selected):
            check(f"{name} hdr_probe.swift exists", False, f"no {MATH_PROBE}")
        return
    binary, why = build_probe(MATH_PROBE, sources, "hdr_probe")
    if binary is None:
        for name in sorted(P_ROWS & selected):
            check(f"{name} the probe builds over app/Sources", False, why)
        return
    request, answer = WORK / "math.json", WORK / "math-answer.json"
    answer.unlink(missing_ok=True)
    shader = Path(sources).parent / "Resources/Shaders/Compositor.metal"
    request.write_text(json.dumps(math_request(shader)))
    ran = bounded.run([str(binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(P_ROWS & selected):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], row.get("detail", ""))


def half(value):
    """`value` rounded to IEEE half, as an `rgba16Float` texel stores it."""
    return struct.unpack("<e", struct.pack("<e", value))[0]


def math_request(shader):
    """The probe's inputs: the shader, the derived matrices, the selector's
    cases (names the probe maps to Core Video's and Core Media's constants),
    and the oracle's answers for P3: grey steps and 512 seeded triples per
    case, each input rounded to half first (the source texture's own values)."""
    cases = [  # (transfer, primaries, log, want, startsConversion)
        ("HLG", "2020", None, "hlg(bt2020)", True),
        ("HLG", "P3D65", None, "hlg(p3D65)", True),
        ("HLG", "709", None, "hlg(bt709)", True),
        ("HLG", None, None, "hlg(bt2020)", True),
        ("HLG", "DCIP3", None, "hlg(bt2020)", True),
        ("PQ", "2020", None, "pq(bt2020)", True),
        ("PQ", "P3D65", None, "pq(p3D65)", True),
        ("PQ", None, None, "pq(bt2020)", True),
        ("709", "2020", None, "sdrWide(bt2020)", True),
        ("2020", "2020", None, "sdrWide(bt2020)", True),
        ("709", "P3D65", None, "sdrWide(p3D65)", True),
        ("709", "DCIP3", None, "nil", None),
        ("709", "709", None, "nil", None),
        ("sRGB", "709", None, "srgb(bt709)", False),
        ("sRGB", None, None, "srgb(bt709)", False),
        ("sRGB", "P3D65", None, "srgb(p3D65)", True),
        ("sRGB", "2020", None, "srgb(bt2020)", True),
        ("sRGB", "DCIP3", None, "srgb(bt709)", False),
        (None, None, None, "nil", None),
        (None, "2020", None, "nil", None),
        (None, "2020", "AppleLog", "nil", None),
        ("HLG", "2020", "AppleLog", "nil", None),
        ("240M", "2020", None, "nil", None),
    ]
    steps = [i / 32 for i in range(33)] + [0.453, 0.4999, 0.5001, 1.1]
    seed = 0x5eed_0f15
    triples = []
    for _ in range(512):
        triple = []
        for _ in range(3):
            seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
            triple.append((seed >> 11) / 2 ** 53 * 1.1 - 0.02)
        triples.append(triple)
    p3 = []
    for kind, code, primaries in (("hlg", 1, "bt2020"), ("pq", 2, "bt2020"),
                                  ("sdr", 3, "bt2020"), ("sdr", 3, "p3d65"),
                                  ("hlg", 1, "p3d65"), ("pq", 2, "bt709"),
                                  ("srgb", 4, "bt709"), ("srgb", 4, "p3d65")):
        grey = steps + ([0.02, 0.04] if kind == "srgb" else [])
        inputs = [[half(c) for c in rgb] for rgb in [[g, g, g] for g in grey] + triples]
        p3.append({"kind": kind, "code": code, "primaries": primaries, "inputs": inputs,
                   "outputs": [convert(kind, primaries, rgb)[0] for rgb in inputs]})
    return {"shader": str(shader), "cases": cases,
            "matrices": {name: to709(name) for name in PRIMARIES},
            "p3": p3,
            "constants": {"hlgSystemGamma": HLG_GAMMA, "hlgGain": HLG_GAIN,
                          "shoulderKnee": KNEE, "hlgWhite": HLG_WHITE,
                          "pqReferenceWhite": PQ_REFERENCE, "pqWhite": PQ_WHITE,
                          "displayGamma": DISPLAY_GAMMA, "coreMedia709Gamma": CM709_GAMMA}}


# ---- hdr H-4 (#277, spec §11 HD-8, HD-15): the scopes -----------------------------

def half_away(v):
    """round() as Metal and Swift's `.rounded()` do: halves away from zero."""
    return int(v + 0.5) if v >= 0 else -int(-v + 0.5)


def level8(v):
    """GR-5's level of a saturated value: round(255·v), 0…255."""
    return min(255, max(0, half_away(255 * v)))


def sat(rgb):
    return [min(max(c, 0.0), 1.0) for c in rgb]


def luma(rgb, weights=LUMA2020):
    return sum(w * c for w, c in zip(weights, rgb))


def chroma_of(rgb, matrix="bt2020nc"):
    """Cb, Cr of an R'G'B' on `matrix`'s weights (the scopes' formula)."""
    if matrix == "bt2020nc":
        y = luma(rgb, LUMA2020)
        return (rgb[2] - y) / 1.8814, (rgb[0] - y) / 1.4746
    y = luma(rgb, LUMA709)
    return (rgb[2] - y) / 1.8556, (rgb[0] - y) / 1.5748


def chroma_bins(rgb, matrix="bt2020nc", zoom=1):
    """The vectorscope's bins (cb, cr) at `zoom` (GR-31), None off the plot."""
    raw = [128 + half_away(255 * zoom * c) for c in chroma_of(rgb, matrix)]
    if zoom == 1:
        return tuple(min(255, max(0, v)) for v in raw)
    return tuple(raw) if all(0 <= v <= 255 for v in raw) else None


def bar_codes(rgb):
    """BT.2020-NCL limited-range 10-bit codes (Y, Cb, Cr) of an R'G'B'."""
    y = luma(rgb, LUMA2020)
    return (half_away(64 + 876 * y), half_away(512 + 896 * (rgb[2] - y) / 1.8814),
            half_away(512 + 896 * (rgb[0] - y) / 1.4746))


def hlg_bars():
    """SV's fixture: 960×128, 1 s, ProRes 422 HQ, the six bars' BT.2020 codes, re-tagged
    HLG by stream copy as `hlg` is."""
    out = MEDIA / "hlg_bars.mov"
    if not out.exists():
        codes = [bar_codes(rgb) for _, rgb in HLG_BARS]

        def expr(i):  # geq's X is the plane's own: 4:2:2 chroma is half as wide
            width = BAR_W if i == 0 else BAR_W // 2
            e = str(codes[-1][i])
            for k in range(len(codes) - 2, -1, -1):
                e = f"if(lt(X,{(k + 1) * width}),{codes[k][i]},{e})"
            return e
        lavfi = (f"color=c=black:size={BARS_W}x{BARS_H}:rate=30:duration=1,format=yuv422p10le,"
                 f"geq=lum='{expr(0)}':cb='{expr(1)}':cr='{expr(2)}'")
        raw = ffmpeg_make(MEDIA / "hlg_bars_raw.mov", [
            "-f", "lavfi", "-i", lavfi, "-c:v", "prores_ks", "-profile:v", "3",
            "-pix_fmt", "yuv422p10le"])
        if raw is None:
            REFUSED["hlg_bars"] = "hlg_bars_raw.mov was not made"
            return None
        primaries, transfer, matrix = RETAGS["hlg"]
        ffmpeg_make(out, ["-i", str(raw), "-c", "copy", "-bsf:v",
                          f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:"
                          f"colorspace={matrix}", "-color_primaries", primaries, "-color_trc",
                          transfer, "-colorspace", matrix, "-movflags", "+write_colr"], 120)
    return checked("hlg_bars", out if out.exists() else None, {
        "codec_name": "prores", "width": BARS_W, "height": BARS_H, "color_primaries": "bt2020",
        "color_transfer": "arib-std-b67", "color_space": "bt2020nc"})


# A waveform column bin of the 1024 px ramp is 4 px wide, so a level holding at most 8 of its
# pixels lies on at most two rows. The render's row 64, where the chroma half begins, is off
# every oracle level of its column (the decoder's chroma upsampling mixes the halves there;
# SW prints the rows, row 64 alone in H-4's runs): SW and SD hold the oracle to the levels
# holding more than 8 px, and every level to the PNG's own pixels.
SEAM_PIXELS = 8


def wave_columns(counts, more_than=0):
    """A waveform JSON's (or a parade channel's) 256 columns as sets of the levels holding
    more than `more_than` pixels."""
    return [{level for level, n in enumerate(column) if n > more_than} for column in counts or []]


def apart(a, b):
    """The largest distance from a level in `a` to the nearest in `b` (both ways)."""
    if not a and not b:
        return 0
    if not a or not b:
        return 999
    return max(max(min(abs(x - y) for y in b) for x in a),
               max(min(abs(x - y) for y in a) for x in b))


def oracle_columns(source, matrix, oracle, plane):
    """Per waveform column bin (4 px of the 1024 px ramp), each grey- and chroma-row
    pixel's oracle envelope (lo, hi): the least and the greatest level of `plane(rgb)` of
    the saturated oracle R'G'B' at its Y', Cb and Cr codes each moved by −1, 0, +1 (H-2's
    envelope: the lift's toe spreads a code over several levels near black)."""
    cols = []
    for c in range(256):
        ranges = []
        for x in range(c * W // 256, (c + 1) * W // 256):
            for row in (GREY_ROW, CHROMA_ROW):
                luma_code, cb, cr = source.codes(x, row)
                outs = [level8(plane(sat(oracle(rgb_of(luma_code + a, cb + b, cr + d, matrix)))))
                        for a in (-1, 0, 1) for b in (-1, 0, 1) for d in (-1, 0, 1)]
                ranges.append((min(outs), max(outs)))
        cols.append(ranges)
    return cols


def fits(levels, ranges):
    """Both ways within ±1: every level inside some pixel's envelope widened by 1, and every
    pixel's widened envelope holding some level."""
    def inside(level, lo, hi):
        return lo - 1 <= level <= hi + 1
    return all(any(inside(v, lo, hi) for lo, hi in ranges) for v in levels) and all(
        any(inside(v, lo, hi) for v in levels) for lo, hi in ranges)


def png_columns(frame, width, height, plane):
    """Per waveform column bin, `plane(rgb)`'s levels over every pixel of the PNG."""
    cols = [set() for _ in range(256)]
    for y in range(height):
        for x in range(width):
            cols[x * 256 // width].add(level8(plane(frame.px(x, y))))
    return cols


def run_sw(client, state):
    """SW: HLG projects of the hlg ramp (identity) and the bt709 ramp (the lift): the
    waveform's columns on BT.2020 luma, the parade's channels, at the oracle ±1 and at the
    PNG's own pixels ±1; the histogram's planes the column sums exactly."""
    misses, figures = [], []
    for name, matrix, oracle in (("hlg", "bt2020nc", lambda rgb: rgb),
                                 ("bt709", "bt709", lift)):
        path = fixture(name)
        source = yuv_frames(path, W, H) if path else None
        doc = hlg_doc(client, f"sw-{name}", [path])
        png, files, text = scope_render(doc, f"sw-{name}", waveform=True, parade=True,
                                        histogram=True)
        state[f"sw_{name}_closed"] = doc.close()
        wave, par, hist = (scope_json(files, k) for k in ("waveform", "parade", "histogram"))
        frame = Frame(png, W, H) if png else None
        if source is None or None in (wave, par, hist) or frame is None or not frame.ok:
            misses.append(f"{name}: {doc.why or text[-200:]}")
            continue
        src = source[0]
        got = wave_columns(wave.get("counts"), SEAM_PIXELS)
        every = wave_columns(wave.get("counts"))
        want = oracle_columns(src, matrix, oracle, luma)
        seen = png_columns(frame, W, H, luma)
        off = [c for c in range(256) if len(got) != 256 or not fits(got[c], want[c])]
        drawn = max(apart(every[c], seen[c]) for c in range(256)) if len(every) == 256 else 999
        seam = sum(len(every[c] - got[c]) for c in range(len(every)))
        # The rows whose PNG level is no oracle level of its column ±1: the seam's.
        seam_rows = sorted({y for y in range(H) for x in range(0, W, 4)
                            if not any(lo - 1 <= level8(luma(frame.px(x, y))) <= hi + 1
                                       for lo, hi in want[x * 256 // W])})
        if len(got) != 256 or off:
            misses.append(f"{name} waveform: {len(off)} columns off the oracle ±1, e.g. "
                          f"{[(c, sorted(got[c]), sorted(want[c])) for c in off[:2]]}")
        if drawn > 1:
            misses.append(f"{name} waveform: off the PNG's own pixels by {drawn} levels")
        if not set(seam_rows) <= {GREY_ROW * 2 - 1, GREY_ROW * 2}:
            misses.append(f"{name}: PNG rows off the oracle beyond the seam: {seam_rows}")
        channels = (par.get("counts") or {})
        p_off, p_eg = 0, []
        for i, key in enumerate(("red", "green", "blue")):
            pick = (lambda k: lambda rgb: rgb[k])(i)
            have = wave_columns(channels.get(key), SEAM_PIXELS)
            ref = oracle_columns(src, matrix, oracle, pick)
            bad = [c for c in range(256) if len(have) != 256 or not fits(have[c], ref[c])]
            p_off += len(bad)
            p_eg += [(key, c, sorted(have[c]), sorted(ref[c])) for c in bad[:2]]
        if p_off:
            misses.append(f"{name} parade: {p_off} channel columns off the oracle ±1, e.g. "
                          f"{p_eg[:3]}")
        sums = [sum(column[level] for column in wave.get("counts") or []) for level in range(256)]
        if hist.get("luma") != sums:
            misses.append(f"{name} histogram: luma ≠ the waveform's column sums")
        for key in ("red", "green", "blue"):
            col_sums = [sum(column[level] for column in channels.get(key) or [])
                        for level in range(256)]
            if hist.get(key) != col_sums:
                misses.append(f"{name} histogram: {key} ≠ the parade's column sums")
        parted = sum(1 for c in range(256)
                     if abs(level8(luma(sat(oracle(src.rgb(c * 4, CHROMA_ROW, matrix))), LUMA709))
                            - level8(luma(sat(oracle(src.rgb(c * 4, CHROMA_ROW, matrix))))))
                     > 2)
        if parted < 50:
            misses.append(f"CONTROL {name}: only {parted} chroma-row columns part Rec. 709 from "
                          f"BT.2020 by > 2 levels")
        figures.append(f"{name}: waveform {len(off)} columns off the oracle, {seam} seam levels "
                       f"(≤ {SEAM_PIXELS} px) left to the PNG (its rows off the oracle: "
                       f"{seam_rows}), worst against the PNG {drawn}; "
                       f"parade {p_off} off; {parted} chroma-row columns part Rec. 709 from "
                       f"BT.2020 by > 2 levels (CONTROL)")
    check("SW HLG projects of the hlg ramp (identity) and the bt709 ramp (the lift): every "
          "waveform column's occupied levels (holding > 8 px; the grey/chroma seam's left to "
          "the PNG) within ±1 of round(255·Y′₂₀₂₀) of the oracle at its codes ±1, and every "
          "level within ±1 of "
          "the PNG's own pixels; the parade's channels within ±1 of theirs; the "
          "histogram's planes the waveform's and the parade's column sums exactly",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def vector_counts(js):
    """A vectorscope JSON's occupied bins: {(cb, cr): count}."""
    return {(cb, cr): n for cr, row in enumerate(js.get("counts") or [])
            for cb, n in enumerate(row) if n}


def skin_hlg():
    cb, cr = chroma_of(lift(list(SKIN_PATCH)))
    return math.degrees(math.atan2(cr, cb))


def run_sv(client, state):
    """SV: the hlg_bars fixture in an HLG project: the vectorscope's six fullest bins at
    this script's BT.2020 bins of the bars' codes ±1; its targets BT.2111's 75 % bars
    exactly, null at ×2 off the plot; the skin line the lifted patch's."""
    misses, figures = [], []
    path = fixture("hlg_bars")
    source = yuv_frames(path, BARS_W, BARS_H) if path else None
    doc = hlg_doc(client, "sv", [path], BARS_W, BARS_H)
    png, files, text = scope_render(doc, "sv", vectorscope=True)
    _, zoomed, ztext = scope_render(doc, "sv-x2", vectorscope=True, vectorscope_zoom=2)
    state["sv_closed"] = doc.close()
    js, js2 = scope_json(files, "vectorscope"), scope_json(zoomed, "vectorscope")
    if source is None or js is None or js2 is None:
        check("SV the hlg_bars vectorscope", False,
              f"{doc.why or REFUSED.get('hlg_bars') or text[-200:] or ztext[-200:]}")
        return
    bars = {}
    parted = 0
    for k, (name, nominal) in enumerate(HLG_BARS):
        rgb = sat(rgb_of(*source[0].codes(k * BAR_W + BAR_W // 2, BARS_H // 2), "bt2020nc"))
        bars[name] = chroma_bins(rgb)
        b709 = chroma_bins(rgb, "bt709")
        parted += max(abs(a - b) for a, b in zip(bars[name], b709)) >= 2
    counts = vector_counts(js)
    fullest = sorted((n, bins) for bins, n in counts.items() if bins != (128, 128))[::-1][:6]
    free = dict(bars)
    for n, bins in fullest:
        match = next((name for name, at in free.items()
                      if max(abs(a - b) for a, b in zip(at, bins)) <= 1), None)
        if match is None:
            misses.append(f"bin {bins} ({n} px) is no bar's ±1 (bars {free})")
        else:
            free.pop(match)
    figures.append(f"fullest {[(b, n) for n, b in fullest]}; the bars' BT.2020 bins {bars}")
    for name, nominal in HLG_BARS:
        want = list(chroma_bins(list(nominal)))
        if (js.get("targets") or {}).get(name) != want:
            misses.append(f"target {name} {(js.get('targets') or {}).get(name)} ≠ {want}")
        at2 = chroma_bins(list(nominal), zoom=2)
        got2 = (js2.get("targets") or {}).get(name)
        if got2 != (list(at2) if at2 else None):
            misses.append(f"×2 target {name} {got2} ≠ {at2}")
    angle, want_angle = js.get("skin_line_degrees"), skin_hlg()
    if not isinstance(angle, (int, float)) or abs(angle - want_angle) > 0.05:
        misses.append(f"skin line {angle} ≠ {want_angle:.4f}")
    if parted < 4:
        misses.append(f"CONTROL: only {parted} bars part Rec. 709 from BT.2020 by ≥ 2 bins")
    figures.append(f"skin line {angle} (want {want_angle:.4f}); {parted} bars part Rec. 709 "
                   f"from BT.2020 by ≥ 2 bins (CONTROL)")
    check("SV hlg_bars (BT.2111's 75 % bars as BT.2020 HLG codes) in an HLG project: the six "
          "fullest non-centre vectorscope bins each within ±1 of one bar's BT.2020 bin; the "
          "JSON's targets this script's bins, null at ×2 where off the plot; the skin line the "
          "lifted patch through BT.2020 ±0.05°", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


SS_SENTENCES = {
    "waveform": r"Waveform \(HLG signal; reference white at 75 %, 203 cd/m², and 100 % at "
                r"1,000 cd/m²\): highlights clipped in \d+\.\d % of pixels, shadows in \d+\.\d "
                r"%; its 256 × 256 counts are in \S+\.waveform\.json\.",
    "parade": r"Parade \(HLG signal\): red clips high in \d+\.\d % of pixels and low in "
              r"\d+\.\d %, green in \d+\.\d % and \d+\.\d %, blue in \d+\.\d % and \d+\.\d %; "
              r"its 3 × 256 × 256 counts are in \S+\.parade\.json\.",
    "vectorscope": r"Vectorscope \(Rec\. 2020 Cb and Cr of the HLG values\): \d+\.\d % of "
                   r"pixels are neutral; its 256 × 256 counts are in \S+\.vectorscope\.json\.",
    "histogram": r"Histogram \(HLG signal\): highlights clipped in \d+\.\d % of pixels, "
                 r"shadows in \d+\.\d % \(by Y′, BT\.2020 weights\); its R′, G′, B′ and Y′ "
                 r"counts per 256 levels are in \S+\.histogram\.json\.",
    "zoomed": r"Vectorscope at ×2 \(Rec\. 2020 Cb and Cr of the HLG values\): \d+\.\d % of "
              r"pixels are neutral and \d+\.\d % lie off the plot; its 256 × 256 counts are "
              r"in \S+\.vectorscope\.json\.",
}


def want_scale():
    """HD-15 (h)'s scale, recomputed here."""
    return {"unit": "cd/m²", "reference_white_percent": 75, "clip_percent": 100,
            "ticks": [{"percent": p, "level": half_away(255 * p / 100),
                       "nits": round(1000 * hlg_inverse(p / 100) ** 1.2, 1)}
                      for p in (0, 25, 50, 75, 100)]}


def same_scale(got, want):
    if not isinstance(got, dict) or set(got) != set(want):
        return False
    ticks = got.get("ticks") or []
    return all(got[k] == want[k] for k in want if k != "ticks") and len(ticks) == 5 and all(
        set(a) == set(b) and all(abs(a[k] - b[k]) < 1e-9 for k in b)
        for a, b in zip(ticks, want["ticks"]))


def run_ss(client, state):
    """SS: an HLG project's scope JSON names its signal and scale, the vectorscope its
    matrix; the four sentences (and the zoomed one) read as HD-15 (h) writes them."""
    misses = []
    doc = hlg_doc(client, "ss", [fixture("hlg")])
    _, files, text = scope_render(doc, "ss", **SCOPES_ALL)
    _, zoomed, ztext = scope_render(doc, "ss-x2", vectorscope=True, vectorscope_zoom=2)
    state["ss_closed"] = doc.close()
    scale = want_scale()
    for kind in SCOPE_KINDS:
        js = scope_json(files, kind)
        if js is None:
            misses.append(f"{kind}: no JSON ({text[-200:]})")
            continue
        if js.get("signal") != "hlg":
            misses.append(f"{kind} signal {js.get('signal')!r}")
        if kind == "vectorscope":
            if js.get("matrix") != "Rec. 2020" or "scale" in js:
                misses.append(f"vectorscope matrix {js.get('matrix')!r}, scale {'scale' in js}")
        elif not same_scale(js.get("scale"), scale):
            misses.append(f"{kind} scale {js.get('scale')}")
        if not re.search(SS_SENTENCES[kind], text):
            misses.append(f"the {kind} sentence: {text[:600]!r}")
    js2 = scope_json(zoomed, "vectorscope") or {}
    if js2.get("signal") != "hlg" or js2.get("matrix") != "Rec. 2020" \
            or not re.search(SS_SENTENCES["zoomed"], ztext):
        misses.append(f"the zoomed vectorscope: {js2.get('signal')}, {js2.get('matrix')}, "
                      f"{ztext[:400]!r}")
    check("SS an HLG project's waveform, parade and histogram JSON carry signal \"hlg\" and "
          "HD-15's scale (ticks 0/25/50/75/100 % at levels 0/64/128/191/255 and their cd/m², "
          "recomputed here; reference white 75, clip 100); the vectorscope's signal \"hlg\" "
          "and matrix \"Rec. 2020\"; the four sentences and the ×2 one as HD-15 (h) writes "
          "them", not misses, f"failed {misses or 'none'}; scale wanted {scale}")


def run_sd(client, state):
    """SD: the SDR version's scopes (`sdr_version`, a JPEG) are an SDR project's; Show
    Ungraded's (`ungraded`) stay HLG."""
    misses, figures = [], []
    path = fixture("hlg")
    source = yuv_frames(path, W, H) if path else None
    doc = hlg_doc(client, "sd", [path])
    png, files, text = scope_render(doc, "sd-sdr", sdr_version=True, waveform=True,
                                    vectorscope=True)
    _, jfiles, jtext = scope_render(doc, "sd-jpeg", format="jpeg", waveform=True,
                                    vectorscope=True)
    clip = (doc.project().get("clips") or [{}])[0].get("id") if doc.ok else None
    exposed = doc.call("set_video", clips=[clip], patch={"color": {"exposure": 1}}) if clip \
        else {"ok": False}
    _, ufiles, utext = scope_render(doc, "sd-ungraded", ungraded=True, waveform=True) \
        if exposed["ok"] else (None, {}, exposed.get("error"))
    _, efiles, _ = scope_render(doc, "sd-exposed", waveform=True) if exposed["ok"] \
        else (None, {}, None)
    state["sd_closed"] = doc.close()
    wave, vec = scope_json(files, "waveform"), scope_json(files, "vectorscope")
    frame = Frame(png, W, H) if png else None
    if wave is None or vec is None or frame is None or not frame.ok:
        misses.append(f"sdr_version: {doc.why or text[-200:]}")
    else:
        if {"signal", "scale"} & (set(wave) | set(vec)) or vec.get("matrix") != "Rec. 709":
            misses.append(f"sdr_version keys {sorted(set(wave) | set(vec))}, matrix "
                          f"{vec.get('matrix')!r}")
        seen = png_columns(frame, W, H, lambda rgb: luma(rgb, LUMA709))
        got = wave_columns(wave.get("counts"))
        worst = max(apart(got[c], seen[c]) for c in range(256)) if len(got) == 256 else 999
        figures.append(f"sdr_version's waveform against Rec. 709 levels of its PNG: worst "
                       f"{worst} levels")
        if worst > 1:
            misses.append(f"sdr_version's waveform off the PNG's Rec. 709 levels by {worst}")
        if "Waveform: highlights" not in text or "(Rec. 709 Cb and Cr of the encoded values)" \
                not in text:
            misses.append(f"sdr_version's sentences {text[:300]!r}")
    jw, jv = scope_json(jfiles, "waveform"), scope_json(jfiles, "vectorscope")
    if jw is None or jv is None or "signal" in jw or "signal" in jv:
        misses.append(f"the JPEG's scopes: {None if jw is None else sorted(jw)} {jtext[-200:]}")
    uw, ew = scope_json(ufiles, "waveform"), scope_json(efiles, "waveform")
    if uw is None or source is None:
        misses.append(f"ungraded: {utext}")
    else:
        got = wave_columns(uw.get("counts"), SEAM_PIXELS)
        want = oracle_columns(source[0], "bt2020nc", lambda rgb: rgb, luma)
        off = [c for c in range(256) if len(got) != 256 or not fits(got[c], want[c])]
        moved = ew is not None and ew.get("counts") != uw.get("counts")
        figures.append(f"ungraded: signal {uw.get('signal')!r}, {len(off)} columns off SW's hlg "
                       f"oracle; the exposed render's waveform differs {moved}")
        if uw.get("signal") != "hlg" or off or not moved:
            misses.append(f"ungraded: signal {uw.get('signal')!r}, {len(off)} columns off, the "
                          f"exposure moved the graded waveform {moved}")
    check("SD in an HLG project: {sdr_version, waveform, vectorscope} carries no signal or "
          "scale, the matrix \"Rec. 709\", the waveform within ±1 of Rec. 709 levels of its PNG; "
          "a JPEG frame's scopes no signal; {ungraded, waveform} with exposure +1 on the clip "
          "signal \"hlg\" at SW's hlg oracle ±1", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def panel_state(views):
    """The scopes panel as `snapshot_ui` dumps it: the two captions and the top readouts."""
    def text(identifier):
        v = next((v for v in views if v.get("id") == identifier), None)
        return None if v is None or v.get("hidden") else v.get("text")
    found = []
    for identifier in ("scopes.top.highlights", "scopes.top.shadows"):
        m = re.search(r"clipped (\d+\.\d) %", text(identifier) or "")
        found.append(float(m.group(1)) if m else None)
    return text("scopes.top.caption"), text("scopes.bottom.caption"), tuple(found)


def wait_panel(doc, tag, top, bottom, readouts=None):
    """Polls the panel until its captions are `top`/`bottom` and (when given) its top
    readouts within 0.2 of `readouts`, for `PANEL_WAIT` s: the last state seen and whether
    it matched."""
    deadline = time.monotonic() + PANEL_WAIT
    n, state = 0, (None, None, (None, None))
    while time.monotonic() < deadline:
        state = panel_state(editor_views(doc, f"{tag}-{n}"))
        n += 1
        shown = state[2]
        near = readouts is None or (None not in shown and None not in readouts and all(
            abs(a - b) <= 0.2 for a, b in zip(shown, readouts)))
        if state[0] == top and state[1] == bottom and near and None not in shown:
            return state, True
        time.sleep(0.5)
    return state, False


def run_sp(client, state):
    """SP: View ▸ Scopes on an HLG project, paused: the HLG captions and the top readouts
    at render_frame's; Show SDR Version turns both to Rec. 709 at the SDR version's
    readouts; off again the HLG captions return and Show Ungraded keeps them; an SDR
    project's captions Rec. 709. Only the non-persisting View items are performed."""
    misses, figures = [], []
    hlg_cap = ("HLG · cd/m²", "Rec. 2100 HLG")
    doc = hlg_doc(client, "sp", [fixture("hlg")])
    _, files, _ = scope_render(doc, "sp-hlg", waveform=True)
    _, sfiles, _ = scope_render(doc, "sp-sdr", sdr_version=True, waveform=True)
    hw, sw = scope_json(files, "waveform") or {}, scope_json(sfiles, "waveform") or {}
    hlg_r = (hw.get("highlights"), hw.get("shadows"))
    sdr_r = (sw.get("highlights"), sw.get("shadows"))
    steps = []

    def menu(path):
        got = doc.call("perform_menu_item", path=path) if doc.ok else {"ok": False}
        steps.append(f"{' ▸ '.join(path)} {got.get('error', 'ok')}")
        return got["ok"]
    if menu(SCOPES_MENU):
        seen, ok = wait_panel(doc, "sp-hlg", *hlg_cap, hlg_r)
        figures.append(f"HLG: {seen} against render_frame's {hlg_r}")
        if not ok:
            misses.append(f"HLG panel {seen}")
        if menu(SDR_VERSION_MENU):
            seen, ok = wait_panel(doc, "sp-sdr", SDR_CAPTION, SDR_CAPTION, sdr_r)
            figures.append(f"Show SDR Version: {seen} against {sdr_r}")
            if not ok:
                misses.append(f"Show SDR Version panel {seen}")
            parted = None not in hlg_r + sdr_r and max(
                abs(hlg_r[0] - sdr_r[0]), abs(hlg_r[1] - sdr_r[1])) > 1
            if not parted:
                misses.append(f"CONTROL: the HLG {hlg_r} and SDR {sdr_r} readouts part by ≤ 1")
            if menu(SDR_VERSION_MENU):
                seen, ok = wait_panel(doc, "sp-back", *hlg_cap, hlg_r)
                figures.append(f"off again: {seen}")
                if not ok:
                    misses.append(f"off again {seen}")
                if menu(UNGRADED_MENU):
                    seen, ok = wait_panel(doc, "sp-ungraded", *hlg_cap)
                    figures.append(f"Show Ungraded: {seen}")
                    if not ok:
                        misses.append(f"Show Ungraded {seen}")
                    menu(UNGRADED_MENU)
        menu(SCOPES_MENU)
    state["sp_closed"] = doc.close()
    sdr = Doc(client, "sp-sdr-project", W, H)
    sdr.place(fixture("bt709")) if sdr.ok else None
    got = sdr.call("perform_menu_item", path=SCOPES_MENU) if sdr.ok else {"ok": False}
    steps.append(f"SDR project View ▸ Scopes {got.get('error', 'ok')}")
    seen, ok = wait_panel(sdr, "sp-sdrproject", SDR_CAPTION, SDR_CAPTION) if got["ok"] \
        else (None, False)
    figures.append(f"an SDR project: {seen}")
    if not ok:
        misses.append(f"the SDR project's panel {seen}")
    sdr.call("perform_menu_item", path=SCOPES_MENU) if got["ok"] else None
    state["sp_sdr_closed"] = sdr.close()
    if any(not s.endswith(" ok") for s in steps):
        misses.append(f"menu steps {steps}")
    check("SP View ▸ Scopes on an HLG project, paused: captions \"HLG · cd/m²\" over "
          "\"Rec. 2100 HLG\", the top readouts within 0.2 of render_frame's; with Show SDR "
          "Version both \"Rec. 709 · encoded\" at {sdr_version}'s readouts (CONTROL: they part "
          "from the HLG ones by > 1); off again the HLG captions, kept under Show Ungraded; an "
          "SDR project's \"Rec. 709 · encoded\"", not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


def scope_render(doc, tag, t=T, **options):
    """`render_frame` with `options` (scope booleans among them): (png, {kind: json path},
    the text with WORK's path spelled `<work>`), png None when no frame was written."""
    png, got = render_opts(doc, tag, t=t, **options)
    text = str(got.get("reply", "")) if got.get("ok") else str(got.get("error"))
    files = {kind: Path(f"{png}.{kind}.json") for kind in SCOPE_KINDS
             if png is not None and options.get(kind)}
    return png, files, text.replace(str(WORK), "<work>")


def scope_json(files, kind):
    try:
        return json.loads(files[kind].read_text())
    except (KeyError, OSError, ValueError):
        return None


def run_si(client, mode, control, state):
    """SI: every H1 SDR scene at 0.5 s, `render_frame` with the four scopes and with
    `{vectorscope, vectorscope_zoom: 4}`: each JSON byte-identical to DIR's, and the text
    (WORK's path spelled `<work>`) equal. `capture` writes DIR's."""
    folder = control / "si"
    if mode == "capture":
        folder.mkdir(parents=True, exist_ok=True)
    misses, compared, written = [], 0, 0
    for name, width, height in H1_FIXTURES:
        path = h1_media(name, None if mode == "capture" else control)
        doc = Doc(client, f"si-{name}", width, height)
        if path is None:
            doc.ok, doc.why = False, f"{name}: {REFUSED.get(name)}"
        elif doc.ok:
            doc.place(path)
        for variant, options in (("all", SCOPES_ALL),
                                 ("x4", {"vectorscope": True, "vectorscope_zoom": 4})):
            tag = f"si-{name}-{variant}"
            png, files, text = scope_render(doc, tag, **options)
            if png is None or not all(f.exists() for f in files.values()):
                misses.append(f"{tag}: {doc.why or text[-200:]}")
                continue
            if mode == "capture":
                for kind, f in files.items():
                    shutil.copy2(f, folder / f"{tag}.{kind}.json")
                    written += 1
                (folder / f"{tag}.txt").write_text(text)
                continue
            for kind, f in files.items():
                want = folder / f"{tag}.{kind}.json"
                if not want.exists():
                    misses.append(f"{tag}.{kind}: no control JSON")
                elif f.read_bytes() != want.read_bytes():
                    misses.append(f"{tag}.{kind}: JSON differs ({len(f.read_bytes())} vs "
                                  f"{len(want.read_bytes())} bytes)")
                else:
                    compared += 1
            said = folder / f"{tag}.txt"
            if not said.exists() or said.read_text() != text:
                misses.append(f"{tag}: the text differs: {text[-300:]!r}")
        state[f"si_{name}_closed"] = doc.close()
    want_files = len(H1_FIXTURES) * (len(SCOPE_KINDS) + 1)
    if mode == "capture":
        state["si_captured"] = not misses and written == want_files
        print(f"  SI references captured: {written} JSON files of {want_files}"
              f"{'; NOT ' + str(misses) if misses else ''}", flush=True)
        return
    check(f"SI {len(H1_FIXTURES)} SDR scenes at 0.5 s: render_frame's four scopes' JSON and "
          f"{{vectorscope, vectorscope_zoom: 4}}'s byte-identical to {control.name}'s, and "
          f"its text the same", not misses and compared == want_files,
          f"{compared} of {want_files} JSON files equal; failed {misses[:8] or 'none'}")


# ---- the run --------------------------------------------------------------------

def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        return [f"{log} could not be read"]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's edits, built by its own make.
    (app bundle, copy) or (None, why)."""
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    for path, anchor, replacement in edits:
        target = copy / path
        if target.is_symlink() or not target.resolve().is_relative_to(WORK):
            # A core file is a symlink into the tree: the copy gets its own core
            # (log_proof.py's way; hdr H-1's `hdr10.rs` mutants).
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
    parser.add_argument("mode", nargs="?", choices=["capture", "compare"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--measure", action="store_true", help="TI alone")
    parser.add_argument("--mutant", choices=sorted(MUTANTS) or None)
    parser.add_argument("--control", default=CONTROL)
    args = parser.parse_args()
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
    elif args.measure:
        selected = {"TI", "TH", "TO", "Z1"}
    else:
        selected -= {"TI", "TH", "TO"}
        if args.mutant:
            selected -= {"H1a"} | H7_ROWS | H2_ROWS | H3_ROWS | H4_ROWS
    if args.mode == "capture":
        if not args.only:
            selected = {"H1", "H2", "H3", "H4", "H5", "H6", "R0", "Z1"}
        control.mkdir(parents=True, exist_ok=True)
    if args.mode is None and not args.mutant:
        selected -= {"H1"}
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
        print(f"grading-3 T3-1 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
    else:
        what = args.mode or ("measure" if args.measure else "run")
        print(f"grading-3 T3-1 — honest sources over MCP ({what}, {config} build {binary})",
              flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    state = {}
    closed = True
    log = WORK / "instance.log"
    needs_instance = bool(selected & ({"H1", "H1m", "H1a", "H1s", "H1w", "H2", "H3", "H4", "H5",
                                       "H6", "R0"} | H7_ROWS | H2_ROWS
                                      | (H3_ROWS - {"DX"}) | H4_ROWS))
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
                recording = run_r0(state) if "R0" in selected or "H1" in selected \
                    or "H5" in selected else None
                extra_h1, extra_h5 = [], None
                if recording and recording["arm"] in (None, "srgb(bt709)"):
                    extra_h1 = [("rec_tags", W, H)]
                    MEDIA_REC["rec_tags"] = recording["path"]
                elif recording and recording["arm"].startswith("sdrWide"):
                    gamut = "p3d65" if "p3D65" in recording["arm"] else "bt2020"
                    extra_h5 = ("rec_tags", gamut, recording["matrix"]
                                if recording["matrix"] in KR_KB else "bt709")
                    MEDIA_REC["rec_tags"] = recording["path"]
                if "H1" in selected:
                    run_h1(client, args.mode, control, sources, state, extra_h1)
                if "H1m" in selected:
                    run_h1m(client, control, sources, state)
                if "H1a" in selected:
                    run_h1a(client, sources, state)
                if selected & {"H1s", "H1w"}:
                    run_srgb_rows(client, control, sources, state)
                if "H2" in selected:
                    run_h2(client, state)
                scenes = {}
                wanted = set()
                if selected & {"H3", "H4"}:
                    wanted |= {"hlg", "pq"}
                if "H5" in selected:
                    wanted |= {"b2020_709", "p3_709", "b2020_2020"} | (
                        {"rec_tags"} if extra_h5 else set())
                for name in sorted(wanted):
                    scenes[name] = fixture_scene(client, name)
                if "H3" in selected:
                    run_h3(client, scenes)
                if "H4" in selected:
                    run_h4(scenes)
                if "H5" in selected:
                    run_h5(client, scenes, extra_h5)
                if "H6" in selected:
                    run_h6(client, sources, state)
                if selected & H7_ROWS:
                    run_h7(client, args.mode, control, sources, state)
                # hdr H-2 (#277): the HLG working space.
                for row, run in (("HS", run_hs), ("HH", run_hh), ("HP", run_hp),
                                 ("HT", run_ht), ("HL", run_hl), ("HW", run_hw),
                                 ("HK", run_hk), ("HM", run_hm), ("HF", run_hf),
                                 ("HX", run_hx),
                                 # hdr H-3 (#277): the deliverables.
                                 ("DT", run_dt), ("DP", run_dp), ("DV", run_dv),
                                 ("DI", run_di), ("DE", run_de), ("DR", run_dr),
                                 ("DS", run_ds), ("DM", run_dm)):
                    if row in selected:
                        run(client, state)
                # hdr H-4 (#277): the scopes.
                if "SI" in selected:
                    run_si(client, args.mode, control, state)
                for row, run in (("SW", run_sw), ("SV", run_sv), ("SS", run_ss),
                                 ("SD", run_sd), ("SP", run_sp)):
                    if row in selected:
                        run(client, state)
            except Exception as error:  # a row that could not run is a failure
                import traceback
                traceback.print_exc()
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
                closed = False
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    if "TI" in selected:
        run_ti(binary)
    if "TH" in selected:
        run_th(binary)
    if "TO" in selected:
        run_to(binary)
    if "DX" in selected:
        run_dx(binary)
    if selected & P_ROWS:
        run_math_probe(sources)
    found = complaints(log) if needs_instance else []
    fixtures_ok = all(v for k, v in state.items() if k.endswith("fixture"))
    closed = closed and all(v for k, v in state.items() if k.endswith("closed"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Frame Job: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; state {{{', '.join(f'{k}: {v}' for k, v in state.items() if k != 'h1_record')}}}; "
          f"refused {REFUSED or 'none'}; complaints {found}")
    if needs_instance:
        print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    if args.mode == "capture":
        try:  # a capture of other rows (`--only`) keeps an earlier one's H1 record
            kept = json.loads((control / "capture.json").read_text())
        except (OSError, ValueError):
            kept = {}
        record = dict(kept, **(state.get("h1_record") or {}), tree=str(ROOT), config=config)
        if "R0" in selected:
            record["r0"] = state.get("r0")
        (control / "capture.json").write_text(json.dumps(record, indent=1))
        shown = [n for n in ("H2", "H3", "H4", "H5", "H6") if n in rows]
        failing = [n for n in shown if not rows[n]]
        print(f"captured into {args.folder}; on the control H2–H6 FAILED: {failing} "
              f"(passed, so not discriminating: {[n for n in shown if rows[n]]})")
        captured = (state.get("capture_ok") or "H1" not in selected) \
            and state.get("si_captured", "SI" not in selected)
        return 0 if rows.get("Z1") and captured and rows.get("H7i", True) else 1
    scored = [name for name in ROWS if name in rows and name not in RECORDS]
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
        caught = not survived
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy (survived: {', '.join(survived) or 'none'}; other rows failed: "
              f"{', '.join(others) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


MEDIA_REC = {}
WRITTEN = {}

if __name__ == "__main__":
    sys.exit(main())
