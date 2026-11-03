# Spec §11 — decisions: Creator jobs, motion blur onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md),
[`creator-jobs-4.md`](creator-jobs-4.md), [`creator-jobs-5.md`](creator-jobs-5.md),
[`creator-jobs-6.md`](creator-jobs-6.md) and [`creator-jobs-7.md`](creator-jobs-7.md) (CJ-, VR-,
TX-, SW-, CU-, CO- and FC-), so a citation never has to say which file; `creator-jobs.md` says
what the road map builds and how its IDs are made (CJ-7). This file is new because
`creator-jobs-7.md` held CJ6's entries at 586 lines, past the road map's ~500-line split rule;
each phase's decisions are appended here from now on, before its code.

## CU11a — motion blur in the model and the recipe (2026-11-02)

Recorded before the code. CU-110…CU-116 are CU11's, recorded at CU11a: spike CU-S5 ran at the
phase's head and chose N = 16; a clip carries `video.motion_blur` (format 42, provisional until
the phase lands), every recipe layer a twenty-ninth key `blur` listing its sub-frame placements,
the cursor key its shutter's source ends, and `rc_cursor_query`'s `state` the cursor's positions
there. Nothing is drawn yet: CU11b draws it and shows it (CU-116). Nothing sends anything
anywhere, so nothing is keyed (CJ-3).

- **CU-110 — CU-S5's verdict: zoom blur at N = 16.** The rule is the road map's (rule_sha256
  `7e6b75fb…826`, matching CJ0a's table): ship zoom blur at the largest N in {16, 8, 4} adding
  ≤ 4 ms at 1080p and ≤ 8 ms at 4K, one N for preview and export. `tools/proof/cursor_spike/
  blur_spike.py` built `blur_spike.swift` over `app/Sources` and drew one full-canvas
  `rgba16Float` layer at a 2× `ease_in_out` zoom's middle (t = 0.5 s of a [0, 1 s) action) once,
  and N times at the shutter's centred sub-frame placements (shutter 0.5) at 1/N opacity into a
  `mattePool` composite through a pipeline whose destination factors are both `.one`, then once
  onto the destination through `renderer.pipeline`. Five runs of 60 frames after 10 warm-up
  frames each; GPU time from the command buffer; the runs are the repeat (three lanes shared the
  machine: the one-minute load average was 201.08 at the end). Host: Apple M2 Max, macOS 26.5.1
  (25F80), on AC. Added time, the median over runs of (the run's median at N − the run's median
  once): **1920×1080** N = 16 1.717 ms, N = 8 1.107 ms, N = 4 0.517 ms (once 0.113–0.327 ms);
  **3840×2160** N = 16 6.636 ms, N = 8 3.276 ms, N = 4 1.333 ms (once 0.421–0.854 ms). N = 16
  passes both bounds, so zoom blur ships at N = 16 and cursor blur with it. The figures are in
  `tools/proof/work/creator_spike/CU-S5/results.json`.
- **CU-111 — What blur skips.** A layer is drawn sharp, its `blur` null, when any of these holds
  (`sharp` in `recipe.rs`'s `layer`): it is drawn into a nest's container (`drawn_into`); it has a
  matte role (`matte` non-null); it is inside a transition (`transition` non-null); it is a
  routed dissolve's (`dissolve` non-null); its moved video has a `shadow`; or its clip is an
  adjustment clip. After Behind Subject's subject copies and cut layers are added
  (`frame_subjects`), `sharpen_matted` nulls `blur` and drops the cursor's `shutter` on every
  layer with a non-null `matte`, so a copy and its cut layer are sharp too. A layer whose every
  sample equals the first (an unmoving layer) has `blur` null. The text burn-in's layer has
  `blur` null. `set_video`, `paste` and `paste_attributes` refuse `motion_blur` above 0 on a nest
  clip ("clip 9 shows a nest and cannot take motion blur: set it on the clips inside") and on an
  adjustment clip ("clip 4 is an adjustment clip and cannot take motion blur"); 0 is always
  accepted. Show Ungraded and Show Selection keep `blur`: they change the grade, not the
  placement.
- **CU-112 — One N, the canvas's frame.** One N, the core's `MOTION_BLUR_SAMPLES` (16, CU-110),
  serves the preview, `render_frame` and every export. The shutter is a fraction of one frame of
  the CANVAS's rate, whatever an export's `fps` override, so a frame's blur is the same at any
  export rate. R5-1 stands: motion blur is a closed property of the clip, not a runtime. CJ-1
  lifted motion blur from spec §1's exclusions; this is where it is built.
- **CU-113 — `video.motion_blur`.** A number in [0, 1], the shutter as a fraction of one canvas
  frame; 0 (the default) is off. Out of range is refused "video.motion_blur must be between 0 and
  1, not 1.5"; an action's end is clamped to [0, 1] (NaN → 0). Written only above 0 (serde
  `skip_serializing_if` zero), so `{motion_blur: 0}` removes the key. `video_json` always carries
  it, so an end animates from a base of 0, `clip_state` reports it and a split's state patch
  holds it. A blurred background copy (Fill Background) drops it: the copy is drawn behind and
  sharp. Format 42 (provisional; the integrator renumbers): a file of version 41 or older opens
  as it was, with no key.
- **CU-114 — The `blur` key and the cursor's `shutter`.** Every recipe layer has a twenty-ninth
  key, `blur`, after `cutout`: null, or `{"shutter": s, "samples": [{x, y, scale, rotation,
  clip_rect}; N]}`, sample k the layer's placement at project time t + round(((2k+1−N)/(2N))·s·F),
  k = 0…N−1 ascending, F = 600,000·den/num the canvas's frame in ticks (centred samples: the
  shutter straddles the frame's instant). Each time is clamped into the instance's span
  [start, end − 1], so a sample never reads past the clip. The placement is the one the layer
  itself is drawn at (`placement`), so an inner clip of a moving nest follows the nest's fold and
  its `clip_rect`. `s` is the evaluated `video.motion_blur` at t, so it animates. The key is null
  when `s` ≤ 0, when the layer is sharp (CU-111), and when every sample equals the first (f64 ==,
  `clip_rect` included). On a media clip's layer with a cursor and a shutter, the cursor key gains
  `"shutter": {"from": a0, "to": a1, "samples": N}` after `props`: a0 and a1 the source ticks
  the shutter's ends (t ∓ round(s·F/2), clamped as the samples) read, computed as `at` is
  (`in + source_read_by(clip, end)`, ≥ 0); omitted when a0 == a1, for a still, and with no
  shutter.
- **CU-115 — `state`'s `ends`.** `rc_cursor_query`'s `state` takes an optional `"ends": [T0,
  T1]` (source ticks) and then answers `"ends": [[x0, y0], [x1, y1]]` in movie pixels, each with
  the same smoothing and the same `(0, 0)` fallback as its `x`, `y`; no key when not asked. CU11b
  draws the cursor's N sprite samples along the segment between the two.
- **CU-116 — The split, and what CU11b owes.** CU11 is two pipelines. CU11a (this) is CU-S5, the
  decisions, the core (`motion_blur.rs`, `recipe_blur.rs`, the wiring, format 42, the tests) and
  the minimal Swift mirrors (`VideoProps.motionBlur`, `VideoPatch.motionBlur`, `set_video`'s
  catalog clause saying drawing is not built yet). CU11b draws and shows it:
  `Compositor+MotionBlur.swift` and its accumulate pipeline (N draws at 1/N into a pooled
  canvas-sized target, composited once with the layer's blend); the cursor's N sprite samples in
  `layerSample`; the Transform section's Motion blur row (after `VideoPane.swift`'s pure move);
  the Auto Zoom sheet's "Motion blur" (on, at the owner's 50 %, answered 2026-11-01) and
  `auto_zoom`'s `motion_blur`; the guide pages and spec §4.3b, §7.5b; JOB-26; the proof rows
  MB1–MB4 and the road map's three mutants. CU11a's proof is `tools/proof/cu11_proof.py`: Z1 (the
  launch's log has no parity complaint) and K1 (`set_video`'s `motion_blur` stored, refused out
  of range, removed at 0, refused on a nest and an adjustment clip). Its mutants: M1 samples
  leading (k/N·s·F); M2 the `transition` arm dropped from `sharp`; M3 the equality test dropped;
  M4 `sharpen_matted` not called; M5 the nest refusal dropped; M6 `state`'s ends read at `at`.

