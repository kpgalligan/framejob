# Road map "precision-2" — the paths still 8-bit (#257): deep stills and the 10-bit reverse

**Opened 2026-10-11** (P2-0, in the worktree `~/devel/reelcut-i257` on branch `i257`, from
`19ef985`, merged into main after its gate). The design brief this road map answers is
`~/.claude/litecode/reelcut/i257-8bit-paths/I-257.md` (2026-10-11, tree `19ef985`), and the
owner's answers are `~/.claude/litecode/reelcut/i257-8bit-paths/answers.md`. Both live outside
the repo, so everything a later phase needs from them is written here. Where the brief and this
file differ, this file wins. The precision road map is closed: its condensed record is
`designs/adr/precision.md`, the original `archive/precision.md`, and its decisions are spec §11
PR-1..PR-5 (`designs/spec/11-decisions/precision.md`). This road map's decisions are PR-6..PR-8,
in the same file.

## Goal

Settle the four items PR-5 left 8-bit and #257 names. Build two: **deep stills** (a 16-bit PNG
or TIFF drawn at 16-bit float, P2-1) and **the 10-bit reversed-clip intermediate** (HEVC Main 10
carrying the source's colour labels, ProRes 422 for an odd size, P2-2). Close two as not wanted:
**10-bit `hevc_alpha`** and **10-bit screen recording** (PR-8). The reverse phase also fixes the
odd-size defect the brief found (a 1919×1079 source reversed to 1918×1078). Each code phase lands
whole on main, judged by its own proofs; its person check joins `docs/manual-checks.md`'s
standing list in the phase that creates it.

## The owner's choices

**2026-10-11**, verbatim (`answers.md`): "I-257.md choices "All as recommended" — 1a deep stills
BUILD; 2a every reverse at HEVC Main 10 with the source colour labels BUILD; 3 10-bit hevc_alpha
CLOSE (not wanted, write into §11); 4 10-bit screen recording CLOSE (not wanted, §11); 5 worktree
~/devel/reelcut-i257 branch i257, merged per phase. The odd-size reverse defect (1919×1079 →
1918×1078) is FIXED in the reverse phase P2-2, not filed (owner rule: do a leftover now)." The
choices therefore read:

1. **(a) Deep stills, build.** A still whose file is deeper than 8 bits a component is drawn at
   16-bit float; an 8-bit still is drawn as today (PR-6).
2. **(a) The 10-bit reverse, build, for every reverse.** Every reverse is written as HEVC Main 10,
   the source's colour labels carried over (HLG stays HLG), the frames held as 10-bit 4:2:0. The
   odd-size fix makes one exception: an odd width or height is written as ProRes 422 from `x422`
   frames, so the size stays exact (PR-7).
3. **Close.** A 10-bit `hevc_alpha` is not wanted (PR-8).
4. **Close.** 10-bit screen recording is not wanted (PR-8).
5. **(b) The grading-2 way.** One worktree outside the repo folder, `~/devel/reelcut-i257` on
   branch `i257`, each phase merged into main as soon as its `make gate` passes ("Where the work
   happens" below).

## Deep stills (P2-1)

**Where the depth is lost** (all line numbers as at `19ef985`). `MediaCacheFiles.decodeImage`
(ImageIO's `CGImageSourceCreateThumbnailAtIndex` with `FromImageAlways`, `WithTransform`, max
8192) returns a 16-bit-a-component image for a 16-bit PNG and a 16-bit TIFF, measured (bpc 16,
bpp 64). The depth is thrown away by `LayerRenderers.renderImage` (`LayerRenderers.swift:446`),
which draws every image into `LayerRenderers.bitmap` (`:464`, 8-bit premultiplied BGRA, sRGB),
then uploads it as `.bgra8Unorm` (`upload`, `:485`).

**What changes** (PR-6). In `renderImage`: when `image.bitsPerComponent > 8`, draw into a
16-bit-float premultiplied RGBA sRGB context (`premultipliedLast | floatComponents |
byteOrder16Little`) and upload it as `.rgba16Float`. Otherwise keep today's path byte for byte.
`Compositor.source(for:)` (`Compositor.swift:678`) already samples a float texture through
`.textured(…, premultiplied: true…)`, and the shader reads `bgra8Unorm` and `rgba16Float` alike,
as it does for the deep video sources (PR-2). No shader, uniform, recipe or format change. The
decode is unchanged. Thumbnails, posters and the media row stay 8-bit (PR-5).
`LayerRenderers.swift` is 498 lines and takes about 30 (the brief's estimate), so it pays no
toll.

**Measured** (brief §8, host below): `ramp16.png` keeps bpc 16 and bpp 64 through the app's
decode; today's 8-bit bitmap gives 256 distinct greens, a 16-bit-float bitmap **1,024** distinct
10-bit codes. Decode+draw, median of 5: 87.3 ms (8-bit, the app's path) against 87.5 ms
(16-bit float) for the 1080p PNG; 12.2 against 13.7 ms for the TIFF. `ramp8.png` is 256 either
way at 25.7 against 63.4 ms, which is why an 8-bit still keeps today's path. A 3840×2160 deep
bitmap is 66,355,200 bytes (66.4 MB against 33.2 MB). The layer pool holds up to 64 entries
(`LayerRenderers.cacheLimit`), and only deep stills pay the doubled size.

**`render_frame`** keeps PR-4's mechanism: its PNG is the CGImage `AVAssetImageGenerator` hands
back. A stills-only project has only `CompositionBuilder.addPlaceholderIfNeeded`'s empty track,
so whether a deep still makes that image 16-bit is not established until S4 ("Not established"
below). The deep claim is proven through `prores_422` (S1).

## The 10-bit reverse (P2-2)

**Where the depth and the labels are lost** (all in `ReverseRenderer.swift`, line numbers as at
`19ef985`):
- `read` (`:752`) asks the reader for 32BGRA. It asks for `x420`
  (`kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`) for an even-sized source and `x422` for an
  odd-sized one. The `dimensions` read can stay 32BGRA.
- `copyBuffer` (`:844`) refuses any buffer with more than one plane, so `x420` frames would be
  silently dropped, and it drops the decoder's colour attachments. It becomes a per-plane copy
  with `CVBufferPropagateAttachments`, so the frames' own labels reach the writer.
- `videoSettings` (`:1075`) writes H.264 High at ≤ 1080p and HEVC Main above, labelled BT.709
  (primaries, transfer, matrix). It becomes HEVC with `kVTProfileLevel_HEVC_Main10_AutoLevel` at
  every size, at HEVC's rate (0.12 bits/pixel/frame, 2–240 Mbps), for an even-sized source, and
  ProRes 422 for an odd-sized one; neither carries `AVVideoColorPropertiesKey`. The adaptor's
  pixel format follows (`x420` or `x422`).
- `sliceDuration` (`:1109`) sizes slices at 4 bytes a pixel. It counts the held format's bytes
  per pixel. Decoded frame bytes at 1080p: BGRA 8,294,464; `x420` 6,225,184; `x422` 8,359,264.
- `ReverseCache.digest` (`:87`) covers the source's path, size and modification second only, so
  a package would keep playing its old 8-bit reverse. The digest's input gains a renderer
  version; the next render lands under a new name, and `prune` (`:72`) already deletes the old
  sibling. §5.6's `<media id>-<digest>.mov` pattern is unchanged.

**The colour labels.** Measured: an HLG BT.2020 ramp reversed today holds HLG-coded values (mean
|Δ| 0.5 8-bit levels against the source, both read as `64RGBAHalf`), but its file says
`bt709/bt709/bt709`. The Main 10 variant with no forced labels keeps
`arib-std-b67/bt2020/bt2020nc` and reads back identical (mean |Δ| 0.0). Through the brief's
transcode (which keeps the reader's attachments), forcing BT.709 converted the picture (mean
|Δ| 20.8 and 20.6 8-bit levels), so forcing labels is wrong either way. PR-2 stands: HDR stays
tone-mapped in the compositor; the reverse only stops mislabelling. The forward clip goes
through AVFoundation's HLG-to-SDR conversion (PR-2), so today's reversed HLG clip is very
likely drawn flatter than its forward twin (REASONED; V3 reads it).

**The odd-size fix.** HEVC 4:2:0 cannot hold an odd size: measured, a 1919×1079 source came back
1918×1078 from both today's renderer (H.264) and the Main 10 variant (HEVC, coded 1920×1088
cropped to 1918×1078). `videoSettings`' own doc says the size must be exact, or the clip
stretches the moment it is reversed. The brief's transcode probe wrote ProRes 422 from `x422` at
1919×1079: ffprobe of `/Users/kevingalligan/devel/reelcut/tools/proof/work/i257/out/odd_pr422x422.mov`
reads `prores,Standard,1919,1079,yuv422p10le`, against `hevc,Main 10,1918,1078` for
`odd_m10x420.mov`.
- **Its cost** (brief §8, codec cost alone): 66.8 Mbps against today's 12.0 at 1080p (0.23 s
  against 1.16 s for 300 frames), 226.3 against 29.0 at 4K (0.56 s against 1.65 s for 150
  frames), so roughly 5–8× today's file. On the flat 1919×1079 ramp fixture the file is
  2,727,219 bytes against 10,812 for today's (`odd_pr422x422.mov` against `odd_today.mov`). PR-7
  accepts this cost for exact size.
- **Why the branch is rare** (REASONED, not measured): a Retina capture is 2× its point size, so
  its pixel sizes are even. Odd sizes come from 1× displays and from cropped or odd-sized
  imported sources.
- If P2-2 measures the real renderer's odd-size path at any size but the source's, P2-2 stops
  and PR-7 returns to the owner.

**Measured on the real renderer** (brief §8: every `app/Sources` file but `main.swift`, with only
`ReverseRenderer.swift` swapped for a patched scratch copy; one run each, at load 16–18):

| Source | today: wall / file / peak RSS | Main 10: wall / file / peak RSS |
|---|---|---|
| ramp10_1080 (1 s) | 0.32 s / 0.03 MB / 306 MB | 0.34 s / 0.01 MB / 238 MB |
| motion10_1080 (10 s) | 1.53 s / 14.88 MB (11.9 Mbps) / 612 MB | 1.53 s / 9.11 MB (7.3 Mbps) / 477 MB |
| motion10_2160 (5 s) | 1.82 s / 18.16 MB (29.1 Mbps) / 783 MB | 1.86 s / 17.98 MB (28.8 Mbps) / 552 MB |
| testsrc2_640.mp4 (8-bit H.264, 1 s) | 0.16 s / 0.20 MB / 65 MB | 0.18 s / 0.22 MB / 57 MB |
| ramp10_odd (1919×1079) | 1918×1078 | 1918×1078 |

- Depth: today 219 distinct 10-bit codes at 2.226 steps RMS; Main 10 **872** at **0.466**,
  against the source's own 975 at 0.567.
- Codec cost alone, 4K (150 frames): today's HEVC Main 1.65 s; Main 10 from `x420` at HEVC's
  rate 1.90 s; each 28.8–29.0 Mbps.
- These figures are the even-sized HEVC Main 10 path only. The ProRes branch's are above.

**Host** (brief §8): Apple M2 Max, 96 GB, macOS 26.5.1 (25F80), `pmset -g`: `powermode 0`, AC
power, battery 100 % charged. ffmpeg 9.0.2. `vm.loadavg` was 3.33–3.84 for the transcode, still
and alpha runs, and 17.70 before and 15.91 after the real-renderer runs, with other sessions
working, so those wall times are comparisons on one load, not absolute figures.

**The toll** (P2-0, below): `ReverseRenderer.swift` was 1,311 lines. `// MARK: - Progress`
(`ReverseProgressSheetController`) went out whole to `ReverseProgressSheetController.swift`.
The next seam is named in `designs/adr/app-file-history.md`: `ReverseCache`,
`ReverseResolution`, `ReverseStatus` and `ReverseSource` to `ReverseCache.swift`.

## Closed as not wanted

PR-8, in brief:
- **10-bit `hevc_alpha`.** Main 10 with alpha works on this Mac (877 colour levels against 219
  at Main), but the alpha plane stays 8-bit at every profile (256 levels, measured). An alpha
  export's content is mostly PR-5's 8-bit graphics, text and captions, and `prores_4444` is the
  deep alpha master. No player's Main 10 alpha support was checked.
- **10-bit screen recording.** `SCRecordingOutputConfiguration` has no profile, depth or rate key
  (only `avc1`/`hvc1` and MP4/MOV, measured). The only documented 10-bit route is the HDR10 PQ
  preset (`captureHDRRecordingPreservedSDRHDR10`: `x420`, ITU-R 2100 PQ), which PR-2 would
  tone-map back. A self-written encoder would rebuild the recorder's pause and segment
  machinery.

## Spec §11 and the documents

- **§11:** PR-6..PR-8 recorded in P2-0, before any code, with PR-5's "Amended by" line and the
  index rows.
- **§5.6** (`05.6-persistence.md`, the digest sentence): "and the renderer's version" — P2-2.
- **§7.5** (`07.5-compositor.md`): a deep still is an `rgba16Float` source — P2-1.
- **`ReverseRenderer`'s doc comment**: "The intermediate is 8-bit BGRA into H.264/HEVC, so … a
  reversed HDR clip is tone-mapped by the decoder" is wrong today (brief §10: the decoder does
  not tone-map in this path; the copy drops the attachments and the writer mislabels). P2-2
  rewrites it.
- **`docs/manual-checks.md`**, under Precision: **PRC-3** (P2-2), a reversed iPhone HDR clip
  beside its forward twin, and a reversed log clip with a LUT, look the same as the forward part
  and show no new banding; **PRC-4** (P2-1), a 16-bit gradient still graded with a strong curve
  shows no contour bands in the preview and in a `prores_422` export.
- **`app/CLAUDE.md`**: the `ReverseRenderer.swift` entry and the moved sheet's entry (edited in
  P2-0, below).

