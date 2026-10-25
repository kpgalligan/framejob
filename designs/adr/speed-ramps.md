# Speed ramps: a clip's rate changing over time, as a Speed action (road map "speed-ramps")

- **Status:** Built and closed 2026-10-24, for #111. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-ramps` on branch `speed-ramps` and merged into main alone after its gate (SR-4). Five of them were spikes, each judged by a rule fixed before its run:
  - SR1, the road map, SR-1…SR-5 and the segment spike: STOP (`ffcb4b5`)
  - SR1b, the rendered-audio spike (SR-6, SR-7): SPLIT, off GO, on STOP (`874ecc8`)
  - SR1c, Keep pitch as resample, then pitch-shift (SR-8, SR-9): STOP (`214aee8`)
  - SR2a, `speed` as an action target, the speed map and the plan (SR-10, SR-11; format 27) (`2ee4e34`)
  - SR2b, the render wired into playback and export (SR-12) (`a579f71`), after its toll, `CompositionBuilder+Orientation.swift` (`5042934`)
  - SR1d, Keep pitch through Apple's time-pitch in rate mode with a 56 ms lead (SR-13…SR-15): STOP, landed on the owner's answer (`242f104`)
  - SR1e, the closed loop measured and closed (SR-16, SR-17) (`e2e79b9`)
  - SR3a, trims, roll, slip, split, freeze and the handle on a ramped clip (SR-18) (`27bbe72`)
  - SR3b, rate edits scale the whole profile; copies and re-snaps carry a ramp (SR-19) (`d35c716`)
  - SR4, Swift's mappers (SR-20) (`6a1b7a9`), after its toll, `CoreValues.swift` and `ReelOpSchema.swift` (`0b4be0b`)
  - SR5, the UI and #338 (SR-21, SR-22) (`6d1a968`), after its toll, `InspectorLabels.swift` (`a572d3f`)
  - The close: this record (the commit that moved the original to `archive/`)