## CO6 — layouts at the playhead (2026-11-03)

Recorded before the code. CO-60…CO-67 are CO6's: Clip ▸ Camera Layout ▸ and the op
`switch_layout` place a camera clip and the screen behind it in one of five layouts the core
solves, eased over 0.5 s from the playhead and held until the next switch, as one undo step
"Camera Layout". No persisted field, no format bump and no `rc_*` export; nothing is sent
anywhere, so nothing is keyed (CJ-3). The owner's answers (2026-11-01): a switch takes 0.5 s,
eased in and out; the nest is offered, not made automatically.

- **CO-60 — The geometry (`core/src/layout.rs`).** W × H is the container's canvas (a nest's
  own inside a scope); `m = 0.04·min(W, H)`. Every scale is clamped to `SCALE_MIN…SCALE_MAX`;
  `x` and `y` are rounded half away from zero to whole canvas pixels, as CAM-10 (3) rounds them;
  scale, crop and radius are not rounded. A radius is written in source pixels: its canvas length
  ÷ the scale. A role writes all six placement keys — `x`, `y`, `scale`, `crop`,
  `corner_radius`, `opacity` — always, and nothing else.
  - **Full placement** is `add_clip`'s: x 0, y 0, `fit_scale(sw, sh)` (honouring
    `canvas.fit_new_clips`, never scaling up), no crop, radius 0, opacity 1. The screen takes it
    in `corner`, `camera_full` and `screen_only`.
  - **corner** (shape `square` by default, `rounded` or `circle`; corner `bottom_right` by
    default, `bottom_left`, `top_right` or `top_left`): the box is `0.25·W × H/3`, the picture's
    outer corner `0.05·W` and `0.05·H` in from the chosen canvas corner. `square` and `rounded`
    fit the whole camera, uncropped, in the box (CAM-10 (3)'s numbers exactly); `rounded`'s
    radius is `0.08·min(0.25·W, H/3)` canvas pixels. `circle` crops the largest square of the
    source (side d = min(a, b)), scale `min(0.25·W, H/3)/d`, radius d/2.
  - **side_by_side**: the inner width `W − 3m`; the screen fitted in the left `(W − 3m)·2/3 ×
    (H − 2m)` and centred there; the camera cropped to fill the right `(W − 3m)/3 × (H − 2m)`; m
    round and between them; each radius `0.02·min(W, H)` canvas pixels.
  - **stacked**: the screen at `min((W − 2m)/sw, (H − 3m)·2/3/sh)`, centred across, its top at
    m; the camera cropped to fill `(W − 2m) × (H − 3m − the screen's height)` below it, m
    between; the 2 % radii.
  - **camera_full**: the camera at `fill_scale`, x 0, y 0, no crop, radius 0.
  - **screen_only**: the camera keeps its x, y, scale, crop and radius — evaluated at `at` for
    an action's end, its base for a later clip's base — at opacity 0.
  - A crop's centre is placed by (★) (`edit_zoom.rs`): the cropped centre is the anchor plus
    `s·((l − r)/2, (t − b)/2)`.
- **CO-61 — A switch is a layout action, and it holds.** Defaults 0.5 s (`DEFAULT_SWITCH`)
  and `ease_in_out` (owner, 2026-11-01). Per role, the clip under `at` gets a layout action at
  clip time `at − start`, its duration clamped to the clip's end and to the start of the next
  later layout action on that clip, at least one frame. At the clip's first frame it instead
  takes the layout as its base props plus a one-frame layout action at clip time 0 whose end
  equals them: a cut, recognisable by content. A layout action on that clip starting exactly at
  `at` is replaced (removed first). A layout action on that clip still running at `at` (start <
  `at` < end) is shortened to end at `at` (`set_action`, duration `at −` its start, a whole
  number of frames since both sit on the grid) and the new action eases on from its end; a
  non-layout action running at `at` meets `add_action`'s own overlap refusal. The REACH runs
  from `at` to the earliest of the first later layout action's absolute start on that role's
  track (one starting after `at`), `through`, and the track's end; every clip on that track with
  a picture STARTING inside it takes the layout, solved with its own source size, as its base
  props and keeps its actions. Composed from `remove_action`, `set_action`, `add_action`,
  `set_action_end`, `set_video` and `nest_clips`; one op, one undo step "Camera Layout".
- **CO-62 — A switch never fights a zoom.** A role clip in the reach (the clip under `at` and
  the later reach clips) holding a non-layout action that moves it (`moves && !is_layout`) and
  ends after `at` refuses: "The {screen|camera} clip {id} at {timecode of its start}
  {zooms|moves} (action {a}); nest the {role}'s clips so the layout moves the nest and the
  {zoom|action} stays inside it." — `zooms` and `zoom` when the action `is_zoom`. Exception: in
  `corner`, `camera_full` and `screen_only` a SCREEN role clip that already holds its full
  placement — the clip under `at` by its six keys evaluated at `at`, a later reach clip by its
  base — is not checked for movers, because the switch changes nothing it draws; its layout
  action (all six keys, equal to the full placement) is still written. One helper,
  `holds_full` (each of the nine numbers within 1e-9), answers "holds its full placement" here
  and below. With `nest: true` each refused role's clip under `at` and its later reach clips
  (but a later clip whose own layout action ends the reach) are nested first, in the same step,
  and the switch then lays out the nest clip; it is refused instead when one of them is laid
  out — its base six keys, or the end of any of its layout actions, not `holds_full` of its full
  placement: "clip {id} is already laid out; a nest would lay it out twice." A layout action
  whose end is the full placement (an earlier corner, camera_full or screen_only switch's screen
  end) never blocks a nest, and an earlier layout action never refuses. A camera clip in the
  reach that is, or would become, a nest clip refuses `circle` and `rounded`: "clip {id} is a
  nest clip, which cannot draw a rounded corner or a circle." `side_by_side` and `stacked` write
  their 2 % radius on a nest clip, which draws square corners (`nest.rs` folds only x, y, scale,
  rotation, opacity and crop): a recorded limit.
- **CO-63 — Actions are classed by content, with no tag.** CU-73's `action_class.rs` as built
  (CU7): a layout action names all six placement keys in `video`; a zoom names exactly `scale`,
  `x` and `y`, so a layout action is never a zoom and Auto Zoom's Replace never removes one.
  `switch_layout` is `is_layout`'s first reader.
- **CO-64 — The roles.** `camera` must be a clip with `video` and a source size, else "clip {id}
  has no picture to lay out", playing at `at` (start ≤ `at` < end), else "clip {id} does not play
  at {timecode}". `screen`, when given, passes the same two and sits on a track behind the
  camera's: "the screen (clip {s}) must be on a track behind the camera's (clip {c})". When
  absent, the screen is the clip playing at `at` on the front-most track behind the camera's that
  is not hidden and not a matte track, with `video`, `enabled.video` and a source size, not an
  adjustment clip. None found: `side_by_side` and `stacked` refuse "no clip draws behind clip
  {c} at {timecode} to be the screen"; the other three lay out the camera alone. `through` not
  after `at`, a non-positive `duration` and a non-finite `focus` are errors. The refusal order is
  the camera, the screen, the nest-clip shape, the movers (with `nest`, the laid-out refusal in
  their place), then `add_action`'s own.
- **CO-65 — `focus`.** A point in the camera's source pixels measured from the UNCROPPED
  source's centre, y down; a layout's crop is centred on it and clamped inside the source; absent
  is (0, 0). CO7 fills it from the masks.
- **CO-66 — The menu.** Clip ▸ Camera Layout ▸ holds Corner ▸, Rounded Corner ▸ and Circle ▸
  (each Bottom Right, Bottom Left, Top Right, Top Left), a separator, then Side by Side,
  Stacked, Camera Full and Screen Only: one selector, `switchCameraLayout:`, its tag an index
  into `CameraLayoutChoice.menuRows`; no key equivalent, no persisted state. The road map's
  "Corner ▸ the four corners" is read as each corner shape's own submenu, because
  `perform_menu_item` resolves a path by the first title match and a sibling item and submenu
  both titled "Corner" would leave one unreachable. The roles: two selected picture clips on
  different tracks — the front one is the camera, the other the screen; one — it is the camera
  and the core finds the screen; none — the clip at the playhead on the front-most track named
  "Camera". The item is enabled when that yields a camera containing the playhead and no sheet
  is up. `at` is the playhead; `duration` and `curve` are left to the core. A refusal reaches the
  inspector's refusal strip through `applyEdit`. The nest is offered, not automatic (owner,
  2026-11-01): CO7's sheet makes the offer; here the refusal's sentence says how.
  `switch_layout` is the MCP mirror, an op tool printed from the core's schema.
