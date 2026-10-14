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
  other half, run by that script.
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
  `L13_OPEN` HOLDS (a fixture there is printed beside its issue). One not
  REACHED is an instrument failure, named in REFUSED. `slog3_fr_422` (the
  even HEVC 4:2:2 file: the HEVC branch, #280) is printed and not scored.
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
`slog3_fr_odd`. Each is wanted with its codec, profile, pix_fmt and size,
and read back as above. Mutants: `full-range-ignored` (L10, L12),
`apple-log-rescaled` (L11), `range-from-reverse` (L12), and B98's
`odd-range-ignored` (L13: `Intermediate.pixelFormat(fullRange:)` answers the
video-range `x422` whatever the flag, spec §11 PR-10).

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
        "L11", "L12", "L13", "Z1"]
LP_ROWS = {"LP1", "LP2", "LP3", "LP4"}
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
                  "slog3_fr_422": ("slog3", "pc", ("bt2020", "bt709", "bt2020nc"))}
RANGE_SETTINGS = {"slog3_fr": SETTINGS["slog3"], "slog3_vr": SETTINGS["slog3"],
                  "vlog_fr": SETTINGS["vlog"], "applelog_fr": {"log": "apple_log"}}
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
                "slog3_fr_422": (W, H, *HEVC422)}
# The VP9 fixtures' tags are printed, not required (their range is).
TAGS_PRINTED = {"slog3_fr_vp9", "slog3_vr_vp9"}
# L13 (B98, #289): the odd fixtures scored, in pairs (full range, its
# video-range twin); `slog3_fr_422` printed only. L13_OPEN: fixture → the
# issue a range-independent or unfixed pair was filed as; such a fixture is
# scored on REACHED alone, its hold figures printed beside the reference.
L13_PAIRS = (("slog3_fr_odd", "slog3_vr_odd"), ("slog3_fr_vp9", "slog3_vr_vp9"))
L13_PRINTED = ("slog3_fr_422",)
# B98's VP9 pair: an MP4's VP9 track carries no `FullRangeVideo` extension, so
# GR-22's flag (`CompositionBuilder.isFullRange`) reads it as video range and
# PR-10's full-range read never fires (measured after PR-10: toe 90, spread 28).
L13_OPEN: dict[str, str] = {"slog3_fr_vp9": "#291", "slog3_vr_vp9": "#291"}
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
    "labels-over-setting": ([(STAGE_SWIFT,
                              "            let conversion = layer.input.flatMap(InputConversion"
                              ".choose(input:))\n                ?? InputConversion.choose(for: "
                              "frame)\n",
                              "            let conversion = InputConversion.choose(for: frame)\n"
                              "                ?? layer.input.flatMap(InputConversion.choose("
                              "input:))\n")], ["L1"]),
    "remove-lut-keeps-conversion": ([("core/src/lut.rs", "                row.color = None;\n",
                                      "")], ["L8"]),
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


def l9_media(name, control):
    """L9's fixture: DIR's copy when DIR holds one (compare, mutants), else
    MEDIA's (capture copies it into DIR)."""
    if control is not None:
        copy = control / "media" / f"{name}.mov"
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


def range_rows(client, row, names):
    """Each of `names` with its Camera Log at 0.5 s against the oracle at its
    OWN decoded codes, in its range, with the domain by its flag: (misses,
    worst, the 0 % patch's render and its video-domain oracle)."""
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
        bad = [(x, y, v, o) for x, y, v, o in gaps if spread(v, o) > 1]
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
            shutil.copy2(path, control / "media" / f"{name}.mov")
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
    parser.add_argument("mode", nargs="?", choices=["capture", "compare", "reverse-variants"])
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
        selected -= {"L9"}
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
    needs_instance = bool(selected - LP_ROWS - {"Z1"})
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
                for name, run in (("L1", run_l1), ("L2", run_l2), ("L3", run_l3),
                                  ("L4", run_l4), ("L5", run_l5), ("L6", run_l6),
                                  ("L7", run_l7), ("L8", run_l8), ("L10", run_l10),
                                  ("L11", run_l11), ("L12", run_l12), ("L13", run_l13)):
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
        shown = [n for n in ROWS if n in rows and n not in ("L9", "Z1")]
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
