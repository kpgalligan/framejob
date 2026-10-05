#!/usr/bin/env python3
"""Issue batch B85 phase 3 (#103; spec §11 G-33) — the size an export reports
is the size the file has, HEVC with alpha is a row whose frames carry the
canvas's alpha, a miss within a pixel is filled and not padded, and a missing
encoder ends in the preset's own sentence — on instances this script
launches.

    python3 tools/proof/hevc_alpha_proof.py [--app PATH]
    python3 tools/proof/hevc_alpha_proof.py --rows size [--app PATH]
    python3 tools/proof/hevc_alpha_proof.py --control plain-hevc-reader|sheet-default
    python3 tools/proof/hevc_alpha_proof.py --mutant encoder-refused|report-and-fill|shape-and-note
    python3 tools/proof/hevc_alpha_proof.py --record-baseline [--app PATH]

With no option it scores every row below but G1 and X1. `--rows size` is
Gate A, phase A's gate: the rows marked ◆, and G1. **G1 is RED BY DESIGN on
a build that holds phase B** — it requires the pad the baseline recorded
and an unknown `hevc_alpha` — and the script says so on G1's line and on
its last line; Gate A was passed on the phase A build (commit fcfeebf).

Each launch is the Release build on a scratch socket of its own, and only
that process is stopped, by its launcher. **Every instance runs in a
scratch home**, `CFFIXED_USER_HOME=tools/proof/work/hevc-alpha/<launch>/home`,
and every package, PNG and export is under `tools/proof/work/hevc-alpha/`,
which is removed at the start and at exit. It is launched with every key of
`screens.py`'s `PINS` as a launch argument (never written),
`ReelcutInspectorWidth` replaced by 280 (the inspector's narrowest) and
`ReelcutExportChoice` by `{"preset_id":"hevc_alpha"}` — sent as
`<string>…</string>`, because the argument domain DROPS a value that begins
with a brace and is not a property list, and the sheet then opens on the
owner's own remembered choice (measured: it did). Two menu-driven things
are done, neither persisting: File ▸ Export… is performed and its sheet
cancelled, and the inspector's Document tab is picked. **No sheet's Export
or Add to Queue is ever pressed**: the remembered export choice has one
writer, `ExportChoice.remember()` (`ExportPresetsStore.swift`), whose one
caller is `ExportSheetController.commit(queue:)` — those two buttons;
`cancel_sheet` presses the sheet's Escape button, whose action only
dismisses, and the `export` tool's handler (`AgentServer+Render.swift`)
reads and writes no default. What a RUN shows of it is `mcp.py`'s guard: a
moved owner-visible key is a `mcp: DEFAULTS MOVED` line on stderr, and
status 3 when no other Reelcut shares the domain — so a run's stderr is
kept beside its score. Every export is one second, and the largest frame
written is 1296 × 728.

Fixtures: **CLEAR** 640 × 360, background alpha 0, an opaque red 200 × 120
card; **FAINT** the same with the card at opacity 0.5; **SOLID** the same
on opaque black; **SUB** 334 × 222, background alpha 0, an opaque red
160 × 100 card (its `720p` row is 1084 × 720, 0.76 px off the canvas's
shape); **SUBWHITE** 334 × 222 and **WIDE** 400 × 100, an opaque white
background under a white card (the card is there for the duration);
**ODDFULL** `open_project` of a 321 × 181 opaque red PNG ffmpeg wrote,
trimmed to a second and saved as a package (the picture covers the canvas);
**ODD** the same with the background at alpha 0 and the picture at half
scale (its `720p` row is 1276 × 720, 0.51 px off shape); **TALLFULL** and
**TALL** the same pair from a 181 × 320 PNG (the evened 180 × 320 misses by
1.77 px fitted and 1 px filled); **ODDBIG** `open_project` of a 1001 × 667
PNG, never exported; **TONE** CLEAR plus a one-second 48 kHz stereo WAV on a
track of its own. `--rows size` and the recorder build only the seven the
baseline's cases use.

Rows (◆ = also Gate A's):
- ◆ **H0**: with the instance listening, `<home>/Library/Application
  Support` is a directory (the scratch home took). When it fails no tool is
  called.
- ◆ **T0**: `export`'s `size` description holds "written one pixel smaller
  on that edge"; in the full rows also "h264, hevc, hevc_alpha and
  prores_422 need even dimensions", "letterboxed if the shape differs by
  more than a pixel (within a pixel the picture fills the frame instead)"
  and "except on prores_4444 and hevc_alpha", and its `preset` description
  holds "Three rows keep a transparent canvas transparent: prores_4444 and
  hevc_alpha (the movie rows — see size, which constrains them) and apng."
- ◆ **R1**: ODDFULL with no `size` as `h264`, `hevc` and `prores_422` (and
  `hevc_alpha` in the full rows), and `hevc` again with `size: "document"`:
  the answer's `width` × `height` is 320 × 180 and so is ffprobe's stream.
  The line prints the baseline's pair for each. ◆ **R2**: TALLFULL the
  same, 180 × 320.
- ◆ **R3**: ODDFULL as `prores_4444`, `apng` and `gif` with no `size`: the
  answer and the file are 321 × 181.
- ◆ **R4**: CLEAR as `h264` at `[321, 181]`: answer and file 320 × 180; as
  `prores_4444` at `[321, 181]`: both 321 × 181; CLEAR with no `size` as
  `h264`, `hevc`, `prores_422` and `prores_4444`: both 640 × 360.
- ◆ **E2**: File ▸ Export… on ODDFULL, `snapshot_ui` of the sheet,
  `cancel_sheet`: the Format popup reads "HEVC with Alpha (MOV)" — the pin
  took (under `--rows size` "H.264 (MP4)" is allowed too, which is what a
  taken pin showed on phase A's build, where an owner who last exported
  H.264 could not be told apart) — the Size popup reads exactly "Document
  (even) · 320 × 180", a text begins "320 × 180 · ", the two size fields
  read 320 and 180, and no text holds "321 × 181". On ODDBIG the Size popup
  reads "Document (even) · 1000 × 666" with no `truncated` problem naming
  it and an intrinsic width no wider than its frame; on CLEAR, "Document
  size · 640 × 360".
- **A1**: CLEAR as `hevc_alpha`: the answer's `preset` / `container` /
  `codec` are `hevc_alpha` / `mov` / `hevc_alpha`, the path ends `.mov`,
  ffprobe says `hevc` / `hvc1` at 640 × 360; decoded, the corner is alpha 0,
  the card's centre alpha 255 with red above 200, and every pixel more than
  4 px from the card's edge is exactly 0 outside it and 255 inside.
  **A2**: FAINT: the centre's alpha is 128 ± 3 and its red within 3 of its
  alpha (premultiplied). **A3**: SOLID: the alphas are {255}. **A4**: CLEAR
  at `720p`: 1280 × 720, corner alpha 0, centre 255. **A5**: TONE: an `aac`
  stream at 48000 Hz with 2 channels, and `loudness` in the answer.
- **S1**: CLEAR as `hevc_alpha` at `[640, 480]`: refused, the error names
  "640 × 360" and "640 × 480" and holds "alpha"; no file. **S2**: WIDE as
  `prores_4444` and as `hevc_alpha` at `[402, 100]`: refused, the error
  names "400 × 100" and "402 × 100"; no file (a fit would leave 2 px, and
  402 × 100 is no canvas-shaped size less a pixel).
- **O1**: ODD as `hevc_alpha` with no `size`: NOT refused, the answer and
  the file are 320 × 180, every pixel of row 0, row 179, column 0 and
  column 319 is alpha 0, the picture's centre is 255; the same for TALL at
  180 × 320 and for CLEAR at `[321, 181]` (320 × 180). **O2**: ODD as
  `prores_4444`: 321 × 181, corner alpha 0, centre 255; TALL as
  `prores_4444` at `[180, 320]` (a typed size the earlier guard refused):
  written, all four edges alpha 0. **O3**: ODD as `apng`: 321 × 181, corner
  alpha 0. **O4**: ODD as `hevc_alpha` at `720p`: 1276 × 720, all four
  edges alpha 0, the centre 255, the answer's size the file's. **O5**:
  CLEAR as `hevc_alpha` at `[400, 225]` and at `[1296, 729]` — odd sizes
  typed in the canvas's own proportions, one smaller than the canvas and
  one larger: NOT refused, the answer and the file are 400 × 224 and
  1296 × 728, all four edges alpha 0, the centre 255; and CLEAR as
  `prores_4444` at a typed `[400, 224]`: written the same. These are the
  first arm of `shapeGap`'s limit — a canvas-shaped size less at most one
  pixel on each axis, at any scale — and all three were REFUSED, in the
  shape sentence, by the arm phase B first built (the canvas itself less a
  pixel): that build is this row's red.
- **P1**: SUB as `hevc_alpha` at `720p`: 1084 × 720 and every pixel of row
  0, row 719, column 0 and column 1083 is alpha 0. **P2**: the same as
  `prores_4444`.
- ◆ **B1**: CLEAR as `hevc`: what the baseline holds for it is equal — the
  stream's and the file's fixed parameters as ffprobe reads them (codec,
  tag, profile, level, pixel format, size, both frame rates, the frame
  count, the four colour values; the container, the stream count, the
  duration), the extension, the set of alphas, the corner pixel and the
  SHA-256 of frame 0's decoded RGBA. The stream's `bit_rate` and the
  file's `size` and `bit_rate` (`B1_UNSCORED`) are printed beside the
  baseline's and NOT compared: they are byte counts of a hardware HEVC
  bitstream, which the encoder does not promise to repeat.
- **B2**: SUBWHITE at `720p` as `hevc`, `h264` and `prores_422`:
  1084 × 720 and the middle row's columns w−1, w−2 and w−3 each have every
  channel above 235, printed beside the baseline's (two black columns).
  **B3**: ODDFULL and TALLFULL with no `size` as `hevc`, `h264` and
  `prores_422`: the middle row's columns 0, 1, w−2, w−1 and the middle
  column's rows 0, 1, h−2, h−1 are red (r > 200, g and b < 60), printed
  beside the baseline's classes.
- ◆ **B4**: `prores_4444` for CLEAR at the document size, CLEAR at `720p`
  and ODD at the document size: the size and frame 0's digest equal the
  baseline's.
- **L1**: SUBWHITE as `hevc` at `[640, 640]`: 640 × 640, the middle
  column's top and bottom pixels are black (every channel under 40) and the
  centre is white — a different shape is still letterboxed. **L2**: WIDE as
  `hevc`, `h264` and `prores_422` at `[402, 100]`: the answer and the file
  are 402 × 100, the middle row holds exactly 2 black pixels whose columns
  equal the baseline's, and its column 200 is white (every channel above
  235) — a frame typed two pixels wider than the canvas is letterboxed as
  before, where a limit of `max(cw, ch)` for every frame would fill it.
- **N1**: `select_inspector_tab` Document on CLEAR, `snapshot_ui` of the
  inspector: exactly one view's text is "Transparent — kept by 3 export
  formats.", its intrinsic width is at most 244, and no `truncated` problem
  names it.
- **E1**: File ▸ Export… on CLEAR: the Format popup reads "HEVC with Alpha
  (MOV)" with no `truncated` problem naming it, exactly one text — the
  sheet's footnote — contains "MOV" and ends "alpha", and that view's
  `tooltip` in the layout dump equals its whole text. The footnote's WIDTH
  is printed and NOT scored: beside the sheet's three buttons its slot is
  88 pt and "HEVC_ALPHA · MOV · alpha" needs 144, so it is drawn cut with a
  tail ellipsis (`sheetFootnote`, `Sheets.swift`; a footnote gives way
  before a button, #141) — exactly as ProRes 4444's "PRORES4444 · MOV ·
  alpha" has been (measured: 144 pt in 88 on both). So the word "alpha" is
  in the footnote's text and its tooltip and not on the sheet's drawn
  face, which this proof prints and does not hide; whether the summary
  gets a line of its own is a layout choice no row decides. The tooltip
  clause is red on a build whose `syncReadout` writes only `stringValue`:
  the tooltip there is the empty string the label was built with. Only
  this row's sheet is opened (the choice is pinned to `hevc_alpha`):
  ProRes 4444's footnote goes through the same two assignments and has no
  row of its own.
- **X1**, scored only under `--mutant encoder-refused`: CLEAR as
  `hevc_alpha` answers exactly "This Mac cannot export with the
  “hevc_alpha” preset." and nothing is at the path, not even an empty file.
- **I1**, printed and never scored: FAINT's `hevc_alpha` and `prores_4444`
  files each imported into a new 640 × 360 project on an opaque white
  background, `render_frame` at 0.5 s, the card's centre pixel.
- ◆ **G1**, scored ONLY under `--rows size`: ODDFULL and TALLFULL with no
  `size` as `h264`, `hevc` and `prores_422`: frame 0's digest equals the
  baseline's, and so do eight pixels — the middle row's columns 0, 1, w−2,
  w−1 and the middle column's rows 0, 1, h−2, h−1 — at least one of them
  black; and `export` of CLEAR as `hevc_alpha` is refused as an unknown
  preset with no file. So phase A moved no pixel where it acts, and the row
  is red on a tree that already fills or already lists the row.
- ◆ **Z1**: every project closes, and the launch's log holds no
  `Reelcut: ` line.

**Controls**, no build. `--control plain-hevc-reader` scores A1's and A2's
pixel readers over `hevc` exports of CLEAR and FAINT: both must FAIL (a
plain HEVC file's alphas are all 255, and ffprobe cannot tell the two rows
apart). `--control sheet-default` launches with `screens.py`'s own empty
`ReelcutExportChoice`: E1 must FAIL (the sheet opens on H.264).

**Mutants**, each ONE `tree_copy.make_copy` with every named anchor
asserted to occur exactly once and replaced, built by the copy's own
`make app` under a 1500 s bound, running only its named rows:
- `encoder-refused` — `videoSettings` adds an encoder specification nothing
  satisfies for `.hevcWithAlpha`, and `encoderOutcome` returns its argument
  untouched when the environment holds `RC_MUTANT_UNMAPPED`. Two launches:
  without the variable A1 FAILS and X1 PASSES; with it X1 FAILS, and the
  line prints what a Mac without the mapping says.
- `report-and-fill` — `Preset::even_sized` answers false (the copy's
  `core/` is made its own for this one: `own_core`) and `fillsTheBox`
  answers false. R1, R2, R4 and E2 FAIL, O1, O5, P1, P2, B2 and B3 FAIL,
  and R3, S1, S2, L1 and L2 PASS.
- `shape-and-note` — the guard returns before the shape test for
  `.hevcWithAlpha`, `transparencyNote` always joins the names, `shapeGap`'s
  limit is `max(cw, ch)` whatever the frame's size, and `fillsTheBox`
  answers true when the environment holds `RC_MUTANT_FILL_ALL`. Two
  launches: without the variable S1, N1, L2 and S2 FAIL (S2's `prores_4444`
  half by the limit alone) while L1 and O1 PASS; with it L1 FAILS.
A control or a mutant exits 0 only when every named row did what is named,
1 when one did not, 2 when it could not be performed.

**The baseline** is `tools/proof/hevc_alpha_baseline.json`, written only by
`--record-baseline`, on the build BEFORE G-33's code: it refuses to write
unless `git status` shows `core/` and `app/` unchanged, the answer for
ODDFULL and TALLFULL says the canvas's odd size over an evened file on each
of `h264`, `hevc` and `prores_422` (R1's and R2's comparison FAILS — that
refusal to pass is Gate A's red), and each of those files' eight pixels
holds a black one. It keeps, per case, only what every recording agreed
on: a first run writes `recordings: 1`, a second merges into it, and a value
two recordings disagree on is stored `null` and named under `disagreed`.
The rows refuse a baseline of fewer than two recordings.

**The baseline is one host's bytes and one build's**, and says which. Its
cases are hardware H.264 and HEVC bitstreams, ffprobe's values for one of
them (its `size` and `bit_rate` are held and printed, never compared: B1)
and ffmpeg's RGBA digests, so it is stamped with `host` — the
chip, the macOS version and build, and ffmpeg's version (`host()`) — and
the rows print it under their heading. **On a host that is not the
baseline's the rows that read a digest — B1, B4 and G1 — are NOT scored**:
each prints a `skip` line naming both hosts, every other row is scored as
it stands (L2 without its "columns equal the baseline's" clause, and it
says so), and the script exits 2 when everything it could score passed,
because the claim is then incomplete: the instrument, not the product. A
control or a mutant names none of those three rows and runs in full there
(L2, where a mutant names it, likewise without the columns clause).
`head` is the commit of the BUILD's tree, not of this checkout: `--app` has
to be `build/Build/Products/Release/Reelcut.app` at the top of a git work
tree (`build_tree`), `head` is that tree's `git rev-parse HEAD`, the `git
status` above is that tree's, and a build anywhere else — a proof's tree
copy has no `.git` — is not recorded.
What it cannot see is a STALE build inside its tree: `make app` there
first. A recording at another commit or on another host than the file's
starts the file over. So another host records its own, from a work tree of
a commit before G-33's code built there, with this script and `--app`
aimed at that build. Where a digest is `null` its row compares the case's five
sample pixels exactly instead (G1: the classes of the eight pixels — black,
red or neither) and says so on its line. Besides the digest rows' cases it
holds what the fill rows are printed beside: SUBWHITE's right-hand edge at
`720p` (B2), WIDE at `[402, 100]` on the three opaque rows — the columns of
the middle row's black pixels (L2) — and that `prores_4444` refuses that
size (S2).

Exit 0 when every row passed (the last line is `n/n`), 1 when one failed, 2
when the instrument could not run or could not score every row — no
baseline, fewer than two recordings, or another host's; 3 is `mcp.py`'s, a
moved default.
"""