- **CO-67 — The proof.** `tools/proof/co6_proof.py` (Release), with `co6_probe.swift`: L1 each
  layout lands its end, all six keys, at the core's numbers on 1920 × 1080 and 1080 × 1920; L2 a
  first-frame switch writes base props and a one-frame action equal to them; L3 after three cuts
  a switch on the second clip carries to the third and fourth and stops at a fifth with a
  first-frame layout action; L4 two switches on one clip, the second holding; L5 a later clip
  with a mid-clip layout action takes the new base and keeps it; L6 a later screen clip with a
  zoom refused naming clip and action, and with `nest: true` nested, the zoom inside, and
  `render_frame` byte-identical to `nest` then `switch_layout` on a twin; L7 the camera inside an
  existing action refused naming it; L8 `through` ends the reach; L9 one undo restores the
  project; L10 circle's square crop and half-side radius, rounded's radius, a nest-clip camera
  refusing both; L11 (probe) `ActionBands.isZoom` false and the six keys exactly on every L1
  end; L12 the menu with one clip and with none selected, equal to `switch_layout` on twins, one
  undo step each; L13 a full-placement screen with two zooms after `at`: Circle ▸ Bottom Right
  applies with the zooms unchanged, `side_by_side` later refused naming the zoom, and with
  `nest: true` nested; Z1 no `Frame Job: ` line. Nine mutants, each caught: the screen
  exemption dropped (L13), the reach stopping at a later zoom instead of refusing (L6), the
  reach running past a layout action (L3), the reach stopping at the first later clip (L3), a
  layout end missing an unchanged key (L11), the first-frame marker left out (L2), `through`
  ignored (L8), circle's radius from the uncropped side (L10), the menu's roles swapped (L12).
  JOB-64 (`docs/manual-checks.md`): each switch's eased move reads as deliberate at 0.5 s.

