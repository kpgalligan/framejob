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
- **E — Audio (SR-3).** Keep pitch off glides (varispeed); on is `spectral` under SY-40's
  measured drift and SY-41. Sample agreement between playback, export and expectation is claimed
  for keep pitch off; keep pitch on is measured against the constant-rate controls.
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
