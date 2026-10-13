# The effects spike — offline voice effects through AVAudioEngine (2026-09-15)

Five programs, run from a shell on macOS 26.5.1 (25F80), Apple M2 Max, whose
output answers the seven questions a "voice effects" design asks before it
leans on `AVAudioEngine`'s offline manual rendering: pitch shift, reverb,
delay, EQ shelves and bands, and `AUDistortion`'s presets rendered per clip
into a cached file. None is a proof; each is an instrument, tracked so the
numbers can be reproduced rather than believed.

All five share `fx_common.swift` — one synchronous renderer (a fresh engine,
manual mode enabled first, the units in series, `renderOffline` in a loop of
4096-frame calls, no `async`, no run loop) and the measurements taken of what
it renders. Scratch output goes to `../work/effects_spike/` (untracked).

| Program | Answers | Build (from this directory) |
|---|---|---|
| `fx_throughput.swift` | q1 × realtime per unit and a 4-unit chain, from a file, a buffer and a source node, with the file write; q6 a 10 s window 30 s in, cold, and whether it equals a slice of a whole render | `xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 fx_common.swift fx_throughput.swift -o ../work/effects_spike/fx_throughput` |
| `fx_presets.swift` | q2 the SDK enums, each component's `factoryPresets` and parameter tree, every reverb and distortion preset on speech (level, tail, spectral bands), hand-built telephone/radio/robot/bit-crush; WHEN a preset takes effect | same line, its own name |
| `fx_determinism.swift` | q3 two fresh engines, chunk size 4096/1024/333, file vs buffer vs source node, four renders at once, the cache file's bytes (CAF, WAV, M4A); run it twice and `diff` the outputs for the cross-process half | same line, its own name |
| `fx_alignment.swift` | q4 lag against the dry signal (bursts, clicks, speech), reported latency/tailTime, tails past the input end; q5 TimePitch at ±700…±3000 cents and overlap 3/8/32 | same line, its own name |
| `fx_constraints.swift` | q7 formats (mono per unit, 22.05 kHz, int16, mono and 44.1 kHz render formats), misuse (frames over max, play before start, schedule after play), defaults that silently do nothing, engine reuse, a background thread, `.mov`/AAC sources. Each test runs in its own child process, because AVAudioEngine reports some misuse by an Objective-C exception Swift cannot catch | same line, its own name |

Run each from this directory (`../work/effects_spike/fx_alignment`, …).
`FX_FIXTURES` and `FX_WORK` override the fixture and scratch directories.

## Fixtures

Made into `../work/effects_spike/fx/` (the same sentence the silence spike
used, so the two spikes speak about the same file):

```sh
mkdir -p ../work/effects_spike/fx && cd ../work/effects_spike/fx
say -o speech.aiff "The quick brown fox jumps over the lazy dog. [[slnc 1200]] Pack my box with five dozen liquor jugs. [[slnc 800]] How vexingly quick daft zebras jump."
F=/opt/homebrew/bin/ffmpeg
$F -y -v error -i speech.aiff -ar 48000 -ac 2 -c:a pcm_s16le speech48s.wav
$F -y -v error -i speech.aiff -ar 48000 -ac 1 -c:a pcm_s16le speech48m.wav
$F -y -v error -stream_loop -1 -i speech.aiff -f lavfi -i "sine=frequency=110:sample_rate=48000:duration=60" \
  -filter_complex "[0]aresample=48000,atrim=duration=60[s];[1]volume=-12dB[t];[s][t]amix=inputs=2:duration=first:normalize=0,pan=stereo|c0=c0|c1=c0" \
  -ac 2 -ar 48000 -t 60 -c:a pcm_s16le long60.wav
$F -y -v error -f lavfi -i "aevalsrc='if(eq(mod(n\,24000)\,12000)\,0.9\,0)':s=48000:d=10:c=stereo" -c:a pcm_s16le clicks.wav
$F -y -v error -f lavfi -i "aevalsrc='if(between(mod(n\,24000)\,12000\,12479)\,0.5*sin(2*PI*1000*n/48000)*(1-cos(2*PI*(mod(n\,24000)-12000)/480))\,0)':s=48000:d=10:c=stereo" -c:a pcm_s16le bursts.wav
$F -y -v error -f lavfi -i "aevalsrc='0.25*sin(2*PI*220*n/48000)':s=48000:d=5:c=stereo" -c:a pcm_s16le tone220.wav
```

`speech48s.wav` is 498,689 frames (10.39 s); `long60.wav` 60 s of it looped
over a −30 dBFS 110 Hz tone (no digital silence); `clicks.wav` and
`bursts.wav` put one impulse / one 10 ms Hann-windowed 1 kHz burst at
0.25 s + k × 0.5 s. `fx_constraints` also reads `../media/speech.mov` (PCM),
`../media/AV.mov` and `../media/toneA.m4a` (AAC).

## Host state worth naming