## SW0 — measuring several 4K angles (2026-11-02)

Recorded before the code. SW-1, SW-2, SW-4 and SW-5 are SW0's; SW-3 (multicam as a program track)
was recorded at CJ0a, and SW-6 is SW-S2's verdict, appended after its runs. Nothing changes in the
product: no core, FFI, format (42 stands), op, product tool, menu item or key. The owner's answers
that set it (2026-11-01, batch 9): "SW0: build F-4K once: YES. The three-hour file: BUILD BOTH
NOW" — a generated three-hour fixture, not waiting for S-LONG1, a departure from the road map's
recommendation.

- **SW-1 — The preview's rebuilds are counted and timed, in the dev tools only.**
  `PlaybackRebuildLog` (`PlaybackRebuildLog.swift`, the whole file under `FRAMEJOB_DEV_TOOLS`) is
  one log per `Playback`, main thread only. Three calls feed it, each under
  `#if FRAMEJOB_DEV_TOOLS`: `startRebuild` notes a generation's START (uptime nanoseconds) right
  after it takes its generation; `finishRebuild`'s success arm, after the generation guard, KEEPS
  the entry with its `built_ms` — so a superseded generation, discarded by that guard, is never an
  entry, and a build that fails is not one either; and the landing arm of `seekFinished()`
  (`Playback+Scope.swift`, right after `restoring = false`) FILLS the last entry's `landed_ms`
  only while it has none: the restore seek that follows the item swap is the first seek to land
  after the build. A kept entry drops every start at or before its generation. The log keeps the
  last 256 entries, oldest first; `count` counts every entry since the last reset and may exceed
  256; a reset empties both and keeps the starts of generations in flight.
  - **The tool.** The dev tool `playback_rebuilds {project?, reset?}` (`AgentServer+
    PlaybackRebuilds.swift`) runs on main, refuses a project with no editor window in
    `loudness_meter`'s sentence shape, resets first when `reset` is true, and answers `{count,
    rebuilding, rebuilds: [{generation, built_ms, landed_ms}]}` in that key order, times in ms from
    the start rounded to 0.1, `landed_ms` null until the entry lands. It is a `devHandlers` row and
    the last `devTools()` row, never in `devOffMainTools`; the assistant withholds it as every dev
    tool (`devToolNames`). Distribution carries none of it: no `#else` arm, and nothing outside
    `#if FRAMEJOB_DEV_TOOLS` names the log.
  - **Its proof.** `rebuild_log_proof.py` R0–R3: R0 no `Frame Job: ` line, the tool in the
    catalog with exactly `reset` and `project`, the dev marker count `len(DEV_TOOLS)`; R1 one
    `trim_end` on a one-clip project makes exactly one entry with 0 < `built_ms` ≤ `landed_ms`;
    R2 `reset: true` answers `count` 0 and `[]`, and the next `trim_end` exactly one landed entry;
    R3 under `-RCDevRebuildHold 2`, two `trim_end`s within 0.5 s leave `count` 1 and `built_ms` ≥
    2,000. The road map's proof said `set_clip`; R1 uses `trim_end` because `set_clip` only names
    or labels a clip, which the plan does not carry (`core/src/plan.rs`), so it never rebuilds.
    Two mutants: `built-before-guard` (the entry kept for a superseded generation; R3 must fail)
    and `reset-ignored` (R2 must fail).
- **SW-2 — SW-S2 runs now, on fixtures built from repeats.** CJ0a's question 4 was answered yes,
  so SW0 is built. The owner's SW0 answers: F-4K is built once (about 34 GB), and the three-hour
  file is generated now rather than waiting for S-LONG1. Every long fixture is a stream copy of
  repeats of one encoded minute, so the encoding time is a minute per file and the length costs
  only disk. (d) runs on the generated file; S-LONG1 stays owed (TX-S1 and SW-S2 (d) again when it
  exists), and SW9a re-runs SW-S2 on the owner's own files.