## Where the work happens

Grading-2's arrangement (`archive/grading-2.md`, "Where the work happens"):
- One worktree, `~/devel/reelcut-i257` on branch `i257`, outside the repo folder. Each phase:
  `git merge main` first, then the code, then `make gate` in the worktree. When it passes, merge
  into main (a fast-forward when main has not moved, otherwise a merge commit), then start the
  next phase from main.
- Per worktree: `core/target/`, `build/`, `tools/proof/work/`, the generated project. Shared: the
  git objects, and the Debug and Release apps' identities and defaults domains (V-5).
- **There is no format number.** Nothing here is persisted project state: a reverse lives in
  `cache/`, and a still's texture is not written.
- **The pure move** (P2-0) lands on main first, so no merge has a moved file against an edited
  one.

## Phases

Each phase is one implement-review cycle, gated and merged into main alone, ending with the root
`CLAUDE.md`'s "Verification" (targeted tests in the loop on Debug, `make gate` once when the code
is complete, the phase's proof recorded whole on Release, the mutants once at the end). Controls
are captured on the tree before each phase, as precision did, and thresholds are set from them;
the figures quoted are the brief's.

| Phase | What lands | Its proof holds |
|---|---|---|
| P2-0 | This road map; PR-6..PR-8 in `11-decisions/precision.md`, PR-5's "Amended by" line and the index rows; the toll: `ReverseRenderer.swift`'s `// MARK: - Progress` out whole to `ReverseProgressSheetController.swift`, a pure move gated alone. | Both `diff`s against `git show HEAD:` print nothing; `make typecheck` at its baseline; `spec_index_proof.py`; `inventory.py --check`; `make gate`. No mutants: a pure move adds no decision. |
| P2-1 | **Deep stills** (PR-6): `LayerRenderers.renderImage` draws a deeper-than-8-bit image into a 16-bit-float bitmap and uploads `rgba16Float`; §7.5's sentence; PRC-4. | Rows in `precision_proof.py`. **S1**: a 1920×1080 16-bit PNG ramp, alone on the canvas, exported `prores_422`: the middle row's luma keeps ≥ 800 distinct 10-bit codes, and its RMS against the ideal is under the 8-bit control's (today's draw 256 levels; the deep draw 1,024). **S2**: the same with a 16-bit TIFF. **S3**: an 8-bit PNG still's `render_frame` is byte-identical to the control tree's. **S4**: `render_frame` of the 16-bit still: its PNG depth recorded and PR-6 held to it (stop-and-ask, "Not established"). Mutants: `still-eightbit` (a deep image into the 8-bit bitmap: S1 fails); `still-always-deep` (an 8-bit PNG takes the deep path: S3 should fail, but it may be equivalent if k/255 survives the float path exactly, so the phase measures it first and drops it if equivalent). |
| P2-2 | **The 10-bit reverse** (PR-7): `x420` reads for an even size and `x422` for an odd one, a per-plane copy keeping the attachments, HEVC Main 10 (or ProRes 422 when odd) with no colour key, the slice budget per format, the renderer's version in the digest; §5.6's sentence; the doc comment; PRC-3. | Rows in `precision_proof.py` and `source_mirror_probe.py`. **V0** (probe): the real renderer reverses the 10-bit ramp: the intermediate is `hevc` Main 10, read back ≥ 800 levels and under 1 step RMS; `source_mirror_probe` §3's stamps, count and first-stamp-zero still hold (today 219 / 2.226; Main 10 872 / 0.466). **V1** (MCP): `set_reversed` on the 10-bit ramp clip, exported `prores_422`: RMS within the forward clip's (R2) plus a margin. **V2** (probe): an HLG BT.2020 ramp's reverse keeps `arib-std-b67/bt2020/bt2020nc` and reads back equal to the source (today `bt709` ×3; Main 10 mean \|Δ\| 0.0). **V3** (MCP): `render_frame` of an HLG clip forward at t and reversed at the mirrored t agree within a stated bound. **V4**: an old-named (pre-version) reverse in `cache/reversed/` is not used and is pruned. **V5** (probe): an odd-sized 10-bit source (1919×1079) reverses to exactly 1919×1079, with frame count and stamps as `source_mirror_probe` §3. Mutants: `reverse-bgra` (the reader asks for 32BGRA: V0 fails); `reverse-main` (the Main pin: V0 fails); `reverse-709-labels` (forced 709 colour properties: V2 and V3 fail); `reverse-planar-drop` (the old copy's one-plane guard: V0 fails, no frames); `reverse-unversioned` (the digest without the version: V4 fails); `reverse-odd-hevc` (an odd source written as HEVC: V5 fails). |
| P2-3 | **The close**: condense this road map into `designs/adr/precision-2.md`, `git mv` it to `archive/`, add its `archive/INDEX.md` row, close #257, and file any residue as issues (reviewed against the tree first). PRC-3 and PRC-4 stay as standing rows for the owner. | — |