import argparse
import atexit
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import tree_copy  # noqa: E402
import v2_snapshot  # noqa: E402
from screens import PINS  # noqa: E402

WORK = ROOT / "tools/proof/work/hevc-alpha"
APP = ROOT / "build/Build/Products/Release/Reelcut.app"
BASELINE = ROOT / "tools/proof/hevc_alpha_baseline.json"
CALL_BOUND = 120
TOOL_BOUND = 60
BUILD_BOUND = 1500
SECOND = 600_000
SIZE_ROWS = ["H0", "T0", "R1", "R2", "R3", "R4", "E2", "B1", "B4", "G1", "Z1"]
FULL_ROWS = ["H0", "T0", "R1", "R2", "R3", "R4", "E2", "A1", "A2", "A3", "A4", "A5", "S1",
             "S2", "O1", "O2", "O3", "O4", "O5", "P1", "P2", "B1", "B2", "B3", "B4", "L1",
             "L2", "N1", "E1", "Z1"]
DIGEST_ROWS = ("B1", "B4", "G1")     # the rows that read the baseline's host's bytes
EVEN_ROWS = ["h264", "hevc", "prores_422"]
EXTENSION = {"h264": "mp4", "hevc": "mp4", "hevc_alpha": "mov", "prores_422": "mov",
             "prores_4444": "mov", "gif": "gif", "apng": "png"}
A6_PHRASE = "written one pixel smaller on that edge"
B6_SIZE = ["h264, hevc, hevc_alpha and prores_422 need even dimensions",
           "letterboxed if the shape differs by more than a pixel (within a pixel the "
           "picture fills the frame instead)",
           "except on prores_4444 and hevc_alpha"]
B6_PRESET = ("Three rows keep a transparent canvas transparent: prores_4444 and hevc_alpha "
             "(the movie rows — see size, which constrains them) and apng.")
CHOICE = '<string>{"preset_id":"hevc_alpha"}</string>'
ALPHA_FORMAT = "HEVC with Alpha (MOV)"
# What E2's Format popup may read under `--rows size`. Phase A's build had no
# `hevc_alpha` row, so a pin that took showed H.264 — as did an owner who last
# exported H.264 with a pin that did not. The full rows require ALPHA_FORMAT
# alone, which only a taken pin shows.
EVEN_FORMATS = ("H.264 (MP4)", ALPHA_FORMAT)
NOTE = "Transparent — kept by 3 export formats."
NOTE_WIDTH = 244          # the note's row at the inspector's narrowest, 280 pt
UNAVAILABLE = "This Mac cannot export with the “hevc_alpha” preset."
CARD = (220, 120, 420, 240)      # CLEAR's 200 × 120 card, centred on 640 × 360
STREAM_KEYS = ("codec_name,codec_tag_string,profile,level,pix_fmt,width,height,r_frame_rate,"
               "avg_frame_rate,nb_frames,bit_rate,color_range,color_space,color_transfer,"
               "color_primaries")
FORMAT_KEYS = "format_name,nb_streams,duration,size,bit_rate"
# What B1 reads and does NOT compare: byte counts of a hardware HEVC bitstream,
# which the encoder does not promise to repeat. They are dropped from both
# sides before `held` and printed; the probe still reads them and the
# baseline still holds them, so its file is as it was recorded.
B1_UNSCORED = (("stream", "bit_rate"), ("format", "size"), ("format", "bit_rate"))
rows = {}
details = {}       # a row's halves, for a mutant that names one of them


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def skip(name, why):
    rows[name.split()[0]] = None
    print(f"  skip {name}\n       {why}", flush=True)


# ---- readers ---------------------------------------------------------------------

def tool(argv):
    """One bounded ffmpeg, ffprobe or git child; its stdout as text."""
    done = bounded.run(argv, TOOL_BOUND)
    if done["rc"] != 0:
        raise RuntimeError(f"{argv[0]} rc {done['rc']} (expired {done['expired']}): "
                           f"{done['stderr'].strip()[-300:]}")
    return done["stdout"]