- **SW-4 — `-RCDevRebuildHold <s>`, a dev-only launch default.** When positive, `Playback.init`
  installs `PlaybackRebuildLog.heldHop()` as `rebuildHop`: each rebuild's main-thread landing
  waits s seconds (`DispatchQueue.main.asyncAfter`) and then finishes as the build answered. It is
  installed only when the default is present, because `scope_playhead_probe.swift` sets
  `rebuildHop` itself. It is what makes R3 deterministic: two edits inside one held flight.
- **SW-5 — The fixtures and the disk rule.** `tools/proof/creator_spike/angles_fixtures.py` writes
  every fixture under the gitignored `tools/proof/media/creator/`, never committed. The source is
  lavfi `testsrc2=size=3840x2160` with `noise=alls=16:allf=t` and a hue per angle; each long file
  is a stream-copy concat (`-f concat -safe 0 … -c copy`) of repeats of a one-minute encode.
  - **F-4K** (`f4k/`, behind `--build-4k`): `a1_h264.mov` and `a2_h264.mov`, 10 min at 30000/1001,
    `h264_videotoolbox -profile:v high -b:v 100M -g 15`, `-video_track_timescale 30000` (as the
    GH5 writes); `a3_hevc.mov` and `a4_hevc.mov`, 10 min, `hevc_videotoolbox -profile:v main10
    -pix_fmt p010le -tag:v hvc1 -b:v 50M -g 30`; `p1_prores.mov` and `p2_prores.mov`, 1 min,
    `prores_ks -profile:v 3 -pix_fmt yuv422p10le` (ProRes 422 HQ), projected at 710 Mb/s;
    `h1_hevc5994.mov` and `h2_hevc5994.mov`, 2 min at 60000/1001, HEVC Main 10 at 50M, `-g 60`,
    timescale 60000; `mic1.wav` and `mic2.wav`, 10 min of mono 48 kHz `pcm_s24le` pink noise
    (`anoisesrc=color=pink:amplitude=0.03`). Projected total about 34.8 GB (32.4 GiB).
  - **The long file** (`long/long_hevc.mov`, behind `--long`): 3 h of HEVC Main 10 at 29.97 from
    180 repeats of one minute, its rate the first of 50, 40, 30 and 20 Mb/s whose projection leaves
    at least 20 GiB free; below 20 Mb/s it refuses. It is made and measured before F-4K exists and
    removed after (d) unless `--keep-long`; F-4K is kept (SW2c may re-run (a) on it); `--clean`
    removes everything.
  - **The disk rule.** Before each output the script projects its size as bitrate × duration plus
    the one-minute segment; if `shutil.disk_usage`'s free space minus that projection is under
    20 GiB it writes nothing more, prints `STOP: <file> needs <x> GiB, <y> GiB free, floor 20 GiB`
    and exits 3, and the phase records that STOP with its figures rather than generating.
  - **Where it ran.** The road map puts SW0 in lane C; it ran in lane A (2026-11-02), as the
    orchestrator scheduled it. Nothing in the phase depends on its lane.
