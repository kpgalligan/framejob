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