Stills come before the reverse because they are smaller and touch nothing the reverse touches.

## Not established

- **S4: `render_frame`'s depth for a stills-only project drawn deep.** Whether
  `AVAssetImageGenerator` hands back a 16-bit image when the only sources are deep stills (the
  composition has only `addPlaceholderIfNeeded`'s empty track). If S4 reads an 8-bit PNG, P2-1
  stops and the point returns to the owner as an amendment of PR-4's "any source is deeper";
  P2-1 does not append a bullet that contradicts PR-4.
- **V3: what the compositor shows for a reversed HLG clip against its forward twin.** The
  mislabel is measured; its look on screen is REASONED.
- Whether ImageIO decodes a 10-bit HEIF deep (no fixture was made).
- `source_mirror_probe.py` §3 on the new renderer (the brief's frame counts and sizes came from
  its scratch entry only); V0 and V5 run it.
- HEVC Main 10 decode cost during playback against H.264's, for the ≤ 1080p reverses that switch
  codec. Apple silicon decodes both in hardware, and the compositor decodes every source to
  `64RGBAHalf` already (REASONED: no difference worth measuring).
- The odd-size ProRes branch's cost on camera footage: the brief's figures are synthetic
  (testsrc2 and a flat ramp), and testsrc2 flatters HEVC (REASONED: ProRes's share would be
  larger still on camera footage).
- The real renderer's figures are one run each, at load 16–18.

## P2-0 — the road map, PR-6…PR-8 and the toll

**What landed** (2026-10-11, in the worktree on `i257`, from `19ef985`). This road map; PR-6,
PR-7 and PR-8 appended to `designs/spec/11-decisions/precision.md`, with a paragraph in its
opening saying who recorded them and one `**Amended by PR-6 and PR-7**` line under PR-5
(PR-1..PR-5's bodies untouched); the index rows in `11-decisions/README.md` (`precision.md`'s Lines and
Holds cells, PR-5's row amended, three new rows); `designs/spec/README.md`'s `11-decisions/`
cell, and its `05.2-project-schema.md` row's stale "(format version 16)" corrected to 18 (the
file's heading and `RC_FORMAT_VERSION` are both 18); a bullet in
`designs/adr/app-file-history.md`'s "Named next cuts"; and one pure move, gated alone, with no
behaviour change:

| Move | `wc -l` before → after | New file | What widened |
|---|---|---|---|
| `ReverseRenderer.swift` → `ReverseProgressSheetController.swift`: `// MARK: - Progress` through EOF (HEAD lines 1122–1311, the whole `ReverseProgressSheetController`), byte for byte under `import AppKit` and a blank line; the blank line before the MARK (1121) dropped | 1,311 → 1,120 | 192 | nothing |

`ReverseRenderer.swift` keeps both its imports. The class's one caller
(`ProjectDocument.swift:928`) and the doc comments that name it (`CaptionExporter.swift:352`,
`EditorViewController+SaveFrame.swift:273`, `TranscribeSheetController.swift:12`) name the
class, not the file, so they stay right. `tools/proof/capture_spike/inventory.json`'s one
`other_caller` anchor ``ReverseRenderer.swift `document?.ensureReversedMedia()` `` now names
`ReverseProgressSheetController.swift` (`inventory.py --check` needs an anchor to occur once in
the file it names).

**Verification**, 2026-10-11, AC power (`pmset -g`: powermode 0; `pmset -g batt`: AC Power,
100 % charged):
- `diff <(git show HEAD:app/Sources/ReverseRenderer.swift | sed -n '1122,1311p') <(sed -n
  '3,$p' app/Sources/ReverseProgressSheetController.swift)`: no output, exit 0. The new file's
  first two lines are `import AppKit` and an empty line.
- `diff <(git show HEAD:app/Sources/ReverseRenderer.swift | sed -n '1,1120p')
  app/Sources/ReverseRenderer.swift`: no output, exit 0.
- `make typecheck`: exit 0, 0 errors, exactly the 4 baseline warnings (3 in
  `CompositionBuilder.swift`, 1 in `Exporter.swift`); tsc printed no error.
- `python3 tools/proof/capture_spike/inventory.py --check`: 5/5 (K1–K5).
- `python3 tools/proof/spec_index_proof.py`: 153/153 checks passed. `precision.md`'s cell went
  from 114 to 183, and the `11-decisions/` cell from 6696 in 19 files to 6768 in 19.
- `make gate`, cold (no `build/` or `core/target/` in the worktree), on the final code and spec
  tree: PASS in 494 s (typecheck 5 s, fmt 2 s, lint 30 s, test 272 s, app 185 s, with D25 and
  D26 ok). The cargo suites passed 1,367 tests in 119 result lines and failed none;
  `inventory.py --check` 5/5 and `spec_index_proof.py` 153/153 among its proof steps. No test
  file was added or removed. This road map and the history file are not gate inputs
  (`gate.py`: only `designs/spec/` and `docs/` count among the `*.md`), so writing this record
  after the run changes no stamp.
- No app was launched and no MCP proof run: nothing a proof drives changed.
- No mutants: a pure move adds no decision.

**CLAUDE.md edits** (applied by the orchestrator after the gate; `app/CLAUDE.md` is not a gate
input, so the stamp holds):
- `app/CLAUDE.md` (lines 429–432), the `ReverseRenderer.swift` entry now reads:
  ```
  - `ReverseRenderer.swift` — `Source::Media.reversed` resolved to
    `cache/reversed/<id>-<digest>.mov`, rendered on demand behind
    `ReverseProgressSheetController.swift`'s sheet, substituted per
    CLIP by `CompositionBuilder`.
  ```
- `app/CLAUDE.md`, "Dialogs and windows" (line 1716): after
  `` `ExportProgressSheetController.swift` · `` it lists
  `` `ReverseProgressSheetController.swift` · ``.

P2-1 (deep stills, PR-6) is next, from main after this phase's merge.

## P2-1 — deep stills

**What landed** (2026-10-11, in the worktree on `i257`, from `34445fa`; main had not moved).
- **The product.** `app/Sources/LayerRenderers.swift` went from 498 to 537 lines and pays no
  toll.
  - `renderImage` decides on one line, `let deep = image.bitsPerComponent > 8`. A deep image is
    drawn into the new `deepBitmap(_:)` and uploaded `rgba16Float`. `deepBitmap` is 16-bit,
    `premultipliedLast | floatComponents | byteOrder16Little`, sRGB, with `bitmap(_:)`'s size
    guard.
  - Every other image takes today's three statements unchanged. `bitmap(_:)` is unchanged.
    `upload` gains `pixelFormat:`, defaulting to `.bgra8Unorm`.
  - The file header and `bitmap`'s doc now name the deep still as the one exception.
  - Nothing else in the product changed: no compositor, shader, decode, core, FFI, MCP or
    format change. Thumbnails, posters and media rows stay 8-bit (PR-5).
- **The proof.** `tools/proof/precision_proof.py` gains:
  - the rows S1, S2 and S4, the capture row Sc and the compare row S3;
  - the mutants `still-eightbit` and `still-deep-linear`;
  - an `also` key on a mutant: rows run and printed beside the named ones, and not required to
    fail;
  - an R1 fix, below.
- **The documents.**
  - §7.5's sentence on deep stills.
  - §11: PR-6's "Measured in P2-1" bullet, and an **Amended by PR-6** line under PR-4. No
    existing bullet was edited.
  - The `11-decisions/README.md` rows for PR-4 and PR-6, and `precision.md`'s Lines cell
    (183 → 190).
  - `designs/spec/README.md`'s cells: `07.5-compositor.md` 311 → 314, and `11-decisions/` 6768
    → 6775 in 19 files.
  - The README's Export bullet.
  - PRC-4 in `docs/manual-checks.md`.
  - A "precision-2 P2-1" paragraph and its commands in `tools/proof/README.md`.

**S4 and the owner's ruling.** S4 read an 8-bit PNG for the deep still. `render_frame` of a
project whose only picture is `ramp16.png` is depth 8 with the deep draw in place, as is
`ramp8.png`'s. The export keeps the depth (S1). P2-1 stopped there, per PR-6. The owner, on
2026-10-11: "Accept it". `render_frame` and Save Frame of a project whose only picture is a deep
still stay 8-bit, and exports keep the depth. That is now written down:
- PR-6's measured bullet says what S4 measured and that the owner accepted it.
- PR-4's amendment line says "any source is deeper" counts video sources only.
- S4 became a row that records the behaviour (both stills render 8-bit) rather than a STOP.

This settles the road map's "Not established" S4 item.

**The 8-bit control's fixture, changed after the first capture.** The spec's `ramp8.png` was
the 16-bit ramp converted by ffmpeg to `rgb24`. Its first control capture read a staircase tone
of 0.0301, under TONE_SEEN 0.3, which is step 3's "the instrument does not discriminate" stop.
- The file is a clean, undithered staircase of 256 monotonic levels.
- ffmpeg's `rgb48`→`rgb24` conversion truncates. That puts the steps near 256/(W−1) cycles a
  pixel, where Core Graphics' 8-bit draw rounds and puts them at 255/(W−1), the frequency
  `staircase_tone` reads. Columns 900–940: steps at 904, 911, 919, 926, 934 against Core
  Graphics' 907, 915, 922, 930, 937.
- Over the ~1,856 columns read, that offset nearly cancels the tone.
- The orchestrator chose to write the ramp 8-bit directly and rounded:
  `format=gbrp,geq=…round(X*255/(W-1))…`, `rgb24`. Every threshold is unchanged.
- The new file equals round(x·255/1919) in 1920 of 1920 columns. It matches Core Graphics' 8-bit
  draw of `ramp16.png` (the control's `still-png16.png`) in 1916 of 1920, max |Δ| 1, with the
  steps in the same columns (900, 907, 915, 922, 930, 937).

**The control** (`tools/proof/work/precision/ctl-p21/`, `RC_PROOF_APP=release … capture`, on
P2-0's product, re-captured with the rounded fixture): 6/6.
- Sc figures. `png16` and `tif16` each: `render_frame` depth 8, 512 distinct 10-bit codes, RMS
  1.414, tone [1.2236, 0.0134]. `png8`: depth 8, 513 distinct, RMS 1.4157, tone
  [1.2258, 0.0119].
- S3's renders: `still8.png` digest `044a37f9abf253b3`, `still8a.png` `ea377c67865e0f1e`, both
  8-bit.
- `--only S1,S2,S4 --control ctl-p21` on the same unchanged Release tree printed 1/4: S1 and S2
  FAIL (512 distinct), S4 recorded depth 8 for both stills, Z1 ok.
- On the old tree the deep ramp's RMS (1.414) is already a hair under the 8-bit control's
  (1.4157). S1 rejects the old draw on its distinct-code and tone halves; the RMS half alone
  does not discriminate.

**R1 against a deep-decoding control** (an instrument fix). The recorded run's first pass printed
13/14: R1 failed only on its control clause, "control 1418", where the clause wants ≤ 256.
- That clause is PR2's, written for a capture whose tree decoded 32BGRA. `ctl-p21` decodes
  `64RGBAHalf`.
- R1 now holds the control to ≤ 256 only when the capture's recorded `formats.source` is 32BGRA
  (or absent, PR0's). Otherwise it prints the control "decoded …: printed, not held to ≤ 256".
- The recorded run below is on the fixed instrument.

**Verification**, 2026-10-11, AC power (`pmset -g`: powermode 0; `pmset -g batt`: AC Power,
100 % charged). Other sessions were working: `vm.loadavg` read 2.75–50.37 around the runs and
149.85 at the end of the mutants. No timing is claimed here.
- `make typecheck`: exit 0, 0 errors, exactly the 4 baseline warnings; tsc clean.
- `make app-debug`: `** BUILD SUCCEEDED **`.
- Debug, in the loop:
  - `--only S1,S2,S4 --control ctl-p21`: S1 and S2 ok, S4 8-bit (the STOP above).
  - `compare ctl-p21 --only S3`: 2/2.
  - `--selftest`: 3/3.
- `make gate`, after the documents: PASS in 281 s (typecheck 15 s, fmt and lint skipped, test
  174 s, app 91 s; D25 and D26 ok).
- The R1 fix and the dropped mutant changed `precision_proof.py`, a test-step input, so the gate
  ran again on the final tree: PASS in 107 s (test 105 s, every other step skipped). Its test
  step: 1,367 cargo tests passed in 119 result lines, 0 failed; `spec_index_proof.py` 153/153.
- **Recorded, Release**, `RC_PROOF_APP=release precision_proof.py --control ctl-p21`: **14/14**,
  exit 0.
  - C0, D1, D2, P1 (RMS 0.914, control 0.914), H1 and R1 (depth 16, 1418 distinct) passed.
  - R2 (0.707), C1 (largest |Δ| 1), T1 and T2 (hevc_10bit 1.459, hevc 6.18; tone 0.014 against
    0.758) passed.
  - **S1** (PNG) and **S2** (TIFF) passed: 862 distinct 10-bit codes, RMS 0.4007, tone
    [0.0069, 0.0063]. The 8-bit control: 513, 1.4157, [1.2258, 0.0119]. The control tree: 512,
    1.414, [1.2236, 0.0134].
  - **S4** passed: `ramp16.png` depth 8, distinct green 256; `ramp8.png` depth 8, 256.
  - Z1 passed with no `Reelcut: ` line.
- **Recorded, Release**, `RC_PROOF_APP=release precision_proof.py compare ctl-p21`: **10/10**,
  exit 0.
  - K1–K6 byte-identical to the control (`{0: 921600}` each), and E1 and E2 ok.
  - **S3** ok: `still8.png` and `still8a.png` each render as an 8-bit PNG byte-identical to the
    control's, `{0: 921600}`.
- **Mutants** (Debug copies built by `tree_copy.build_app`, in 32–47 s):
  - `still-eightbit` (`let deep = false`): **MUTANT PASS**. S1 and S2 FAILED (512 distinct, RMS
    1.414, tone 1.2236). Its `also` row S4 passed (8 and 8).
  - `still-deep-linear` (the deep bitmap in `linearSRGB`): **MUTANT PASS**. S1 and S2 FAILED
    (846 distinct, RMS 214.9438, tone 0.024; they fail on RMS). Its `also` row S4 passed.
  - `still-always-deep` (`let deep = true`, compare): **MUTANT FAILURE**, exit 1. S3 passed: the
    opaque and the alpha-ramp still each rendered byte-identical to the 8-bit draw
    (`{0: 921600}`). On those two scenes — 1:1 over black, no colour control — an 8-bit still
    drawn into the half-float bitmap reaches the same 8-bit frame. It was dropped from
    `MUTANTS`; the fix pass below added a scene that catches it and restored it.
  - The mutant runs printed no `DEFAULTS MOVED`; nor did any other run.
- The recorded runs ran with `still-always-deep` still in `MUTANTS`. Dropping it changed no row,
  so they stood for that instrument; fix pass 1's recorded runs, below, supersede them.

**Fix pass 1** (the review's findings 1–3, 2026-10-11, same host; the product unchanged).
- **S3's colour scene (finding 1).** S3 gains a third scene: `still8a.png` under
  `video.color` brightness 0.1 and contrast 0.5 (`S3_COLOR`). The compositor un-premultiplies
  before the controls, so there the 8-bit draw's premultiplied rounding is carried through a
  non-identity step, which the first two scenes never reach.
  - Its reference: `capture ctl-p21 --only S3c` (a new capture path that renders S3's scenes
    into an existing capture and replaces only `capture.json`'s `S3`, recording `S3_tree`), on
    P2-1's own Release build, whose 8-bit draw is P2-0's code unchanged. That run's opaque and
    alpha digests (`044a37f9abf253b3`, `ea377c67865e0f1e`) equal the control tree's, and the
    rest of `capture.json` is byte-for-byte as captured. `S3-color.png`: `cbcb6961d228ca82`.
  - `still-always-deep` restored. **MUTANT PASS**: S3 FAILED, on the colour scene alone
    (`{0: 921138, 1: 462}`); the opaque and alpha scenes stayed `{0: 921600}`. So the "8-bit
    path byte for byte" constraint has a mutant guarding it again.
- **The mixed case (finding 2).** Two new rows, each `ramp16.png` on a track above a clip on a
  1920×1080 canvas, covering it:
  - **S5**, over the 8-bit H.264 clip: `render_frame` depth **8**, middle-row distinct green
    256.
  - **S6**, over the 10-bit ramp clip: depth **16**, middle-row distinct green **1,920** (the
    still's: the 10-bit clip alone reads 1,418, R1). A deep still in a deep frame keeps its
    depth. Under `still-eightbit` S6 reads depth 16 and 256.
  - So "any source is deeper" counts video sources only in every case measured. PR-4's
    amendment line (uncommitted, so corrected rather than appended to) and its index row now
    say exactly that: S4 and S5 8-bit, S6 16-bit with the still's depth kept, and that the
    owner's ruling covered the stills-only case. `precision.md` 190 → 193 lines;
    `11-decisions/` 6775 → 6778.
- **R1's title (finding 3)** now reads "(a 32BGRA-decoded control ≤ 256)".
- **10-bit HEIC (the leftover, bounded).** ffmpeg cannot mux HEIF. Measured from `ramp16.png`,
  reading the HEIC's middle row with ffmpeg (distinct 10-bit Y codes):
  - `sips -s format heic`: HEVC Main 10 `yuv420p10le` tiles, but 410 codes (its default
    quality's coding noise over an 8-bit staircase); `-s formatOptions best`: Rext 4:4:4
    10-bit, 256 codes.
  - ImageIO's `CGImageDestination` (`public.heic`) handed the PNG's own 16-bit INTEGER image:
    Main 10, 256 codes at quality 0.99 (285 at 0.9, 448 at 0.75).
  - The same writer handed the image drawn into a 16-bit-FLOAT sRGB bitmap: Main 10
    `yuv420p10le`, **1,024 codes** at 0.99 (Display P3 the same; extended sRGB wrote 8-bit
    Main Still Picture).
  - ImageIO decodes that file at `bitsPerComponent` 10, so `renderImage` draws it deep.
  - The float route is the fixture: `tools/proof/heic10_writer.swift`, built through
    `swift_build.build`; `still10_heic` keeps `ramp10.heic` only when ffprobe reads Main 10
    `yuv420p10le` and its middle row holds ≥ 800 codes.
  - **S7** is S1 with it: 862 distinct 10-bit codes, RMS 0.4699, tone [0.0183, 0.0139],
    against the 8-bit control's 513, 1.4157, [1.2258, 0.0119]. Under `still-eightbit`: 521,
    1.4428, tone 1.0891 (FAILED). `ctl-p21` holds no HEIC figures, so S7 prints no control
    tree; the mutant is its discrimination. This settles the "Not established" HEIF item.
- **Verification**, on the final instrument (logs `fix1-*.log` in the batch's handoff):
  - Debug, in the loop: `--only S5,S6` 3/3; `--only S7` 2/2 (the first S7, on the `sips`
    fixture, failed at 567 codes — the fixture, not the draw); `compare ctl-p21 --only S3`
    2/2; `--selftest` 3/3; `spec_index_proof.py` 153/153.
  - **Recorded, Release**, `--control ctl-p21`: **17/17**, exit 0. S1/S2 862, 0.4007,
    [0.0069, 0.0063]; S4 8 and 8; S5 8 (256); S6 16 (1,920); S7 as above; R1 depth 16, 1,418
    (control 1,418, printed, not held).
  - **Recorded, Release**, `compare ctl-p21`: **10/10**, exit 0. K1–K6 `{0: 921600}`, E1 and
    E2 ok, S3 ok on all three scenes (`{0: 921600}` each).
  - Mutants (Debug copies): `still-always-deep` MUTANT PASS (S3 FAILED); `still-eightbit`
    MUTANT PASS (S1, S2, S6, S7 FAILED; S4 beside passed). `still-deep-linear` was not re-run:
    its anchor and its rows' checks are unchanged (only S1/S2's title string was touched).
  - No run printed `DEFAULTS MOVED`.

**Fix pass 2** (review 2's findings, 2026-10-11, same host; the product changed in one comment).
- **`ramp10.heic` out of the preflight (finding 1).** `still10_heic` is no longer in `STILLS`, so
  R1, K1–K6, `--measure` and the other mutants no longer depend on the Swift build or ImageIO's
  HEIC writer. `run_s` makes it only when S7 is selected, and a refusal (the writer not
  building, exiting non-zero, or the file failing the Main 10 / ≥ 800-code check) is S7's
  FAIL naming the reason (`HEIC_REFUSED`). Forced (the writer's build made to raise, the
  cached file moved aside): S7 FAIL with "heic10_writer did not build: forced: …", 1/2, exit 1.
- **S3c keeps a recorded reference (finding 2).** `s3_capture(…, keep=)` re-renders only a scene
  DIR lacks; a scene recorded in `capture.json` whose `S3-<name>.png` is in DIR at that digest
  is kept, and a fixture copy already in DIR is not replaced. On a scratch copy of `ctl-p21`
  with `S3-color.png` and its row removed and `S3-alpha.png` altered by one byte: opaque kept
  (`044a37f9abf253b3`), alpha re-rendered (`ea377c67865e0f1e`), colour rendered
  (`cbcb6961d228ca82`), the fixture copies untouched; 2/2.
- **Wording (finding 3).** README.md and `renderImage`'s doc comment now say a still deeper than
  8 bits (a 16-bit PNG or TIFF, a 10-bit HEIC) is drawn deep.
- **Verification** (logs `fix2-*.log`): `make app-debug`; Debug `--only S7` 2/2 (862, 0.4699,
  [0.0183, 0.0139]); the forced failure above; `--selftest` 3/3; the S3c guard above; `make gate`
  PASS (typecheck 5 s, test 127 s, app 87 s; fmt and lint skipped); Release `--only S7 --control
  ctl-p21` 2/2, the same figures. The mutants and the whole recorded runs were not re-run: no
  mutant anchor moved, and S7's check and the other rows' code are unchanged.

**What is owed.**
- PRC-4 (`docs/manual-checks.md`): the owner's look at a 16-bit gradient still under a strong
  curve, in the preview and in a `prores_422` export.
- That a deep still over 8-bit video renders an 8-bit frame (S5) is measured and recorded in
  PR-4's amendment; the owner's ruling named only the stills-only case.

**CLAUDE.md edits owed** (applied by the orchestrator; `app/CLAUDE.md` is not a gate input). In
`app/CLAUDE.md` (lines 1242–1244), the `LayerRenderers.swift` entry's first lines become:
```
- `LayerRenderers.swift` · `LayerRenderersText.swift` · `LayerRenderersReveal.swift`
  · `LayerRenderersWords.swift` · `LayerRenderersBackdrop.swift` — text,
  shape and still descriptions to textures (premultiplied `bgra8Unorm`; a
  still deeper than 8 bits a component is drawn at 16-bit float and
  uploaded `rgba16Float`, spec §11 PR-6),
```

P2-2 (the 10-bit reverse, PR-7) is next, from main after this phase's merge.