- **SW-6 — SW-S2's verdict: (b) and (d) answered; (a) and (c) re-run on a quiet machine.**
  `rule_sha256` `ecd9d732…324f0961`, matching CJ0a's table (`rule_matches: true`): **the rule
  and its pin are unchanged.** macOS 26.5.1 (25F80), Apple M2 Max, 12 cores, 96 GiB, on AC
  (`pmset` powermode 0), three lanes on the machine; Release, `angles_spike.py`, three runs a
  row, each run with its host's facts, all in `tools/proof/work/creator_spike/SW-S2/results.json`.
  - **(b) rebuild: within 1,500 ms — no guide figure and no Performance issue.** The two-hour
    timeline held 1,072 clips (1,000 program shots, 48 angle and 24 microphone placements). All
    30 rolls landed; the median `landed_ms` was **78.75 ms** (spread 76.8–134.0; run medians
    78.3, 79.3 and 79.2), `built_ms` about 45 ms after a first roll of 97–101 ms. Run under a
    one-minute load average of 33.6–34.9, so the margin (19×) is not one the noise can swallow.
  - **(d) long files, recorded.** On the generated three-hour file (SW-5's rate rule chose
    30 Mb/s at 68.6 GiB free; `ffprobe` 30,473,383 b/s, 10,804.8 s, 41,157,328,852 bytes), each
    of 0:30:00, 1:00:00, 2:00:00 and 2:59:00 composed on the first `play_preview {seconds: 0.5}`
    in every run (12 of 12, no "still seeking" refusal). The wall time from the `set_playhead`
    send, an upper bound that includes that call's own 0.5 s play: medians 0.535, 0.558, 0.586
    and 0.529 s (spreads 0.534–0.538, 0.556–0.564, 0.582–0.591, 0.529–0.543), at a one-minute
    load average of 3.0–3.7. A three-hour file seeks as quickly at its end as at its start.
  - **(a) cuts on one composition track: not called.** Median ratios over three runs (spread in
    brackets): H.264 0.9999 [0.8523–1.0], HEVC 0.9837 [0.9717–0.9996], ProRes 422 HQ 0.6774
    [0.6502–0.84], HEVC 59.94 0.6921 [0.3955–0.8868]. H.264's and HEVC's runs fall on both sides
    of 0.99 (`noise_bound`); ProRes' and HEVC 59.94's are all below it, but five of those six
    runs ran at a one-minute load average of 47–116 (the other lanes' builds), and ProRes' one
    quiet run (6.7) gave 0.84. The verdict — keep the plan's assignment, or build SW2c — is
    owed to a run on a quiet machine (`angles_spike.py --rows a`, F-4K kept). Since review, a
    pair whose every run is below 0.99 decides the row, so the runner prints "SW2c is owed" for
    these figures; that call is withheld for the load above, and a quiet run's print is the one.
  - **(c) angles at once: not called.** Median Half ratios N = 1…4: 0.8401, 0.9422, 0.9994,
    0.9994 (spreads 0.6479–0.842, 0.6268–0.9994, 0.535–1.0, 0.9766–1.0); Full 0.9983, 1.0,
    0.9883, 0.9283. N = 2…4 straddle 0.98 (`noise_bound`), and N = 1 below it while N = 4 is
    above says the load (8.7–120 at the Half runs), not the angle count, decided them. As
    measured the live count would be 4 ("four live"); the mapping SW9a ships is owed to a run on
    a quiet machine (`--rows c`).
  - **The fixtures.** F-4K is 38,086,813,978 bytes (35.5 GiB) under
    `tools/proof/media/creator/f4k/`, kept: ProRes 422 HQ of noise came in at 915.6 Mb/s against
    the 710 the projection assumed (6.87 GB a file); every other file within 2 % of its rate
    (H.264 100.5, HEVC 50.4, HEVC 59.94 50.8 Mb/s). The three-hour file was removed after (d).
    SW-S2 runs again at SW9a on the owner's files, and (d) on S-LONG1 when it exists.

## CO7 — the Layout section, the nest offer and the crop on the person (2026-11-03)

Recorded before the code. CO-70…CO-73 are CO7's: the camera's crop in Circle, Side by Side and
Stacked centres on the person when the camera clip's person masks are cached for every frame it
plays; a Layout section in the Picture sub-tab sends the menu's op; a switch refused for a zoom
offers Nest and Switch as one undo step. No core change, no persisted field, no format bump, no
`rc_*` export and no new tool; nothing is sent anywhere, so nothing is keyed (CJ-3). The road map
asks the owner nothing at this phase.

- **CO-70 — The crop on the person.** The menu, the Layout section and the `switch_layout` tool
  send the same `focus` (CO-65). The camera clip's windows are `CutoutWants.windows(of:)`: its
  plan video segments whatever its cutout, mirrored about the pivot when reversed, over
  `CutoutStatus.detail`'s handles (`project`, plus `editedProject` with a nest open). The need is
  CO-22's rule (`CutoutWants.need`); the coverage is the `masks` marker that `answers(for:)` the
  stamp (`CutoutStatus.stamp`), its pack the payload. Focus is sent only when every needed index
  is covered: the mean, over found frames, of `CutoutStatus.centroid` (the number
  `analyze_cutout` answers as `centroid`), minus (w/2, h/2) of the media; otherwise none, and the
  crop centres on the source (CO-65). Only what is cached is read and no job is started (CO-6);
  the read is never keyed (CJ-3). The centroid is read off main and memoised on (pack path, file
  size, modification date, need, media size), at most 64 entries, cleared whole when full. The
  menu and the section read on `CameraLayoutFocus.queue` and apply on main only if
  `document.project` and `document.scope` are unchanged, else beep and change nothing. The tool
  fills `focus` when it is omitted or null (an explicit `[x, y]` wins), on the server thread with
  three hops as `auto_zoom` does, and refuses a changed project: "the project changed while
  switch_layout read the camera's person masks, so nothing was laid out. Call switch_layout
  again." Its answer carries `focus`, `[x, y]` or null. **A filled focus never reaches a nest
  clip:** `focus` is in the camera MEDIA's pixels, and `nest_then_switch` re-points the switch at
  the nest clip that replaces a moving camera, keeping `focus`; so a filled focus sent with
  `nest: true` goes only when `CameraLayoutCommand.keepsFocus` answers true — false only when the
  `nest: true` trial applies and the camera's id is absent from the applied project's view (the
  scoped view when the op is scoped) — and otherwise the op goes without it. Both senders call it
  on main: the offer sheet when it builds its op, the tool in its last hop. A caller's explicit
  focus is never dropped.
- **CO-71 — The Layout section** (`video.layout`, the Picture sub-tab). Offered when exactly one
  clip is selected and it is a `.media` clip with `video` and a source size; after Transform and
  Behind Subject, before Crop; shut by default. Rows: Layout (Corner, Side by Side, Stacked,
  Camera Full, Screen Only), Shape (Square, Rounded, Circle), Corner (Bottom Right, Bottom Left,
  Top Right, Top Left), Duration (s, 2 decimals, 0.01–10, quick 0.25 0.5 1 2, 0.5 by default),
  and Switch at Playhead. Shape and Corner are enabled only for Corner. The choices are per
  window (`ClipPane`), not persisted, not undoable, no Reset; the summary is the choice
  ("Circle, Bottom Right", "Side by Side"). Switch at Playhead is enabled while the window has no
  sheet and does not read the playhead (`inspectorPlayheadMoved()` refreshes only a clip with
  actions); pressed off the clip, the core's "clip N does not play at …" reaches the refusal
  strip through `performGroupedEdit`, with no undo step. It sends exactly the menu's op with the
  clip as camera and no screen, `duration` only when it is not 0.5 s.
- **CO-72 — The nest offer.** `CameraLayoutCommand.run`, which the menu and the section share,
  trials the op (no `nest`) on `document.project`, scoped as `ProjectDocument.addressed` scopes
  it. When it is refused and the same op with `nest: true` trials applied, a sheet goes up: "Lay
  out the clips in a nest?", the core's sentence verbatim, then "Nest and Switch puts those clips
  in a nest first, so the layout moves the nest and the zoom keeps playing inside it. One Undo
  takes both back.", buttons Nest and Switch and Cancel (Escape). Nest and Switch commits the ONE
  `switch_layout {nest: true}` through `performGroupedEdit` as one undo step "Camera Layout";
  Cancel changes nothing. Otherwise, and with no window, the op is committed through
  `performGroupedEdit`, whose arms beep, post the refusal strip or apply. The tool never offers:
  an agent sends `nest: true`. Because the item can now raise a sheet, `switchCameraLayout:`'s
  verdict in the menu inventory and `UIMenu.verdicts` is `sheet` (as `setTransitionKind:`'s is),
  so the screen catalog can reach the sheet.
- **CO-73 — The proof.** `tools/proof/co7_proof.py` (Release) with `co7_probe.swift`: Z1 no
  `Frame Job: ` line; P1 (probe) the section's place, its Switch at Playhead equal to the menu's
  Circle ▸ Top Left on a twin, one undo step each, Duration 1.00 a 600000-tick action, and a
  press off the clip refused at the strip with no step; P2 (canned masks of a person left of
  centre) the circle's crop centre at the masks' centroid within a pixel, P2b with half the
  window analysed the source's centre, P2c `analyze_cutout`'s centroid the same point; P3 no
  masks, the source's centre; P4 (probe, an editor in a window) the offer sheet, Cancel, and Nest
  and Switch equal to `switch_layout {nest: true}` and undone in one step; P5 the tool's filled
  focus equal to the menu's project and answered; P6 a filled focus dropped when `nest: true`
  nests the camera. Four mutants, each caught: the coverage guard dropped (P2b), the sheet's
  edits as two steps (P4), the fill skipped (P5), `keepsFocus` always true (P6). No new JOB row
  (JOB-64 stands).

## SW1 — copy pieces to a track, and Switch Angle (2026-11-03)

Recorded before the code. SW-10…SW-16 are SW1's: agents get `copy_pieces`, a core op that copies
a clip's pieces between given project times onto another track, each piece exactly the middle two
`split`s would leave; people get Clip ▸ Switch Angle ▸, and agents `switch_angle`, either of which
re-picks one shot from a covering camera track as one undo step. No persisted field, no format
bump (42 stands) and no `rc_*` export; nothing is sent anywhere, so nothing is keyed (CJ-3). The
owner's answers (2026-11-01): no ⌥1–⌥9 keys for Switch Angle (bare 1–9 come with the viewer in
SW9b), and a re-pick does not keep the shot's own video settings. SW1 ran in lane A (the road map
says lane C; nothing depends on the lane).

