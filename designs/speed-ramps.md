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
- **SR2 — the core target and the plan (A–E).** `speed_map.rs`, the door, the evaluator's rate,
  `content_length_in_source` and the plan's segments, format 27, C's refusals, `core/tests/`
  suites (constant clips' plans byte-identical), spec §5.2, §5.4, §6, §7.2, §7.10; the
  `set_action_end` prose and its `audio_left_out` (P's MCP half); the Swift lead rule if SR1 asks
  for it (`CompositionBuilder.swift` is at 581 lines: a pure move first). Its proof,
  `tools/proof/ramp_proof.py`, is #111's: over MCP on Release, an export compared to expectation
  frame for frame (an index fixture) and click for click (keep pitch off), playback against
  export, undo, a constant clip's plan unchanged, and a mutant made to fail on purpose.
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