- **Original:** `archive/speed-ramps.md` is the full record. It has no section numbers, so it is cited by its own headings: "orig SR2b" is its "SR2b — the renderer wired in" section, and "orig rule I" is the rule I bullet of its "Decided here".
- **Spec decisions:** SR-1..SR-22 in spec §11: SR-1…SR-12 in `designs/spec/11-decisions/speed-ramps.md`, SR-13…SR-22 in `speed-ramps-2.md` (split at the close by the spec's ~500-line rule). They stay binding, and where the original words them differently, §11's text wins:
  - SR-1: a speed ramp is a Speed action on the action lane, ramping from the rate in force to its end rate along its curve and held after.
  - SR-2: the clip keeps its slot; a ramp changes how much source it plays, and an edit reading past the media's end is refused, naming the rate or end that fits.
  - SR-3: audio follows the clip's own Keep pitch, with no time-stretch of Frame Job's own (SY-41).
  - SR-4: the working arrangement: the worktree, each phase gated and merged alone, synthetic fixtures, no `--live` run, owner media never read.
  - SR-5: the segment spike's rule: abutting constant-rate segments every G frames, judged for placement, click, dropout, video and agreement, and a verdict of GO, GO-UNIFORM-LEAD, GO-EXPORT-ONLY or STOP.
  - SR-6: a ramped clip's audio is rendered offline into `cache/ramp-audio/` and carried as one ×1 segment; with Keep pitch off, a Kaiser-windowed-sinc tape glide.
  - SR-7: the rendered-audio spike's rule: placement against the ideal map, a dense click scan, PT1's ×1 tap correction and a verdict per Keep pitch arm.
  - SR-8: Keep pitch on as resample, then pitch-shift (superseded whole by SR-13).
  - SR-9: the third spike's rule: SR-7's arm ON plus the rendered pitch and its lag.
  - SR-10: `end.speed`, the rate rule, S in closed form, per-frame video segments placed as one unit, one audio segment carrying the map, the slot's refusals and format 27.
  - SR-11: Keep pitch inside a ramp glided like tape as an interim (lifted by SR-13 and SR-15).
  - SR-12: the render wired in: a file per plan ramp segment, ready iff it exists, owners and one serial queue, the landing under the cache ledger, the export's wait.
  - SR-13: Keep pitch on is `AVAudioUnitTimePitch` in rate mode, its rate commanded `rateLeadFrames` ahead, for ramps and held spans alike.
  - SR-14: the fourth spike's rule: the lead swept first on RK1 and RK2, then judged on a held-out RK3 and a gliding fixture.
  - SR-15: SR-13's arm lands at 56 ms though SR-14's run stopped; a deep slow-down plays up to about 22 ms late.
  - SR-16: SR1e closes as measured: the 56 ms lead stays, no closed loop and no re-fit; SR-15's limit widened.
  - SR-17: a corrected playback tap is trimmed, never zero-padded; a click outside it is unobserved.
  - SR-18: edits on a ramped clip through S: S∞ past the end, the head at the base rate, a split's halves meeting at S(cut).
  - SR-19: `set_speed` and `rate_stretch` scale the whole profile by one factor; copies and re-snaps carry a ramp; the ×12 figure is the greatest rate a clip names.
  - SR-20: `rc_project_source_map`, read only for a ramped clip through one interpolation; Synchronize Audio refuses a ramp.
  - SR-21: the UI: Rate inside a selected action writes its `end.speed`, the band names `speed`, the ×12 question for an end rate, the Speed sheet's ramp line, RMP-1..RMP-4.
  - SR-22: `set_action` refuses only an edit that takes an action further past its clip's end (#338).
  - Amended: SR-6 (by SR2a's two lines, SR2b's, SR-8 and SR-13); SR-7's PT1 (by SR-17); SR-8 (superseded by SR-13); SR-10 (by SR-18 and SR-19, twice); SR-11 (lifted by SR-13 and SR-15); SR-12 (i) (by SR-15); SR-15 (by SR-16); SR-18 (e) and (h) (by SR-19); SR-19 (i) (by SR-22); CI-6 (by SR-21).

## Context

#111 asked that a clip's rate can ramp from one value to another over a span, with playback and export agreeing frame for frame and sample for sample (a proof comparing export to expectation, made to fail on purpose once), undo working, and spec §5.2 and §6 describing it. A clip played at one rate (`Clip.speed`, `set_speed`, Clip ▸ Speed…), and AVFoundation's `scaleTimeRange` is piecewise-constant, so a ramp built from it is many abutting constant-rate segments. On 2026-10-23 the owner chose three things: a ramp is a Speed action on the existing lane; the clip keeps its slot and an edit past the media's end is refused; and audio follows the clip's own Keep pitch, with the road map opening on a spike that stops for the owner if the segments click or misplace audio. (orig "Goal", "The owner's choices")

## Decisions

- **A rate is an action target, and the clip keeps its slot (SR-1, SR-2, SR-10).** `speed` is a top-level number in an action's `end`, clamped to ×0.1–×1000, on media clips only. Its integral S is in closed form per curve, so every reader gets one exact answer. A ramp edit never changes `start` or `duration`; the out point is `in + S(duration)`, and an edit that passes the media's end is refused with the largest end rate that fits (S is affine in one action's end rate), or else the latest clip end. A clip whose actions name no `speed` plans byte for byte as before. (orig rules A–C; SR2a)
- **The segments click, so the audio is rendered (SR-5, SR-6, SR-7).** SR1 ran the plan a ramp would emit through the app's own builder, exporter and player. At G1, V1 clicked at 30 of 61 boundaries in export, V2 at 69 of 91 and V3 at 52 of 121, mostly a slope kink about 45 samples before each boundary, where each time-scaled segment's varispeed unit starts afresh. Placement spread 1.4 ms against SY-27's 0.5 ms. Frames were right everywhere. V1L ruled out GO-UNIFORM-LEAD. The owner chose "Render it ourselves". In SR1b, every rendered ramp and control with Keep pitch off placed at +0.000 ms median and 0.000 ms spread, with no click, no dropout and no wrong frame, and the export was the render (≤ 1.53e-5, the WAV's quantisation). (orig SR1, SR1b)
- **Keep pitch on took four mechanisms (SR-8, SR-11, SR-13, SR-15, SR-16).**
  - SR1b's time-pitch unit, driven by a moving rate, misplaced RK1 by up to 33.48 ms and RK2 by up to 49.36 ms, against ceilings of 17.60 and 19.14.
  - SR1c's resample, then pitch-shift (SR-8) fixed the timing (max 1.21 ms) but dropped out 17 times through RK1's ramp, about every 117 ms. The owner chose "SR2 now, fix after", and SR-11's tape glide inside a ramp shipped as the interim.
  - SR1d's diagnostic found the dropouts are the unit's own in pitch mode: one each time a gliding partial crosses an 11.7 Hz analysis bin (RK1's 17 crossings, 17 dropouts). No block size, flag, smoothness or K removed them. Rate mode with the rate read ahead had none. The sweep picked L* = 56 ms (RK1 8.06 ms, RK2 5.55 ms), but the held-out RK3 (×2 → ×0.5 ease in-out) read 22.10 ms against 19.14. The owner chose "Land it, then tighten" (SR-15).
  - SR1e measured a closed loop. The unit's consumed input does not fix where its output sits: a controller cost more than it fixed, and an oracle loop did not converge. A 50 ms re-fit passed every held-out shape (minimax 11.38 ms), but it sits 3 ms from a cliff (RK3 15.01 ms at 53, 22.10 at 56, 36.60 at 60). The owner chose "Keep 56 ms, close SR1e" (SR-16).
  - Every mechanism stayed Apple's algorithm (SY-41).
  (orig SR1b, SR1c, SR1d, SR1e)
- **The instruments trim a corrected tap (SR-17).** The ×1 playback tap read 21.000 ms early in one session and 86.333 ms in another, on the same package and through a probe built before SR2b's app changes, so it is host state (#335). At −86.333 ms, zero-padding read as a 0.05 s "dropout" on every rendered clip, RC-off-x1 with Keep pitch off included. The correction now trims, and selftest S22 replays that reading. (orig SR2b "The tap offset (#335) is host state", SR1d "What it shows", SR1e)
- **One file per plan ramp segment, wanted by owners (SR-12).** A render is keyed by everything that shapes it and is ready iff its file exists, so no second state has to follow the disk. Renders run on one serial queue, and a render no owner wants is dropped, so an edit storm costs at most the one render in flight. An export waits for its renders and never writes a silent ramp. Two defects were found and fixed in SR2b:
  - The first Release run hung: an `AVAssetTrack` does not retain its asset, and an optimised build ended `rampAssets` before `fill` read their tracks. `build` now holds them with `withExtendedLifetime`.
  - The review found that a cancelled render wanted again was never re-queued, so an export waited at "Preparing…" until it was cancelled.
  (orig SR2b "Found on the way", "The review's fix")
- **A split's halves meet at S(cut) (SR-18).** The design review showed that an `ease_out` split re-eased to the rate at the cut repeated 1/3 s of footage. So the head's end rate is solved in closed form, and the rate steps at the cut for `ease_out` and `ease_in_out`. The cheaper loss is a rate step, not a repeated or skipped frame. (orig SR3a)
- **One factor scales the whole profile; one ×12 figure (SR-19).** A rate edit on a ramped clip multiplies the base, every end rate and every speed span by f, so the shape and the window are kept. The review found doubles miss by an ULP (×49 asked ×1 gave 0.9999999999999999), so an unclamped f writes the clamped rate itself. The ×12 test reads the greatest rate the clip names, the figure `SpeedAudioDrop` already read, so no rate is computed in Swift (D2-1). (orig SR3b)
- **Swift reads the core's map, only for a ramp (SR-20).** One export answers a clip's map, and `SourceMap` is the one read-side interpolation. It is checked once at decode and binary-searched both ways, because a map holds a point every 600 ticks and the waveform reads it per pixel column. A constant clip reads exactly as before. Synchronize Audio refuses a ramped clip, since its drift line assumes one rate. (orig SR4)
- **The inspector's rule carries over (SR-21, SR-22).** A field inside an action writes that action's end (CI-2), so Rate inside the selected action writes `end.speed`, and the rate shown comes from `clip_state.speed`. Keep pitch and Fit to stay the clip's. `set_action` refusing every edit of an action already past its clip's end left no way to re-curve one, so it now refuses only a further overrun (#338). (orig SR5)

## What it built — where it lives now

- Rust, new: `speed_map.rs` (`SpeedMap`, `end_speed`, `is_ramped`, `ease_integral`, `of_length`, `time_for_source`, `head_end_rate`, `rate_at`, `rate_in_force`, `peak_rate`; SR2a, SR3a, SR3b, SR5), `speed_segments.rs` (`ramp_spans`, `ramp_audio`, `Project::source_map`; SR2a, SR4), `edit_action_speed.rs` (`read_speed_end`, R1–R3, `largest_fitting_end_rate`; SR2a, SR3a).
- Rust, changed: `evaluate.rs` (`Segment.ramp`, one clip's segments placed as one unit, the ×12 test on `peak_rate`), `source_window.rs` (the ramp arms of every bound, `source_read_by`, `source_advanced_through`, `front_edge_held`, `window_of`/`overrun`), `edit_action.rs` (the refusals wired in; SR-22's past-end test), `edit_clip_timing.rs` (`scaled_span`, `profile_factors`, `scaled_profile`), `frame_grid.rs` (`resnap_actions`, the second hold), the splitters, trims, roll and freeze, `actions.rs` (`clip_state`'s `speed`), `ffi_query.rs` (`rc_project_source_map`), the header; format 27.
- Rust tests: `ramp_plan.rs` (11), `ramp_door.rs` (9), `schema_v27.rs` (4), `ramp_trim.rs` (8), `ramp_split.rs` (10), `ramp_freeze.rs` (1), `ramp_transition.rs` (2), `ramp_reversed.rs` (2), `ramp_nest.rs` (2), `ramp_scale.rs` (12), `ramp_carry.rs` (10), `ramp_source_map.rs` (5), `ramp_inspector.rs` (8), each against closed-form oracles written in the file.
- Swift, new: `RampAudioRenderer.swift`, `RampAudioResampler.swift`, `RampCAFWriter.swift` and `RampAudioRenderer+TimePitch.swift` (SR1b; the last rewritten by SR1c, then by SR1d as SR-13's led rate-mode arm with `rateLeadFrames` 2 688), `RampVarispeedStream.swift` (SR1c, the Keep pitch off glide as a stream), `RampAudioCache.swift`, `RampAudioRenders.swift`, `ProjectDocument+RampAudio.swift` and `Exporter+RampAudio.swift` (SR2b), `SourceMap.swift` and `TimelineView+SourceMap.swift` (SR4). `RampAudioRenderer+Hybrid.swift` (SR2b, SR-11's mix) was deleted by SR1d.
- Swift, changed: `CompositionBuilder.swift` (`fill`'s ramp arm, the held assets), `CompositionPlan.swift` (`PlanSpeedRamp`, its `source`), `ReelCore.swift` (`ReelProject.sourceMap`), `ReverseCache.swift`'s `ReverseResolution.rampAudio`, `ProjectDocument.swift`'s six wiring lines, `Exporter.swift`'s wait, `MediaPeaks.sourceTick`, `MediaTranscript.swift`, `Transcriber.swift` (`Job.ramp`), `Transcriber+Jobs.swift`, `TranscriptReader.swift`, `FillerTranscription.swift`, `AudioSync.swift` (the refusal), `SpeedAudioDrop.swift` (the named peak, `mayCross` for `set_action_end`), `VideoPane+Speed.swift` (`baseRate`, `rateRead`, `rateOps`), `InspectorPane.swift` (`InspectorBinding.speed(_:)`), `InspectorMarks.swift` (the `speed` path), `ActionBands.swift` (`keys`, `isZoom`), `ActionSnapshot.swift` (`ActionPatch.speed`), `SpeedSheetController.swift` (`rampLine`), and the catalog prose of `set_action_end`, `set_action`, `remove_action`, `trim_start`, `set_speed`, `rate_stretch` and `sync_audio`. The dev-only launch default `-RCDevRampRenderHold <s>` (SR-12 (j)).
- Pure moves: `CompositionBuilder+Orientation.swift` (581 → 507), `CoreValues.swift` and `ReelOpSchema.swift` (`ReelCore.swift` 803 → 774), `InspectorLabels.swift` (`InspectorPane.swift` 737 → 491) (`designs/adr/app-file-history.md`).
- No op, tool, menu item or key added; no export setting changed. One FFI export, `rc_project_source_map`.
- Proofs and spikes: `tools/proof/ramp_spike/` (`ramp_spike.py`, `render_spike.py`, `ramp_spike_probe.swift`, its `README.md`; SR1–SR1e); `tools/proof/ramp_proof.py` (D0–D5, X0, E1, E2, N1, K1, R1, W1, U1, P1, L1–L3, T1, S1, V1–V3, C1, F1–F5, Q0–Q4, Y1, G1–G6, Z1, Z2, its `--baseline` and mutants), `ramp_mapper_probe.swift` (SR4), `ramp_ui_probe.swift` (SR5); `tools/proof/README.md`'s speed-ramps sections; the screen `designs/screens/10d-clip-speed-action.md` on `screens.py`'s `ramp` fixture.
- Documents: spec §4.3b, §4.4, §5.2, §5.4, §5.6, §6 (`06b`, `06c`), §7.1, §7.2, §7.4, §7.8, §7.9a, §7.10 and §9; the README's Editing bullet.
- Person checks, in `docs/manual-checks.md`'s "Speed ramps" section: RMP-1 (a ramp sounds right with Keep pitch off and on), RMP-2 (playback through a ramp looks smooth), RMP-3 (a ramped clip's filmstrip and waveform look right, SR-20 (h)), RMP-4 (the Speed section inside an action feels right).

**Headline numbers** (Mac14,6, macOS 26.5.1; every run under `env -u RC_ASSEMBLYAI_KEY`, none `--live`, so nothing was spent).

The spikes:

| Spike | Verdict | What decided it |
|---|---|---|
| SR1 (SR-5) | STOP | At G1, V1 30 of 61 boundaries clicking in export, V2 69 of 91, V3 52 of 121; V1-G1's placement spread 1.385 ms; 0 wrong frames in every read |
| SR1b (SR-7) | SPLIT — off GO, on STOP | RV1–RV3 and every RC-off control +0.000/0.000 ms, no click, no dropout; RK1 max 33.48 ms against 17.60, RK2 49.36 against 19.14 |
| SR1c (SR-9) | STOP | RK1 max 0.85 ms, RK2 1.21; RK1 17 dropouts, RK2 9; RC-on-x0.5 0/15 found; LG-RK1 28.25 cents RMS at τ +56 ms against 25 |
| SR1d (SR-14) | STOP, landed by SR-15 | L* 56 ms; RK1 8.06 ms, RK2 5.55, RK3 22.10 against 19.14; no export dropout; the gliding fixture 0 dropouts at ×0.9, ×1.1 and ×2 where SR-8 gave 2, 2 and 18 |
| SR1e (diagnostic) | closed by SR-16 | The best loop row RK3 18.54 ms but RK1 16.02 and H2 33.44; the oracle loop RK1 8.06 → 21.97 over three passes; the 50 ms re-fit's minimax 11.38 ms, not taken |

| Measure | Measured | Command |
|---|---|---|
| The final product proof (SR5) | 43/43 in 150 s: E1 70/70 clicks at +0.000 ms, 0 wrong frames; L1 71/71 max 8.55 ms, L2 23/23 5.54, L3 35/35 21.47; R1 70/70 at −0.010 ms; W1 landed 2.4 s after the edit; U1 every constant clip's plan, video and audio as the `5042934` baseline; T1 1 640 000; Q4 edges 21 539 and 0 ticks off | `RC_PROOF_APP=release ramp_proof.py` |
| A Keep pitch ramp's pitch (SR1d) | K1 inside the ramp 5.34 cents median, outside 0.01; the spike's PR medians within 0.01 cents of 220 Hz | `ramp_proof.py` K1; `render_spike.py --verdict rate` |
| The render's cost | Keep pitch off 0.010–0.041 s per second of audio (SR1b), Keep pitch on in rate mode 0.0049–0.0143 (SR1d); 192 512 bytes per second of mono audio | `render_spike.py`'s RS rows |
| The map's reads (SR4) | 100 000 lookups in 0.10 s and 0.11 s, 10 000 `sourceTick` in 0.015 s, every breakpoint exact | `ramp_proof.py` F5 |
| Planted mutants | `ramp_proof.py --mutant expect-shift` (E1 median −2.000 ms) and `keep-shift` (L1 max 41.00 ms) each exit 1 | `ramp_proof.py --mutant` |

Mutants, each run once on the final instrument and each caught: SR1 five (the spike's), SR1b five, SR1c nine and a product mutant (`pitchCents`'s sign, read 880 Hz), SR2a ten, SR2b five (PM1–PM4, IM1), SR1d twelve selftest mutants and three product mutants (PM1–PM3), SR1e two (`trim-off`, `window-off`), SR3a nine, SR3b twelve, SR4 eleven, SR5 nine. From SR2a on, every phase passed `make gate` and a whole Release run of `ramp_proof.py` (6/6 at SR2a, 43/43 at SR5).

## Known limits

- **Keep pitch after a deep slow-down plays late** (SR-15, widened by SR-16). RK3 (×2 → ×0.5 ease in-out) reads up to 22.10 ms against SR-7's 19.14 ms ceiling, and SR1e's held-out shapes at 56 ms read H7 22.47 ms and H8 23.90 ms. For ×4 → ×1 (H3), 44 of 70 clicks are found, so about 26 are unmeasured. A 0.5 s ×3 → ×0.5 slow-down (H5) drops out once, with a 150-cent window. Only L3's case is pinned. The owner declined the 50 ms re-fit ("Keep 56 ms, close SR1e").
- **The lead rests on Apple's unpublished behaviour** (SR-13): a macOS change to the time-pitch unit's window could move it. L1–L3 fail on Release when it does. Keep pitch on is measured against controls, never claimed sample-exact (SR-3).
- **A render after every map edit** (SR-12): the whole clip is rendered again, one render at a time (no partial re-render), and an undone map's file is not kept. A failure stays failed until relaunch. A ramp is silent until its render lands, and an export waits for it.
- **Many video segments** (SR-10): inside a ramp, one per canvas frame (30 a second at 30 fps).
- **Splits and trims** (SR-18): an `ease_out` or `ease_in_out` split steps the rate at the cut. An `ease_in` or `ease_in_out` split moves the second half's out point. A `trim_start` that would read past the file lands nearer its old start than asked.
- **Scaling and carries** (SR-19):
  - A clamped factor leaves the base off the asked rate.
  - A ramped `rate_stretch` that the hold trims lands up to a frame short.
  - A re-snap moves a ramp's out point by the grid's rounding.
  - A speed action can lie past its clip's end after any of these ops.
- **The named peak** (SR-19, SR-21): an end rate above ×12 on an action past the clip's end leaves the audio out and asks the ×12 question, though the clip never plays above ×12.
- **The slot's refusal** (SR-2): a fast ramp near the media's end is refused, not shortened.
- **Words and silences through the chord** (SR-20): they are placed through S's piecewise-linear chord, the one the renderer plays. Captions made before a ramp edit keep their old times until they are made again (rule O).
- **Synchronize Audio refuses a ramped clip** (SR-20 (e)), as mover or anchor.
- **`glide` shapes nothing** (SR-13): the core still writes it and the cache key still names it.
- **Synthetic fixtures only** (SR-4, SR-5): a click train, one sine and one sweep. A real voice and a real picture are the person's checks RMP-1..RMP-4 (SR-20 (h), SR-21 (h)).
- **Older defects the road map found, filed and outside it:**
  - #334: a constant ×4 clip's exported audio has sample steps (3 in SR1, 28 events in SR1b's dense scan; its rendered twin none).
  - #335: the ×1 playback tap reads 21.000 or 86.333 ms early, by host session; the instruments trim it (SR-17).
  - #336: an export may fail when an audio track's only clip is all empty time (SR2b's PM2).
  - #337: a time-scaled clip's exported audio overruns or falls short of the timeline, run to run. CX2's `prores_422` audio was 196 095 frames in one run on a 4 s (192 000-frame) timeline, and CK05's was 1 213 frames (≈ 25 ms) short. U1 compares over the common length.

## Open items

- #334, #335, #336, #337: the older defects above, open.
- #299: Frame Job's own time-stretch for Keep pitch (SY-41), deferred by the road map; its comment of 2026-10-24 names a ramp's case and SR-15/SR-16's measured lateness.
- A rate graph drawn on the action lane (SR-1's risk line: a ramp is a band, not a graph): #339.
- Ramp presets, a Speed ▸ Ramp… sheet: #340.
- Re-timing existing captions and word captions with a ramp edit (rule O, SR-20 (g)): #341.
- Spec §4.3a at 523 lines, past the ~500-line split rule; a clean split needs `04.3b` renamed: #342.
- #338 was closed by SR-22.

#111 is closed by the orchestrator after this record's merge.

Not filed, each decided at the close:
- A partial re-render: SR1b showed one would be possible (RV1-edit's first 48 000 samples equal RV1's), but SR-12 accepts the whole-clip render at 0.0049–0.041 s per second of audio.
- `detach_audio`'s reduction of the twin's actions to `speed` and `audio`: not built by decision (SR-19 (e)), so re-enabling the twin's video stays lossless.
- `coarse_ms` in two instruments: already one definition (orig SR1e).

## Where to look in the original

- "Goal": #111's done-when.
- "The owner's choices": the three decisions of 2026-10-23.
- "How it fits the tree (at `80291b7`)": the rate, the source window, actions, the plan, Swift's composition and readers, the UI and the instruments the phases built on.
- "Decided here": rules A–Q, each with its Amended-by lines, and the deferred list.
- "Phases": what each of SR1…SR5 was to build, including SR1b–SR1e as they were added.
- "SR1 — the spike": the full table, the VERDICT line, the findings and the owner's "Render it ourselves".
- "SR1b — the rendered-audio spike": the table, the SPLIT, the cost, #334 and #335 answered, the owner's "Resample, then pitch-shift".
- "SR1c — Keep pitch as resample, then pitch-shift": D_K, the off arm unchanged, the table, the pitch and lag rows, the STOP and "SR2 now, fix after".
- "SR2a — the core target and the plan": the landed list, the ten mutants.
- "SR2b — the renderer wired in": the baseline, the landed list, the hang and `withExtendedLifetime`, the four mutants, #335 as host state, the review's re-queue fix (W1), U1's three changes of rule and #337.
- "SR1d — Keep pitch as Apple's time-pitch in rate mode, the rate commanded ahead": the diagnostic's dropout table and the bin-crossing count, the lead sweep's table, the measured run, the STOP, "Land it, then tighten" and the switch.
- "SR1e — the closed loop, measured and closed": the look-ahead A(r), the controller and oracle tables, the held-out shapes H1–H8 by lead, "Keep 56 ms, close SR1e", S22.
- "SR3a — edits on a ramped clip (F–K)": the landed list and nine mutants.
- "SR3b — a ramp's rate scaled and carried (L, M)": the landed list, ten mutants, and the review's fix pass (the ULP and the re-clamp).
- "SR4 — Swift's mappers (N, O)": the landed list, eleven mutants, and the F, Q and Y rows.
- "SR5 — the UI (P, Q) and #338": the landed list, nine mutants, the screens run, the review's two nits.