- **SW-10 — The switch writes a program track; it does not cut the cameras in place.**
  Picture-only cuts on the stacked cameras make two to three clips per shot where the program
  track makes one (a four-camera three-hour show at 8 s shots is about 5,400 against 1,350, past
  `MAX_CLIPS`); moving one cut there is trimming pieces on several tracks, here an ordinary roll;
  both decode one camera at a time.
- **SW-11 — `copy_pieces {clip, track, ranges, video?, audio?}`** copies the pieces of `clip`
  between each range's ends onto `track` at the same times, with fresh ids (the clip's and every
  action's). `ranges` are project times; `video` and `audio`, when given, set each piece's
  `enabled` switches. A copy has no transition and its link is cleared. Allowed inside a nest.
  As built (`core/src/edit_pieces.rs`), in this order:
  - `Err("no clip with id N")` for an unknown clip, then `Err("no track with id N")` for an
    unknown track.
  - Each pair is put in order (a reversed pair is the same range) and both ends are snapped by
    `snapped`, as `split` snaps. A range empty on the grid is dropped; nothing left is an
    identity (an empty `ranges` too). The ranges are sorted by start.
  - Then the refusals, each in its own sentence: a nest clip ("clip N is a nest: a piece of it
    would replay the nest from its first frame"); a range outside the clip ("range [a, b] is
    outside clip C, which runs from S to E"); overlapping ranges ("ranges [a, b] and [c, d]
    overlap"; ranges that only touch are allowed); a locked destination (`locked_track(T, "no
    piece can be copied onto it")`); a destination holding a clip over a range ("track T holds
    clip X between S and E", the clip's own ends, the first by start).
- **SW-12 — A piece is exactly the middle a `split` at its two ends would leave:** source window,
  a ramp's map and rate (SR-18), its actions clipped, a graphic's `in` and `length` (G-9), its
  words rebased (W-3), all from `split_clip`'s own arithmetic (`edit_split.rs`) on a scratch copy
  — `self` cloned with `clips` holding only the source clip, cloned again per range, split at
  `from` when `from` is past the clip's start and the middle split again at `to` when `to` is
  before its end. `split_clip` and its callers do not change. The middle is written into the
  result with a fresh id and fresh action ids from the result's own counter, never the scratch's;
  `track` the destination, `start` = `from`, `transition_in` and `linked` cleared, `enabled`
  overridden by `video`/`audio` where given; the exit is `finish`.
- **SW-13 — An angle is a TRACK; Clip ▸ Switch Angle ▸ re-picks one shot.** A track COVERS a span
  when its media clips with pictures together leave no part of it uncovered (a clip with its
  picture off, or on a hidden track, still counts). The submenu lists, for the one selected clip,
  every other track of its container covering the clip's whole span, front first, by name, up to
  nine; choosing one re-picks by SW-14's sequence, one `copy_pieces` per angle clip the span
  crosses, as one step "Switch Angle". `switch_angle {clip, angle}` does the same and refuses an
  angle not covering the shot, naming the first uncovered tick. No key (the owner, 2026-11-01).
- **SW-14 — A re-picked shot keeps its span, its switches and both its transitions, and nothing
  else** (a punch-in, grade or action on the old shot does not carry: the owner, 2026-11-01).
  With B between A and C: record B's span, switches and `transition_in`, A's end and C's start
  and `transition_in`; `delete` B; `trim_end` A to B's start and `trim_start` C to B's end, each
  `alone`; `copy_pieces` the angle over B's span with B's switches; trim A and C back to their
  old edges, re-forming both overlaps as they were; `set_transition` and `set_transition_style`
  give the new first piece B's `transition_in` and C its own. When the angle's clips cut the span
  into pieces and an overlap would break the overlap rule against a short piece, that transition
  is dropped and the step is "Switch Angle (transition removed)".
- **SW-15 — The menu and the tool.**
  - (a) Clip ▸ Switch Angle ▸ sits after Camera Layout ▸ and has no key. `SwitchAngleMenuFiller`
    fills it on open (the `LookMenuFiller` pattern), one item per `SwitchAngle.angles`: its title
    the track's name, a name two listed tracks share getting " (n)", n the track's 1-based
    position from the back; its tag the row index, its `representedObject` `NSNumber(track id)`,
    its selector `switchAngle(_:)`. With not exactly one selected clip, or no angle, the menu holds
    the single item "No Covering Angle", always disabled: it carries `switchAngle(_:)` with no
    track, which the validator turns off, and the menu is built holding it, so the selector is a
    live leaf before any project opens (the menu's three-way check, `v2_menu.py` H1; as built —
    the spec drafted it with no action).
  - (b) An item is enabled when exactly one clip is selected, its track is unlocked, it has no
    `linked`, the item's track is still in `angles`, and no sheet is up. Allowed inside a nest.
  - (c) `SwitchAngle.plan`'s refusals, in this order: the angle is the clip's own track ("track T
    is clip C's own track; an angle is another track"); the clip's track is locked ("track T is
    locked, so clip C cannot be re-picked"); a linked clip ("clip C is linked to clip P (Detach
    Audio's pair); Switch Angle re-picks a clip with no link"); not covering ("track T does not
    cover clip C: nothing with a picture plays on it at tick X"). An unknown clip or track
    throws.
  - (d) Covering counts only clips with `.media` sources whose media has a picture
    (`sourceSize(of:) != nil`); `enabled.video` and the track's `hidden` are ignored. The pieces
    are those angle clips sorted by start, each taking `[max(start, s), min(end, next angle
    clip's start, e))`, so where two angle clips overlap the later one takes over at its own
    start. Empty pieces are skipped, and each angle clip gets one `copy_pieces` with
    `video`/`audio` set to B's `enabled`.
  - (e) SW-14's ops are tried one at a time on the container's handle
    (`ReelProject.applying(_ op:)`), because `applying([ReelOp])` does not stop at a refusal.
    The new piece ids are read from the snapshot after the copies (a scoped view shares its
    parent's `next_id`). After `delete` B and the two trims away, A's end and C's start are read
    back. If any op before the trim-backs (`delete`, a trim away, a `copy_pieces`) answers
    refused, or a trim away is held short of its target (A's end is not exactly s, or C's start
    not exactly e, as a ramp's held edge leaves it, `source_window.rs`'s `front_edge_held`), the
    plan is refused and nothing is committed: a refusal gives that op's own sentence, a held trim
    "clip X's edge is held at tick Y, short of tick Z, so clip B cannot be re-picked". A
    trim-back that is refused, or held short of its old edge, is left out together with the
    transition ops for that edge; if the clip of that edge still holds a `transition_in`, it gets
    `set_transition` to none. When anything is left out, the step is "Switch Angle (transition
    removed)". A is the clip before B on its track ending after s, and C the clip after B
    starting before e; only these are trimmed. The menu commits through `applyEdit` and selects
    the pieces; the tool commits through `performGroupedEdit` and answers `{ok, step, pieces,
    transitions_removed, project}`, `pieces` in time order. `switch_angle` takes no `scope`: it
    reads the container `set_scope` has open, as `text_behind_subject` does, and runs on main.
- **SW-16 — The proof.** `tools/proof/switch_pieces_proof.py` (Release), P1–P5 and six mutants,
  with no manual check. P1 `copy_pieces` of a ×0.999 drift-corrected angle onto a new track:
  `render_frame` at five times byte-identical to the angle shown alone; P2 Switch Angle by
  `perform_menu_item` replaces the shot's media over the same span and one undo restores it; P3
  `switch_angle` the same, a non-covering angle refused in its sentence, and an angle of two
  abutting files re-picking a shot crossing their join as two pieces; P4 a shot with a dissolve on
  its incoming edge, its outgoing edge and both, every overlap's span, kind, curve and audio shape
  read back equal, a two-piece re-pick breaking the overlap rule named "Switch Angle (transition
  removed)", and P4d, a ramp-down C reaching its media's end, refused in the held-edge sentence
  with the project unchanged; P5 `copy_pieces` of 1,000 ranges on a two-hour angle within 0.5 s
  (median of five; over it, the figure in the guide and a Performance candidate). P5's fixture is
  generated into `tools/proof/media/creator/sw1/`: a two-hour 320×180 H.264 file stream-copied
  from repeats of one encoded minute, never committed. The mutants: the piece's `in` without the
  clip's speed (core); the occupancy refusal removed (core); the link kept on the copy (core);
  candidates not required to cover (P3); delete and copy as two steps (P2); neighbours not
  trimmed back (P4). The core mutants run against `cargo test --test copy_pieces`.