def probe_video(path):
    """The first video stream's codec, profile, pixel format and size, or
    None where the file holds no video (`phase7_proof.py`'s reader)."""
    answer = tool(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
                   "stream=codec_name,profile,pix_fmt,width,height", "-of", "json", str(path)])
    streams = json.loads(answer).get("streams", [])
    return streams[0] if streams else None


def probe_whole(path):
    """ffprobe's values for the first video stream and for the file."""
    answer = json.loads(tool(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
         f"stream={STREAM_KEYS}:format={FORMAT_KEYS}", "-of", "json", str(path)]))
    return (answer.get("streams") or [{}])[0], answer.get("format") or {}


def probe_audio(path):
    """The first audio stream's codec, rate and channel count, or None."""
    answer = tool(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries",
                   "stream=codec_name,sample_rate,channels", "-of", "json", str(path)])
    streams = json.loads(answer).get("streams", [])
    return streams[0] if streams else None


class Raster:
    """Frame 0 of a written file, decoded to straight 8-bit RGBA
    (`phase7_proof.py`'s reader; the size comes off the file)."""

    def __init__(self, path):
        stream = probe_video(path)
        if stream is None:
            raise RuntimeError(f"{path} holds no video stream to decode")
        self.width, self.height = int(stream["width"]), int(stream["height"])
        done = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-vframes", "1", "-f", "rawvideo",
             "-pix_fmt", "rgba", "-"], capture_output=True, timeout=TOOL_BOUND, check=True)
        self.data = done.stdout
        if len(self.data) != self.width * self.height * 4:
            raise RuntimeError(f"{path}: decoded {len(self.data)} bytes, wanted "
                               f"{self.width * self.height * 4}")

    def pixel(self, x, y):
        i = (y * self.width + x) * 4
        return list(self.data[i:i + 4])

    def centre(self):
        return self.pixel(self.width // 2, self.height // 2)

    def digest(self):
        return hashlib.sha256(self.data).hexdigest()

    def alphas(self):
        return sorted(set(self.data[3::4]))

    def edges(self):
        """Every alpha along row 0, row h−1, column 0 and column w−1."""
        w, h, alpha = self.width, self.height, self.data[3::4]
        return sorted(set(alpha[0:w]) | set(alpha[(h - 1) * w:h * w]) | set(alpha[0::w])
                      | set(alpha[w - 1::w]))

    def samples(self):
        """Five pixels: the centre and the four quarter points."""
        w, h = self.width, self.height
        return [self.pixel(x, y) for x, y in
                ((w // 2, h // 2), (w // 4, h // 4), (3 * w // 4, h // 4),
                 (w // 4, 3 * h // 4), (3 * w // 4, 3 * h // 4))]

    def eight(self):
        """The middle row's columns 0, 1, w−2, w−1, then the middle column's
        rows 0, 1, h−2, h−1."""
        w, h = self.width, self.height
        return ([self.pixel(x, h // 2) for x in (0, 1, w - 2, w - 1)]
                + [self.pixel(w // 2, y) for y in (0, 1, h - 2, h - 1)])


def kind(pixel):
    """black (every channel under 40), red (r > 200, g and b < 60) or neither."""
    r, g, b = pixel[:3]
    if r < 40 and g < 40 and b < 40:
        return "black"
    return "red" if r > 200 and g < 60 and b < 60 else "neither"


def white(pixel):
    return all(channel > 235 for channel in pixel[:3])


def card_reading(raster, card=CARD, margin=4):
    """A1's pixel reader: the corner is alpha 0, the centre alpha 255 with
    red above 200, and every pixel more than `margin` px from the card's
    edge is exactly 0 outside it and 255 inside. `(good, text)`."""
    w, h, alpha = raster.width, raster.height, raster.data[3::4]
    x0, y0, x1, y1 = card
    far = margin + 1
    outside = inside = 0
    for y in range(h):
        line = alpha[y * w:(y + 1) * w]
        if y < y0 - far or y >= y1 + far:
            outside += w - line.count(0)
            continue
        left, right = line[:x0 - far], line[x1 + far:]
        outside += len(left) - left.count(0) + len(right) - right.count(0)
        if y0 + far <= y < y1 - far:
            middle = line[x0 + far:x1 - far]
            inside += len(middle) - middle.count(255)
    corner, centre = raster.pixel(0, 0), raster.centre()
    good = (corner[3] == 0 and centre[3] == 255 and centre[0] > 200 and outside == 0
            and inside == 0)
    return good, (f"corner {corner}, centre {centre}; pixels more than {margin} px outside "
                  f"the card that are not alpha 0: {outside}; inside it that are not 255: "
                  f"{inside}; the alphas present: {len(raster.alphas())} values")


def faint_reading(raster):
    """A2's pixel reader: the centre's alpha is 128 ± 3 and its red within
    3 of its alpha. `(good, text)`."""
    centre = raster.centre()
    good = abs(centre[3] - 128) <= 3 and abs(centre[0] - centre[3]) <= 3
    return good, f"centre {centre}"


# ---- the instance ----------------------------------------------------------------

def attempt(client, name, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    try:
        return {"ok": True, "reply": client.call_with(name, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def must(client, name, arguments):
    got = attempt(client, name, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{name} {arguments}: {got['error']}")
    return got["reply"]


class Session:
    """One launch: its folder under WORK, its instance, the fixtures made on
    it and the exports it has written (each once)."""

    def __init__(self, label, app, choice=CHOICE, env=None):
        self.label, self.app, self.choice, self.env = label, Path(app), choice, env or {}
        self.dir = WORK / label
        self.home, self.out, self.log = self.dir / "home", self.dir / "out", self.dir / "log"
        self.launched = self.client = None
        self.fx, self.made, self.cases, self.foreign = {}, {}, {}, None

    def launch(self):
        """The app on a scratch socket, in the scratch home, with every pin;
        `choice` None keeps `screens.py`'s own empty export choice."""
        self.home.mkdir(parents=True)
        self.out.mkdir()
        arguments = ["-NSRecentDocumentsLimit", "0"]
        for key, value in PINS:
            if key == "ReelcutInspectorWidth":
                value = "<real>280</real>"
            elif key == "ReelcutExportChoice" and self.choice is not None:
                value = self.choice
            arguments += [f"-{key}", value]
        environment = {"CFFIXED_USER_HOME": str(self.home)}
        environment.update(self.env)
        self.launched = mcp.launch(str(self.app / "Contents/MacOS/Reelcut"),
                                   arguments=arguments, env=bounded.child_env(environment),
                                   log_path=str(self.log), timeout=CALL_BOUND)
        self.client = self.launched.client
        return self.client is not None

    def stop(self):
        if self.launched is not None:
            self.launched.stop()
            mcp.remove_scratch(self.launched.socket_path)


# ---- fixtures --------------------------------------------------------------------

def shapes(s, name, width, height, background, card, fill, opacity=None):
    """A new project with one card for a second; its package."""
    path = s.dir / f"{name}.reelcut"
    must(s.client, "new_project", {"path": str(path)})
    must(s.client, "set_canvas", {"project": str(path), "width": width, "height": height,
                                  "background": background})
    track = must(s.client, "get_project", {"project": str(path)})["project"]["tracks"][0]["id"]
    must(s.client, "add_shape_clip",
         {"project": str(path), "track": track, "at": 0, "duration": SECOND,
          "shape": {"kind": "rectangle", "width": card[0], "height": card[1], "stroke": None,
                    "fill": fill}})
    if opacity is not None:
        clips = must(s.client, "get_project", {"project": str(path)})["project"]["clips"]
        must(s.client, "set_video", {"project": str(path), "clips": [clips[0]["id"]],
                                     "patch": {"opacity": opacity}})
    must(s.client, "save_project", {"project": str(path)})
    return path


def picture(s, name, width, height, clear=False):
    """A red PNG of that size opened as a document, its clip trimmed to a
    second, saved as a package; with `clear`, the background at alpha 0 and
    the picture at half scale."""
    png = s.dir / f"{name}.png"
    tool(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
          f"color=c=red:s={width}x{height}", "-frames:v", "1", str(png)])
    must(s.client, "open_project", {"path": str(png)})
    project = must(s.client, "get_project", {"project": str(png)})["project"]
    canvas = (project["canvas"]["width"], project["canvas"]["height"])
    if canvas != (width, height) or len(project["clips"]) != 1:
        raise RuntimeError(f"{name}: the document is {canvas} with {len(project['clips'])} "
                           "clips")
    clip = project["clips"][0]["id"]
    must(s.client, "trim_end", {"project": str(png), "clip": clip, "to": SECOND})
    if clear:
        must(s.client, "set_canvas", {"project": str(png), "background": [0, 0, 0, 0]})
        must(s.client, "set_video", {"project": str(png), "clips": [clip],
                                     "patch": {"scale": 0.5}})
    package = s.dir / f"{name}.reelcut"
    must(s.client, "save_project", {"project": str(png), "path": str(package)})
    return package


def tone(s):
    """CLEAR's card over a clear canvas, plus a second of 48 kHz stereo sine
    on a track of its own."""
    path = shapes(s, "TONE", 640, 360, [0, 0, 0, 0], (200, 120), [1, 0, 0, 1])
    wav = s.dir / "TONE.wav"
    tool(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
          "aevalsrc=0.2*sin(2*PI*440*t)|0.2*sin(2*PI*440*t):s=48000:d=1", "-c:a",
          "pcm_s16le", str(wav)])
    media = must(s.client, "import_media", {"project": str(path), "path": str(wav)})["media"]
    must(s.client, "add_track", {"project": str(path)})
    tracks = must(s.client, "get_project", {"project": str(path)})["project"]["tracks"]
    must(s.client, "add_clip", {"project": str(path), "track": tracks[-1]["id"],
                                "media": media, "at": 0})
    must(s.client, "save_project", {"project": str(path)})
    return path


def fixtures(s, full):
    """The seven fixtures the baseline's cases use, and with `full` the
    five the alpha and fill rows add."""
    clear, white_, red = [0, 0, 0, 0], [1, 1, 1, 1], [1, 0, 0, 1]
    s.fx["CLEAR"] = shapes(s, "CLEAR", 640, 360, clear, (200, 120), red)
    s.fx["SUBWHITE"] = shapes(s, "SUBWHITE", 334, 222, white_, (100, 100), white_)
    s.fx["WIDE"] = shapes(s, "WIDE", 400, 100, white_, (40, 40), white_)
    s.fx["ODDFULL"] = picture(s, "ODDFULL", 321, 181)
    s.fx["ODD"] = picture(s, "ODD", 321, 181, clear=True)
    s.fx["TALLFULL"] = picture(s, "TALLFULL", 181, 320)
    s.fx["ODDBIG"] = picture(s, "ODDBIG", 1001, 667)
    if full:
        s.fx["FAINT"] = shapes(s, "FAINT", 640, 360, clear, (200, 120), red, opacity=0.5)
        s.fx["SOLID"] = shapes(s, "SOLID", 640, 360, [0, 0, 0, 1], (200, 120), red)
        s.fx["SUB"] = shapes(s, "SUB", 334, 222, clear, (160, 100), red)
        s.fx["TALL"] = picture(s, "TALL", 181, 320, clear=True)
        s.fx["TONE"] = tone(s)


# ---- one export, and what is read from it ----------------------------------------

def export(s, fixture, preset, size=None):
    """`export` of one fixture, once per session: whether it answered, the
    answer, its size, the file's size as ffprobe reads it, and the path."""
    tag = "default" if size is None else (size if isinstance(size, str)
                                          else f"{size[0]}x{size[1]}")
    key = (fixture, preset, tag)
    if key in s.made:
        return s.made[key]
    path = s.out / f"{fixture}-{preset}-{tag}.{EXTENSION[preset]}"
    if path.exists():
        path.unlink()
    arguments = {"project": str(s.fx[fixture]), "preset": preset, "path": str(path)}
    if size is not None:
        arguments["size"] = size
    got = attempt(s.client, "export", arguments)
    out = {"ok": got["ok"], "error": got.get("error"), "path": path, "answer": None,
           "file": None, "reply": None, "written": path.exists()}
    if got["ok"] and isinstance(got["reply"], dict):
        out["reply"] = got["reply"]
        out["answer"] = [got["reply"].get("width"), got["reply"].get("height")]
        stream = probe_video(path) if path.exists() else None
        if stream is not None:
            out["file"] = [int(stream["width"]), int(stream["height"])]
    s.made[key] = out
    return out


def written(s, fixture, preset, size=None):
    """An export that has to have answered, and its decoded frame 0."""
    done = export(s, fixture, preset, size)
    if not done["ok"] or done["file"] is None:
        raise RuntimeError(f"{fixture} as {preset} at {size or 'no size'}: "
                           f"{done['error'] or 'no video in the file'}")
    return done, Raster(done["path"])


def framed(done):
    """The answer's and the file's size, frame 0's digest, five samples."""
    raster = Raster(done["path"])
    return raster, {"answer": done["answer"], "file": done["file"],
                    "frame0": raster.digest(), "samples": raster.samples()}


def case_b1(s):
    done = export(s, "CLEAR", "hevc")
    if not done["ok"]:
        raise RuntimeError(f"CLEAR as hevc: {done['error']}")
    raster, case = framed(done)
    stream, whole = probe_whole(done["path"])
    case.update({"extension": done["path"].suffix, "stream": stream, "format": whole,
                 "alphas": raster.alphas(), "corner": raster.pixel(0, 0)})
    return case


def case_plain(s, fixture, preset, size=None):
    done = export(s, fixture, preset, size)
    if not done["ok"]:
        raise RuntimeError(f"{fixture} as {preset} at {size}: {done['error']}")
    return framed(done)[1]


def case_odd(s, fixture, preset):
    """An odd canvas at its default size: `framed` plus the eight pixels."""
    done = export(s, fixture, preset)
    if not done["ok"]:
        raise RuntimeError(f"{fixture} as {preset}: {done['error']}")
    raster, case = framed(done)
    eight = raster.eight()
    case.update({"eight": eight, "eight_class": [kind(p) for p in eight]})
    return case


def case_b2(s, preset):
    done = export(s, "SUBWHITE", preset, "720p")
    if not done["ok"]:
        raise RuntimeError(f"SUBWHITE as {preset} at 720p: {done['error']}")
    raster, case = framed(done)
    w, h = raster.width, raster.height
    case["edge3"] = [raster.pixel(x, h // 2) for x in (w - 1, w - 2, w - 3)]
    return case


def case_l2(s, preset):
    done = export(s, "WIDE", preset, [402, 100])
    if not done["ok"]:
        raise RuntimeError(f"WIDE as {preset} at [402, 100]: {done['error']}")
    raster, case = framed(done)
    middle = raster.height // 2
    case["black"] = [x for x in range(raster.width) if kind(raster.pixel(x, middle)) == "black"]
    case["column200"] = raster.pixel(200, middle)
    return case


def case_s2(s):
    done = export(s, "WIDE", "prores_4444", [402, 100])
    return {"refused": not done["ok"], "error": done["error"], "written": done["written"]}


# ---- the baseline ----------------------------------------------------------------

def measure(s):
    """Every case the baseline holds, on the build that is running."""
    cases = {"B1 CLEAR hevc": case_b1(s),
             "B4 CLEAR prores_4444 document": case_plain(s, "CLEAR", "prores_4444"),
             "B4 CLEAR prores_4444 720p": case_plain(s, "CLEAR", "prores_4444", "720p"),
             "B4 ODD prores_4444 document": case_plain(s, "ODD", "prores_4444"),
             "S2 WIDE prores_4444 402x100": case_s2(s)}
    for preset in EVEN_ROWS:
        for fixture in ("ODDFULL", "TALLFULL"):
            cases[f"G1 {fixture} {preset}"] = case_odd(s, fixture, preset)
        cases[f"B2 SUBWHITE {preset} 720p"] = case_b2(s, preset)
        cases[f"L2 WIDE {preset} 402x100"] = case_l2(s, preset)
    return cases


def merge(old, new, where, disagreed):
    """What both hold equal; a value they disagree on is None and named."""
    if isinstance(old, dict) and isinstance(new, dict):
        return {key: merge(old.get(key), new.get(key), where + [key], disagreed)
                for key in sorted(set(old) | set(new))}
    if old == new:
        return old
    disagreed.add(" / ".join(where))
    return None


def host():
    """What the baseline's bytes depend on besides the build: the chip (the
    hardware encoders), the macOS version and build (VideoToolbox), and
    ffmpeg's version (the decoder behind every digest, and ffprobe)."""
    def first(argv):
        text = tool(argv).strip()
        if not text:
            raise RuntimeError(f"{' '.join(argv)} printed nothing")
        return text.splitlines()[0].strip()

    return {"chip": first(["sysctl", "-n", "machdep.cpu.brand_string"]),
            "macos": f"{first(['sw_vers', '-productVersion'])} "
                     f"({first(['sw_vers', '-buildVersion'])})",
            "ffmpeg": " ".join(first(["ffmpeg", "-version"]).split()[:3])}


def host_text(stamp):
    if not isinstance(stamp, dict):
        return "no host stamped"
    return (f"{stamp.get('chip')} · macOS {stamp.get('macos')} · {stamp.get('ffmpeg')}")


def build_tree(app):
    """The git work tree a build sits in — `<tree>/build/Build/Products/
    Release/Reelcut.app`, where `make app` puts it — or None when `app` is
    anywhere else or `<tree>` is not the top of a work tree. A proof's tree
    COPY is not one: it has no `.git`, and `git` would answer for the tree
    around it."""
    app = Path(app).resolve()
    if app.parts[-5:-1] != ("build", "Build", "Products", "Release"):
        return None
    tree = app.parents[4]
    done = bounded.run(["git", "-C", str(tree), "rev-parse", "--show-toplevel"], TOOL_BOUND)
    top = done["stdout"].strip()
    if done["rc"] != 0 or not top or Path(top).resolve() != tree:
        return None
    return tree


def unchanged_build(tree):
    """The BUILD's tree's `git rev-parse HEAD`, and what its `git status`
    lists under core/ and app/."""
    head = tool(["git", "-C", str(tree), "rev-parse", "HEAD"]).strip()
    dirty = tool(["git", "-C", str(tree), "status", "--porcelain", "--", "core", "app"])
    return head, [line for line in dirty.splitlines() if line.strip()]


def record(s, today):
    """`--record-baseline`'s measuring half: the document to write, or None
    when this build is not one a baseline may be recorded on. `today` is
    `host()`'s answer."""
    tree = build_tree(s.app)
    if tree is None:
        print(f"NOT RECORDED: the build's commit cannot be read — {s.app} is not "
              "build/Build/Products/Release/Reelcut.app at the top of a git work tree")
        return None
    head, dirty = unchanged_build(tree)
    if dirty:
        print(f"NOT RECORDED: core/ or app/ of {tree} differs from its HEAD, so this is "
              f"not the build before G-33's code: {dirty}")
        return None
    cases = measure(s)
    refused = []
    for fixture, canvas, even in (("ODDFULL", [321, 181], [320, 180]),
                                  ("TALLFULL", [181, 320], [180, 320])):
        for preset in EVEN_ROWS:
            case = cases[f"G1 {fixture} {preset}"]
            print(f"  {fixture} as {preset}: the answer says {case['answer']}, the file is "
                  f"{case['file']}; the eight pixels are {case['eight_class']}", flush=True)
            if case["answer"] != canvas or case["file"] != even:
                refused.append(f"{fixture} as {preset}: R1/R2's comparison does not fail the "
                               f"way the build before G-33 fails it (wanted the answer "
                               f"{canvas} over a file of {even})")
            if "black" not in case["eight_class"]:
                refused.append(f"{fixture} as {preset}: no black pixel among the eight")
    if not cases["S2 WIDE prores_4444 402x100"]["refused"]:
        refused.append("WIDE as prores_4444 at [402, 100] was not refused")
    if refused:
        print("NOT RECORDED:\n  " + "\n  ".join(refused))
        return None
    earlier = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
    if (earlier is not None and earlier.get("head") == head
            and earlier.get("host") == today):
        disagreed = set(earlier.get("disagreed") or [])
        cases = merge(earlier["cases"], cases, [], disagreed)
        count = earlier["recordings"] + 1
    else:
        if earlier is not None:
            print(f"  the earlier baseline was recorded at {earlier.get('head')} on "
                  f"{host_text(earlier.get('host'))}; starting over")
        disagreed, count = set(), 1
    return {"head": head, "host": today, "recordings": count, "disagreed": sorted(disagreed),
            "cases": cases}


def write_baseline(document):
    BASELINE.write_text(json.dumps(document, indent=1, sort_keys=True) + "\n")
    print(f"RECORDED: recording {document['recordings']} at {document['head']} on "
          f"{host_text(document['host'])}; {len(document['cases'])} cases; the recordings "
          f"disagree on {document['disagreed'] or 'nothing'}")
    if document["recordings"] < 2:
        print("  one more --record-baseline is needed: the rows refuse a baseline of fewer "
              "than two recordings")


def held(base, now):
    """Whether everything the baseline kept for a case equals today's.
    Where the recordings disagreed on `frame0`, the five sample pixels
    stand in for it, and the text says so."""
    bad = [key for key in sorted(base) if base[key] is not None and base[key] != now.get(key)]
    values = []     # what moved, so a failed line can be read after the files are gone
    for key in bad:
        was, got = base[key], now.get(key)
        if isinstance(was, dict) and isinstance(got, dict):
            values += [f"{key}.{sub}: baseline {was.get(sub)!r}, now {got.get(sub)!r}"
                       for sub in sorted(set(was) | set(got)) if was.get(sub) != got.get(sub)]
        else:
            values.append(f"{key}: baseline {str(was)[:80]!r}, now {str(got)[:80]!r}")
    note = ""
    if base.get("frame0") is None:
        if base.get("samples") is None:
            bad.append("frame0 (the recordings agreed on neither it nor the samples)")
        else:
            note = " [the recordings disagreed on frame0: the samples compared exactly instead]"
    return not bad, (f"differs in {bad} — {'; '.join(values)}" if bad else "equal") + note


# ---- the sheet and the inspector -------------------------------------------------

def layout_of(s, name, **arguments):
    """One `snapshot_ui` capture's layout dump: `(views, problems)`."""
    answer = v2_snapshot.snap(s.client, path=str(s.out / f"{name}.png"), **arguments)
    v2_snapshot.captures.clear()
    with open(answer["layout_path"]) as handle:
        layout = json.load(handle)
    return layout["views"], layout.get("problems") or []


def truncated_texts(views, problems):
    return [views[p["view"]].get("text") for p in problems
            if p.get("kind") == "truncated" and p.get("view", -1) < len(views)]


def sheet(s, fixture):
    """File ▸ Export… on the fixture, the sheet's layout dump, then
    `cancel_sheet` — the sheet is opened, read and cancelled, and nothing
    in it is pressed. `(views, problems)`, or raises."""
    project = str(s.fx[fixture])
    must(s.client, "perform_menu_item", {"project": project, "path": ["File", "Export…"]})
    try:
        return layout_of(s, f"sheet-{fixture}", window="sheet", project=project)
    finally:
        attempt(s.client, "cancel_sheet", {"project": project})


def read_sheet(views, problems):
    """The Format and Size popups' texts, the size fields, every text, each
    text's tooltip, and the texts a `truncated` problem names."""
    visible = [v for v in views if not v.get("hidden") and v.get("text")]
    popups = [v for v in visible if v.get("class") == "NSPopUpButton"]

    def after(label):
        at = next((v["i"] for v in visible if v["text"] == label), None)
        return next((v["text"] for v in popups if at is not None and v["i"] > at), None)

    times = next((v for v in visible if v["text"] == "×"), None)
    fields = [v["text"] for v in visible
              if times is not None and v.get("parent") == times.get("parent")
              and v["text"].isdigit()]
    size = after("Size:")
    room = next(([v["intrinsic"][0], v["frame"][2]] for v in popups if v["text"] == size),
                None)
    return {"format": after("Format:"), "size": size, "room": room, "fields": fields,
            "texts": [v["text"] for v in visible],
            "widths": {v["text"]: [v["intrinsic"][0], v["frame"][2]] for v in visible},
            "tips": {v["text"]: v.get("tooltip") for v in visible},
            "truncated": truncated_texts(views, problems)}


# ---- the rows --------------------------------------------------------------------

def sized(done):
    return f"answer {done['answer']} file {done['file']}" + (
        "" if done["ok"] else f" ({done['error']})")


def row_t0(s, full):
    properties = (((s.client.schemas().get("export") or {}).get("inputSchema") or {})
                  .get("properties", {}))
    size = properties.get("size", {}).get("description", "")
    preset = properties.get("preset", {}).get("description", "")
    if not full:
        check(f"T0 export's size description holds \"{A6_PHRASE}\"", A6_PHRASE in size,
              "" if A6_PHRASE in size else f"it reads: {size}")
        return
    missing = [p for p in [A6_PHRASE] + B6_SIZE if p not in size]
    if B6_PRESET not in preset:
        missing.append(B6_PRESET)
    check("T0 export's size description says what an odd edge does, names the four "
          "even-sized rows, the fill within a pixel and the two rows that refuse another "
          "shape; its preset description names the three rows that keep transparency",
          not missing, f"missing: {missing}" if missing else "")


def row_r12(s, full):
    """R1, R2 — an odd canvas at its default size: the answer is the file's."""
    presets = EVEN_ROWS + (["hevc_alpha"] if full else [])
    for row, fixture, even in (("R1", "ODDFULL", [320, 180]), ("R2", "TALLFULL", [180, 320])):
        good, lines = True, []
        for preset in presets:
            done = export(s, fixture, preset)
            base = s.cases.get(f"G1 {fixture} {preset}")
            good = good and done["ok"] and done["answer"] == even and done["file"] == even
            lines.append(f"{preset}: {sized(done)}" + (
                f" (baseline: answer {base['answer']} file {base['file']})" if base else
                " (no baseline: the row is G-33's)"))
        named = export(s, fixture, "hevc", "document")
        good = good and named["ok"] and named["answer"] == even and named["file"] == even
        lines.append(f"hevc, size document: {sized(named)}")
        check(f"{row} {fixture} with no size as {', '.join(presets)}, and hevc at "
              f"`document`: the answer and the file are {even[0]} × {even[1]}",
              good, "\n       ".join(lines))


def row_r3(s):
    good, lines = True, []
    for preset in ("prores_4444", "apng", "gif"):
        done = export(s, "ODDFULL", preset)
        good = good and done["ok"] and done["answer"] == [321, 181] and done["file"] == [321, 181]
        lines.append(f"{preset}: {sized(done)}")
    check("R3 ODDFULL with no size as prores_4444, apng and gif: the answer and the file "
          "are 321 × 181", good, "; ".join(lines))


def row_r4(s):
    good, lines = True, []
    for preset, size, want in (("h264", [321, 181], [320, 180]),
                               ("prores_4444", [321, 181], [321, 181]),
                               ("h264", None, [640, 360]), ("hevc", None, [640, 360]),
                               ("prores_422", None, [640, 360]),
                               ("prores_4444", None, [640, 360])):
        done = export(s, "CLEAR", preset, size)
        good = good and done["ok"] and done["answer"] == want and done["file"] == want
        lines.append(f"{preset} at {size or 'no size'}: {sized(done)}")
    check("R4 CLEAR at [321, 181] is 320 × 180 as h264 and 321 × 181 as prores_4444; with no "
          "size it is 640 × 360 on h264, hevc, prores_422 and prores_4444",
          good, "\n       ".join(lines))


def row_e2(s, full):
    formats = (ALPHA_FORMAT,) if full else EVEN_FORMATS
    on_odd = read_sheet(*sheet(s, "ODDFULL"))
    on_big = read_sheet(*sheet(s, "ODDBIG"))
    on_clear = read_sheet(*sheet(s, "CLEAR"))
    big = "Document (even) · 1000 × 666"
    check("E2 the Export sheet on ODDFULL reads \"Document (even) · 320 × 180\", a text "
          "beginning \"320 × 180 · \" and the fields 320 and 180, with no \"321 × 181\" "
          f"anywhere; on ODDBIG \"{big}\", not truncated; on CLEAR \"Document size · "
          f"640 × 360\"; the Format popup reads {' or '.join(repr(f) for f in formats)}",
          on_odd["format"] in formats
          and on_odd["size"] == "Document (even) · 320 × 180"
          and any(t.startswith("320 × 180 · ") for t in on_odd["texts"])
          and on_odd["fields"] == ["320", "180"]
          and not any("321 × 181" in t for t in on_odd["texts"])
          and on_big["format"] in formats and on_big["size"] == big
          and big not in on_big["truncated"]
          and on_big["room"] is not None and on_big["room"][0] <= on_big["room"][1]
          and on_clear["format"] in formats
          and on_clear["size"] == "Document size · 640 × 360",
          f"ODDFULL: format {on_odd['format']!r}, size {on_odd['size']!r}, fields "
          f"{on_odd['fields']}, readout "
          f"{[t for t in on_odd['texts'] if ' fps · ' in t]}\n       ODDBIG: format "
          f"{on_big['format']!r}, size {on_big['size']!r}, its intrinsic width and "
          f"its frame's {on_big['room']}, truncated {on_big['truncated']}\n       "
          f"CLEAR: format {on_clear['format']!r}, size "
          f"{on_clear['size']!r}")


def row_a1(s):
    done = export(s, "CLEAR", "hevc_alpha")
    if not done["ok"] or done["file"] is None:
        check("A1 CLEAR as hevc_alpha is a QuickTime HEVC file whose frame carries the "
              "canvas's alpha", False, f"no file: {done['error']}")
        return
    reply = done["reply"]
    named = [reply.get("preset"), reply.get("container"), reply.get("codec")]
    stream, _ = probe_whole(done["path"])
    probed = [stream.get("codec_name"), stream.get("codec_tag_string"), stream.get("pix_fmt")]
    pixels, text = card_reading(Raster(done["path"]))
    check("A1 CLEAR as hevc_alpha: the answer says hevc_alpha / mov / hevc_alpha, the path "
          "ends .mov, ffprobe says hevc / hvc1 at 640 × 360, and decoded the corner is "
          "alpha 0, the card's centre 255 with red above 200, and every pixel more than "
          "4 px from the card's edge is exactly 0 outside it and 255 inside",
          named == ["hevc_alpha", "mov", "hevc_alpha"]
          and str(reply.get("path", "")).endswith(".mov") and done["path"].suffix == ".mov"
          and probed[:2] == ["hevc", "hvc1"] and done["file"] == [640, 360] and pixels,
          f"answer {named}, path …{str(reply.get('path'))[-28:]}; ffprobe {probed} "
          f"{done['file']}\n       {text}")


def row_a2(s):
    _, raster = written(s, "FAINT", "hevc_alpha")
    good, text = faint_reading(raster)
    check("A2 FAINT as hevc_alpha: the card's centre is alpha 128 ± 3 with its red within "
          "3 of its alpha (premultiplied)", good, text)


def row_a3(s):
    _, raster = written(s, "SOLID", "hevc_alpha")
    check("A3 SOLID as hevc_alpha: every alpha is 255", raster.alphas() == [255],
          f"alphas {raster.alphas()[:8]}")


def row_a4(s):
    done, raster = written(s, "CLEAR", "hevc_alpha", "720p")
    corner, centre = raster.pixel(0, 0), raster.centre()
    check("A4 CLEAR as hevc_alpha at 720p: 1280 × 720, corner alpha 0, centre alpha 255",
          done["answer"] == [1280, 720] and done["file"] == [1280, 720] and corner[3] == 0
          and centre[3] == 255, f"{sized(done)}; corner {corner}, centre {centre}")


def row_a5(s):
    done = export(s, "TONE", "hevc_alpha")
    if not done["ok"]:
        check("A5 TONE as hevc_alpha carries AAC sound", False, str(done["error"]))
        return
    sound = probe_audio(done["path"]) or {}
    heard = [sound.get("codec_name"), sound.get("sample_rate"), sound.get("channels")]
    loudness = done["reply"].get("loudness")
    check("A5 TONE as hevc_alpha: an aac stream at 48000 Hz with 2 channels, and "
          "`loudness` in the answer",
          heard == ["aac", "48000", 2] and isinstance(loudness, dict),
          f"audio {heard}; loudness "
          f"{(loudness or {}).get('summary') if isinstance(loudness, dict) else loudness!r}")


def refusal(done, phrases):
    """Whether an export was refused naming every phrase, with no file."""
    return (not done["ok"] and all(p in (done["error"] or "") for p in phrases)
            and not done["path"].exists())


def row_s1(s):
    done = export(s, "CLEAR", "hevc_alpha", [640, 480])
    check("S1 CLEAR as hevc_alpha at [640, 480] is refused, naming 640 × 360 and 640 × 480 "
          "and the alpha channel, and writes no file",
          refusal(done, ["640 × 360", "640 × 480", "alpha"]),
          done["error"] or f"EXPORTED {sized(done)}")


def row_s2(s):
    halves, lines = {}, []
    for preset in ("prores_4444", "hevc_alpha"):
        done = export(s, "WIDE", preset, [402, 100])
        halves[preset] = refusal(done, ["400 × 100", "402 × 100"])
        lines.append(f"{preset}: {done['error'] or 'EXPORTED ' + sized(done)}")
    details["S2"] = halves
    check("S2 WIDE as prores_4444 and as hevc_alpha at [402, 100] is refused, naming "
          "400 × 100 and 402 × 100, and writes no file", all(halves.values()),
          "\n       ".join(lines))


def clear_edges(s, fixture, preset, size, want, centre=True):
    """One alpha export that has to be written at `want` with all four
    edges at alpha 0 (and, with `centre`, the middle at 255): `(good, text)`."""
    done = export(s, fixture, preset, size)
    label = f"{fixture} as {preset} at {size or 'no size'}"
    if not done["ok"] or done["file"] is None:
        return False, f"{label}: {done['error'] or 'no file'}"
    raster = Raster(done["path"])
    edges, middle = raster.edges(), raster.centre()
    good = (done["answer"] == want and done["file"] == want and edges == [0]
            and (middle[3] == 255 or not centre))
    return good, (f"{label}: {sized(done)}; the alphas along the four edges {edges[:6]}"
                  f"{'…' if len(edges) > 6 else ''}, centre {middle}")


def row_o1(s):
    results = [clear_edges(s, "ODD", "hevc_alpha", None, [320, 180]),
               clear_edges(s, "TALL", "hevc_alpha", None, [180, 320]),
               clear_edges(s, "CLEAR", "hevc_alpha", [321, 181], [320, 180])]
    check("O1 ODD and TALL as hevc_alpha with no size, and CLEAR at [321, 181], are NOT "
          "refused: the answer and the file are the even size, every pixel of the four "
          "edges is alpha 0 and the centre is 255",
          all(good for good, _ in results), "\n       ".join(text for _, text in results))


def row_o2(s):
    done = export(s, "ODD", "prores_4444")
    first, text = False, f"ODD as prores_4444: {done['error'] or 'no file'}"
    if done["ok"] and done["file"] is not None:
        raster = Raster(done["path"])
        corner, centre = raster.pixel(0, 0), raster.centre()
        first = (done["answer"] == [321, 181] and done["file"] == [321, 181]
                 and corner[3] == 0 and centre[3] == 255)
        text = f"ODD as prores_4444: {sized(done)}; corner {corner}, centre {centre}"
    second, typed = clear_edges(s, "TALL", "prores_4444", [180, 320], [180, 320])
    check("O2 ODD as prores_4444 keeps 321 × 181 with its corner at alpha 0 and its centre "
          "255; TALL as prores_4444 at [180, 320] is written with all four edges alpha 0",
          first and second, f"{text}\n       {typed}")


def row_o3(s):
    done, raster = written(s, "ODD", "apng")
    corner = raster.pixel(0, 0)
    check("O3 ODD as apng: 321 × 181, corner alpha 0",
          done["answer"] == [321, 181] and done["file"] == [321, 181] and corner[3] == 0,
          f"{sized(done)}; corner {corner}")


def row_o4(s):
    good, text = clear_edges(s, "ODD", "hevc_alpha", "720p", [1276, 720])
    check("O4 ODD as hevc_alpha at 720p: 1276 × 720 in the answer and the file, all four "
          "edges alpha 0, the centre 255", good, text)


def row_o5(s):
    """A typed size of the canvas's OWN shape: never refused, whichever
    side of the canvas it is on — the first arm of `shapeGap`'s limit."""
    results = [clear_edges(s, "CLEAR", "hevc_alpha", [400, 225], [400, 224]),
               clear_edges(s, "CLEAR", "hevc_alpha", [1296, 729], [1296, 728]),
               clear_edges(s, "CLEAR", "prores_4444", [400, 224], [400, 224])]
    check("O5 CLEAR as hevc_alpha at [400, 225] and at [1296, 729] — odd sizes of the "
          "canvas's own shape, one smaller than it and one larger — is NOT refused and is "
          "written one pixel smaller, 400 × 224 and 1296 × 728, and as prores_4444 at a "
          "typed [400, 224] it is written too: the answer's size is the file's, every "
          "pixel of the four edges is alpha 0 and the centre is 255",
          all(good for good, _ in results), "\n       ".join(text for _, text in results))


def row_p(s, row, preset):
    good, text = clear_edges(s, "SUB", preset, "720p", [1084, 720])
    check(f"{row} SUB as {preset} at 720p: 1084 × 720, every pixel of row 0, row 719, "
          "column 0 and column 1083 is alpha 0", good, text)


def less_byte_counts(case):
    """A B1 case without `B1_UNSCORED`'s three values, and those values as
    text. A part the case does not hold as a dictionary is left as it is."""
    kept, printed = dict(case), []
    for part, key in B1_UNSCORED:
        values = case.get(part)
        printed.append(f"{part}.{key} {values.get(key) if isinstance(values, dict) else None!r}")
        if isinstance(values, dict):
            kept[part] = {k: v for k, v in kept[part].items() if k != key}
    return kept, ", ".join(printed)


def row_b1(s):
    if s.foreign:
        skip("B1 CLEAR as hevc equals the baseline's file", s.foreign)
        return
    base, was = less_byte_counts(s.cases["B1 CLEAR hevc"])
    now, got = less_byte_counts(case_b1(s))
    good, text = held(base, now)
    check("B1 CLEAR as hevc: the stream's and the file's fixed parameters as ffprobe reads "
          "them, the extension, the alphas, the corner and frame 0's digest equal the "
          "baseline's", good,
          f"{text}\n       printed, not scored (a hardware encoder's byte counts): {got}"
          f"\n       the baseline's: {was}")


def row_b2(s):
    good, lines = True, []
    for preset in ("hevc", "h264", "prores_422"):
        now = case_b2(s, preset)
        base = s.cases.get(f"B2 SUBWHITE {preset} 720p") or {}
        good = good and now["file"] == [1084, 720] and all(white(p) for p in now["edge3"])
        lines.append(f"{preset}: {now['file']} columns w−1, w−2, w−3 {now['edge3']} "
                     f"(baseline {base.get('edge3')})")
    check("B2 SUBWHITE at 720p as hevc, h264 and prores_422: 1084 × 720 and the middle "
          "row's last three columns are white — no black column at the right",
          good, "\n       ".join(lines))


def row_b3(s):
    good, lines = True, []
    for fixture in ("ODDFULL", "TALLFULL"):
        for preset in ("hevc", "h264", "prores_422"):
            now = case_odd(s, fixture, preset)
            base = s.cases.get(f"G1 {fixture} {preset}") or {}
            good = good and now["eight_class"] == ["red"] * 8
            lines.append(f"{fixture} {preset}: {now['eight']} (baseline classes "
                         f"{base.get('eight_class')})")
    check("B3 ODDFULL and TALLFULL with no size as hevc, h264 and prores_422: the middle "
          "row's columns 0, 1, w−2, w−1 and the middle column's rows 0, 1, h−2, h−1 are "
          "all red — no black line at any edge", good, "\n       ".join(lines))


def row_b4(s):
    if s.foreign:
        skip("B4 prores_4444's three files equal the baseline's", s.foreign)
        return
    good, lines = True, []
    for fixture, size in (("CLEAR", None), ("CLEAR", "720p"), ("ODD", None)):
        base = s.cases[f"B4 {fixture} prores_4444 {size or 'document'}"]
        now = case_plain(s, fixture, "prores_4444", size)
        same, text = held(base, now)
        good = good and same
        lines.append(f"{fixture} at {size or 'the document size'}: {now['file']} {text}")
    check("B4 prores_4444 for CLEAR at the document size, CLEAR at 720p and ODD at the "
          "document size: the size and frame 0's digest equal the baseline's",
          good, "; ".join(lines))


def row_l1(s):
    done, raster = written(s, "SUBWHITE", "hevc", [640, 640])
    top, bottom, centre = raster.pixel(320, 0), raster.pixel(320, 639), raster.centre()
    check("L1 SUBWHITE as hevc at [640, 640]: 640 × 640, the middle column's top and "
          "bottom pixels are black and the centre is white — another shape is letterboxed",
          done["file"] == [640, 640] and kind(top) == "black" and kind(bottom) == "black"
          and white(centre), f"{sized(done)}; top {top}, bottom {bottom}, centre {centre}")


def row_l2(s):
    good, lines = True, []
    for preset in ("hevc", "h264", "prores_422"):
        now = case_l2(s, preset)
        base = s.cases.get(f"L2 WIDE {preset} 402x100") or {}
        same = s.foreign is not None or now["black"] == base.get("black")
        good = (good and now["answer"] == [402, 100] and now["file"] == [402, 100]
                and len(now["black"]) == 2 and same and white(now["column200"]))
        lines.append(f"{preset}: answer {now['answer']} file {now['file']}, black columns "
                     f"{now['black']} (baseline {base.get('black')}), column 200 "
                     f"{now['column200']}")
    check("L2 WIDE as hevc, h264 and prores_422 at [402, 100]: 402 × 100, exactly 2 black "
          "pixels in the middle row" + (" [another host's baseline: their columns are "
                                        "printed, not compared]" if s.foreign else
                                        ", at the baseline's columns,")
          + " and column 200 white — a frame typed wider than the canvas is letterboxed",
          good, "\n       ".join(lines))


def row_n1(s):
    project = str(s.fx["CLEAR"])
    must(s.client, "select_inspector_tab", {"project": project, "tab": "document"})
    views, problems = layout_of(s, "inspector-CLEAR", window="editor", view="inspector",
                                project=project)
    visible = [v for v in views if not v.get("hidden") and v.get("text")]
    notes = [v for v in visible if v["text"] == NOTE]
    said = [v["text"] for v in visible if v["text"].startswith("Transparent")]
    widths = [v["intrinsic"][0] for v in notes]
    check(f"N1 the Document tab on CLEAR shows \"{NOTE}\" once, no wider than "
          f"{NOTE_WIDTH} pt at the inspector's narrowest, and not truncated",
          len(notes) == 1 and widths[0] <= NOTE_WIDTH
          and NOTE not in truncated_texts(views, problems),
          f"texts beginning \"Transparent\": {said}; the note's intrinsic width {widths}, "
          f"its frame {[v['frame'] for v in notes]}; truncated "
          f"{truncated_texts(views, problems)}")


def row_e1(s):
    seen = read_sheet(*sheet(s, "CLEAR"))
    summary = [t for t in seen["texts"] if "MOV" in t and t.endswith("alpha")]
    tips = [seen["tips"].get(t) for t in summary]
    cut = [f"{t!r} needs {seen['widths'][t][0]} pt and has {seen['widths'][t][1]}"
           for t in summary if t in seen["truncated"]]
    check(f"E1 the Export sheet on CLEAR opens on \"{ALPHA_FORMAT}\", not truncated, its "
          "footnote's text holds \"MOV\" and ends \"alpha\", and the footnote's tooltip is "
          "that whole text",
          seen["format"] == ALPHA_FORMAT and len(summary) == 1 and tips == summary
          and ALPHA_FORMAT not in seen["truncated"],
          f"format {seen['format']!r}; texts holding MOV and ending alpha: {summary}; "
          f"tooltip {tips}"
          + (f"\n       printed, not scored: the footnote is drawn cut — {'; '.join(cut)} "
             "beside the three buttons, so it ends in a tail ellipsis before the word "
             "(Sheets.swift's sheetFootnote; ProRes 4444's footnote is cut the same way); "
             + ("its tooltip carries the whole line" if tips == summary else
                "its tooltip does NOT carry the line")
             if cut else ("; the footnote is drawn whole" if summary else "")))


def row_x1(s):
    done = export(s, "CLEAR", "hevc_alpha")
    said = (done["error"] or "")
    said = said[len("export: "):] if said.startswith("export: ") else said
    details["X1"] = said or f"EXPORTED {sized(done)}"
    check("X1 with no encoder for the row, CLEAR as hevc_alpha answers exactly "
          f"\"{UNAVAILABLE}\" and nothing is at the path",
          (not done["ok"]) and said == UNAVAILABLE and not done["path"].exists(),
          f"it answered: {details['X1']}; a file at the path: {done['path'].exists()}"
          + (f" ({done['path'].stat().st_size} bytes)" if done["path"].exists() else ""))


def row_g1(s):
    """Gate A's own row: phase A moved no pixel where it acts, and phase B
    is absent."""
    if s.foreign:
        skip("G1 ODDFULL's and TALLFULL's files equal the baseline's", s.foreign)
        return
    good, lines = True, []
    for fixture in ("ODDFULL", "TALLFULL"):
        for preset in EVEN_ROWS:
            base = s.cases[f"G1 {fixture} {preset}"]
            done = export(s, fixture, preset)
            if not done["ok"] or done["file"] is None:
                good = False
                lines.append(f"{fixture} {preset}: no file ({done['error']})")
                continue
            raster = Raster(done["path"])
            eight = raster.eight()
            now = {"frame0": raster.digest(), "samples": raster.samples(), "eight": eight,
                   "eight_class": [kind(p) for p in eight]}
            if base["frame0"] is None:
                same = (base["eight_class"] is not None
                        and base["eight_class"] == now["eight_class"])
                text = ("[the recordings disagreed on frame0: the eight pixels' classes "
                        "compared instead] " + ("equal" if same else
                                                f"{now['eight_class']} against "
                                                f"{base['eight_class']}"))
            else:      # R1 and R2 score the sizes
                same, text = held({key: base[key] for key in ("frame0", "eight")}, now)
            black = now["eight_class"].count("black")
            good = good and same and black >= 1
            lines.append(f"{fixture} {preset}: {text}, {black} of the eight black")
    absent = export(s, "CLEAR", "hevc_alpha")
    unknown = (not absent["ok"]) and absent["error"].startswith(
        'export: unknown export preset "hevc_alpha"') and not absent["path"].exists()
    design = ""
    if absent["ok"]:
        design = ("\n       RED BY DESIGN: this build holds phase B — hevc_alpha is a row "
                  "and a miss within a pixel is filled, so the pad the baseline recorded is "
                  "gone. G1 is Gate A's row, passed on the phase A build (fcfeebf); this "
                  "build's proof is the full rows (no --rows).")
        details["G1"] = "by design"
    check("G1 ODDFULL and TALLFULL as h264, hevc and prores_422: frame 0's digest and the "
          "eight edge pixels equal the baseline's, a black one among them; hevc_alpha is "
          "still an unknown preset and writes no file",
          good and unknown,
          "\n       ".join(lines) + f"\n       hevc_alpha: {absent['error'] or 'EXPORTED'}"
          + design)


def line_i1(s):
    """I1, printed and never scored: what Reelcut draws when it re-imports
    its own translucent alpha exports over white."""
    for preset in ("hevc_alpha", "prores_4444"):
        try:
            done = export(s, "FAINT", preset)
            if not done["ok"]:
                raise RuntimeError(done["error"])
            package = s.dir / f"I1-{preset}.reelcut"
            project = str(package)
            must(s.client, "new_project", {"path": project})
            s.fx[f"I1-{preset}"] = package
            must(s.client, "set_canvas", {"project": project, "width": 640, "height": 360,
                                          "background": [1, 1, 1, 1]})
            track = must(s.client, "get_project",
                         {"project": project})["project"]["tracks"][0]["id"]
            media = must(s.client, "import_media",
                         {"project": project, "path": str(done["path"])})["media"]
            must(s.client, "add_clip", {"project": project, "track": track, "media": media,
                                        "at": 0})
            png = s.out / f"I1-{preset}.png"
            must(s.client, "render_frame", {"project": project, "t": SECOND // 2,
                                            "path": str(png)})
            raster = Raster(png)
            print(f"  I1   (printed, not scored) FAINT's {preset} file re-imported over an "
                  f"opaque white 640 × 360 canvas, render_frame at 0.5 s: the card's centre "
                  f"is {raster.centre()} and the corner {raster.pixel(0, 0)}; the file's own "
                  f"centre pixel decodes {Raster(done['path']).centre()}", flush=True)
        except Exception as error:  # printed either way; the line is never a score
            print(f"  I1   (printed, not scored) {preset}: could not be measured — "
                  f"{type(error).__name__}: {error}", flush=True)


ROWS = {
    "T0": lambda s, full: row_t0(s, full),
    "R1": lambda s, full: row_r12(s, full),     # R1 and R2 are scored together
    "R3": lambda s, full: row_r3(s),
    "R4": lambda s, full: row_r4(s),
    "E2": lambda s, full: row_e2(s, full),
    "A1": lambda s, full: row_a1(s),
    "A2": lambda s, full: row_a2(s),
    "A3": lambda s, full: row_a3(s),
    "A4": lambda s, full: row_a4(s),
    "A5": lambda s, full: row_a5(s),
    "S1": lambda s, full: row_s1(s),
    "S2": lambda s, full: row_s2(s),
    "O1": lambda s, full: row_o1(s),
    "O2": lambda s, full: row_o2(s),
    "O3": lambda s, full: row_o3(s),
    "O4": lambda s, full: row_o4(s),
    "O5": lambda s, full: row_o5(s),
    "P1": lambda s, full: row_p(s, "P1", "hevc_alpha"),
    "P2": lambda s, full: row_p(s, "P2", "prores_4444"),
    "B1": lambda s, full: row_b1(s),
    "B2": lambda s, full: row_b2(s),
    "B3": lambda s, full: row_b3(s),
    "B4": lambda s, full: row_b4(s),
    "L1": lambda s, full: row_l1(s),
    "L2": lambda s, full: row_l2(s),
    "N1": lambda s, full: row_n1(s),
    "E1": lambda s, full: row_e1(s),
    "X1": lambda s, full: row_x1(s),
    "G1": lambda s, full: row_g1(s),
}


def score(s, names, full):
    """Each named row in turn; one that cannot run is a failure, not an
    exit. R2 rides on R1."""
    for name in names:
        if name in ("H0", "Z1") or (name == "R2" and "R1" in names):
            continue
        try:
            ROWS["R1" if name == "R2" else name](s, full)
        except Exception as error:  # a row that could not run is a failure
            check(f"{name} could not be scored", False, f"{type(error).__name__}: {error}")
            if name == "R1":
                rows.setdefault("R2", False)


def close_all(s):
    closes = [attempt(s.client, "close_project", {"project": str(path), "discard": True})
              for path in s.fx.values()]
    return all(c["ok"] for c in closes), [c.get("error", "ok") for c in closes]


def session(label, app, body, full, choice=CHOICE, env=None, baseline=None, foreign=None):
    """One launch: H0, the fixtures, `body(s)`, then every project closed
    and Z1. True when the instance listened and the body ran to its end."""
    s = Session(label, app, choice, env)
    s.cases, s.foreign = (baseline or {}).get("cases") or {}, foreign
    ran = False
    try:
        if not s.launch():
            print(f"instrument failure: the app did not listen at {s.launched.socket_path}")
            return False
        print(f"  instance PID {s.launched.child.pid} at {s.launched.socket_path}"
              + (f", with {' '.join(sorted(s.env))} set" if s.env else ""), flush=True)
        support = s.home / "Library/Application Support"
        check("H0 the scratch home took: <home>/Library/Application Support is a directory",
              support.is_dir(), str(support))
        if rows.get("H0"):
            try:
                fixtures(s, full)
                body(s)
                ran = True
            except Exception as error:  # a body that could not run is a failure
                print(f"  FAIL could not go on: {type(error).__name__}: {error}", flush=True)
            closed, how = close_all(s) if s.fx else (False, ["no fixture was made"])
            complaints = [line.strip() for line in open(s.log, errors="replace")
                          if "Reelcut: " in line]
            check("Z1 every project closes and the log holds no `Reelcut: ` line",
                  closed and not complaints, f"closed {how}; complaints {complaints}")
    finally:
        s.stop()
    return ran


# ---- mutants and controls --------------------------------------------------------

SETTINGS = "app/Sources/ExporterWriter+Settings.swift"
MUTANTS = {
    "encoder-refused": {
        "anchors": [
            (SETTINGS,
             "        if codec == .hevcWithAlpha {\n",
             "        if codec == .hevcWithAlpha {\n"
             "            output[AVVideoEncoderSpecificationKey] = [\n"
             "                kVTVideoEncoderSpecification_EncoderID as String:\n"
             "                    \"com.example.no-such-encoder\"\n"
             "            ]\n"),
            ("app/Sources/ExporterErrors.swift",
             "        guard case .failure(let error) = result else { return result }\n",
             "        if ProcessInfo.processInfo.environment[\"RC_MUTANT_UNMAPPED\"] != nil {\n"
             "            return result\n"
             "        }\n"
             "        guard case .failure(let error) = result else { return result }\n"),
        ],
        "launches": [({}, {"fail": ["A1"], "pass": ["X1"]}),
                     ({"RC_MUTANT_UNMAPPED": "1"}, {"fail": ["X1"], "pass": []})],
    },
    "report-and-fill": {
        "anchors": [
            ("core/src/export_table.rs",
             "        self.avf_preset.is_some() && self.codec != \"prores4444\"\n",
             "        false\n"),
            (SETTINGS,
             "        return shape.gap > 0 && shape.gap <= shape.limit\n",
             "        return shape.gap > 0 && shape.gap <= shape.limit && false\n"),
        ],
        "launches": [({}, {"fail": ["R1", "R2", "R4", "E2", "O1", "O5", "P1", "P2", "B2",
                                    "B3"],
                           "pass": ["R3", "S1", "S2", "L1", "L2"]})],
    },
    "shape-and-note": {
        "anchors": [
            (SETTINGS,
             "        let shape = shapeGap(encodedSize(settings), canvas: canvas)\n"
             "        guard shape.gap > shape.limit else { return }\n",
             "        if codecType(for: settings.codec) == .hevcWithAlpha { return }\n"
             "        let shape = shapeGap(encodedSize(settings), canvas: canvas)\n"
             "        guard shape.gap > shape.limit else { return }\n"),
            ("app/Sources/DocumentPane.swift",
             "        guard formats.count < 3 else {\n",
             "        guard formats.count < 3 || !formats.isEmpty else {\n"),
            (SETTINGS,
             "        let limit = inside ? max(cw, ch) : (d > 0 ? ch : cw)\n",
             "        let limit = max(cw, ch)\n"
             "        _ = inside\n"),
            (SETTINGS,
             "        let shape = shapeGap(encodedSize(settings), canvas: canvas)\n"
             "        return shape.gap > 0 && shape.gap <= shape.limit\n",
             "        if ProcessInfo.processInfo.environment[\"RC_MUTANT_FILL_ALL\"] != nil {\n"
             "            return true\n"
             "        }\n"
             "        let shape = shapeGap(encodedSize(settings), canvas: canvas)\n"
             "        return shape.gap > 0 && shape.gap <= shape.limit\n"),
        ],
        "launches": [({}, {"fail": ["S1", "N1", "L2", "S2"], "pass": ["L1", "O1"],
                           "half": ("S2", "prores_4444")}),
                     ({"RC_MUTANT_FILL_ALL": "1"}, {"fail": ["L1"], "pass": []})],
    },
}


def own_core(copy):
    """Makes the copy's `core/` its own, so a mutant may edit it:
    `tree_copy.make_copy` links `core` to the tree's, and an anchor replaced
    through that link would be replaced in the TREE. The sources and the two
    Cargo files are copied, `include/` is linked, and the tree's release
    artifacts are cloned (`cp -c`, copy-on-write) so the copy's cargo
    compiles the two local crates and not every dependency; when the clone
    fails the build is simply a cold one. The reason, or None."""
    link, tree = copy / "core", ROOT / "core"
    try:
        if not link.is_symlink():
            return f"{link} is not the link make_copy makes"
        link.unlink()
        link.mkdir()
        for name in ("Cargo.toml", "Cargo.lock"):
            shutil.copy2(tree / name, link / name)
        shutil.copytree(tree / "src", link / "src")
        os.symlink(tree / "include", link / "include")
        (link / "target").mkdir()
    except OSError as error:
        return f"the copy's core/ could not be made its own: {error}"
    cloned = bounded.run(["cp", "-cRp", str(tree / "target/release"),
                          str(link / "target/release")], 600)
    if cloned["rc"] != 0:
        shutil.rmtree(link / "target/release", ignore_errors=True)
        print("  the tree's release artifacts could not be cloned; the copy's core builds "
              "cold", flush=True)
    return None


def build_mutant(name):
    """A copy of the tree with every anchor of the mutant replaced, built by
    its own `make app`. The app bundle, or None and why."""
    anchors = MUTANTS[name]["anchors"]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if any(path.startswith("core/") for path, _, _ in anchors):
        reason = own_core(copy)
        if reason:
            return None, reason
    for path, anchor, replacement in anchors:
        target = copy / path
        if target.resolve().is_relative_to(ROOT) and not target.resolve().is_relative_to(WORK):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    print(f"  building the copy ({len(anchors)} anchors replaced, each found once)…",
          flush=True)
    built = bounded.run(["make", "app"], BUILD_BOUND, cwd=str(copy))
    app = copy / "build/Build/Products/Release/Reelcut.app"
    if built["rc"] != 0 or not (app / "Contents/MacOS/Reelcut").exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    print(f"  built in {built['seconds']:.0f} s", flush=True)
    return app, ""


def run_mutant(name, baseline, foreign):
    print(f"B85 phase 3 — the {name} MUTANT", flush=True)
    app, why = build_mutant(name)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    verdicts = []
    for index, (env, want) in enumerate(MUTANTS[name]["launches"], 1):
        rows.clear()
        details.clear()
        named = want["fail"] + want["pass"]
        order = [r for r in FULL_ROWS + ["X1"] if r in named]
        print(f" launch {index} of {len(MUTANTS[name]['launches'])}: "
              f"{', '.join(want['fail'])} must FAIL"
              + (f"; {', '.join(want['pass'])} must PASS" if want["pass"] else ""), flush=True)
        ran = session(f"mutant-{index}", app, lambda s: score(s, order, True), True, env=env,
                      baseline=baseline, foreign=foreign)
        if not ran or any(r not in rows for r in named) or not rows.get("Z1"):
            print(f"mutant {name}: the control could not be performed — launch {index} "
                  f"reached {sorted(r for r in named if r in rows)} of {sorted(named)} "
                  f"(Z1 {rows.get('Z1')})")
            return 2
        wrong = ([f"{r} passed" for r in want["fail"] if rows[r]]
                 + [f"{r} failed" for r in want["pass"] if not rows[r]])
        if "half" in want:
            row, half = want["half"]
            if (details.get(row) or {}).get(half) is not False:
                wrong.append(f"{row}'s {half} half did not fail")
        if "X1" in want["fail"]:
            print(f"       what a build without the mapping answers: {details.get('X1')}")
        verdicts.append((index, wrong))
    caught = all(not wrong for _, wrong in verdicts)
    print(("MUTANT PASS" if caught else "MUTANT FAILURE") + f": {name} — "
          + "; ".join(f"launch {i}: " + ("every named row did what is named" if not wrong
                                         else ", ".join(wrong)) for i, wrong in verdicts))
    return 0 if caught else 1


def control_readers(s):
    """A1's and A2's pixel readers over plain `hevc` exports."""
    for row, fixture, reader in (("A1", "CLEAR", card_reading), ("A2", "FAINT", faint_reading)):
        _, raster = written(s, fixture, "hevc")
        good, text = reader(raster)
        check(f"{row} the reader over {fixture} exported as plain hevc", good,
              f"{text}; alphas {raster.alphas()[:4]}")


def run_control(name, app, baseline, foreign):
    print(f"B85 phase 3 — the {name} CONTROL", flush=True)
    if name == "plain-hevc-reader":
        named, choice, body = ["A1", "A2"], CHOICE, control_readers
    else:
        named, choice, body = ["E1"], None, lambda s: score(s, ["E1"], True)
    ran = session("control", app, body, True, choice=choice, baseline=baseline,
                  foreign=foreign)
    if not ran or any(r not in rows for r in named) or not rows.get("Z1"):
        print(f"control {name}: could not be performed — reached "
              f"{sorted(r for r in named if r in rows)} of {named} (Z1 {rows.get('Z1')})")
        return 2
    caught = not any(rows[r] for r in named)
    print(("CONTROL PASS" if caught else "CONTROL FAILURE") + f": {name} — "
          + ", ".join(f"{r} {'FAILED' if not rows[r] else 'passed'}" for r in named)
          + (" as it must" if caught else "; each had to fail"))
    return 0 if caught else 1


# ---- main ------------------------------------------------------------------------

def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def foreign_text(baseline, today):
    return ("not scored — the baseline is another host's, and this row reads its bytes.\n"
            f"       the baseline's host: {host_text(baseline.get('host'))}\n"
            f"       today's host:        {host_text(today)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--rows", choices=["size"])
    parser.add_argument("--record-baseline", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--control", choices=["plain-hevc-reader", "sheet-default"])
    args = parser.parse_args()
    if sum(map(bool, (args.rows, args.record_baseline, args.mutant, args.control))) > 1:
        print("instrument failure: --rows, --record-baseline, --mutant and --control are "
              "one at a time")
        return 2
    try:
        today = host()
    except Exception as error:  # no chip, no macOS version or no ffmpeg to name
        print(f"instrument failure: the host could not be read: {error}")
        return 2
    binary = Path(args.app) / "Contents/MacOS/Reelcut"
    if not args.mutant and not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    remove_work()
    atexit.register(remove_work)
    WORK.mkdir(parents=True)
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
    if args.mutant or args.control:
        # Neither names a digest row; the baseline is what L2's columns are
        # compared with and what the fill rows are printed beside, when it is
        # this host's and whole.
        usable = baseline is not None and baseline.get("recordings", 0) >= 2
        foreign = (None if usable and baseline.get("host") == today else
                   "no baseline of this host's to compare with")
        if args.mutant:
            return run_mutant(args.mutant, baseline if usable else None, foreign)
        return run_control(args.control, args.app, baseline if usable else None, foreign)
    if args.record_baseline:
        print("B85 phase 3 — recording the baseline", flush=True)
        print(f"  host {host_text(today)}", flush=True)
        document = []
        ran = session("record", args.app, lambda s: document.append(record(s, today)), False)
        if not (ran and rows.get("H0") and rows.get("Z1")):
            print("NOT RECORDED: the instrument could not run")
            return 2
        if not document or document[0] is None:
            return 1
        write_baseline(document[0])
        return 0

    if baseline is None:
        print(f"instrument failure: no baseline at {BASELINE} (--record-baseline, twice, "
              "on the build before G-33's code)")
        return 2
    if baseline.get("recordings", 0) < 2:
        print(f"instrument failure: the baseline holds {baseline.get('recordings')} "
              "recording; it takes two")
        return 2
    foreign = None if baseline.get("host") == today else foreign_text(baseline, today)
    full = args.rows != "size"
    names = FULL_ROWS if full else SIZE_ROWS
    print("B85 phase 3 — " + ("the size reported is the size written, HEVC with alpha, the "
                              "fill within a pixel" if full else
                              "Gate A: the size reported is the size written"), flush=True)
    print(f"  host {host_text(today)}" + (
        f" — the baseline's, recorded on the build of {str(baseline.get('head'))[:7]}"
        if foreign is None else
        f" — NOT the baseline's ({host_text(baseline.get('host'))}): "
        f"{', '.join(r for r in DIGEST_ROWS if r in names)} will not be scored"), flush=True)

    def body(s):
        score(s, names, full)
        if full:
            line_i1(s)

    session("rows", args.app, body, full, baseline=baseline, foreign=foreign)
    skipped = [name for name in names if name in rows and rows[name] is None]
    scored = [name for name in names if name not in skipped]
    passed = sum(1 for name in scored if rows.get(name))
    failed = [name for name in scored if not rows.get(name)]
    print(f"{passed}/{len(scored)}" + (
        f" — not scored: {', '.join(skipped)} (the baseline is another host's; record one "
        "for this host: tools/proof/README.md, this proof's section)" if skipped else "")
        + (" — G1 is RED BY DESIGN on a build that holds phase B; it is Gate A's row and "
           "the only one that failed" if failed == ["G1"] and details.get("G1") else ""))
    if failed:
        return 1
    return 2 if skipped else 0


if __name__ == "__main__":
    sys.exit(main())
