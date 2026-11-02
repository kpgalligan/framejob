# The cutout spikes — road map "creator-jobs", CO0

What the road map measures before any cutout code is written:
- **CO-S1:** which segmentation, at what rate and read size, and how fast. Run here for speed only: S-KEY1 (the keyed truth) does not exist yet.
- **CO-S2:** how the mask reaches the compositor — a second composition track filled from mask chunks, or, when that fails, a per-media mask pack.
- **CO-S3** (the edge refinement) is not run: it needs S-KEY1. The runner prints `CO-S3 owed: S-KEY1 missing (runs at CO4's head)`.
- **CJ-S2 rule 1 for the mask request** (road map CO1's head, `--only device`): which device the `masks` kind is pinned to. Three runs of every frame of `push_1080.mov` on each of the CPU, the GPU and the Neural Engine, each run's SHA-256 over all its masks' bytes and its realtime factor; `deciders.device_rule` picks. A pick other than the Neural Engine re-measures Standard on it (`--only s1 --device <pick>`). The answer is in "CO1's record" and spec §11 CO-1 and CO-11.

**The answers are not here.** They are in `designs/creator-jobs.md`'s "CO0's record" (the VERDICT lines and the rows) and in spec §11 CO-1, CO-3, CO-4 and CO-7 (`designs/spec/11-decisions/creator-jobs-3.md`). Each rule is the road map's own entry under "Every spike, with its rule", fixed at CJ0a. R0 recomputes CJ-7's hash of the entry through `creator_spike/rule.py` and refuses a changed rule (`RULE CHANGED <id>`, exit 1, nothing written). Each `results.json` (`tools/proof/work/creator_spike/CO-S1/`, `CO-S2/`) stores its value as `rule_sha256`.

```sh
python3 tools/proof/cutout_spike/cutout_spike.py --selftest     # deciders.py's rows, no build
python3 tools/proof/cutout_spike/cutout_spike.py --build-only   # both probes through swift_build
python3 tools/proof/cutout_spike/cutout_spike.py --only s1      # CO-S1 (about 15 minutes)
python3 tools/proof/cutout_spike/cutout_spike.py --only s2      # CO-S2, after s1 (about 25 minutes)
python3 tools/proof/cutout_spike/cutout_spike.py --only s2 --pack   # the mask pack too, whatever the track answers
python3 tools/proof/cutout_spike/cutout_spike.py --only device       # CO1's head: CJ-S2 rule 1 for masks (about 10 minutes)
python3 tools/proof/cutout_spike/cutout_spike.py --only s1 --device gpu   # Standard re-measured on the pick
```

**Exit codes.**
- **0:** every requested row was answered or skipped by name, whatever the verdict.
- **1:** an instrument failure (a probe that does not build, a probe crash, a fixture that does not probe as made, CO-S2 run before CO-S1's results exist, the pack's free-space check), a selftest row, or `RULE CHANGED`.
- **2:** not performed: `core/target/release/libframejob_core.a` or `build/codecs/stamp.json` is missing (`swift_build.build` links both).

**Owed, never a failure.** S-KEY1's rows (CO-S1 (a) flicker, (b) the rate by B, (d) Best, (e) the read size, (f) the rotated composite; and CO-S3) and S-TH1's speed rows are printed `SKIP` with their reason, and their VERDICT fields read `owed`. S-TH4 is replaced by an `ffmpeg` HLG variable-frame-rate fixture in CO-S2 (1).

## Fixtures

All under `tools/proof/media/cutout/` (untracked), reused while they probe as made:
- `push_1080.mov` (H.264) and `push_4k.mov` (HEVC 8-bit), 20 s at 30 fps: E9's slow push-in (`zoompan`, `noise=alls=6:allf=t`) over Photos' FlexAudio cover `AAE4E824-DD67-4DB0-933F-AD2D619E4EF6.jpg`, padded to 16:9 as E9's `person_hero`. Adobe's `video-hero-MUSE.jpg` is the fallback only: person `.balanced` finds no person in its back view. The image's SHA-256 is in `fixtures.json`; a different image remakes both push-ins.
- `screen_4k.mov`: `testsrc2`, 3840×2160, 30 fps, 30 s, HEVC 8-bit tagged BT.709.
- `barcode.mov` and `barcode_rev.mov` (the probe's writer): 1920×1080, 30 fps, 160 s, H.264, timescale 600. Frame k carries k as 22 blocks across the middle band: block 0 white, block 1 black, blocks 2…21 the index's 20 bits. A block reads 1 above the level halfway between the two references. `barcode_rev.mov` holds the same frames in reverse at the same times, as `ReverseRenderer` would write them.
- `hlg_vfr.mov` (`ffmpeg`): `barcode.mov`'s first 40 s with frames 119, 270 and 899 dropped (`select`, `-fps_mode passthrough`), HEVC Main 10 tagged bt2020/arib-std-b67/bt2020nc. The runner checks that its frame times are barcode's less those three.
- `long_60m.mov` (the probe's writer): 60 minutes of the same code.
- `push_640.mov` and its rotation twins (CO1's M5): `push_1080.mov`'s first 3 s at 640 × 360 in uncompressed BGRA (`rawvideo` bgra; AVFoundation on macOS 26.5.1 refuses PNG in MOV, -11833, and decodes `rgb24` twins up to 0.65 levels apart). `push_640_cw.mov` is its `transpose=1` tagged `-display_rotation 90`, so it displays alike; `push_640_t.mov` the transposed frames untagged (360 × 640); `push_640_r.mov` the original tagged `-display_rotation -90`, displaying as `push_640_t.mov`. Each pair is checked to decode, rotated by ffmpeg, to the same first frame.

## The instruments

| File | What it is |
|---|---|
| `cutout_spike.py` | The runner: R0, the fixtures, the builds, every row, `results.json` and the VERDICT lines. |
| `deciders.py` | The rules as pure functions (`s1_speed_only`, `s2_track`, `s2_pack`, `device_rule`, `nearest`, `reversed_time`, `analysed_frames`, `expected_mask`) and `selftest()`. Stdlib only. |
| `mask_speed.swift` | CO-S1's probe, Vision only, built from this file alone. `job` (one candidate at one rate and read size, every frame decoded through `AVAssetReaderTrackOutput` 32BGRA, a fresh request per sampled frame pinned to the Neural Engine, or to an optional device), `first` (a fresh process's first request), `dump` (Standard's masks with their times) and `devices` (CO1: person `.balanced` on every frame pinned to one device, the SHA-256 of all its masks' bytes). |
| `mask_track_probe.swift` | CO-S2's probe entry, built with `app/Sources`. The cases are projects built through `ReelProject`/`ReelOps`, planned by the core and built by `CompositionBuilder.build`; the mask tracks (`2001 + i`) are made by `makeTrack` and filled by `fill`. `ProbeCompositor` (a `Compositor` subclass) and `ProbeConvertingCompositor` record every picture and mask pair before the real compositor runs. Modes: `fixtures`, `registration`, `colour`, `codec`, `playback`, `build`, `fixed` and `pack`. |
| `mask_track_writer.swift` | The bar code, the bar-code movies, mask frames (a ramp over the top half, the analysed index over the bottom), the nearest-hold sample placement (`chunkSamples`), the two pinned encodings, the native decode, the fixed cost and (3)/(4)'s codec row. |

**Registration** is scored in the runner, not the probe. Each record is (composition ticks, picture track, the picture's index read, the mask's index read). It must equal `deciders.expected_mask`: the nearest analysed frame (ties to the earlier) in the stream the segment reads. In the reverse case, the picture's time and the analysed times are both mapped by `reversed_time(pts, end, T) = T − end`. A (case, rate) row passes when it read every frame of the composition and every pair matched.

**The pack** (`--pack`, or automatically when the track answers `none`) is one file per media under `work/cutout_spike/pack/`. It holds a frame table (each source frame's time and its nearest analysed mask's slot), an offset table (each distinct analysed mask's time, offset and length) and each distinct analysed mask once, LZFSE-compressed. `long_60m`'s pack holds the tables only, because its build row reads nothing else. Before any pack is written, the runner refuses, as a scored failure naming the shortfall, when free space is under the packs' raw-size estimate plus 10 GB.
