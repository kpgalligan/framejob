# Road map "speed-ramps" — a clip's rate changing over time

**Opened 2026-10-23** (SR1, in the worktree `~/devel/framejob-ramps` on branch `speed-ramps`,
from `81900d9`, each phase gated, committed and merged into main alone), for issue #111. This
road map's decisions are SR-1 onwards, in `designs/spec/11-decisions/speed-ramps.md`.

## Goal

A clip plays at one rate today (`Clip.speed`, `set_speed`, Clip ▸ Speed…). After this road map
a clip's rate can ramp from one value to another over a span, as a **Speed action** on the
action lane, while the clip keeps its slot on the timeline. #111's done-when: a clip can ramp
from one rate to another over a span; playback and export agree frame for frame and sample for
sample (a proof in `tools/proof/` comparing export to expectation, made to fail on purpose
once); undo works; spec §5.2 and §6 describe it.

## The owner's choices

**2026-10-23** (asked and answered in the session that opened this road map):

1. **A speed ramp is a Speed ACTION** on the existing action lane, like zoom or opacity: speed
   becomes an action target; an action ramps from the rate in force to its end rate over its
   span along its curve and holds after (spec §5.4's evaluation rule). It reuses the action
   inspector, band drags and `add_action` / `set_action` (the MCP mirror).
2. **The clip keeps its slot**: a ramp never changes the clip's timeline length; it changes how
   much SOURCE the clip plays (the source out point moves). Later clips and the clip's other
   actions stay put. An edit whose ramp would read past the media's end is REFUSED, naming the
   rate (or the end) that fits.
3. **Audio follows the clip**, under the clip's own Keep pitch: off, the pitch glides like tape
   (varispeed); on, Apple's time-pitch as `set_speed` uses now (SY-41: no own time-stretch). The
   road map OPENS WITH A SPIKE measuring whether the many small rate segments a ramp needs
   (AVFoundation's `scaleTimeRange` is piecewise-constant) click or misplace audio, in playback
   and export; if they do, the phase stops and the owner is asked, with the measurement.

Also the owner's, standing: no feature size budget; memory limits relative to physical RAM;
features before performance.

## How it fits the tree (at `81900d9`)

- **The rate.** `Clip.speed` (`core/src/model.rs`, serde default 1). `set_speed`, `rate_stretch`,
  the trims and `rescale_actions` (actions keep their clip-relative fraction) are
  `core/src/edit_clip_timing.rs`; `SPEED_MIN`/`SPEED_MAX` ×0.1–×1000 and `AUDIO_SPEED_MAX` ×12
  (#190) there too, published by `rc_speed_limits`.
- **The source window.** `core/src/source_window.rs` is the one place a media clip's window is
  measured and moved: `content_length_in_source` (`round(duration × speed)`, D4-1) is what the
  plan reads, `in_advanced`/`source_advanced` the one mover, `latest_end_on_grid`,
  `earliest_start_on_grid`, `duration_at_speed` and `duration_resnapped` the bounds (D4-2..D4-5).
  Callers: trims, roll (`edit_edge.rs`), split (`edit_split.rs`), the handle transition
  (`edit_transition.rs`), freeze (`edit_time.rs`), paste, relink, `frame_grid.rs`.
- **Actions.** `Action {id, start, duration, curve, end}` (`model.rs`); `actions.rs`'s
  `evaluate_clip` (merge every ended action's `end`, lerp inside the spanning one by `ease`);
  `edit_action.rs` — the no-overlap rule, `check_end_patch` (`END_GROUPS`: video, audio, text;
  `graphic` is `edit_action_graphic.rs`'s arm), `off` (CI-14).
- **The plan.** `core/src/evaluate.rs`: `segment_of` gives ONE `Segment` per clip, `Pitch::of`
  one pitch name per clip (`off`, `time_domain` at ×0.98–×1.02, `spectral`; SY-26, SY-39),
  `place` puts each segment on the first free composition track (audio: same pitch only),
  `video_of` maps an instance path to ONE video track id for the recipe; above ×12 the clip has
  no audio segment. `plan.rs` writes the JSON (spec §7.2). The recipe reads no source time.
- **Swift's composition.** `CompositionBuilder.fill` (`app/Sources/CompositionBuilder.swift`,
  581 lines) walks a track's segments behind a cursor and `scaleTimeRange`s each time-scaled one,
  so N abutting segments already build. `CompositionBuilder+AudioPlacement.swift`: the varispeed
  lead (575 ticks, SY-24) is applied only to a TIME-SCALED segment; the noise-reduction lead per
  track. `audioParameters` sets the algorithm from a plan track's first segment's pitch.
- **Swift readers of `clip.speed`** (source ↔ timeline by one rate): `TimelineView.sourceTime`
  (filmstrip, waveform; `TimelineView.swift` is frozen), `MediaTranscript.project`,
  `TranscriptReader`, `Transcriber+Jobs` (transcripts, captions, `detect_fillers`,
  `get_transcript`), `AudioSync` and `AudioSync+Correction`. Readers of PLAN segments, which
  follow a ramp with no change: `MediaPeaks.sourceTick` → `SilenceDetector` (`detect_silence`),
  Normalize Clip.
- **UI and MCP.** `VideoPane+Speed.swift` (Rate, Keep pitch, Fit to), `SpeedSheetController`,
  `SpeedAudioDrop` (the ×12 question), `ActionBands.keys` (a band's label), `ActionPatch`
  (`ActionSnapshot.swift`: video, audio, text, graphic). `set_action_end`'s handler passes its
  patch raw (`AgentServer+Actions.swift`, `setActionEndRaw`); its prose is
  `AgentCatalog+Actions.swift`.
- **Instruments.** `export_offset_proof.py` (click fixtures, `locate`, SY-27's pin),
  `keep_pitch_survey.py`, `media_less_playback_probe.py` (driving the editor's own player,
  `AVPlayerItemVideoOutput`), `swift_build.py`, `graphics_spike/bounded.py`.

## Decided here

Each phase records the rules it builds in spec §11 as SR-n entries before its code.

- **A — The target.** `speed` is a top-level NUMBER in an action's `end`, beside the groups:
  `{"speed": 2.0}`; format 27 (`schema_v27.rs`). The rate in force at clip time t is §5.4's rule
  on one number: the clip's `speed`, then each ended action's `end.speed` in start order; inside
  an action `r_from + (r_to − r_from)·ease(u)`; held after. Media clips only: `set_action_end`
  refuses `speed` on any other source, by name (a nest clip, a still and a graphic take no rate,
  as `set_speed` refuses them). A finite number, clamped to ×0.1–×1000 as `set_speed` clamps; any
  other JSON kind is an `Err`; a `null` removes it (the crate's removal rule); `off` cannot name
  it. **A clip whose actions name no `speed` is CONSTANT** and every path is today's, byte for
  byte (its plan text included).
- **B — The source map.** `S(t) = ∫₀ᵗ rate`, in closed form per curve (the eases are
  polynomials). One new module, `core/src/speed_map.rs`, answers S, its inverse and a clip's
  segments; `source_window.rs` reads it in `content_length_in_source` and every bound, so D4-1's
  one reader holds.
- **C — The slot (SR-2).** A ramp edit never changes `start` or `duration`; the out point is
  `in + S(duration)`. `set_action_end`, `set_action` and `remove_action` refuse when that passes
  the media's end: `set_action_end` names the largest end rate that fits (S is affine in one
  action's end rate), the other two the latest clip end that fits. `add_action` cannot change a
  rate (its end starts empty).
- **D — The plan.** A ramped clip has one segment per G timeline frames inside each speed
  action (G from SR1's verdict) and one per constant span, boundaries on the frame grid; segment
  k reads `[in + round(S(t_k)), in + round(S(t_k+1)))`, so the source is contiguous and totals
  `S(duration)`. All of a clip's segments are placed as ONE unit on one composition track (the
  recipe's `video_of` names one id). One pitch per ramped clip: `off` with keep pitch off,
  `spectral` with it on (no near-unity band inside a ramp). Audio segments above ×12 are left out
  one by one. Each segment's envelope is the clip's over that span. If SR1 answers
  GO-UNIFORM-LEAD, every audio segment of a ramped clip takes the varispeed lead, scaled or not.
  *Amended by SR-6 (SR1b):* a ramped clip's AUDIO is not segments: Swift renders it offline into
  `cache/ramp-audio/` and the composition carries it as one ×1 segment over the clip's slot (no
  SY-24 lead); the plan's form for it is SR2's, recorded as an SR-6 Amended-by line first.
- **E — Audio (SR-3).** Keep pitch off glides (varispeed); on is `spectral` under SY-40's
  measured drift and SY-41. Sample agreement between playback, export and expectation is claimed
  for keep pitch off; keep pitch on is measured against the constant-rate controls.
  *Amended by SR-6 (SR1b):* off is `RampAudioRenderer`'s variable-rate Kaiser-windowed sinc (a
  tape glide), on is `AVAudioUnitTimePitch` driven offline with its rate set every 256 frames.
  *Amended by SR-8 (SR1c):* on is resample, then pitch-shift — the off arm's glide at 48 kHz × K
  (K = ⌈max rate⌉, 1…4), `AVAudioUnitTimePitch` held at ×1 with `pitch` = −1200·log₂ rate cents
  clamped to ±2400 (past ×0.25–×4 the excess glides like tape, the owner's tape-glide option
  applied continuously from the bound), a measured constant delay D_K discarded, and a fixed
  decimation by K.
- **F — Reversed clips: no case.** `in` and S are measured in the direction the clip plays
  (`Source::Media` in `model.rs`), so the reversed asset is indexed by the same segments and
  `ReverseMirror` mirrors each.
- **G — Nests.** A clip inside a nest may ramp; `nest.rs`'s `lifted` tail cut truncates its
  segments at the nest clip's extent. A nest clip takes no rate (A).
- **H — Transitions.** A handle read before a ramped clip's start is read at its base rate, a
  tail after its end at its last rate; the handle form's bounds read the map.
- **I — split, and every splitter through `edit_split.rs`.** The second half's `in` is
  `in + S(cut)`, exact, and its base speed the rate at the cut; a straddled speed action follows
  the crate's split rule (the first half ends at the rate at the cut, the second runs on to the
  original end with the original curve). Exact when the straddled action is `linear`; an eased
  one re-eases from the cut as every property does, so the second half's out point moves. A
  splitter never refuses for it: when that out point would pass the media's end, the second
  half's end rate is lowered to the largest that fits.
- **J — freeze_frame.** The still's `at` is `in + S(at − start)`.
- **K — Trims, roll, slip.** Actions stay in clip time (the crate rule, `trim_start`'s doc).
  `trim_start` advances `in` by S(Δ) under the map before the edit, a head extension at the base
  rate; every trim, roll and slip clamps through the ramp-aware bounds (a gesture clamps, it does
  not refuse); `slip`'s delta is converted at the base rate.
- **L — set_speed and rate_stretch on a ramped clip scale the whole profile** by one factor f:
  base and every `end.speed` × f, actions keep their fractions (`rescale_actions`), the same
  source window, duration `D / f` snapped and held to the file (D4-3). `rate` sets the base
  (f = rate ÷ speed); `duration` and `rate_stretch` fit (f = D ÷ D'); f is clamped so every rate
  stays in ×0.1–×1000.
- **M — detach_audio, paste, relink, re-snap.** The detached audio clip copies each action whose
  end names `speed`, reduced to its `speed` and `audio` keys, so the sound stays with the
  picture. `paste`, `relink_media` and `frame_grid.rs`'s re-snap hold a ramped window inside its
  file through the ramp-aware bound, as they hold a constant one today.
- **N — Swift's mappers.** One core answer, `rc_project_source_map(project, clip)` → the clip's
  breakpoints `[[clip_t, source_t], …]` (its plan segment boundaries, ramped or not), wrapped in
  `ReelCore.swift`, read by `TimelineView.sourceTime` (through a non-frozen helper),
  `MediaTranscript.project`, `TranscriptReader` and `Transcriber+Jobs`. `detect_silence` and
  Normalize Clip already read plan segments: tested, not changed. Synchronize Audio refuses a
  ramped clip, mover or anchor, by name (its drift line assumes one rate).
- **O — Captions.** Words made before a ramp edit are not re-timed by it, as `set_speed` does not
  re-time them today; captions regenerated after the edit follow the ramp (N).
- **P — The ×12 question (#190).** Asked when an edit takes a clip with sound from a peak rate at
  or below ×12 to above it; `set_action_end`'s, `set_action`'s and `remove_action`'s answers
  carry `audio_left_out` / `audio_note` when an agent's edit crosses.
- **Q — UI.** With the playhead in an action, the Speed section's Rate writes that action's
  `end.speed` (the inspector's `in_action` rule); Keep pitch and Fit to stay clip-level. A band's
  label names `speed` (`ActionPatch` gains it). The Speed sheet edits the base rate under L.

**Deferred, filed as issues at the close unless built:** a rate graph drawn on the lane, ramp
presets (a Speed ▸ Ramp… sheet), Frame Job's own time-stretch for keep pitch (#299, SY-41),
re-timing existing captions with a ramp edit.

## Phases

- **SR1 — the spike, SR-1…SR-5.** No product code. `tools/proof/ramp_spike/` measures, on
  synthetic fixtures through the app's own `CompositionBuilder`, `Exporter` and editor player, a
  ramp's piecewise segments (written today as abutting constant-rate clips, which is the plan a
  ramp will emit) for clicks, dropouts, misplaced audio and misplaced frames, in export and in
  playback, against constant-rate controls and a planted fault, by a rule recorded as SR-5 before
  the run. Its verdict — GO, GO-UNIFORM-LEAD, GO-EXPORT-ONLY or STOP — decides G and the lead
  for SR2; anything but GO or GO-UNIFORM-LEAD stops the road map for the owner.
- **SR1b — the rendered-audio spike, SR-6 and SR-7.** The owner's answer to SR1's STOP: the
  renderer built as the product files SR2 will call (`RampAudioRenderer.swift`,
  `RampAudioResampler.swift`, `RampAudioRenderer+TimePitch.swift`, `RampCAFWriter.swift`; no caller, no model, format,
  plan or composition change) and measured by `tools/proof/ramp_spike/render_spike.py` through
  SR1's instrument, by SR-7's rule. Its verdict per Keep pitch arm — GO, a named SPLIT, or STOP —
  decides whether SR2 starts with the renderer (a GO arm only); a STOP goes to the owner.
- **SR1c — Keep pitch as resample, then pitch-shift, SR-8 and SR-9.** The owner's answer to
  SR1b's SPLIT: `RampAudioRenderer+TimePitch.swift` rewritten as SR-8's three stages over a new
  `RampVarispeedStream.swift` (the glide as a forward stream, the off arm's own loop moved out of
  `RampAudioRenderer.swift`); SR1b's two review nits; no caller, model, format, plan or
  composition change. `render_spike.py --verdict on` re-runs SR-7's arm ON and scores the
  rendered pitch by SR-9; the off arm's renders are shown byte-identical to SR1b's. GO lets SR2
  start with both arms; a STOP goes to the owner with the measurement.
- **SR2a — the core target and the plan (A–D), SR-10 and SR-11.** `speed_map.rs`,
  `speed_segments.rs`, `edit_action_speed.rs`; `speed` as a number in an action's `end`, the
  evaluator's rate, `content_length_in_source` and the plan's per-frame video segments, the ramped
  clip's ONE audio segment carrying its map (silent until SR2b), format 27 with `schema_v27.rs`,
  C's refusals, `core/tests/` suites (constant clips' plans byte-identical), spec §5.2, §5.4, §6,
  §7.2, §7.10; the `set_action_end` prose and its `audio_left_out` (P's MCP half, `SpeedAudioDrop`
  reading the PEAK rate). The Swift lead rule is moot (SR-10). Its proof, `tools/proof/ramp_proof.py`,
  covers the door over MCP on Release: the speed stored, R1, `audio_left_out`, the errors, undo.
- **SR2b — the renderer wired in.** `CompositionBuilder.swift` (581 lines) gives up its orientation
  helpers to `CompositionBuilder+Orientation.swift` first, as a pure move landed alone; then
  `cache/ramp-audio/` (§5.6), the per-clip render resolution published and pinned beside the plan,
  renders scheduled on edit, `fill`'s ramp arm (the render at `start`, ×1, no lead), pending =
  silent, the export queue waiting on pending renders, SR-11's hybrid in `RampAudioRenderer`, a
  reversed ramped clip's render reading the reversed file; `ramp_proof.py`'s export and playback
  rows (#111's: an export compared to expectation frame for frame on an index fixture and click
  for click with keep pitch off, playback against export, a constant clip's export unchanged, a
  mutant made to fail on purpose); spec §5.6, §7.8.
- **SR1d — Keep pitch as Apple's time-pitch in rate mode, the rate commanded ahead, SR-13 and
  SR-14.** The owner's answer to SR1d's diagnostic STOP: `RampAudioRenderer+TimePitch.swift`
  rewritten as SR1b's rate-driven arm with its rate read a measured lead ahead
  (`rateLeadFrames`), SR-8's three stages and `TimePitchKept` gone, `per` out of
  `RampVarispeedStream` and `position`/`chunk`, `version` 4. `render_spike.py --lead-sweep`
  picks the lead on RK1 and RK2, and `--verdict rate` judges it by SR-14 on RK1, RK2, a held-out
  RK3 and constant renders of a gliding fixture; the off arm's renders are shown byte-identical
  to SR1b's. The run answered STOP; the owner landed it under SR-15 at L* 56 ms (SR-11
  lifted): every Keep pitch ramp goes through the arm, `+Hybrid` is deleted, and
  `ramp_proof.py` gains L1–L3.
- **SR1e — the closed loop, measured and closed, SR-16 and SR-17.** SR-15's follow-up: a
  render-only diagnostic of SR-13's loop found the unit's consumed input does not fix where its
  output sits, so neither a controller nor an oracle loop passes; a 50 ms re-fit passed
  everything measured and the owner did not take it ("Keep 56 ms, close SR1e"). SR-16 records the
  diagnostic and widens SR-15's risk line; SR-17 makes the instruments trim a corrected playback
  tap rather than zero-pad it (#335's artifact): `render_spike.py`'s PT1 and corrected playback,
  `ramp_proof.py`'s P1, selftest S22 and two mutants. No product behaviour changes.
- **SR3 — edits on a ramped clip (F–M).** `source_window.rs`'s bounds and movers through the map,
  split, freeze, trims, roll, slip, the handle transition, `set_speed`/`rate_stretch` scaling,
  `detach_audio`, paste, relink, re-snap; a `core/tests/` suite per rule; spec §6.
- **SR4 — Swift's mappers (N, O).** `rc_project_source_map` (Rust → header → `ReelCore.swift`),
  the filmstrip and waveform, transcripts, captions, `detect_fillers`, `get_transcript`,
  `detect_silence` checked, Synchronize Audio's refusal; proof rows added to `ramp_proof.py`.
- **SR5 — the UI and the close (P, Q).** The Speed section in an action, the band label, the ×12
  question for a ramp, the Speed sheet on a ramped clip; `docs/manual-checks.md` rows (a ramp
  sounds right, playback looks smooth); the README's bullet; the screen catalog if a screen
  changes. The close is the orchestrator's (ADR, issues, archive).

**Between SR2's merge and SR3's**, an edit of a ramped clip other than the action ops uses
today's one-rate arithmetic; only an MCP `set_action_end` makes a ramp before SR5.

## SR1 — the spike

**Run 2026-10-23** (ended 12:48 −0400, 714 s), the whole spike once on the final instrument:
`env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/ramp_spike.py`. Host Mac14,6, macOS
26.5.1 (25F80), load 7.08 / 20.78 / 18.77 at the start (other sessions on the host), no Frame
Job running. HEAD `81900d9` with SR1's files uncommitted (`81900d9…+dirty`). `rule_sha256`
`9d6b0cd7b000f8b74f0762a35a9f734dfe9d54a5547eeefaa1d2b07edd25688c` (the §11 file holding SR-5,
as the run read it). Selftest S1–S7 7/7; each of the five mutants caught (exit 1).

Instrument rows: Z0 ok (600 frames decode to their index, 100/100 clicks at 0.0000 ms, no click
at 597 fake boundaries on the sine); B2 ok; every read answered (plan 52/52, export 78/78,
playback 60/60 in 680 s); every Q row ok (each variant's plan is one video and one audio
composition track holding exactly the written segments, one pitch: `off`, or `spectral` for the
K variants and `C-on-*`); PT0 ok (C-off-x2's tap: 350 calls, 48 kHz float mono, 60/60 clicks,
median −0.000 ms, spread 0.000 ms). **I0 FAILED, so the run exited 1**: `C-off-x4` clicks in
export at three fake boundaries (0.667, 1.800, 3.633 s: D = 0.149 against a threshold of 0.027,
a sample step of about a third of the sine's amplitude in a constant ×4 clip, which playback
does not show), and F1 clicks at its 2 s boundary and fails placement, as planted, but also at
33 other boundaries — 25 of them V1-G1's own, because the unfaulted ramp clicks too.

Columns: placement (keep pitch off: median/spread ms and found; on: found and max |diff| ms),
clicks (count @ the first boundaries, s), dropouts (count @ the first, s), wrong frames, for
export (E) and playback (P); A playback against export; ideal the written map's error against
the continuous S (reported only). ✗ fails SR-5's rule.

| variant | seg | E place | E click | E drop | E video | P place | P click | P drop | P video | A | ideal ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| V1-G1 | 62 | +0.426/1.385 (70/70) ✗ | 30 @1,1.0333,1.0667,1.1 ✗ | 1 @1.0991 ✗ | 0/240 | +0.406/1.385 (70/70) ✗ | 28 @1,1.0333,1.0667,1.1333 ✗ | 0 | 0/240 | ok | 0.059 |
| V1-G4 | 17 | +0.115/1.075 (70/70) ✗ | 10 @1,1.1333,1.2667,1.6667 ✗ | 1 @0.999 ✗ | 0/240 | +0.094/1.075 (70/70) ✗ | 10 @1,1.1333,1.2667,1.6667 ✗ | 0 | — | ok | 0.844 |
| V1-G15 | 6 | +0.010/0.969 (70/70) ✗ | 1 @1 ✗ | 1 @0.999 ✗ | 0/240 | -0.010/0.969 (70/70) ✗ | 1 @1 ✗ | 0 | — | ok | 13.684 |
| V2-G1 | 92 | +0.424/3.388 (38/39) ✗ | 69 @1,1.1333,1.2,1.2333 ✗ | 1 @0.9995 ✗ | 0/240 | +0.354/3.357 (39/39) ✗ | 71 @1.0333,1.0667,1.1333,1.2 ✗ | 0 | 0/240 | ok | 0.097 |
| V2-G4 | 25 | +0.109/0.850 (38/39) ✗ | 20 @1.1333,1.2667,1.4,1.5333 ✗ | 1 @1.1329 ✗ | 0/240 | +0.069/0.829 (39/39) ✗ | 19 @1.1333,1.2667,1.4,1.5333 ✗ | 0 | — | ok | 1.433 |
| V2-G15 | 8 | +0.034/0.141 (39/39) | 3 @1.5,3,3.5 ✗ | 1 @1.4995 ✗ | 0/240 | +0.003/0.132 (39/39) | 3 @1.5,3,3.5 ✗ | 0 | — | ok | 23.622 |
| V3-G1 | 122 | +0.539/1.117 (61/61) ✗ | 52 @1.0667,1.1333,1.1667,1.2 ✗ | 0 | 0/180 | +0.518/1.117 (61/61) ✗ | 63 @0.6,0.7,0.8,1 ✗ | 0 | 0/180 | ok | 0.127 |
| V3-G4 | 32 | +0.118/0.272 (61/61) | 13 @0.9,1.4333,1.5667,1.8333 ✗ | 0 | 0/180 | +0.097/0.260 (61/61) | 15 @0.7667,0.9,1.0333,1.3 ✗ | 0 | — | ok | 1.959 |
| V3-G15 | 10 | +0.041/0.109 (61/61) | 7 @0.5,1,1.5,2 ✗ | 0 | 0/180 | +0.020/0.110 (61/61) | 5 @0.5,1,1.5,2 ✗ | 0 | — | ok | 22.775 |
| K1-G1 | 62 | 71/71 max 11.48 | 1 @2.2333 ✗ | 2 @1.0023 ✗ | 0/240 | 71/71 max 11.48 | 11 @1.0667,1.1333,1.1667,1.2333 ✗ | 0 | 0/240 | ✗ | 0.043 |
| K1-G4 | 17 | 70/71 max 11.88 | 1 @2.6 ✗ | 5 @0.333 ✗ | 0/240 | 71/71 max 10.72 | 4 @1.2667,1.5333,1.6667,1.8 ✗ | 0 | — | ✗ | 0.792 |
| K1-G15 | 6 | 71/71 max 11.38 | 0 | 6 @0.05 ✗ | 0/240 | 71/71 max 11.37 | 0 | 1 @0.982 ✗ | — | ok | 10.568 |
| K2-G1 | 62 | 22/23 max 12.16 | 0 | 4 @1.0029 ✗ | 0/240 | 23/23 max 14.81 | 0 | 0 | 0/240 | ✗ | 0.051 |
| K2-G4 | 17 | 23/23 max 10.37 | 1 @2.7333 ✗ | 4 @0.05 ✗ | 0/240 | 23/23 max 10.33 | 0 | 0 | — | ok | 0.763 |
| K2-G15 | 6 | 23/23 max 13.66 | 0 | 5 @1.0029 ✗ | 0/240 | 23/23 max 13.61 | 0 | 4 @0.981 ✗ | — | ✗ | 13.516 |
| V1L | 62 | +0.435/0.435 (70/70) | 32 @1,1.0333,1.0667,1.1333 ✗ | 1 @0.9991 ✗ | 0/240 | +0.415/0.435 (70/70) | 31 @1,1.0333,1.0667,1.1333 ✗ | 0 | 0/240 | ok | 0.059 |
| F1 | 62 | -1.574/2.635 (70/70) ✗ | 34 @1,1.0333,1.0667,1.1333 ✗ | 1 @0.999 ✗ | 0/240 | -1.595/2.635 (70/70) ✗ | 33 @1,1.0333,1.0667,1.1333 ✗ | 0 | — | ok | 0.059 |
| C-off-x1 | 1 | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | -21.000/0.000 (30/30) ✗ | 0 | 0 | 0/180 | ✗ | 0.000 |
| C-off-x0.25 | 1 | -0.063/0.000 (7/7) | 0 | 0 | 0/180 | -0.083/0.000 (7/7) | 0 | 0 | — | ok | 0.000 |
| C-off-x0.5 | 1 | -0.021/0.000 (15/15) | 0 | 0 | 0/180 | -0.042/0.000 (15/15) | 0 | 0 | — | ok | 0.000 |
| C-off-x2 | 1 | +0.010/0.000 (60/60) | 0 | 0 | 0/180 | -0.000/0.000 (60/60) | 0 | 0 | 0/180 | ok | 0.000 |
| C-off-x4 | 1 | +0.016/0.000 (80/80) | 3 @0.6667,1.8,3.6333 ✗ | 0 | 0/120 | +0.000/0.000 (80/80) | 0 | 0 | — | ok | 0.000 |
| C-on-x0.5 | 1 | 15/15 max 10.20 | 0 | 2 @0.0694 ✗ | 0/180 | 15/15 max 10.16 | 0 | 0 | — | ok | 0.000 |
| C-on-x0.9 | 1 | 26/27 max 4.27 | 0 | 0 | 0/180 | 26/27 max 4.23 | 0 | 0 | — | ok | 0.000 |
| C-on-x1.1 | 1 | 33/33 max 3.41 | 0 | 3 @0.05 ✗ | 0/180 | 33/33 max 3.39 | 0 | 0 | — | ok | 0.000 |
| C-on-x2 | 1 | 59/60 max 10.88 | 0 | 1 @0.307 ✗ | 0/180 | 60/60 max 10.69 | 0 | 0 | — | ok | 0.000 |

```
VERDICT: STOP — V1-G1 export: placement, click, dropout; V2-G1 export: placement, click, dropout; V3-G1 export: placement, click; K1-G1 export: click, dropout; K2-G1 export: dropout; V1-G1 playback: placement, click; V2-G1 playback: placement, click; V3-G1 playback: placement, click; K1-G1 playback: click, agreement; K2-G1 playback: agreement
```

What it shows (findings, for the owner):

- **Abutting time-scaled segments click, in export and in playback alike.** At G1 V1 clicks at
  30 of 61 boundaries in export (28 in playback), V2 at 69 of 91, V3 at 52 of 121. Most are a
  slope kink about 45 samples before the boundary (the varispeed lead's 46 samples: each
  time-scaled segment's varispeed unit starts afresh), 1.3–5.5 × the threshold; several per
  variant are sample steps of 0.1–0.5 on a 0.5 sine (V1-G1 at 1.000, 1.100, 1.633 and 2.967 s,
  47–213 × the threshold). Coarser grains click less (V1-G4 10, V1-G15 1; V3-G15 7) but never
  none, and their ideal-map error grows to 10–24 ms at G15.
- **The 1 s boundary is not the uniform-lead case.** V1-G1 clicks at 1.000 s (its ×1 head
  meeting the first scaled segment) at 213 × the threshold, and V1L — the same head time-scaled
  by one tick so it takes the lead — clicks there just as hard, and at 31 other boundaries, so
  GO-UNIFORM-LEAD does not apply.
- **Placement drifts across a ramp.** V1-G1's ×1 head plays 0.96 ms early (575 ticks: the
  lead's size) and its ×2 tail 0.43 ms late, a spread of 1.4 ms against SY-27's 0.5 ms; V2-G1
  spreads 3.4 ms. V1L, its head scaled, holds a spread of 0.435 ms at +0.435 ms. Frames are
  right everywhere: 0 wrong frames in every export and every playback read.
- **Playback agrees with export for keep pitch off** (every V variant within 0.04 ms median,
  0.06 ms spread) — the artifacts are the composition's, not the player's. Keep pitch on does
  not: K1-G1 21.6 ms, K2-G1 11.5 ms max |diff|.
- **Keep pitch on (`spectral`)** places within 10.4–14.8 ms of expectation and passes its
  placement rule against its controls, but K1-G1 clicks (export 1, playback 11) and K1-G1 and K2-G1 show
  dropouts at 1.00 s in export (the G4 and G15 variants also at the clip's head).
- **Two control readings outside the ramp question:** `C-off-x4` exports three sample steps
  (above); and `C-off-x1`'s playback tap reads −21.000 ms (spread 0) where export reads 0.000 —
  only the unscaled ×1 control, every scaled control's tap agreeing with its export within
  0.02 ms, so it is read as the tap's own timing on a track with no time-scaled segment, not
  measured further here.

The verdict is **STOP**: SR2 does not start, and the road map waits for the owner.

**The owner's answer (2026-10-23, AskUserQuestion on the STOP):** "Render it ourselves
(Recommended)". A ramped clip's audio is rendered offline by Swift into a cached file, as a
reversed clip's media is (no segment boundaries): with Keep pitch off by a continuous
variable-rate resampler (a true tape glide), with Keep pitch on by Apple's time-pitch unit
driven offline with a smoothly changing rate (still Apple's algorithm, SY-41). SR-3 stands
(audio follows the clip's Keep pitch); its mechanism is a new §11 entry recorded before the
code, and a second spike, SR1b, measures the rendered audio against the same instrument before
SR2 starts. The instrument's two failed checks are SR1b's to answer: F1's "clicks at 2 s alone"
assumed a clean ramp (re-pinned against a rendered ramp), and `C-off-x4`'s export steps are
#334, a constant-rate defect outside the road map. `C-off-x1`'s −21 ms tap reading is #335.

## SR1b — the rendered-audio spike

**Run 2026-10-23** (ended 13:46:56 −0400, 616 s), the whole spike once on the final instrument:
`env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py`. Host Mac14,6, macOS
26.5.1 (25F80), load 22.97 / 36.46 / 41.10 at the start (other sessions on the host), no Frame
Job running. HEAD `22a332c` with SR1b's files uncommitted (`22a332c…+dirty`). `rule_sha256`
`4dd0a7def64092d81094e9b2d7e56a5dd6538ab682b07054ebbc0bb8bed2b543` (the §11 file holding SR-6 and
SR-7, as the run read it). Selftest S8–S13 6/6; each of the five mutants caught (exit 1); SR1's
`ramp_spike.py --selftest` 7/7 and its five mutants still caught. The probe built `-O`.

Instrument rows: Z0 ok; B2 ok; every read answered (render 33/33, plan 48/48, export 72/72,
playback 58/58 in 592 s); every Q row ok (a rendered variant's plan: the written video segments
and one ×1 audio segment of the render, pitch `off`); R44 ok (the 44.1 kHz WAV refused:
`unreadable("r44.wav is 44100 Hz; only a 48 kHz source with no trim is rendered")`); ID1 ok
(RC-off-x1's render equals the fixture's samples exactly, max |diff| 0 on both fixtures); PT1 ok
(RC-off-x1's tap: 348 calls, 30/30, median −21.000 ms, spread 0.000 ms, so m1 = −21.000 ms); every
C-off-* passes placement and dropout in export and the click rule but for C-off-x4; **F1 ok**
(RF1 in export: one click event, at 2.000 s, and placement fails, −2.000/2.639 ms); I0 ok, exit 0.

Columns as SR1's: placement (keep pitch off median/spread ms and found; on found and max |diff|
ms), clicks (events @ the first, s), dropouts, wrong frames, for export (E) and playback (P,
rendered variants corrected by m1); A playback against export; render s/s the render's wall
seconds per second of audio. ✗ fails SR-7's rule; `?` a reported keep-pitch control.

| variant | arm | E place | E click | E drop | E video | P place | P click | P drop | P video | A | render s/s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RV1 | off | +0.000/0.000 (70/70) | 0 | 0 | 0/240 | +0.000/0.000 (70/70) | 0 | 0 | 0/240 | ok | 0.0274 |
| RV2 | off | +0.000/0.000 (39/39) | 0 | 0 | 0/240 | +0.000/0.000 (39/39) | 0 | 0 | 0/240 | ok | 0.0147 |
| RV3 | off | +0.000/0.000 (61/61) | 0 | 0 | 0/180 | +0.000/0.000 (61/61) | 0 | 0 | 0/180 | ok | 0.0248 |
| RK1 | on | 71/71 max 33.48 ✗ | 0 | 0 | 0/240 | 71/71 max 33.48 ✗ | 0 | 0 | 0/240 | ok | 0.0065 |
| RK2 | on | 23/23 max 49.36 ✗ | 0 | 0 | 0/240 | 23/23 max 49.36 ✗ | 0 | 0 | 0/240 | ok | 0.0047 |
| RF1 | — | -2.000/2.639 (70/70) ✗ | 1 @2 ✗ | 0 | 0/240 | -2.000/2.639 (70/70) ✗ | 1 @2 ✗ | 0 | — | ok | 0.0190 |
| RV1-edit | — | — | — | — | — | — | — | — | — | — | 0.0243 |
| RC-off-x1 | off | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | ok | 0.0096 |
| C-off-x1 | — | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | -21.000/0.000 (30/30) ✗ | 0 | 0 | — | ✗ | — |
| RC-off-x0.25 | off | +0.000/0.000 (7/7) | 0 | 0 | 0/180 | +0.000/0.000 (7/7) | 0 | 0 | 0/180 | ok | 0.0135 |
| C-off-x0.25 | — | -0.063/0.000 (7/7) | 0 | 0 | 0/180 | -0.083/0.000 (7/7) | 0 | 0 | — | ok | — |
| RC-off-x0.5 | off | +0.000/0.000 (15/15) | 0 | 0 | 0/180 | +0.000/0.000 (15/15) | 0 | 0 | 0/180 | ok | 0.0120 |
| C-off-x0.5 | — | -0.021/0.000 (15/15) | 0 | 0 | 0/180 | -0.042/0.000 (15/15) | 0 | 0 | — | ok | — |
| RC-off-x2 | off | +0.000/0.000 (60/60) | 0 | 0 | 0/180 | +0.000/0.000 (60/60) | 0 | 0 | 0/180 | ok | 0.0222 |
| C-off-x2 | — | +0.010/0.000 (60/60) | 0 | 0 | 0/180 | -0.000/0.000 (60/60) | 0 | 0 | — | ok | — |
| RC-off-x4 | off | +0.000/0.000 (80/80) | 0 | 0 | 0/120 | +0.000/0.021 (80/80) | 0 | 0 | 0/120 | ok | 0.0405 |
| C-off-x4 | — | +0.016/0.000 (80/80) | 28 @0.112,0.134,0.304,0.474 ✗ | 0 | 0/120 | +0.000/0.000 (80/80) | 0 | 0 | — | ok | — |
| RC-on-x0.5 | on (anchor) | 15/15 max 14.14 | 0 | 0 | 0/180 | 15/15 max 14.14 | 0 | 0 | — | ok | 0.0053 |
| C-on-x0.5 | — | 15/15 max 10.20? | 0 | 2 @0.0694 ✗ | 0/180 | 15/15 max 10.16? | 0 | 0 | — | ok | — |
| RC-on-x0.9 | on (anchor) | 27/27 max 4.89 | 0 | 0 | 0/180 | 27/27 max 4.89 | 0 | 0 | — | ok | 0.0056 |
| C-on-x0.9 | — | 25/27 max 4.37? | 0 | 0 | 0/180 | 26/27 max 4.23? | 0 | 0 | — | ok | — |
| RC-on-x1.1 | on (anchor) | 33/33 max 3.59 | 0 | 0 | 0/180 | 33/33 max 3.59 | 0 | 0 | — | ok | 0.0053 |
| C-on-x1.1 | — | 33/33 max 3.41? | 0 | 3 @0.1009 ✗ | 0/180 | 33/33 max 3.39? | 0 | 0 | — | ok | — |
| RC-on-x2 | on (anchor) | 60/60 max 12.60 | 0 | 0 | 0/180 | 60/60 max 12.60 | 0 | 0 | — | ok | 0.0060 |
| C-on-x2 | — | 59/60 max 10.88? | 0 | 1 @0.265 ✗ | 0/180 | 60/60 max 10.69? | 0 | 0 | — | ok | — |

```
VERDICT: SPLIT — off GO, on STOP — RK1 export: placement; RK1 playback: placement; RK2 export: placement; RK2 playback: placement
```

What it shows (findings, for the owner):

- **Keep pitch off: GO.** Every rendered ramp (RV1 ×1→×2 linear, RV2 ×2→×0.5 ease in-out, RV3
  ×0.25→×4 ease in) and every rendered control places on the ideal map to within 0.000 ms median
  and 0.000 ms spread (RC-off-x4's playback 0.021 ms), with no click, no dropout and no wrong
  frame, in export and in playback, and playback agrees with export (after m1). Where SR1's
  segments clicked at 30–69 boundaries a ramp, the rendered glide clicks nowhere; the planted
  fault is now the only click the scan finds (RF1, at 2.000 s).
- **Keep pitch on: STOP, on placement alone.** RK1 (×1.1→×2) and RK2 (×0.9→×0.5) have no click,
  no dropout and no wrong frame, and agree with export, but are misplaced beyond their controls:
  RK1 max 33.48 ms against a ceiling of 17.60 (RC-on-x2's 12.60 + 5.0), RK2 49.36 ms against
  19.14 (RC-on-x0.5's 14.14 + 5.0), identically in export and playback. The error builds across
  the ramp and then holds: RK1 is about +21 ms late after speeding up, RK2 about −46 ms early
  after slowing down. Every RC-on anchor passes (each rendered constant control's max |diff| is
  within 0.2–3.9 ms of the composition's own `spectral` control's), so the unit is right at a constant rate and
  wrong while its rate moves. The shape fits the rate taking effect about 50 ms after it is set
  (SR-6 sets it for the block about to be rendered): the unit reports a latency of 0 frames but
  pulls 3 000–6 000 source frames ahead of the map (pulled − map), i.e. it reads ahead and spends
  the new rate on input it has already buffered. Not measured further here; a compensation would
  be a change to SR-6's mechanism, which is the owner's to choose.
- **Cost.** Render time 0.0047–0.0405 s per second of audio on this loaded host (−O; keep pitch
  off 0.010–0.041, on 0.005–0.007), 192 512 bytes per second of mono audio (the CAF's header
  included), the probe's peak RSS 62.6 MiB after 33 renders. An edit re-renders the whole clip:
  RV1-edit (RV1 ending ×2.5) took 0.194 s against RV1's 0.219 s, and its first 48 000 samples
  (1.000 s, everything before the ramp starts) are identical to RV1's, so a partial re-render
  would be possible (not built).
- **The export is the render.** The export WAV against the render at offset 0: max |diff|
  0 for RC-off-x1 and ≤ 1.53e-5 (half a 16-bit step, the WAV's quantisation) for every other
  rendered variant: the ×1 segment passes through untouched.
- **#334 and #335, answered here.** C-off-x4's export clicks (#334) are outside the verdict: the
  dense scan finds 28 events in it (I334, reported), its rendered twin RC-off-x4 none. The ×1 tap
  offset (#335) is −21.000 ms on both C-off-x1 (T335) and RC-off-x1, and only there; PT0
  (C-off-x2's scaled tap) reads −0.000 ms. Both issues stay open; neither touches the rendered
  path's verdict.

The verdict is **SPLIT — off GO, on STOP**: SR2 may start with the renderer for Keep pitch off;
Keep pitch on waits for the owner, with the measurement above.

**The owner's answer (2026-10-23, AskUserQuestion on the SPLIT):** "Resample, then pitch-shift
(Recommended)". A Keep pitch ramp is made in two stages: the keep-pitch-off resampler sets the
timing exactly, then Apple's time-pitch unit, held at rate ×1 (so it never changes rate and
cannot drift), shifts the pitch back by its `pitch` parameter, −1200·log₂(rate) cents, driven
smoothly from the map. Apple's ±2400-cent range bounds it to ×0.25–×4; outside that range a
ramp's Keep pitch is refused or falls back to the tape glide, which SR1c decides and records.
This replaces SR-6's keep-pitch arm (a new §11 entry, SR-8, before the code); a short third
spike, SR1c, measures it against the same instrument before SR2. The review's two nits (the
"no audio track" message when a track's format signature is nil, `RampCAFWriter.write`'s
per-call copy) are SR1c's.

## SR1c — Keep pitch as resample, then pitch-shift

**Run 2026-10-23** (ended 15:18:06 −0400, 291 s), the measured run once on the final instrument:
`env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --variants
RK1,RK2,RC-on-x0.5,RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,RC-off-x1,
RC-on-x1,RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2 --verdict on`. Host Mac14,6, macOS 26.5.1
(25F80), load 74.19 / 54.28 / 37.88 at the start (other sessions on the host), no Frame Job
running. HEAD `14a0edb` with SR1c's files uncommitted (`14a0edb…+dirty`). `rule_sha256`
`93b7f2aed524f75232bf828f81e5b583cf25480f834b8a8daa2af3f6865607be` (the §11 file holding SR-8 and
SR-9, as the run read it). Selftest S8–S17 10/10; each of the nine mutants caught (exit 1); SR1's
`ramp_spike.py --selftest` 7/7. The probe built `-O`. SR1b's work folder was copied first to
`tools/proof/work/ramp-render-spike-sr1b/`; its `results.json` still hashes `ad1ddbe8…f9f7f`.

**The mechanism is feasible.** The engine renders at 96, 144 and 192 kHz (K = 2, 3, 4) with no
refusal, and every constant render holds its pitch: PR median within 0.02 cents of f_e at every
rate (RC-on-x0.2 175.998 Hz, the excess below ×0.25 gliding down 1200·log₂(0.8) = −386 cents
as SR-8 says; RC-on-x6 330.001 Hz, the excess above ×4 gliding up by ×1.5; every other rate
220.000 ± 0.002 Hz; PR-source 220.000 Hz). No fall-back to K = 1 was needed. **The band
survives**: BW-RB-on-x2, a 15 kHz tone through a ×2 Keep pitch render, +0.01 dB re the source
(−6.01 against −6.02 dBFS), where a 48 kHz pipeline would have cut everything above 12 kHz.

**D_K**, from the render-only run with every D_K 0 (`--groups render --variants RC-on-x0.5,
RC-on-x0.9,RC-on-x1,RC-on-x1.1,RC-on-x2,RC-on-x3,RC-on-x6,RB-on-x2`), each RP signed median: K = 1
x0.9 +0.060 ms, x1 +0.000 ms (x0.5 found no click: below), K = 2 x1.1 +0.006, x2 +0.077, K = 3
x3 −0.060 — every one within 0.1 ms, so D_1 = D_2 = D_3 = 0; K = 4 x6 +0.9375 ms, so D_4 =
round(0.9375 × 192) = 180 stage-2 frames. The re-run with D_4 = 180 reads x6 +0.000 ms (max
|diff| 5.38 → 4.44 ms); the other rates are unchanged (their D is 0). The spread across rates at
one K is 0.060 ms (K = 1) and 0.071 ms (K = 2). The unit reports a latency of 0 at every K, and
pulls 3 904 (K = 1), 8 064 (K = 2), 8 128 (K = 3) and 8 448 (K = 4, with D_4) stage-1 frames past
K · frames: its look-ahead, at a constant rate harmless.

**The off arm is unchanged**: a render-only run of RV1, RV2, RV3, RF1, RV1-edit and RC-off-* wrote
20 CAFs each equal byte for byte (`cmp`) to SR1b's; ID1 ok (max |diff| 0 on both fixtures). **The
product mutant** (`pitchCents`'s sign flipped, RC-on-x2) read PR 880.000 Hz, +2400 cents, as
an octave up from the wrong sign must; the sign restored.

Instrument rows: Z0 ok; B2 ok; every read answered (render 24/24, plan 22/22, export 33/33,
playback 25/25 in 272 s); every Q row ok; R44 ok (refused `unreadable`); ID1 ok; PT1 ok
(RC-off-x1's tap: 348 calls, 30/30, median −21.000 ms, spread 0.000, so m1 = −21.000 ms); I0 ok,
exit 0.

Columns as SR1b's. ✗ fails SR-9's rule (SR-7's arm ON); `?` a reported composition control.

| variant | arm | E place | E click | E drop | E video | P place | P click | P drop | P video | A | render s/s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RK1 | on | 66/71 max 0.85 | 0 | 17 @1.089 ✗ | 0/240 | 66/71 max 0.85 | 0 | 17 @1.089 ✗ | 0/240 | ok | 0.0628 |
| RK2 | on | 9/23 max 1.21 ✗ | 0 | 9 @1.121 ✗ | 0/240 | 9/23 max 1.21 ✗ | 0 | 9 @1.121 ✗ | 0/240 | ok | 0.0184 |
| RC-on-x0.5 | on (anchor) | 0/15 ✗ | 0 | 0 | 0/180 | 0/15 ✗ | 0 | 0 | — | ✗ | 0.0177 |
| RC-on-x0.9 | on (anchor) | 27/27 max 0.90 | 0 | 0 | 0/180 | 27/27 max 0.90 | 0 | 0 | — | ok | 0.0208 |
| RC-on-x1.1 | on (anchor) | 33/33 max 0.99 | 0 | 0 | 0/180 | 33/33 max 0.99 | 0 | 0 | — | ok | 0.0588 |
| RC-on-x2 | on (anchor) | 55/60 max 0.85 | 0 | 0 | 0/180 | 55/60 max 0.85 | 0 | 0 | — | ok | 0.0451 |
| C-on-x0.5 | — | 15/15 max 10.20? | 0 | 0 | 0/180 | 15/15 max 10.16? | 0 | 0 | — | ok | — |
| C-on-x0.9 | — | 26/27 max 4.27? | 0 | 0 | 0/180 | 26/27 max 4.23? | 0 | 0 | — | ok | — |
| C-on-x1.1 | — | 33/33 max 3.41? | 0 | 1 @0.565 ✗ | 0/180 | 33/33 max 3.39? | 0 | 0 | — | ok | — |
| C-on-x2 | — | 60/60 max 10.90? | 0 | 1 @0.05 ✗ | 0/180 | 60/60 max 10.69? | 0 | 0 | — | ok | — |
| RC-off-x1 | off | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | ok | 0.0103 |
| RC-on-x1 | — | — | — | — | — | — | — | — | — | — | 0.0122 |
| RC-on-x3 | — | — | — | — | — | — | — | — | — | — | 0.0702 |
| RC-on-x6 | — | — | — | — | — | — | — | — | — | — | 0.1386 |
| RC-on-x0.2 | — | — | — | — | — | — | — | — | — | — | 0.0200 |
| RB-on-x2 | — | — | — | — | — | — | — | — | — | — | 0.0451 |

Pitch and lag (from the renders): PR-RK1 787 windows, median 220.001 Hz, median +0.00 cents,
|cents| median 0.01, max 130.98; PR-RK2 219.999 Hz, −0.01 cents, |cents| median 0.02, max 145.14;
every RC-on anchor within 0.01 cents (max 0.08). **LG-RK1 τ +56 ms, RMS 28.25 cents at τ (31.84
at 0) ✗**; LG-RK2 τ +46 ms, RMS 20.65 at τ (24.36 at 0). RP (the renders' own clicks): RK1 66/71
median −0.017 ms max 0.85; RK2 9/23 +0.709 ms max 1.21; RC-on-x0.5 0/15; RC-on-x0.2 0/6; RC-on-x1
30/30 +0.000; x0.9, x1.1, x2, x3, x6 as above.

```
VERDICT: STOP — RK1 export: dropout; RK1 playback: dropout; RK2 export: placement, dropout; RK2 playback: placement, dropout; RC-on-x0.5 export: anchor placement; RC-on-x0.5 playback: anchor placement; RK1: pitch lag
```

What it shows (findings, for the owner):

- **The timing is fixed.** Every click SR1c finds is within 1.21 ms of the ideal map (RK1 max
  0.85 ms where SR1b's rate-driven unit read 33.48; RK2 1.21 where it read 49.36), the export is
  the render (XR ≤ 1.53e-5, the WAV's quantisation) and playback agrees with export (RK1 0.001 ms
  spread). The drift SR1b stopped on is gone: the unit at ×1 does not drift.
- **The pitch holds at a constant rate and follows a ramp about 50 ms late.** Every constant
  render reads f_e within 0.08 cents; across a ramp the median holds (RK1 +0.00, RK2 −0.01 cents)
  but the windows where the rate is moving read up to 131 (RK1) and 145 (RK2) cents off. The lag
  fit puts the pitch command τ = +56 ms (RK1) and +46 ms (RK2) behind the content; RK1's residual
  at τ, 28.25 cents RMS, is over SR-9's 25, RK2's 20.65 under. Compensating it (setting the
  command ahead by τ) is out of SR1c's scope (the owner's call).
- **The ramps drop out while the pitch moves.** RK1 shows 17 dropouts between 1.089 and 2.987 s,
  about every 117 ms through its 1–3 s ramp and nowhere outside it; RK2 9 between 1.121 and
  2.742 s, their spacing widening as it slows. Identical in export and playback, so they are in
  the render. No constant render drops out, so the cause is the unit's pitch changing every 256
  frames; not measured further here.
- **A slowed click loses its shape.** RC-on-x0.5's render finds 0 of its 15 clicks, RC-on-x0.2 0
  of 6, and RK2 finds 9 of 23 — every click to ×0.65, one past it (at ×0.53), none from ×0.50 on — although the click energy sits on its
  expected sample (a look at RC-on-x0.5's render: each click's peak at +0.0 ms): the glide widens
  a click by 1/r and the unit's octave-up shift does not restore its form, so the template's
  correlation falls under 0.5. That is the placement rule's reading, and it fails RC-on-x0.5's
  anchor and RK2's placement; the timing itself is not wrong.
- **Cost.** 0.012–0.139 s per second of audio on this loaded host (−O): K = 1 0.012–0.021, K = 2
  0.045–0.063, K = 3 0.070, K = 4 0.139 (x6), against SR1b's rate-driven 0.005–0.007; the
  keep-pitch-off glide 0.010. Bytes per second as SR1b's (192 512–194 048 with the header); the
  probe's peak RSS 68.7 MiB after 24 renders.
- **The clamp** past ×0.25–×4 is the owner's tape-glide option applied to the excess: RC-on-x6
  reads 330 Hz (×6 / ×4 = ×1.5 above 220) and RC-on-x0.2 176 Hz (×0.8), each exactly on f_e, with
  the timing exact.
- **SR1b's two review nits are fixed**: a track whose format signature cannot be read now answers
  `unreadable("<file>'s audio format cannot be read")`, no longer "has no audio track"; and
  `RampCAFWriter.write` passes the array's own storage to `ExtAudioFileWrite` instead of copying
  the buffer on every call (the off arm's CAFs byte-identical).

The verdict is **STOP**: arm ON fails on RK1's and RK2's dropouts, RK2's placement count,
RC-on-x0.5's anchor placement and RK1's pitch lag. SR2 may start with the renderer for Keep pitch
off only (SR1b's GO); Keep pitch on waits for the owner, with the measurement above.

**The owner's answer (2026-10-23, AskUserQuestion on the STOP):** "SR2 now, fix after
(Recommended)". SR2 starts with the renderer. Until the Keep pitch arm passes, a clip with Keep
pitch on glides like tape INSIDE its ramp (the keep-pitch-off render), Keep pitch applying at the
held rates; SR2 records this as a §11 entry and a known limit. A phase SR1d, after SR2 and before
the UI phase, owns the arm: smoother pitch updates against the dropouts (17 in RK1, about every
117 ms, only while the pitch moves), the pitch commanded ahead by the measured lag (τ +46–56 ms,
sound now that the unit holds a constant rate), SR-7's click template for slowed Keep pitch
clicks (the clicks land on their samples but no longer match it), and the SR1c review's two nits
(`TimePitchKept.append`'s per-block `reserveCapacity`, which inflates the recorded cost; the
PR-source row's unguarded empty track).

## SR2a — the core target and the plan

The decisions were recorded before the code: SR-10 (the target, the rate rule, S, the plan's
ramped segments and audio form, C's refusals, format 27, the Swift lead rule moot), SR-11 (Keep
pitch inside a ramp, a known limit until SR1d) and SR-6's two Amended-by lines (the plan names no
file and carries the map; pending is silent and an export waits).

**What landed.**
- `core/src/speed_map.rs`: `end_speed`, `is_ramped` (a `media` clip with a speed end, false for
  every other source), `ease_integral`, and `SpeedMap` — held and ramp pieces split at every speed
  action's edges, an action ending at the rate in force held — with `source_at`, `time_at`
  (bisection inside a ramp), `rate_at` (no reader until SR3) and `peak`.
- `core/src/speed_segments.rs`: `ramp_spans` (one video segment per held piece, one per canvas
  frame inside a ramp, read through S and clamped into the file) and `ramp_audio` (keep pitch,
  `glide`, the map every 600 ticks inside a ramp).
- `core/src/edit_action_speed.rs`: `read_speed_end` and the refusals R1/R2 (`end_rate_refusal`,
  the fit solved from two readings, floored to 0.001 and stepped down) and R3
  (`overrun_refusal`), wired into `edit_action.rs`'s `set_action_end`, `set_action` and
  `remove_action`.
- `evaluate.rs`: `Segment` carries `ramp`; `place` takes one clip's segments as one unit; a
  ramped clip's segments come from the lifted clip, its ×12 test from the instance's own clip's
  peak. `source_window.rs`'s `content_length_in_source` reads S. Format 27.
- Swift: `PlanSegment.ramp` (`PlanSpeedRamp`), `resolveSource` answering nil for a ramp segment
  (empty time until SR2b), `ActionPatch.speed`, `SpeedAudioDrop` comparing peak rates, the
  catalog prose of `set_action_end`, `set_action` and `remove_action`.
- Tests: `ramp_plan.rs`, `ramp_door.rs`, `schema_v27.rs`; ten mutants (M1–M10) each caught by
  them. `tools/proof/ramp_proof.py` D0–D5.

**Measured.** `cargo test --release` on the untouched tree passed first, and no existing
assertion was edited. `ramp_plan.rs` 11, `ramp_door.rs` 9 and `schema_v27.rs` 4 pass; each of the
ten mutants fails at least one of them (M1 ease_in's integral as u²/2 — the closed-form video
segments; M2 one segment placed at a time — the overlap row; M3 the ×12 test on the base speed —
the ×13 peak and the nest rows; M4 the fit rounded to nearest with no step down — R1 names
×2.667, and R2; M5 a string read as a rate — the error row; M6 any action ramping, M9 any source
ramping — the twins' byte-equal plans; M7 `remove_action` without R3; M8 an equal-rate action as
a ramp; M10 the ×12 test on the nest's cut — the ×20 nest row). `make gate` passed (names,
typecheck at its four warnings, fmt, lint, test 237 s, app 164 s; 417 s).
`env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py`: 6/6 in 3 s —
D2's refusal named ×4 over AV.mov's 3 000 000 ticks and ×4 applied; D3 answered
`audio_left_out` [3] and the one-clip note; the log held no `Frame Job: `.

**Owed.** SR2b (above); `core/CLAUDE.md`'s module map rows for the three new modules and
`evaluate.rs`'s unit placement and peak rule (agents edit no `CLAUDE.md`).

## SR2b — the renderer wired in

The decisions were recorded before the code: SR-12 (the file per plan ramp segment and its
`RampSegmentKey`, ready iff on disk, owners and one serial queue, the landing under the cache
ledger and its re-queue, the prune, a failure not retried, the export's wait, SR-11's mix, the dev
hold) and SR-6's third Amended-by line (the key carries the reversal). The toll was paid first, as
a pure move landed alone (`de1e51e`): `CompositionBuilder.swift`'s orientation helpers to
`CompositionBuilder+Orientation.swift`, 581 → 507 lines (`designs/adr/app-file-history.md`).

**The baseline, before any other app edit.** `ramp_proof.py --baseline` on the Release app the
move's gate built (`de1e51e`, app inputs clean): CX1 (×1), CX2 (×2, keep pitch off) and CK05
(×0.5, keep pitch on), 4 s of the clicks fixture each, their plan texts and decoded md5s in
`tools/proof/work/ramp-baseline/baseline.json` — CX1 audio `6b4d7876…` (both exports), video
`b8c33bd0…`; CX2 audio `a54eb075…`, video `f8ccd0ea…`; CK05 `audio_wav` `22a0745d…`, `prores_422`
audio `63b49c3b…`, video `a00f0f95…`. CK05's two audio md5s are Apple's time-pitch's two outcomes:
three CK05 runs on one instance gave both, in either export, so U1 accepts either for a keep
pitch on constant clip and holds every other stream to its own md5.

**What landed.**
- `RampAudioRenderer.swift`: `Job.glide` (defaulted, so the spike probe compiles), `version` 3,
  `render` sending keep pitch on with glide spans to `+Hybrid`; `RampAudioRenderer+Hybrid.swift`
  (166): SR-11's mix — the off arm over the whole map into `<destination>.glide`, each held span
  alone by SR-8's arm on its own two-point map into `<destination>.held-<i>`, streamed back as
  `w·held + (1 − w)·glide` (`heldFrames`, `heldWeight`, 480-frame crossfades in the held span),
  the temporaries removed on every exit.
- `RampAudioCache.swift` (187): `RampSegmentKey`, `RampAudioRequest`, the name and its digest,
  the map, the requests a plan makes, the render's source (`AudioRateCopy`'s copy where needed,
  the reversed file for a reversed clip), the prune, `CompositionBuilder.rampAudioTracks`.
- `RampAudioRenders.swift` (232): the process-wide scheduler — owners' wants, one serial
  `.utility` queue, cancellation of what no owner wants, the `.landing` rename inside
  `CacheLedger.publish` and the re-queue on a refused one, failures kept for the launch, the
  export's wait, `-RCDevRampRenderHold`.
- `ProjectDocument+RampAudio.swift` (51) and six wiring lines in `ProjectDocument.swift` (1334):
  `rampAudio` published with the resolution, `ensureRampAudio()` after `ensureReversedMedia()` in
  `projectDidChange` and `makeWindowControllers` and after the reverse sheet's republish, the
  release at close, the notification's doc; a landing re-reads the package's date, prunes and
  posts `.reversedMediaDidChange` (`EditorViewController.swift` untouched).
- `Exporter+RampAudio.swift` (43): `withRampAudio`, wired into `Exporter.swift`'s build (595 →
  598) with the key released in `finish`; `ExportError.rampAudioFailed`.
- The builder: `ReverseResolution.rampAudio`; `build` opens the ready renders and holds their
  assets across the audio fill; `resolveSource`'s ramp arm answers the render's track; `fill`
  never scales a ramp segment; `placement` reads a ramp segment as `[0, duration)` with no lead;
  `audioURLs` skips ramp segments (the render's source is copied on the render queue).
- `tools/proof/ramp_proof.py`: `--baseline`, `--mutant expect-shift`, rows X0, U1, E1, E2, N1, K1,
  R1, P1 (its README section); spec §5.6, §7.2, §7.4, §7.8.

**Found on the way.** The first Release run hung at E1: the preview's rebuild after a landing threw
"Clip 3 could not be placed: The operation could not be completed" and its alert's `runModal`
held the main queue, so every later MCP call timed out (read from the modal window with lldb on
the proof's own instance, then that instance stopped by its pid). An `AVAssetTrack` does not
retain its asset, and an optimised build ends a local at its last use — the `rampAssets` the
build opened died before `fill` inserted from their tracks; Debug, which keeps locals to the end
of scope, never showed it. `build` now holds them with `withExtendedLifetime` across the fill.

**Measured.** `make typecheck` 0 errors and the 4 baseline warnings (`preferredTransform`'s in
`+Orientation`); both spike probes typecheck; `capture_spike/inventory.py --check` 5/5;
`spec_index_proof.py` 183/183. Debug: the first whole run read 12/14 — U1 failing on CK05's
other time-pitch outcome, P1 on the tap offset below — and after those two instrument changes
`--only U1,P1` read 4/4.
Mutants, each applied alone, `make app-debug`, its row run, reverted — every one caught: PM1 the
ramp placed 2 400 ticks late, E1 median +4.000 ms; PM2 the export building without its wait, E1
failed (the export answered "The operation could not be completed" rather than a silent file);
PM3 `heldWeight` answering 0, K1 held spans 1200.00 cents; PM4 the name ignoring the reversal,
R1 — the reversed export's clicks and frames still passed (the click train is symmetric under
reversal) and only the name apart and the audio md5 failed; IM1 `--mutant expect-shift`, E1
median −2.000 ms. `make gate` passed (153 s after the fix; 264 s before it).
`env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py`: 14/14 in 81 s —
E1 70/70 clicks at +0.000 ms (spread 0.001), 0 wrong frames, one `2-<16 hex>.caf`; E2 no click
event, no dropout; N1 the constant's md5 back after `undo`; K1 held median 0.01 cents against
220 Hz (580 windows), glide 0.24 cents against 220 · r(t) (195); R1 70/70 at −0.010 ms, 0 wrong
frames on the mirrored map, forward and reversed renders named apart; U1 every plan and md5 as
the baseline's; P1 m1 −86.333 ms, RV1's corrected tap 70/70 at +0.000 ms (spread 0.021), agreeing
with its export, 0 wrong frames on both packages; the log held no `Frame Job: `.

**The tap offset (#335) is host state.** SR1 and SR1b read the ×1 tap 21.000 ms early; this
session reads it 86.333 ms early — on SR1's own `C-off-x1` package too, and through a probe built
from `de1e51e`'s sources, so it is not SR2b's. It is past `place_ideal`'s 60 ms reach, so P1
aligns the control's tap to its clicks by whole samples before `pt1` reads the rest; m1 is the
sum.

**The review's fix.** A running render dropped by every owner, then wanted again before it
stopped (an undo and a redo, or an export's want just after an edit), was cancelled and left
wanted but neither queued nor on disk: the want skipped it as running, and `.cancelled` did not
re-queue it, so an export waited at "Preparing…" until cancelled. `RampAudioRenders` now sets the
running render's cancellation from whether any owner wants it on every reconcile, and puts a
cancelled render that is wanted again back on the queue, as a refused publish already was. Row W1
(RV1, then `undo` and `redo` inside the 2 s hold, the file to land within 60 s, then its clicks)
failed 3 runs out of 3 on Debug before the fix (the redo 15–21 ms after the edit, nothing landed
in 60 s) and passed after it. It reaches the race only when the redo beats the hold's next
cancellation poll, so it catches the defect by chance, not by construction. `make gate` passed
(219 s). `ramp_proof.py` on Release read 14/15: W1 landed 2.3 s after the edit, 70/70 clicks; U1
failed on CK05's `audio_wav`, a third time-pitch md5 (`4b08b903…`). That plan has no ramp segment,
so this fix cannot reach it. Its samples equal the same run's `prores_422` audio (`22a0745d…`,
one of the baseline's) over their common length, and only the length differs, 190 978 frames
against 190 787.
U1 then changed. CK05's two audio streams are compared by their decoded samples against the
baseline's, kept beside `baseline.json`. They must be identical over their common length, with
the lengths within 10 ms. Every other stream keeps its exact md5. The reason is Apple's
time-pitch run-to-run variance, which predates this change: the baseline at `de1e51e` already
held two CK05 audio md5s. The baseline was rebuilt with `--baseline --app` on a Release build of
`de1e51e` in a scratch worktree, so that it could store the PCM.
- Every plan, every video md5, CX1's audio and CK05's `audio_wav` came back as the first
  baseline's.
- CX2's `prores_422` audio did not: `800460bc…` against `a54eb075…`. It has 196 095 frames
  against the wav's 192 047 and is identical over their common length. So keep pitch off at ×2
  is not byte-stable in length either, at `de1e51e`.
- The Release run that followed read 14/15. U1's CK05 audio passed: both streams identical, 0
  frames apart. U1 failed on CX2's `prores_422` audio: `a54eb075…` against the new baseline's
  `800460bc…`.

U1 then changed again, to one rule for every audio stream, and the CK05 10 ms rule was dropped.
- Every audio stream, both exports of all three projects, is compared by its decoded samples
  over the timeline's own length, its first round(timeline × 48 000) frames. Those must be
  identical to the baseline's. A stream shorter than the timeline fails. Frames past the end are
  printed, not scored; that overrun predates this change and is #337.
- Plans and video keep their exact md5s.
- The baseline was rebuilt once more on the same `de1e51e` build, storing every audio stream's
  samples. Every md5 came back as the first baseline's; CX2's `prores_422` audio was `a54eb075…`
  again.
- Audio lengths: CX1 192 000 frames in both exports, CX2 192 047 in both. CK05 is 190 787 in
  both, which is 1 213 frames (≈ 25 ms) shorter than its 4 s timeline.
- The Release run read 14/15:
  - CX1's and CX2's audio are identical over 192 000 frames (CX2 +47 past the end, in the run
    and in the baseline).
  - U1 failed on CK05, both streams shorter than the timeline: `audio_wav` 190 851 frames,
    `prores_422` 190 787, the baseline 190 787. They are identical over their common frames.
  - By this rule CK05 fails at `de1e51e` as well: the ×0.5 keep-pitch export's audio ends ≈ 25 ms
    before its timeline.

The "shorter fails" rule was then dropped, because U1 exists to show that SR2b changed nothing in a
constant clip.
- Each audio stream must be identical to the baseline's over min(timeline frames, its length,
  the baseline's length).
- Its length against the timeline, short or past the end, is printed, not scored. #337 now covers
  short audio too.
- The baseline was not rebuilt.
- The Release run read **15/15** (81 s, exit 0). U1 matched every plan and video md5, and the
  audio was identical over CX1's 192 000, CX2's 192 000 and CK05's 190 787 frames in both exports.
  Against the timeline: CX1 +0, CX2 +47 and CK05 −1 213, in the run and the baseline alike.
- W1 landed 4.0 s after the edit, with 70/70 clicks. The log held no `Frame Job: ` line.

**Owed.** `app/CLAUDE.md`'s map rows for the five new files and their roles, `ReverseCache`'s
`rampAudio`, `RampAudioRenderer`'s caller; the root `CLAUDE.md`'s `-RCDevRampRenderHold` beside
`-RCDevSyncHold`; #335 gains this session's −86.333 ms reading (agents edit no `CLAUDE.md`).

## SR1d — Keep pitch as Apple's time-pitch in rate mode, the rate commanded ahead

### The diagnostic (before any code), and the owner's answer

SR1d opened as SR1c's owed work (smoother pitch steps against the dropouts, the pitch commanded
ahead by the lag, SR-7's template for slowed clicks, item 4's two nits). Its designer ran a short
read-only diagnostic first (a scratch probe built `-O` from this tree's `app/Sources`, SR-8's
`renderTimePitch` loop with knobs plus SR-6's rate-driven loop, scored with `ramp_spike.dropouts`
and `render_spike`'s `pitch_track`, `pitch_lag` and `place_ideal`, imported unchanged; host
Mac14,6 on AC, load 11–60, so no render timing is claimed). The replica reproduced both spikes
exactly: SR-8 on RK1 17 dropouts from 1.089 s, LG τ +56 ms at 28.25 cents, placement 66/71 max
0.85 ms (SR1c's); SR-6's rate mode RK1 max 33.48 ms, RK2 49.36 ms (SR1b's).

**SR-8's dropouts are the unit's own, at analysis-bin crossings.** Each is a smooth dip from 0.49
to 0.02–0.04 (about −25 dB) lasting about 20 ms. No setting of `AVAudioUnitTimePitch` removes
them:

| RK1, SR-8 as built (K = 2) | dropouts |
|---|---|
| block 256 (product) / 32 / 4096 | 17 / 17 / 17 |
| transient preservation off (param 7) | 17 |
| spectral coherence off (param 6) | 9 |
| smoothness 3 / 4 / 16 / 32 (coherence off for 4, 16, 32) | 17 / 9 / 10 / 8 |
| K forced 1 / 3 / 4 | 17 / 11 / 8 |
| coherence off + K 4 | 7 |
| pitch fixed −500 cents, input still gliding | 5 |
| pitch fixed 0, or the unit bypassed | 0 |
| RK2 (K = 1): as built / coherence off / K 4 | 9 / 13 / 5 |

The `pitch` parameter has no `CanRamp` flag (flags `c8800000`). A constant ×2 sine (440 Hz) with
the pitch moved over 1–3 s drops out too: −1200 → −700 cents 6, −1200 → 0 cents 19, a fixed
−1200 cents 0. In pitch mode the phase vocoder drops out once each time a partial crosses one of
its analysis bins, on the input or the output side: the bins are 11.7 Hz wide at 48 and 96 kHz
and 23.4 Hz at 192 kHz (FFT 4096 at 48 kHz, 8192 above); RK1's stage-1 tone glides at 220 × 0.45
= 99 Hz/s, so 11.7 / 99 = 118 ms, the measured spacing of about 117 ms; and the counts match the
crossings (RK1 input 20.7 → 37.5 bins, 17 crossings, 17 dropouts; −1200 → 0 18.8 → 37.5 bins, 19;
−1200 → −700 18.8 → 25.0, 6; K 4 at 23.4 Hz about 8.5 crossings, 8).

**It is not specific to ramps.** A 220 → 440 Hz sweep source at CONSTANT rates through SR-8's arm
drops out 18 times at ×2, twice at ×1.1 and twice at ×0.9, where the composition's own `spectral`
(an `AVAssetReaderAudioMixOutput` on a `scaleTimeRange`d track, `set_speed`'s Keep pitch) and
`.timeDomain` at ×2 give 0. So SR-11's held spans, shipped in SR2b, drop out on gliding pure tones
where a constant Keep pitch clip does not — SR-13's risk line.

**SR1c's LG τ (+46–56 ms) was confounded by the dropouts.** Re-read with every pitch window within
±40 ms of a dropout dropped: RK1 (K 2) τ +36 ms at 0.31 cents RMS (5.96 at 0), RK2 (K 1) τ +35 ms
at 0.27 cents (7.93 at 0); by K on RK1 +35, +36, +24, +19 ms for K 1–4. With a 35 ms lead, away
from the dropouts, RK1 τ +2 ms at 0.43 cents and RK2 τ −1 ms at 1.26; over every window SR-9's LG
still fails (22.62 and 23.43 cents), the windows at the dropouts dominating it.

**The drop-free alternatives.** (a) `AUTimePitch` ('tmpt') in SR-8's place: no dropouts, but its
reported latency moves with the pitch (2 740 frames at +1200 cents, 9 896 at −1200, at 96 kHz,
28–103 ms) and it jitters 7–15 ms within a constant render — not a fix. (b) SR-6's arm, the unit
in rate mode, its rate set every 256 frames from the map at n + lead:

| lead | RK1 placement max | RK2 placement max | dropouts | pitch |
|---|---|---|---|---|
| 0 ms | 33.48 ms | 49.36 ms | 0 | max \|cents\| ≤ 8.8 |
| 50 ms | 11.03 ms | 10.53 ms | 0 | max \|cents\| ≤ 8.8 |
| 60 ms | 8.86 ms (71/71) | 2.92 ms (23/23) | 0 | RMS ≤ 0.33 cents |
| 75 ms | 15.62 ms | 14.09 ms | 0 | max \|cents\| ≤ 8.8 |

against SR-7's ceilings of 17.60 ms (RK1) and 19.14 ms (RK2); SR1b's rate-mode RC-on controls had
found 15/15 at ×0.5, so the slowed-click template problem does not arise in rate mode. That is
SR-6's arm, which the owner had replaced with SR-8, so the designer stopped for the owner.

**The owner's answer (2026-10-23, AskUserQuestion):** "Rate mode + 60 ms lead (Recommended)":
SR-8's stage 2 replaced by Apple's time-pitch in RATE mode with the rate commanded ahead by the
measured lead, for ramps and SR-11's held spans alike, SR-11 lifted on a GO; the lead rests on
Apple's unpublished behaviour, so a `ramp_proof.py` row on Release pins Keep pitch ramp placement
and fails if the lead stops fitting; a new SHA-pinned rule (SR-7's arm ON plus SR-9's pitch where
it applies); the constant-rate finding a risk line; item 4's nits; keep-pitch-off renders
byte-identical.

### Decided, then built

SR-13 (the mechanism), SR-14 (the rule) and the Amended-by lines on SR-6's keep-pitch arm and on
SR-8 were written into §11 before any code; `spec_index_proof.py` 183/183. Then:

- `RampAudioRenderer+TimePitch.swift` (211 → 147): SR1b's rate-driven loop (`14a0edb`) with the
  rate read `lead` output frames ahead, `rateLeadFrames` (2 880 provisionally, then the sweep's
  2 688); `TimePitchKept`, `oversampling`, `pitchCents`, `timePitchCents`,
  `timePitchMaxOversampling` and `timePitchDelayFrames` gone.
- `RampAudioRenderer.swift`: the keep-pitch branch feeds the source as is from ⌊p(0)⌋ − P,
  `Job.leadFrames` (nil = `rateLeadFrames`, set only by the sweep), `Report` (`latencyFrames`,
  `pulledFrames`, `leadFrames`; `oversampling` and `delayFrames` gone), `version` 4,
  `position`/`chunk` without `per:`. `RampVarispeedStream` without `per` (its K = 1 arithmetic
  unchanged). `+Hybrid`'s `Report` call updated (until the verdict).
- `ramp_spike_probe.swift`: a render job's optional `lead_frames`; the render line prints
  `lead_frames` for `oversampling` and `delay_frames`.
- `render_spike.py`: RK3, the `sweep` kind and `glide.wav`, `--lead-sweep` (`lead_sweep`,
  `pick_lead`), `--verdict rate` (`decide_rate`, the ±6000-cent command), RS's lead and
  pulled − map frames, the RW rows, the PR-source guard, S18–S21 and three mutants; the spike's
  README section.

**Item 4's nits.** The first (`TimePitchKept.append`'s `reserveCapacity` on every 256-frame
block) is dissolved: `TimePitchKept` is gone with SR-8. The second (PR-source formatting an empty
fixture track) is guarded: it reads "no window read".

### Measured

`make typecheck` 0 errors and the 4 baseline warnings; the probe typechecks
(`swift_build.py typecheck`) and built `-O`. `render_spike.py --selftest` S8–S21 14/14; each of
the twelve mutants caught (exit 1): `dense-off`, `merge-all`, `pt1-off`, `identity-off`,
`on-anchor-off`, `pitch-flat`, `lag-zero`, `on-verdict-off`, `pitch-rule-off`, `rk3-off` (S18),
`sweep-drop-off` (S19), `lead-pick-max` (S20).

**The copy-aside.** SR1c's work folder was copied once to
`tools/proof/work/ramp-render-spike-sr1c/` before anything was run; its `results.json` hashes
`6cf4ac772152024fce98c29d631af2a6724d9cfb52163f8d5b4fda4b81c86a1e` (SR1c's run, rule
`93b7f2ae…07be`, VERDICT STOP).

**The off arm is unchanged.** A render-only run of RV1, RV2, RV3, RF1, RV1-edit and RC-off-*
(21/21 renders answered, R44 refused `unreadable`, ID1 max |diff| 0 on both fixtures) wrote 20
CAFs, each equal byte for byte (`cmp`) to SR1b's in `ramp-render-spike-sr1b/renders/`.

**The lead sweep** (`--lead-sweep`, 102/102 renders read in 15 s; H0 load 54.61 / 24.40 / 15.43,
HEAD `ea8b846…+dirty`; `lead/sweep.json`), each cell max |diff| ms (found/of) against the ideal
map:

| lead ms | frames | RK1 | RK2 |
|---|---|---|---|
| 0 | 0 | 33.48 (71/71) | 49.36 (23/23) |
| 2 | 96 | 27.79 (71/71) | 48.54 (23/23) |
| 4 | 192 | 31.19 (71/71) | 47.70 (23/23) |
| 6 | 288 | 30.70 (71/71) | 44.27 (23/23) |
| 8 | 384 | 24.89 (71/71) | 43.90 (23/23) |
| 10 | 480 | 28.83 (71/71) | 42.96 (23/23) |
| 12 | 576 | 27.87 (71/71) | 39.24 (23/23) |
| 14 | 672 | 30.13 (71/71) | 38.37 (23/23) |
| 16 | 768 | 25.73 (71/71) | 37.84 (23/23) |
| 18 | 864 | 25.14 (71/71) | 36.98 (23/23) |
| 20 | 960 | 25.15 (71/71) | 33.77 (23/23) |
| 22 | 1056 | 22.95 (71/71) | 32.28 (23/23) |
| 24 | 1152 | 22.79 (71/71) | 31.79 (23/23) |
| 26 | 1248 | 22.07 (71/71) | 28.00 (23/23) |
| 28 | 1344 | 20.52 (71/71) | 27.56 (23/23) |
| 30 | 1440 | 18.92 (71/71) | 27.01 (23/23) |
| 32 | 1536 | 19.26 (71/71) | 25.88 (23/23) |
| 34 | 1632 | 17.21 (71/71) | 21.68 (23/23) |
| 36 | 1728 | 16.96 (71/71) | 21.67 (23/23) |
| 38 | 1824 | 19.84 (71/71) | 20.97 (23/23) |
| 40 | 1920 | 14.63 (71/71) | 17.30 (23/23) |
| 42 | 2016 | 14.26 (71/71) | 16.83 (23/23) |
| 44 | 2112 | 13.54 (71/71) | 15.68 (23/23) |
| 46 | 2208 | 11.99 (71/71) | 11.19 (23/23) |
| 48 | 2304 | 11.47 (71/71) | 10.73 (23/23) |
| 50 | 2400 | 11.03 (71/71) | 10.53 (23/23) |
| 52 | 2496 | 9.66 (71/71) | 10.29 (23/23) |
| 54 | 2592 | 8.83 (71/71) | 6.70 (23/23) |
| 56 **L\*** | 2688 | 8.06 (71/71) | 5.55 (23/23) |
| 58 | 2784 | 8.33 (71/71) | 4.90 (23/23) |
| 60 | 2880 | 8.86 (71/71) | 2.92 (23/23) |
| 62 | 2976 | 9.13 (71/71) | 3.44 (23/23) |
| 64 | 3072 | 10.75 (71/71) | 4.42 (23/23) |
| 66 | 3168 | 10.85 (71/71) | 7.53 (23/23) |
| 68 | 3264 | 11.72 (71/71) | 8.50 (23/23) |
| 70 | 3360 | 13.30 (71/71) | 9.21 (23/23) |
| 72 | 3456 | 14.03 (71/71) | 9.81 (23/23) |
| 74 | 3552 | 14.26 (71/71) | 13.71 (23/23) |
| 76 | 3648 | 16.35 (71/71) | 14.25 (23/23) |
| 78 | 3744 | 16.51 (71/71) | 15.23 (23/23) |
| 80 | 3840 | 17.17 (71/71) | 18.65 (22/23) |
| 82 | 3936 | 19.05 (71/71) | 19.34 (22/23) |
| 84 | 4032 | 19.38 (71/71) | 20.13 (23/23) |
| 86 | 4128 | 19.63 (71/71) | 23.71 (23/23) |
| 88 | 4224 | 21.11 (71/71) | 24.59 (23/23) |
| 90 | 4320 | 22.39 (71/71) | 25.30 (23/23) |
| 92 | 4416 | 22.65 (71/71) | 28.85 (23/23) |
| 94 | 4512 | 23.26 (71/71) | 29.54 (23/23) |
| 96 | 4608 | 25.23 (71/71) | 29.85 (23/23) |
| 98 | 4704 | 25.52 (71/71) | 30.58 (23/23) |
| 100 | 4800 | 26.21 (71/71) | 34.67 (23/23) |

Every lead found every click but 80 and 82 ms (RK2 22/23). RK1's own best is 56 ms (8.06 ms),
RK2's 60 ms (2.92 ms). **L\* = 56 ms = 2 688 frames**, the greater max |diff| 8.06 ms; it went
into `rateLeadFrames` before the measured run. The 0, 50 and 60 ms rows repeat the diagnostic's.

**The run.** `env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_spike/render_spike.py --variants
RK1,RK2,RK3,RC-on-x0.5,RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,
RC-off-x1,RC-on-x1,RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2,RW-on-x0.9,RW-on-x1.1,RW-on-x2 --verdict
rate`, ended 2026-10-23 21:34:59 −0400, 315 s. Host Mac14,6, macOS 26.5.1 (25F80), load 6.35 /
15.90 / 16.44 at the start, no Frame Job running. HEAD `ea8b846` with SR1d's files uncommitted
(`ea8b846…+dirty`). `rule_sha256`
`3b90e2c5019a97afe43dbdd2240c7d6b4351a24cccc673d3659d40d4b23f2c04` (the §11 file holding SR-13
and SR-14, unchanged since they were written). Every read answered (render 29/29, plan 24/24,
export 36/36, playback 28/28 in 298 s); every Q row ok; R44 ok; ID1 ok; PT1 ok (RC-off-x1's tap,
83 calls, coarse −4 144 samples, then 30/30 at +0.000 ms, spread 0.021: m1 −86.333 ms); I0 ok;
exit 0.

An earlier attempt of the same command crashed before its verdict: PT1's row formatted a None
median, because this session's ×1 tap offset (−86.333 ms, #335, as SR2b's record read it) is past
`place_ideal`'s 60 ms reach, so RC-off-x1's tap found no click. That run judged nothing. PT1 was
then given `ramp_proof.py` P1's coarse alignment (`coarse_ms`: the tap moved by whole samples to
its nearest click peaks before `pt1` reads the rest, m1 the sum; SR2b's precedent) and its row
guarded, and the command run once more — the run above.

Columns as SR1b's. ✗ fails SR-14's rule; `?` a reported composition control.

| variant | arm | E place | E click | E drop | E video | P place | P click | P drop | P video | A | render s/s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RK1 | on | 71/71 max 8.06 | 0 | 0 | 0/240 | 71/71 max 8.06 | 0 | 2 @0.05 ✗ | 0/240 | ok | 0.0143 |
| RK2 | on | 23/23 max 5.55 | 0 | 0 | 0/240 | 23/23 max 5.55 | 0 | 2 @0.05 ✗ | 0/240 | ok | 0.0055 |
| RK3 | on | 35/35 max 22.10 ✗ | 0 | 0 | 0/240 | 35/35 max 36.64 | 0 | 2 @0.05 ✗ | 0/240 | ✗ | 0.0051 |
| RC-on-x0.5 | on (anchor) | 15/15 max 14.14 | 0 | 0 | 0/180 | 15/15 max 14.14 | 0 | 2 @0.05 ✗ | — | ok | 0.0050 |
| RC-on-x0.9 | on (anchor) | 27/27 max 4.89 | 0 | 0 | 0/180 | 27/27 max 4.89 | 0 | 2 @0.05 ✗ | — | ok | 0.0050 |
| RC-on-x1.1 | on (anchor) | 33/33 max 3.59 | 0 | 0 | 0/180 | 33/33 max 3.59 | 0 | 2 @0.05 ✗ | — | ok | 0.0051 |
| RC-on-x2 | on (anchor) | 60/60 max 12.60 | 0 | 0 | 0/180 | 60/60 max 36.64 ✗ | 0 | 2 @0.05 ✗ | — | ✗ | 0.0059 |
| C-on-x0.5 | — | 15/15 max 10.20? | 0 | 0 | 0/180 | 15/15 max 10.16? | 0 | 0 | — | ok | — |
| C-on-x0.9 | — | 26/27 max 4.27? | 0 | 0 | 0/180 | 26/27 max 4.23? | 0 | 0 | — | ok | — |
| C-on-x1.1 | — | 33/33 max 3.41? | 0 | 2 @0.05 ✗ | 0/180 | 33/33 max 3.39? | 0 | 0 | — | ok | — |
| C-on-x2 | — | 60/60 max 10.90? | 0 | 2 @0.099 ✗ | 0/180 | 60/60 max 10.69? | 0 | 0 | — | ok | — |
| RC-off-x1 | off | +0.000/0.000 (30/30) | 0 | 0 | 0/180 | +0.000/0.021 (30/30) | 2 @0.086,0.168 ✗ | 2 @0.05 ✗ | 0/180 | ok | 0.0094 |
| RC-on-x1 | — | — | — | — | — | — | — | — | — | — | 0.0050 |
| RC-on-x3 | — | — | — | — | — | — | — | — | — | — | 0.0068 |
| RC-on-x6 | — | — | — | — | — | — | — | — | — | — | 0.0089 |
| RC-on-x0.2 | — | — | — | — | — | — | — | — | — | — | 0.0056 |
| RB-on-x2 | — | — | — | — | — | — | — | — | — | — | 0.0065 |
| RW-on-x0.9 | — | — | — | — | — | — | — | — | — | — | 0.0051 |
| RW-on-x1.1 | — | — | — | — | — | — | — | — | — | — | 0.0049 |
| RW-on-x2 | — | — | — | — | — | — | — | — | — | — | 0.0052 |

Pitch (from the renders, under the rate-mode command, f_e = 220 Hz): PR-RK1 787 windows, median
219.999 Hz, −0.01 cents, |cents| median 0.01, max 7.52; PR-RK2 220.002 Hz, +0.01, max 8.65; PR-RK3
220.001 Hz, +0.01, max 21.76; every RC-on render within 0.04 cents of 220 Hz (max |cents| 0.23,
RC-on-x0.2), RC-on-x6 220.001 Hz and RC-on-x0.2 220.005 Hz where SR-8 read 330 and 176;
PR-source 220.000 Hz. LG-RK1 τ −11 ms, 0.26 cents RMS at τ (2.81 at 0); LG-RK2 −11 ms, 0.28
(3.00); LG-RK3 −11 ms, 0.30 (7.23). **RW: 0 dropouts at ×0.9, ×1.1 and ×2** on the gliding
fixture, where SR-8's arm gave 2, 2 and 18. BW-RB-on-x2 +0.01 dB. RP (the renders' own clicks):
RK1 71/71 median −0.395 ms max 8.06; RK2 23/23 −2.583 max 5.55; **RK3 35/35 +9.993 max 22.10**;
RC-on-x0.5 15/15 −12.629 max 14.14; x0.9 −2.641 max 4.89; x1.1 +2.284 max 3.59; x2 +3.542 max
12.60; x1 +0.000 max 0.00; x3 +7.539 max 24.71; x6 54/60 −6.088 max 14.33; x0.2 6/6 −23.839 max
31.17 (the constant controls as SR1b's to the hundredth: a constant rate never feels the lead).
RS: 0.0049–0.0143 s per second of audio, the unit's latency 0 at every rate, pulled − map
frames 2 174–14 144 (its look-ahead), peak RSS 78.8 MiB after 29 renders. XR: the export WAV is the render
(≤ 1.53e-5, the WAV's quantisation).

```
VERDICT: STOP — RK1 playback: dropout; RK2 playback: dropout; RK3 export: placement; RK3 playback: dropout; RK3: agreement; RC-on-x2 playback: anchor placement
```

What it shows (findings, for the owner):

- **The dropouts are gone.** No rendered ramp or constant drops out in export, and the gliding
  fixture is clean at ×0.9, ×1.1 and ×2. The pitch holds everywhere (every PR median within 0.01
  cents, the worst window 21.76 cents on RK3), the band is kept (+0.01 dB at 15 kHz), and the
  slowed clicks are found (RC-on-x0.5 15/15, RC-on-x0.2 6/6), so SR1c's template problem does not
  arise, as SR-14 expected.
- **The lead fits the ramps it was fitted on and not the held-out one.** RK1 (×1.1 → ×2 linear)
  and RK2 (×0.9 → ×0.5 ease out) pass placement in export and playback with room (8.06 against a
  17.60 ms ceiling, 5.55 against 19.14). RK3 (×2 → ×0.5 ease in-out, which the sweep never saw)
  reads up to 22.10 ms against its ceiling of 19.14 ms (RC-on-x0.5's 14.14 + 5.0), the export
  failing placement. Its clicks sit −1.7 to +12.9 ms in the ×2 head (RC-on-x2's own scatter,
  max 12.60), climb through the slow-down (+10.0 ms at 2.16 s, +16.7 at 2.63 s) and stay +18.2 to
  +22.1 ms late in the held ×0.5 tail, where RC-on-x0.5 sits −12.6 ms EARLY: after a ×4
  deceleration the unit is about 33 ms behind where a constant ×0.5 render puts it, and one
  constant lead does not take that out. That failure is in the render itself (the export is the
  render), so no instrument change moves it.
- **The playback failures are this host's tap offset, not the arm.** Every rendered variant's
  corrected playback — RC-off-x1, the keep-pitch-off ×1 file, included — shows one dropout event
  at 0.05 s, and RC-on-x2 and RK3 a playback max of 36.64 ms with agreement spread 33.129 ms. m1
  is −86.333 ms this session, so the correction moves the tap 4 144 samples later and its first
  86 ms are zeros: SR-5's (b) reads the zeros after the 50 ms edge as a dropout, and a click
  expected at 0.050 s (RC-on-x2's and RK3's first, both starting at ×2) is matched to the onset at
  0.086 s, 36.3 ms away (RC-off-x1's first P click event, at 0.086 s, is that onset). SR1b's and
  SR1c's m1 of −21 ms was inside the 50 ms edge and never showed it. These rows are artifacts of
  #335's offset; RK3's export failure stands without them.
- **Cost.** 0.0049–0.0143 s per second of audio on this host (−O), against SR-8's 0.012–0.139: the
  rate-mode arm is the cheapest Keep pitch path measured.

The verdict is **STOP**: SR-14's arm ON fails on RK3's export placement (a measured failure of the
lead on the held-out ramp) and on playback rows that #335's −86 ms tap offset produces. By SR-14
nothing lands: SR-11 stays, `+Hybrid` stays, the product is not switched, no gate is run and
nothing is committed. The measurement goes to the owner.

**Owed.** The owner's choice on this STOP. Whatever it is: `app/CLAUDE.md`'s map rows for
`RampAudioRenderer+TimePitch.swift` (SR-13's led rate-mode arm, no longer SR-8's three stages) and
`RampVarispeedStream.swift` (no K), and on a later GO `+Hybrid`'s row gone (agents edit no
`CLAUDE.md`); #335 gains this run's −86.333 ms and the zero-padding artifact it causes in
`render_spike.py`'s corrected playback (the SR-5 dropout rule and an early click reading the
padding); `coarse_ms` now lives in both `render_spike.py` and `ramp_proof.py`, one to be dropped
for the other.

### The owner's answer, and the switch

**The owner's answer (2026-10-23, AskUserQuestion on the STOP):** "Land it, then tighten
(Recommended)": switch the product to rate mode with L* = 56 ms now (SR-13's arm for held spans
and ramps alike, SR-11 lifted, `+Hybrid` removed, version 4); RK3's export placement, up to
22.10 ms against SR-14's 19.14 ms ceiling, accepted as a known limit; the run's playback failures
recorded as the instrument's (the −86.333 ms tap correction zero-pads the corrected head, and
RC-off-x1, Keep pitch off, shows the same 0.05 s "dropout"); SR-14's text untouched; then SR1e,
its own handoff, a closed-loop correction steering the rate from the source the unit has actually
consumed, replacing the constant lead if it passes.

**Recorded first:** SR-15 (the acceptance, RK3's measurement, the instrument limitation with
RC-off-x1 as its evidence, L1–L3, SR1e), SR-11's lifted-by line and SR-12 (i)'s Amended-by line;
the README row and Lines cells; `spec_index_proof.py` 183/183. SR-14's text is as its run read it.

**What landed on top of the STOP's tree.**
- `RampAudioRenderer+Hybrid.swift` deleted (`git rm`); `RampAudioRenderer.render` sends keep pitch
  on to SR-13's arm whatever the glide, `Job.glide` gone; `RampAudioRenders`' `job.glide = …` line
  and `RampAudioCache.glide(of:)` gone (the key's `|g…|` text stays — the core still writes
  `glide`, harmless redundancy); `rateLeadFrames`'s doc comment names SR-15's limit and L3.
- Spec §7.2 (`glide` kept in the plan and the key, shaping nothing since SR-13) and §7.4 (the Ramp
  row: no `+Hybrid`, `+TimePitch` the led rate-mode arm).
- `ramp_proof.py`: K1 re-expected (220 Hz inside and outside the ramp); L1 (RK1), L2 (RK2), L3
  (RK3) on the clicks with `L_FOUND` 0.90 and `L_CEILING_MS` 17.60, 19.14 and 27.10 ms — L1's and
  L2's SR-7's floor and ceiling from the measured run's export controls (RC-on-x1.1 / x2 max 3.59 /
  12.60; RC-on-x0.9 / x0.5 4.89 / 14.14), L3's RK3's measured worst 22.10 ms + a stated 5.0 ms
  margin (SR-7's own slack); `ramp_doc(…, curve)` and `ramp_end(…, speed)`; `--mutant keep-shift`
  (each L row's expectation 2 × its ceiling + 1 ms late); P1 calls `render_spike.coarse_ms`, its
  own copy deleted. `tools/proof/README.md`'s SR1d section.

**Measured.** `make typecheck` 0 errors and the 4 baseline warnings; the spike probe typechecks;
`render_spike.py --selftest` 14/14. Debug: `ramp_proof.py --only U1,K1,L1,L2,L3` 7/7 (K1 inside
the ramp 5.34 cents median over 199 windows, outside 0.01 over 588; L1 71/71 max 8.55 ms; L2 23/23
max 5.54; L3 35/35 median +9.878, max 21.47; U1 as the baseline); `--mutant keep-shift` exit 1 (L1
max 41.00 ms, L2 44.81, L3 31/35 max 41.00). `make gate` **PASS** in 262 s (names 1 s, typecheck
6 s, fmt and lint skipped as unchanged, test 146 s, app 108 s).
`env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py`: **18/18 in
66 s**, exit 0 — D1–D5; X0; E1 70/70 at +0.000 ms (spread 0.001), 0 wrong frames, one
`2-<16 hex>.caf`; E2 no click, no dropout; N1 the constant's md5 back after `undo`; K1, L1, L2, L3
as on Debug to the hundredth; R1 70/70 at −0.010 ms, renders named apart; W1 landed 2.3 s after the
edit, 70/70; U1 every plan, video md5 and audio stream as the baseline's; P1 m1 −86.333 ms (coarse
−4 144 samples), RV1's corrected tap 70/70 at +0.000 ms, agreement ok, 0 wrong frames; D0 no
`Frame Job: ` in the log. Product mutants, each applied alone, `make app-debug`, `--only K1,L1,L2`,
reverted (the files `cmp`-equal to before, Debug rebuilt clean after): **PM1** `rateLeadFrames` 0
— L1 max 33.58 ms (median +21.630), L2 max 49.51 (−45.691), caught; **PM2** the rate read at n − L
— L1 57/71 max 40.97, L2 max 60.33, caught; **PM3** glide spans routed to a restored hybrid — K1
inside the ramp 758.70 cents, caught (L1 12.60 and L2 12.93 passed, the tape glide's timing being
exact). Every instance was the proof's own, stopped by its pid.

The app's L rows read a little apart from the spike's renders (RK1 8.55 against 8.06 ms, RK3 21.47
against 22.10): the core's map has breakpoints at the piece edges and every 600 ticks from each
ramp's start, the spike's every 600 ticks from 0.

**Owed.** SR1e (its own handoff). `app/CLAUDE.md`'s map rows: `RampAudioRenderer+Hybrid.swift`
gone (its line 1182 still says `+Hybrid`), `RampAudioRenderer+TimePitch.swift` SR-13's led
rate-mode arm (`rateLeadFrames`), `RampVarispeedStream.swift` the keep-pitch-off glide only (no
K), `RampAudioRenderer`'s keep-pitch branch with no hybrid route (agents edit no `CLAUDE.md`;
the orchestrator applied them). #335 gains this session's −86.333 ms and the zero-padding
artifact it causes in `render_spike.py`'s corrected playback.

## SR1e — the closed loop, measured and closed

### The request

SR-15's follow-up, as the owner's "Land it, then tighten" set it: steer the time-pitch unit's
rate from the source it has actually consumed, so the lag after a deep slow-down cannot
accumulate; if it passes, replace the constant lead and tighten `ramp_proof.py`'s L3 to SR-7's
19.14 ms; score RK3 against SR-7's own ceiling and at least one held-out shape under a SHA-pinned
rule; and fix #335's zero-padding artifact in the instrument as a new rule.

### The diagnostic (render-only, before any code)

The designer measured first: a scratch probe of SR-13's `renderTimePitch` loop (the same
`TimePitchFeeder`, `RampSourceReader`, preroll and discard) compiled from b4b63c9's `app/Sources`
through `swift_build.build` with `-O`, logging each 256-frame block's output, input pulled and
rate commanded, with options for a closed loop and an additive source warp; scored by
`ramp_spike.locate_scaled` with SR-7's reach and edge rules (keep pitch: the unscaled template),
`ramp_spike.dropouts` and `render_spike.pitch_track`, imported unchanged, on SR1's clicks and sine
fixtures, maps with a breakpoint every 600 ticks from 0. Host Mac14,6 on AC, load 21–54, so no
render timing is claimed. Not run under a SHA-pinned rule. The sources are in
`~/.claude/litecode/framejob/speed-ramps-sr1e/diag/` (`main.swift`, `build.py`, `run.py`,
`look.py`, `dlag.py`, `tail.py`, `series.py`, `grid.py`, `ilc.py`); their `H` names that session's
scratchpad, where the outputs went. Nothing in the worktree was edited and no earlier spike's work
folder was touched.

**The replica is exact.** At 56 ms: RK1 71/71 max 8.06 ms, RK2 23/23 5.55 ms, RK3 35/35
22.10 ms — SR1d's measured run to the hundredth. (The app's L rows read a little apart, RK1 8.55
and RK3 21.47 ms, the core's map having breakpoints at the piece edges.)

**What the unit consumes.** At a constant rate it pulls exactly r × 256 frames a block, and the
look-ahead fed − p(output) holds constant, the same on either fixture:

| r | 0.25 | 0.5 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|
| fed − p (frames) | 3 264 | 3 456 | 3 840 | 5 632 | 7 424 | 9 216 |

— A(r) = 3 072 + 768·r for r ≤ 1, 2 048 + 1 792·r for r ≥ 1. While the rate moves it pulls on its
own: RK3 at lead 0, commanded r(n) exactly, climbs from 5 632 to 6 718 frames (+1 086 beyond the
command, in lumps). And what it pulls depends on the content: the same map and commands pull
apart on the clicks and the sine from block 196 (RK3) and 216 (the dip H2), by 512 and 768
frames at the end.

**Consumed input does not pin the output** (the held ×1 tail, the clicks):

| case | fed − p in the tail | tail placement |
|---|---|---|
| X1 (constant) | 3 840 | 0.00 ms |
| H2 dip at lead 56 | 4 896 (+1 056) | 0.00 ms |
| H2 dip, loop holding fed at p + A(r) | 3 837 (−3) | +20 ms (17–23) |

RK3's ×0.5 tails follow no one curve: lead 0 excess +3 262 at −41 ms; the loop 0 at −5 to −8 ms;
lead 56 −759 at +20 ms; the ×0.5 control 0 at −12 ms. The content position is not a function of
(rate, consumed input): it carries the path.

**The controller, measured.** Target fed(m) = p(m + tl) + A(r(m + tl)); cmd = ff + (need −
ff)·256/horizon, bounded to ±bound × ff, ff = r(n + lead); swept horizon 5, 10, 20, 40, 80,
320 ms, bound 0.1, 0.25, 0.5, ff lead 0, 28, 56 ms, tl 0, 28, 56 ms. The best rows (max |diff|
ms):

| config | RK1 | RK2 | RK3 | H1 | H2 | H4 | H5 |
|---|---|---|---|---|---|---|---|
| L = 56 (product) | 8.06 | 5.55 | 22.10 | 20.56 | 2.08 | 14.14 | 27.54 |
| loop h 20, b 0.25, ff 28 | 16.02 | 14.06 | 18.54 | 27.66 | 33.44 | 35.48 | 26.62 |
| loop h 40, b 0.1, ff 0 | 14.86 | 14.61 | 20.05 (34/35) | 26.68 | 55.96 | 24.99 | 25.68 |
| loop h 5.3 (deadbeat), b 0.5, ff 0 | 16.86 | 14.19 | 20.08 | 27.66 | 55.23 | 33.96 | 26.16 |

The loop fixes the ×2 → ×0.5 tails (RK3, H7, H8 within 0–2 ms of target) and costs everything
else; every loop row drives the command to its bound, 10–25 % around the map's rate; tl > 0 makes
every row worse (RK1 29–41 ms, RK2 42–60 ms). **An oracle loop does not converge** either (the
true click error fed back as r·e·48 source frames, at 56 ms): RK1 8.06 → 5.44 → 18.31 → 21.97;
RK3 22.10 → 19.06 → 17.86 → 21.90; H5 27.54 → 27.67 → 27.67 → 27.67.

**The constant lead re-swept over held-out shapes** (none ever fitted): H1 ×0.5 → ×3 ease-out
1–3 s (6 s); H2 ×1 → ×0.25 → ×1 ease in-out over 1–2 and 3–4 s (8 s); H3 ×4 → ×1 linear 1–3 s;
H4 ×0.5 → ×2 ease in-out 1–2 s (6 s); H5 ×3 → ×0.5 linear 1–1.5 s; H6 ×1.2 → ×0.3 → ×1.2 as H2;
H7 ×2 → ×0.5 linear 1–3 s; H8 ×2 → ×0.5 ease-out 1–3 s (8 s unless noted). Ceilings by SR-7 from
the replica's constant renders (x0.25 32.56, x0.3 37.84, x0.5 14.14, x1 0.00, x1.2 6.41, x2 12.60,
x3 24.91 (90/90), x4 21.00 (92/95)): RK3, H4, H7, H8 19.14 ms; H1, H5 29.91; H2 37.56; H3 26.00
with a found floor of 0.87; H6 42.84.

| lead ms | RK1 | RK2 | RK3 | H1 | H2 | H3 | H4 | H5 | H6 | H7 | H8 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 44 | 13.54 | 15.68 | 18.24 | 27.66 (67/69) | 32.90 | 20.81 (69/70) | 14.14 | 25.34 | 23.62 | 18.64 | 16.85 |
| 46 | 11.99 | 11.19 | 11.38 | 25.85 | 29.78 | 20.89 (69/70) | 14.14 | 24.71 | 23.34 | 12.53 | 13.97 |
| 48 | 11.47 | 10.73 | 11.38 | 14.14 | 21.31 (31/32) | 20.99 (68/70) | 14.14 | 24.71 | 12.79 | 12.40 | 14.33 |
| **50** | 11.03 | 10.53 | **11.38** | 26.58 | 18.42 | 20.99 (69/70) | 14.14 | 24.71 | 12.00 | 12.26 | 12.97 |
| 52 | 9.66 | 10.29 | 11.38 (34/35) | 17.35 | 11.24 | 20.69 (69/70) | 14.14 (48/49) | 24.71 | 6.69 | 13.79 | 14.75 |
| 53 | 9.97 | 7.34 | 15.01 | 20.83 | 9.32 | 20.57 (42/70 ✗) | 14.14 | 27.67 (35/36) | 6.37 | 14.30 | 14.09 |
| 56 (product) | 8.06 | 5.55 | 22.10 ✗ | 20.56 | 2.08 | 20.89 (44/70 ✗) | 14.14 (48/49) | 27.54 | 11.24 | 22.47 (34/35) ✗ | 23.90 ✗ |
| 60 | 8.86 | 2.92 | 36.60 ✗ | — | 13.45 | — | 14.14 | 27.67 | 18.97 | 33.81 ✗ | 33.94 ✗ |

SR-14's sweep rule over RK1–RK3 together (2 ms grid, every click found, minimax, a tie to the
smaller lead) picks **50 ms** (2 400 frames), minimax 11.38 ms, every held-out shape under its
ceiling; RK3 is flat at 11.38 over 46–52 ms and meets a cliff at 53 (15.01, 22.10 at 56, 36.60 at
60). Pitch and dropouts on the sine at 50 ms: RK1, RK2, RK3, H2, H7 no dropout, PR medians within
0.01 cents (max |cents| 7.54, 8.68, 21.93, 43.40, 26.55); H5 one dropout with a 150.22-cent
window, the unit's own at a 0.5 s ×3 → ×0.5 slow-down (H5) — at 56 ms it shows the same (1 dropout at
1.452 s, 150.93 cents), and H7 at 56 ms one dropout where 50 ms shows none.

The designer stopped for the owner with three options: A, re-fit the lead to 50 ms under a new
pinned rule (recommended); B, keep 56 ms and close SR1e as measured; C, a closed loop on another
signal (not recommended, the oracle loop not converging).

### The owner's answer

**2026-10-23, AskUserQuestion on the diagnostic's STOP:** "Keep 56 ms, close SR1e": SR-13's
shipped 56 ms lead stays (`rateLeadFrames` unchanged, render version unchanged, product code
unchanged); SR1e closes as measured. A new §11 entry records the diagnostic and the owner's
choice, and SR-15's risk line is widened by an Amended-by line to what SR1e measured at 56 ms;
#335's instrument fix lands as a new rule (trim, not zero-pad) with a selftest row and a mutant;
`coarse_ms`'s duplication checked; the record and the README rows; the designer decides whether
`ramp_proof.py` gains a row for one of the widened cases.

### Decided, then built

SR-16 (the close, the diagnostic, the re-fit not taken, no new L row) with SR-15's *Amended by
SR-16* line, and SR-17 (the trim rule) with SR-7's PT1 *Amended by SR-17* line, were written into
§11 before the instrument code; the index rows and Lines cells; `spec_index_proof.py` 183/183.
SR-14's and SR-15's texts are untouched. **No new L row** (SR-16): H7 and H8 are the same deep
×2 → ×0.5 slow-down L3 pins and cross the same cliff with it (53 → 60 ms: RK3 15.01 → 36.60, H7
14.30 → 33.81, H8 14.09 → 33.94); H3's 44/70 is below any found floor an L row can hold. Then:

- `render_spike.py`: `trim_shift` (the corrected samples and where they start), `corrected_signal`
  (`(samples, rate, window)`, None at k = 0), `place_corrected`, `place_ideal(…, window=)` (a click
  outside the window less EDGE_SKIP_S unobserved: None in `times`, out of `of`, counted in
  `unobserved`; the reach from the full list); `signals_of` and `side_rules` carry the window
  (the dense scan and SR-5's dropouts over the trimmed span, event times + lo); PT1 places
  RC-off-x1's tap through `place_corrected`; selftest S22; the mutants `trim-off` and
  `window-off`. With no window every result is as before; `shift_signal` stays for S10 and
  `ramp_proof.py`'s `placement()`.
- `ramp_proof.py`: P1's two corrected taps (the control's, RV1's) through
  `rsp.place_corrected`; its docstring's L3 and P1 lines.
- `RampAudioRenderer+TimePitch.swift`: `rateLeadFrames`'s doc comment names SR-16 in place of
  "until SR1e" — a comment only, so no byte-identity run is owed.
- `ramp_spike/README.md`'s SR1e section; `tools/proof/README.md`'s SR1d section a line.

**`coarse_ms` is already shared:** `ramp_proof.py`'s P1 calls `rsp.coarse_ms`, and the only
`def` is `render_spike.py`'s. SR1d's owed item needs nothing more.

### Measured

`render_spike.py --selftest` S8–S22 **15/15**. S22 at m1 −86.333 ms (k −4 144): trimmed 59/59,
1 unobserved, max |diff| 0.000 ms, 0 dropouts, agreement 59 pairs at −0.000 ms spread 0.000;
padded, 2 dropouts at 0.05 and 0.069 s. At +86.333 ms (k 4 144): trimmed 59/59, 1 unobserved, max
|diff| 0.000 ms, 0 dropouts, agreement ok; padded, 1 dropout at 5.9136 s. `--mutant trim-off`
caught (exit 1: 59/60, 0 unobserved, 2 and 1 dropouts); `--mutant window-off` caught (exit 1:
59/60, 0 unobserved). `ramp_proof.py` compiles; Debug `--only P1` 3/3 in 73 s (this session's m1
−21.000 ms, coarse −1 008 samples; RV1's trimmed tap 70/70 at +0.000 ms, spread 0.001,
`varispeed_pass`; agreement 70 pairs; 0 wrong frames). No measured spike run: nothing in
`tools/proof/work/ramp-render-spike*` was written.
`make gate` **PASS** in 231 s (names 1 s, typecheck 5 s with exactly the 4 baseline warnings, fmt
and lint skipped as unchanged, test 119 s, app 106 s).
`env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py`: **18/18 in
71 s**, exit 0 — D1–D5; X0; E1 70/70 at +0.000 ms (spread 0.001), one `2-<16 hex>.caf`; E2 no
click, no dropout; N1; K1 inside 5.34 cents, outside 0.01; L1 71/71 max 8.55 ms, L2 23/23 max
5.54, L3 35/35 max 21.47 (as SR1d's); R1 70/70 at −0.010 ms; W1 2.3 s; U1 every plan, md5 and
audio stream as the baseline's (the constants unchanged); P1 m1 −21.000 ms (coarse −1 008
samples), RV1's trimmed tap 70/70 at +0.000 ms, `varispeed_pass`, agreement 70 pairs; D0 no
`Frame Job: ` in the log. Every instance was the proof's own and stopped itself. This session's
tap offset was −21 ms, inside the 50 ms edge, so the Release run does not reproduce the
−86.333 ms case; S22 does.

**Owed.** `app/CLAUDE.md` line 1181, `RampAudioRenderer+TimePitch.swift`'s row: "SR1e's to
tighten" becomes "kept by SR-16" (agents edit no `CLAUDE.md`). #335 gains "the instruments trim,
SR-17" (the orchestrator's, after the commit).