The run of 2026-09-15 was on a machine at a load average of 58–66 on 12
cores (another session's work), so every × realtime figure is a floor under
contention and varied up to 1.6× between runs; the ranges in the design
record are across three runs. The default output device was "MacBook Pro
Speakers" at 48 kHz; a 44.1 kHz render format rendered and reproduced on it,
but no second output device was available to switch to.

---

# Remove Background — the Vision spike (2026-09-15)

Two programs and a fixture script, run from a shell (under the terminal's TCC
attribution) on macOS 26.5.1 (25F80), Apple M2 Max (ANE 16 cores), asking
whether a cached per-media cutout mask can be built on Vision's
`VNGeneratePersonSegmentationRequest` and `VNGenerateForegroundInstanceMaskRequest`
instead of a shipped model. Instruments, not proofs. Both programs share
`vision_common.swift`: stills drawn into the 32BGRA IOSurface buffer
`AVAssetReader` hands the app, the requests with a compute-device pin
(`auto` / `cpu` / `gpu` / `ane`, and `cpuforce`, which sets the CPU on a
request that does not list it), and the mask copied out as row-packed 8-bit
bytes (a float mask as `round(clamp(v,0,1)·255)`). Everything is synchronous
`VN*` API — no `async`. Scratch output goes to `../work/effects_spike/`.

| Program | Answers | Build (from this directory) |
|---|---|---|
| `vision_stills.swift` | `shape` q1 (revisions, devices, output class/format/size per quality and pixel format, the foreground's four outputs, mask size against five input sizes); `cold` / `warm` q2 per request, quality, device and size (Vision work timed alone, copy-out excluded); `det` / `cmp` q3 (fresh vs fresh, reused vs fresh — person segmentation is a `VNStatefulRequest` — and, run twice, against the previous process's dump); `content` q4/q5 (observations, instances, coverage; `MASK_PNG_DIR` writes the masks); `cache` q6 per-mask bytes | `xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 vision_common.swift vision_stills.swift -o ../work/effects_spike/bin/vision_stills` |
| `vision_job.swift` | `job` q2 the realistic job: `AVAssetReader` decode, one mask per 0.1 s of source (or every frame), modes `decode` (floor) / `fresh` / `reused` / `sequence` (`VNSequenceRequestHandler`), optional dump of every mask; `cmpdump` q3 two dumps mask by mask; `stats` q7 consecutive-mask MAD and coverage; `cachesize` q6 a whole job in raw / PNG / LZFSE at native, 256-long-edge and 256×144 | `xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 vision_common.swift vision_job.swift -o ../work/effects_spike/bin/vision_job` |
| `vision_fixtures.sh` | every still and video below | `sh vision_fixtures.sh` |

Typical calls (from `../work/effects_spike/`):

```sh
bin/vision_stills shape vision/frames/person_desk.png
bin/vision_stills warm vision/frames/person_desk_4k.png person-balanced 30 ane
bin/vision_stills det vision/frames/person_duo.png person-fast auto det   # run twice
MASK_PNG_DIR=masks bin/vision_stills content vision/frames/*.png
bin/vision_job job vision/video/job_screen_60s.mov person-balanced auto fresh 10 dumps/a.bin
bin/vision_job cmpdump dumps/a.bin dumps/b.bin 512 384
bin/vision_job stats dumps/sduo-fg-mask-fresh.bin 512 512
bin/vision_job cachesize dumps/a.bin 512 384 1920 1080
```

Kinds: `person-fast`, `person-balanced`, `person-accurate`, `fg-observe`
(the instance-label buffer), `fg-mask` (`generateMask(forInstances:)`, native
512×512 float), `fg-scaled` (`generateScaledMaskForImage`, image size float).

## Fixtures

`vision_fixtures.sh` writes `../work/effects_spike/vision/{frames,video}/`.
It reads no personal folder. Its sources, all already on this machine or in
the tree:

- **cards and text**: `ffmpeg` `color=` (blue, black, white), `drawtext` with
  `/System/Library/Fonts/Helvetica.ttc` (a title card, a code card),
  `testsrc2`, and `../media/A.mov` upscaled.
- **app UI, no person**: `../work/chrome4/shape-open.png` (a harness render of
  Frame Job's chrome) letterboxed to 1920×1080, and `../work/chrome3/open-two.png`
  scrolled top to bottom over 60 s as `job_ui_60s.mov`.
- **screen recordings**: `../work/spike/q7-immediate-1.mov`, `q4-rate-60.mov`,
  `q7-mic-builtin-1.mov`, `q4-size-best_pixels.mov` — road map 3's R0
  recordings of this display, which happened to be PLAYING A FILM, so these
  frames are screencasts with people in them. `job_screen_60s.mov` is the
  first looped to 60 s (a cut every 2.1 s).
- **objects, no person**: iA Presenter's bundled theme photos
  (`/Applications/iA Presenter.app/Contents/Resources/NewTheme/image4.jpg`
  pencils, `image2.jpg` notebook).
- **people (system/app-shipped art)**: Photos' bundled album covers in
  `/System/Library/Photos/Resources/FlexAudio/` — `e5fc4933…` (two men,
  frontal: `person_duo`), `AAE4E824…` (a figure, arms raised, dramatic light:
  `person_hero`), `9048dcfa…` (a small falling silhouette: `person_fall`) —
  and Adobe CEP's `video-hero-MUSE.jpg` (a person from behind at a monitor,
  dim: `person_desk`, also at 3840×2160). All are 256² or 800×450 upscaled,
  i.e. soft. `job_person_60s.mov` is `person_desk` under a slow push-in with
  per-frame noise; `static_{desk,duo,pencils}.mov` are 10 s stills with
  per-frame noise (`noise=alls=6:allf=t`) through H.264 — a static shot.

## Host state worth naming

Load average 5–60 on 12 cores during the run (rustc and python from other
sessions), so times are ceilings, not floors, and varied ~1.3× between
repeats; ANE work suffered least. The ANE's compiled-model cache was already
warm (an earlier process in the session took 10.5 s wall for its first
Vision calls at 1.1 s of CPU — probably the only truly cold figure, and not
reproducible without clearing a system cache), so the `cold` figures are
first-call-in-a-fresh-process, not first-call-ever.
