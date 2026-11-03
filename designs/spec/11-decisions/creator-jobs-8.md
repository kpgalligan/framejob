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
