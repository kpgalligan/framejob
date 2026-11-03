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
