# Spec §11 — decisions: Audio, the live meter onward (road map "audio")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the AU- series of [`audio.md`](audio.md), so a citation never has to say which
file; that file names the condensed record and the original. This file holds AU-70…AU-109. AU-110 on are in [`audio-4.md`](audio-4.md).
It is new because `audio.md` had passed the spec's ~500-line split rule (#424, 2026-11-09); the
entries moved here unchanged, each phase's opening paragraph with its decisions.

AU-70…AU-78 are AP7's (live loudness and true-peak metering; survey A8), recorded before its
code.

- **AU-70 — The meter reads the TRUE mix, rebuilt from the taps off the audio thread.** Each tap,
  after its chain, copies its block (pre-envelope) and first frame
  (`round(time.value·rate/time.timescale)`; a buffer whose time is not numeric, the player's
  silent pre-roll, is skipped) into its sink's `MixRing`, a single-producer ring that takes no
  lock and allocates nothing. The consumer runs on the meter's existing 30 Hz main-thread timer
  (no new `DispatchQueue` seam): it drains every ring, sums by frame index each track ×
  `MediaPeaks.envelope(ramps, at: frame·600000/rate)` — a mono track at unity in both channels, a
  track's first two channels only — and feeds the stereo sum to a `LoudnessMeter` at the taps'
  rate. Frame f is summed once every track has delivered past it, except a track not sounding at
  f (f's tick outside every one of its own `sounding` spans — a gap between clips as well as past
  the last span; #65: the tap delivers nothing there) or more than `stallLag` (0.5 s) behind the
  leading track; such a track is silence at f and is not waited on, and a frame it does deliver
  after the sum has passed it is dropped. Frames a track delivers are summed as delivered. When
  no track sounds at the reached frame the sum fills silence up to what has been delivered, and
  with nothing delivered past it, it waits; that fill is never a `jump`, so a gap on one track or
  on every track neither holds the sum up nor resets it, and a seek across a stretch where
  nothing sounds is read as playing through it (its silence is below the absolute gate and does
  not move I). Tracks reporting different rates are not measured. AVFoundation's ≤ 25 ms slew at
  a volume step is not modelled (S3: ≤ 0.0067 LU).
- **AU-71 — What it shows: momentary, short-term, integrated and the true-peak maximum.**
  Momentary is the last completed 400 ms block, short-term the last 3 s (thirty 100 ms
  sub-blocks), integrated BS.1770-4's two gates over everything measured since the last reset,
  and the true peak the maximum since the reset (Annex 2 at 4×, which S1 found over-reads speech
  by 0.14 dB). All four are `Loudness.swift`'s `LoudnessMeter`, made rate-generic by `KWeighting`
  (moved into `Loudness.swift`): Tables 1–2 exactly at 48 kHz, libebur128's derivation at any
  other rate in 8–192 kHz, the Annex 2 FIR at 4× the taps' rate. The export's 48 kHz arithmetic
  is unchanged.
- **AU-72 — It measures only at ×1, and says when it resets.** At any other rate the chunks are
  discarded, M and S read "—", and I and TP hold. It resets on the panel's Reset and
  `loudness_meter {reset}` (`manual`); on its own when a chunk starts more than `behindTolerance`
  (1.0 s) before the frame the sum reached, or more than `aheadTolerance` (0.1 s) after it with
  some track sounding somewhere in between (`jump`: a seek, a loop's wrap, a play from elsewhere);
  and on a ring overrun (`overrun`). The rule is asked only of a chunk that MOVES its track —
  continues (within the same tolerances) neither what the track delivered last nor what it
  delivered to the measurement — once the chunks before it are summed. Measured in the player:
  after a seek or a play from elsewhere each track first hands over a buffer or two of the old
  position, not in step across tracks, so on a jump each track keeps what follows its own last
  move, and a track that has not moved yet drops what continues its old stream until it moves (for
  at most `stallLag` of frames); a move with no measurement running starts the measurement there
  the same way, uncounted. A chunk within the tolerances continues the measurement with frames
  before the reached frame dropped, so pause and continue and an edit's rebuild (new sinks, the
  restore seek landing behind) neither reset nor count a frame twice. A change of the taps' rate
  restarts the measurement as a `jump`. **A stop** (rate 0, `stopMetering` → `stop()`) drains and
  drops what is still in the rings or pending, never summed; what the sum already reached stays
  measured, and since the player renders ahead of the playhead that can be audio the stop left
  unheard (0.38 s in L1's run). M, S, I and TP hold their last ×1 values, `measuring` goes false
  and the panel is told. "—" for M and S is only while playing at another rate. The meter timer
  runs in the run loop's `.common` modes, so menu tracking and live resize drain the rings and do
  not overrun them. A new window starts empty.
- **AU-73 — Pre-master.** The preview has no master stage (S3; the master limiter AP2's second part
  adds is the export's alone, AU-22), so the meter reads the mix as the preview plays it — each
  clip's own chain, its clip limiter (AU-20) included, since the capture follows the chain — before
  the export's loudness setting, and the panel's footer says so. Running a master chain on the
  rebuilt sum is a later phase's decision.
- **AU-74 — The timeline bar's bars read the mix.** While the consumer is measuring (it summed
  frames within `liveWindow`, 0.15 s), `Playback.meterReading()` answers the mix's sample peak
  and RMS per channel over its last 100 ms; otherwise `LevelMeterTrack.mix` as before (#65
  intact). This removes S3's up-to-3.85 dB over-read at ×1. The view's ballistics and
  `LevelMeter.shared`'s claim rule are unchanged.
- **AU-75 — Where it shows: View ▸ Loudness Meter.** ⌃⌘L, a checkmark, always enabled, after
  Scopes: a 132 pt column at the preview pane's right edge, left of Scopes, full height, zero wide
  and hidden when off (its width constraint at priority 999, as Scopes'). Per window; nothing
  persists (GR-5's rule): no `UserDefaults` key.
- **AU-76 — The column.** A 1 pt `DS.border` leading edge on `DS.chromeBackground`. Header:
  "Loudness" (`DS.sans(11, .semibold)`, `DS.textStrong`) and a `GhostButton`
  (`arrow.counterclockwise`, tooltip "Reset", action `resetLoudnessMeter:`). Body: a −48…0 LUFS
  scale, linear, ticks every 6 LU labelled in `DS.mono(9)` `DS.textFaint`; two bars, M and S,
  `DS.meterFill` on `DS.meterTrough`; the target as a 1 pt `DS.accent` line at
  `NormalizeChoice.targetLUFS` (read at draw; −16 by default, AU-4, AU-15). Readouts: Momentary,
  Short-term, Integrated and True peak max in `DS.sans(10)` `DS.textMuted`, values in
  `DS.mono(11)` `DS.textStrong`, one decimal, U+2212, "LUFS"/"dBTP", "—" when there is none and
  "−∞" for digital silence; the true peak in `DS.meterClip` above −1 dBTP. Footer, `DS.sans(10)`
  `DS.textFaint`, wrapping: "The mix as the preview plays it, before the export's loudness
  setting." (at ×1, paused or stopped) or, while playing at another rate, "Measured only at
  normal speed." No animation: it redraws when the reading changes. Accessibility ids
  `loudness.panel|momentary|short|integrated|truepeak|reset`.
- **AU-77 — MCP: the dev tool `loudness_meter` only.** Reading the meter needs a playing preview,
  which only the dev tool `play_preview` starts; an agent's loudness answers are the export's
  report and AP1's per-clip readout. `loudness_meter {project?, reset?}` answers `{measuring,
  rate, momentary_lufs, short_term_lufs, integrated_lufs, true_peak_dbtp, from_frame, to_frame,
  sample_rate, resets, last_reset}`. The View item and Reset are view state, unmirrored (§7.9's
  Preview Quality exemption).
- **AU-78 — The proof.** `audio_ap7_proof.py`: the probe's rows T1–T16 (EBU Tech 3341 cases 1–5, 9
  and 12, true-peak sines, 44.1 kHz, the mix against a reference sum, continuity, the stall,
  overrun, rate, the bars, gaps) and eleven mutants, each anchoring a distinct branch AU-70, AU-72
  or AU-74 adds (the sum, the continuity rules, the rate gate, the bars), killed by its named row;
  L1–L4 over MCP against an export; SE-30 for what only a person can confirm.

AU-80…AU-84 are AP8's first part, AP8a (the volume line; survey A9), recorded before its code.
AP8 is built in two parts: AP8a draws a clip's gain envelope and edits it through actions; AP8b
(every other audio parameter as action ends) continues at AU-85.

- **AU-80 — The volume line edits through ACTIONS, not keyframes (owner, 2026-10-30, the road
  map's "Asked at AP8", option (a)).** A point on the line is an action's end (`end.audio.volume`);
  a drag writes `set_audio {volume}` or that end; nothing is persisted that actions do not already
  persist. Reason: it keeps spec §2's "Actions, not keyframes", which every phase since has built
  on; it is app-only (no core, FFI, op, tool, format or `UserDefaults` change); and AP8b animates
  every other audio parameter as action ends through the same model. What it costs, accepted
  with it: each point is a span, one action band per point; a point joins the previous one by a
  ramp from it (the clip's start counts as the first); a point cannot go inside an action that
  also animates another property; a point inside an EASED volume action reshapes the ease on both
  sides (AU-83); a point's time moves with its band, not on the line; and an agent makes in two to
  four tool calls (`add_action`, `set_action`, `set_action_end`) what the gesture makes in one
  step. Keyframes (option (b), lifting §2) were declined.
- **AU-81 — What is drawn: what is heard from the clip, within the handle the timeline shows.**
  Every clip with sound — not a nest clip — draws, over its waveform, the gain of the plan audio
  track holding its audio segment, cut to that segment: the plan's ramps, which carry the clip's
  volume and its actions, fades, crossfades, ducks, its track's volume (AU-103) and every
  silencing (clip mute, track mute, a solo elsewhere, `enabled.audio` false: `core/src/audio.rs`'s
  module doc), so a silenced clip's line lies on the floor. A drag edits only the clip's OWN
  volume, relatively (AU-82), so on a silenced clip the line stays on the floor while the readout
  moves. Inside an open nest the timeline reads the scoped handle, whose plan is the nest's own
  mix: the line there leaves out the enclosing nest clip's and tracks' volume, fades, mute and
  solo. The scale is dB, top `20·log10(32)` = +30.103 dB (`AudioNormalize.maxGain`) and bottom
  −60 dB; a gain at or under 0.001 draws at the bottom and one above 32 (a track's volume can carry
  the plan there) at the top. The line's rect is the clip's audio region with its top raised to
  the action lane's bottom where they overlap, inset 1 pt top and bottom; drawn when it is at
  least 12 pt tall and the plan has the clip's segment. A polyline through every ramp's (start,
  from)–(end, to), white 85 %, 1 pt, clipped to the rect; a 5 pt square in the action colour at
  each action end naming `audio.volume` inside the clip, centred on the line — drawing only, not a
  hit target. The envelope is the core's, read through the plan and memoised per handle as the
  speech duck's line is (AU-113); never recomputed in Swift.
- **AU-82 — The drag: vertical, relative, in dB, on the level in force.** A plain press on the
  line selects the clip and edits the level in force at the press: inside an action naming
  `audio.volume`, that action's end; else the latest action ENDED at or before the press naming
  it; else the clip's base `set_audio {volume}`. Each tick the value is
  `clamp(max(v0, 0.001)·10^(Δ/20), 0, 32)` for Δ the dB the pointer moved on the line's scale, and
  0 when the pointer is below the press AND at the rect's bottom (1 pt above it or lower) — the
  "below the press" keeps a press on a floor line (a silenced clip's) from writing 0 without a
  downward move. Beside the pointer, the clip's own resulting value: "+2.5 dB", one decimal,
  "−∞ dB" at 0. One undo step, "Set Volume"; none when nothing moved. Live through the
  document's live edit, so `check_audio`'s 0…32 is met by the clamp before the core sees a value.
- **AU-83 — ⌥-press on the line adds a point, as an action.** At the press's clip time snapped to
  the frame, t (held to the start of the clip's last frame when the snap would reach the clip's end,
  so a press in a last partial frame adds its point there; amended 2026-11-09, #392): inside an action A whose end names ONLY `audio.volume` (no other group, no other
  audio key), A is split at t — A shortened to `t − A.start`, a new action `[t, A.end)` ending at
  A's end volume and carrying A's curve when it is not linear — and the point dragged is A's new
  end, starting at the evaluated volume at t; a press under one frame from A's start beeps (a
  zero-length action is refused, and a live edit swallows refusals). For a linear A the click
  alone leaves what is heard unchanged; for an eased A both halves carry its curve, so the values
  at t and at A's end are kept and the shape between is re-eased on each side. Inside any other
  action or one a trim left running past the clip's end (`add_action` would refuse the split's
  second half), or under one frame after the latest action end at or before t (any kind: actions never
  overlap), a beep and nothing. Otherwise a new action `[prevEnd, t)` (prevEnd that latest end,
  else 0; the core's default curve, linear) ending at the evaluated volume at t, so the click alone
  changes nothing heard. The new id is the base's `next_id`. The click adds the point at once; the
  drag continues as AU-82 on that end; one undo step, "Add Volume Point".
- **AU-84 — The line's hit, the modifiers, the mirror and the proof.** The hit test asks for the
  line after the fade handles, the action band and the two edge grabs, and before the clip body:
  within the line's rect and 3 pt of the line at the pointer's x. A locked track's clip is the
  clip, as before. A press on the line with ⇧ (toggle membership; ⌥⇧ slip) or a double-click
  (rename) goes to the clip's own arm unchanged; only a plain press and one whose modifiers
  include ⌥ but not ⇧ are volume gestures, and ⌥-drag on the body away from the line stays
  Duplicate. The agent's mirror is the ops the gesture sends — `set_audio`, `add_action`,
  `set_action`, `set_action_end` — whose handlers name the volume line; no new tool. The proof is
  `volume_line_proof.py`: probe rows V1–V9 over `app/Sources` (the drawn line against the plan,
  the scale, targets, the drag's arithmetic, points added and split, one undo step, the hit order
  and modifiers, the paint) and thirteen mutants, each killed by its named row; manual check SE-35.

AU-85…AU-89 are AP8's second part, AP8b (every other audio parameter as action ends; survey A9),
recorded before its code. The leveller's target is left out: AP6 part 2, which adds it, has not
landed (`git log` at `e55de46` has no AP6).

- **AU-85 — The plan carries each audio segment's automation.** An audio segment carries
  `automation`, a list of `{at, audio}` points, when its innermost clip (`voice.stages[0]`) has an
  action whose end's `audio` names a tap key — `mono`, `pan`, `compressor`, `noise_reduction`,
  `limiter`, `isolation`, `eq`, `hum`, `channels`, `gate`, `de_esser` (`TAP_KEYS`,
  `core/src/audio_automation.rs`); otherwise the key is absent and the plan is the text it was.
  The points are at the voice's start and end, at each such action's start and end, and on
  `ACTION_SAMPLE` / `MAX_ACTION_SAMPLES`'s grid (1/30 s, the envelope's) inside a non-linear one,
  clipped to the voice, sorted and deduplicated; `at` is project ticks. Each point is
  `evaluate_clip` at `at − origin`, its audio filtered to `TAP_KEYS`. Swift only interpolates,
  linearly between two points: a number when its group is present on both sides, a tick field
  rounded; everything else — presence, a switch, an enum, `bypass` — comes from the left point,
  and so do the four `HELD_AUDIO_NUMBERS` (`eq.high_pass.slope`, `eq.low_pass.slope`,
  `hum.frequency`, `hum.harmonics`), Ints in Swift and switches by AU-86. Not animated, each for
  its reason: volume, mute and the fades (the envelope, `audio.rs`); the duck and the fade shapes
  (read from the base by `audio.rs`); `keep_pitch` (the plan's `pitch`); `voice` (an offline
  render); a nest clip's own keys (a segment names the innermost clip). The leveller's target is
  deferred to AP6 part 2.
- **AU-86 — Evaluation.** The evaluated audio group writes `isolation` even at 0
  (`actions_audio.rs`'s `audio_json`), so an action toward 0.8 ramps from 0 rather than
  switching at its end. The two slopes, the hum's mains and its harmonics are switches: they hold
  their start value until the action's end, in the core (`hold_audio_steps`, after the lerp) and
  in Swift. Every other rule is §5.4's.
- **AU-87 — The tap reads the automation on an absolute sample grid.** For an automated span the
  settings of a run come from the points at the run's ANCHOR: the latest of the 32-frame grid
  boundary at or before the run's first frame, the frame of the point to its left and the span's
  start, all in lookup frames, `round(time·rate) + offset + lead·rate/perSecond`. A run never
  crosses a grid boundary or a point frame, its own or the head's (at `+ headLead`), so the
  settings of a sample do not depend on how the buffers fall: preview and export agree, and a
  render at 512, 4096 or irregular buffers is byte-identical. Pan is computed per sample from the
  two points around the sample's tick (`AudioPanRamp`), isolation's Amount per input frame
  (`AudioIsolationSpan.amounts`). A switch takes effect at its point's frame, with no glide, as at
  a cut (AU-30; S1 measured its splatter at −79 dB). `usesLimiter` and `usesNoiseReduction` are
  true when any point asks, so a limiter switched on at an action's end has its lead for the
  whole track (AU-23). A span with no automation runs today's path unchanged.
- **AU-88 — Wanted renders, what stays on the base, and the EQ slot keyed off.** An isolation
  render and a gate or de-esser level are wanted when the base or any action end asks
  (`AudioDSPParameters.wantsIsolation`, `AudioDynamicsLevels.wanting`), so a clip whose base
  isolation is 0 is requested, loaded and crossfaded by its automation's amounts. A voiced clip
  keeps its base isolation (AU-143), and an action end alone never makes its isolation render
  wanted: its segments play the voice render, made from the base Amount, so only a base Amount
  above 0 wants it (amended 2026-11-09, #397); the limiter keeps its base volume as its divisor (AU-22),
  and the level L keeps the base pan, fold and pick (AU-41). Inside an action the inspector sends
  pan, mono, compressor, noise reduction, limiter, isolation, EQ, hum, channels, gate and
  de-esser to the action's end, and a switch turned off there becomes `off` (CI-14). The duck,
  Keep pitch, the fade shapes, the voice effect and a NEST clip's mono stay with the base. This
  amends CI-3, AU-21, AU-37, AU-46 and AU-50. It extends CI-14: `off` accepts
  `audio.eq.<slot>`, one of the seven slots (`high_pass`, `low_shelf`, `band_1`, `band_2`,
  `band_3`, `high_shelf`, `low_pass`), which stores `null` at that slot of the end's `eq` — the
  only three-part path; any other path of more than two parts keeps the "group.key" sentence, an
  unknown slot is refused naming the seven, and a slot the patch also names is refused in the
  both-sentence. `ReelOp.setActionEnd` lifts an `NSNull` slot inside `audio.eq` into that path.
  Agents use `set_action_end`; there is no new tool, op or format.
  Extended by GR-36: `off` also accepts `video.qualifier.<range>`, a second three-part path.
  `off` naming `audio.eq` beside one of its slots is refused in its own sentence (#398):
  `off names both "audio.eq" and "audio.eq.{slot}": keying the whole EQ off keys every slot
  off, so name one or the other`, `{slot}` the path's third part, in either order.
- **AU-89 — The proof.** `audio_ap8b_proof.py`: probe rows A1–A8 over `app/Sources` (the
  interpolation and its held numbers, an automated EQ and pan block-size invariant, the per-sample
  pan, the track-wide stages from a point, the Amount per frame, the routing, the wanted sets,
  the EQ lift); MCP rows E1–E6 against 24-bit WAV exports (a pan, an EQ gain, a compressor
  threshold, a limiter switched on at an end, isolation's Amount from base 0, an EQ slot keyed
  off), V1 the live meter against the export, U1 one undo step; fourteen mutants, each killed by
  a named row or core test (M14, a voiced clip's end wanting a render, A7's; amended 2026-11-09,
  #397); manual check SE-37.

AP9's decisions, split edits (J- and L-cuts) and a reversible Detach Audio (`archive/audio.md`
AP9, survey A10), recorded before its code.

- **AU-90 — The model is a LINKED PAIR: Detach Audio's two clips name each other in
  `Clip.linked` (format 28), every placement edit keeps both in step in time, trimming the sound
  half's edge alone makes the J- or L-cut, and Attach Audio merges a pair back (owner,
  2026-10-30, the road map's "Asked at AP9", answer (a)).** Each half stays an ordinary clip on
  its own track, so the pair fits spec §2's one kind of track; a sound lead on a track of its own
  cannot collide with "overlap is a transition"; and the plan, playback, export and the overlap
  rule are untouched. Option (b), one clip whose sound overhangs its picture, would have changed
  every one of them. **The half you grab decides, not ⌥**: ⌥-drag on an edge is already Rate
  Stretch (spec §4.4), so a drag on the sound half's edge trims the sound alone, and the owner
  accepted this deviation from the road map's "⌥-drag" wording. `linked` is the partner's id,
  written only when set; a link must be mutual and inside one container (the timeline or one
  nest), and the reader refuses a file with a one-sided link: "clip {a} is linked to clip {b},
  which is not linked back".
- **AU-91 — What follows the link: TIME, not track; one clamp over the pair; a ripple that would
  push a leading sound below 0 refuses; a sound half deleted alone keeps its picture.**
  `move_clip` moves the named clips and their partners by one delta, clamped so no clip of the
  closure starts before 0 (a J-cut picture dragged left stops where its sound reaches 0, so the
  lead is kept), and the track delta is anchored on and applied to the CALLER's clips only — a
  partner keeps its own track, so dragging a sound half to an empty track moves it alone
  vertically and its picture stays. That is what lets the sound of a second consecutive detached
  shot lead into the first without overlapping its neighbour's sound (which the overlap rule
  would turn into a dissolve). `split`, `duplicate`, `nest` and `ripple_delete` (its spans the
  union over the closure) take both halves. A timeline-wide shift (`shift_clips`: the ripples,
  `close_gap`, `insert_time`, `add_transition`'s ripple form) moves every clip on an unlocked
  track at or after the boundary AND each such clip's partner on an unlocked track
  (`edit_time.rs`'s `shifted`), and when a partner would start before 0 the op refuses — "clip
  {s} would start before 0: it leads its linked clip {p} by {lead} ticks" — because a ripple
  closes fully or not at all (`close_gap`'s rule); `insert_time` only moves right and never
  meets it. `delete` takes a picture's sound with it, but a sound half named alone is deleted
  alone and its picture stays silent (its link cleared): Detach Audio then Delete stays the one
  way the app drops a clip's sound. `ripple_delete` of either half removes both, since leaving
  half a pair behind a ripple would leave it out of sync with everything that moved. Locks win
  over links everywhere: a partner on a locked track is not moved, cut, copied or deleted, and
  stays linked.
- **AU-92 — A split pairs its halves.** When both halves of a pair are cut at one time, the two
  second halves name each other and the originals keep their link. When only one is cut (the
  time falls outside the other, as in a J- or L-cut), the uncut partner stays linked to the half
  sharing the longer stretch of time with it, the first on a tie, and the other half is unlinked.
- **AU-93 — Edges: a trim or roll carries to the partner whose same edge coincides, unless
  `alone`.** `trim_start` and `trim_end` without `alone`, on a linked clip whose unlocked
  partner's same edge equals this clip's edge before the edit, apply the same `to` to the
  partner after this clip, each through its own clamps; a refusal from either is the answer.
  `roll` without `alone` also rolls the partner to the same `to` when its start equals this
  clip's and it has a hard-cut predecessor. Otherwise the clip moves alone. `alone` (default
  false) is the J/L-cut: the timeline's trim and roll gestures send it when the clip grabbed is
  a linked SOUND half (linked, picture off), and W and E do the same, so dragging the sound's
  front edge earlier makes a J-cut and its back edge later an L-cut, while dragging the
  picture's edge trims both. A picture-alone gesture is out of scope; an agent sends `alone`.
- **AU-94 — Slip slips both halves; speed and direction are refused on a linked pair.** `slip`
  on a linked clip with an unlocked partner slips both by the smaller in magnitude of the two
  clamped amounts, so the sound stays on its picture. `set_speed`, `rate_stretch`,
  `set_reversed`, `add_speed_ramp`, `set_action`, `set_action_end` and `remove_action` are
  refused when they would change a linked clip's speed, its direction or its speed-naming
  actions (start, duration, curve, `end.speed`): "clip {c} is linked to clip {p}: Attach Audio
  before changing its speed or direction". Re-timing both halves identically is a second
  implementation of every rate op; Attach Audio, then the change, then Detach Audio is the way.
- **AU-95 — Attach Audio (`attach_audio {clip}`, Clip ▸ Attach Audio) merges a linked pair back
  into one clip.** Either half may be named. Refused, each in its own sentence: "clip {c} is not
  linked to a detached sound"; "clips {a} and {b} are not a picture and its detached sound" (the
  sound is the half with its audio on, the picture the half with it off); and "clip {v}'s picture
  and clip {s}'s sound do not cover the same time; trim them to match before Attach Audio" when
  their start, duration, source, speed or actions' spans and curves differ. Otherwise the
  picture's audio is switched on and takes the sound clip's `audio` group, and each of its
  actions' `end.audio` the sound's action at the same index (removed where that one has none);
  its link is cleared and the sound clip is removed. The sound's track stays, as after any
  delete. One undo step.
- **AU-96 — Links settle in one place; copies re-pair.** `Project::finish` clears, before its
  identity comparison, every `linked` whose clip is absent from its container or does not name
  this clip back (`settle_links`), so an op that removes, moves into a nest or replaces half a
  pair (`delete`, `overwrite_clip`, `remove_track`, `add_blurred_background`'s copy, a split's
  other half) needs no code of its own and never writes a one-sided link. `duplicate`, `paste`
  (the timeline and each copied nest) and `unnest` map each copied link through their old → new
  ids, and a link whose partner was not copied is cleared. Copy puts the partner of each selected
  PICTURE half in the payload, so a pasted detached clip arrives as a pair; a selected sound half
  is copied alone.
- **AU-97 — The chrome: a link glyph, an echo, and Clip ▸ Attach Audio (⇧⌥⌘D).** A linked clip's
  name strip shows the SF Symbol `link` after its kind symbol; each selected clip's partner is
  drawn with a dashed accent ring, so a selection shows what the core will move with it (the
  selection itself stays what was clicked). Attach Audio sits after Detach Audio in the Clip menu
  on ⇧⌥⌘D (Detach Audio's ⌥⌘D plus ⇧), and as a button beside Detach Audio in the Sound tab's
  Mix section; it sends one `attach_audio` per pair in the selection.

AU-100…AU-106 are AP10's (tracks, buses and stems; survey A12, A11), recorded before its code.
AP10 is built in two parts: part 1 is a track's volume and pan; part 2 (per-track sub-mixes, track
and bus dynamics, the master chain, stems) continues at AU-107 once AP2 part 2's float write pass
has landed.

- **AU-100 — The preview stays approximate for track dynamics, and says so (owner, 2026-10-30,
  answer 1 (b)).** Linear track stages — the fader, the pan, later a track EQ — are exact per
  composition track in the preview and the export alike. Track and bus dynamics run per
  composition track in the preview, where S3 measured the difference: a limiter's ceiling
  +0.85 dB over through a crossfade, a nest bus +1.4–1.8 dB; the preview has no master chain; the
  guide and the meter say where preview and export differ. The export is exact through per-track
  sub-mixes (S3: −147.7 dB against the reference). Reason: an exact preview — S3's
  `AVAudioEngine` route, 0.02 ppm of drift, 60–150 ms to start — means rewriting the transport
  (Playback's audio, AP7's meter feed, AP13's scrub, picture-to-audio sync), so it is a road-map
  candidate issue, not part of AP10.
- **AU-101 — Stems are separate files (owner, 2026-10-30, answer 2 (a)).** One file per track, or
  per chosen set of tracks, written by one export job. Reason: every NLE and DAW reads separate
  files, where many apps import only a multitrack movie's first audio track. Stems are part 2's.
- **AU-102 — `tracks[].volume` and `tracks[].pan`, format 35.** `volume` is linear, 0…4 (+12.04 dB,
  `TRACK_VOLUME_MAX`), default 1, written only when not 1; `pan` is −1…1, default 0, written only
  when not 0 — after `matte`, on the timeline's tracks and a nest's alike, so every other project
  writes the text it did and there is no migration step. `set_track` takes both and refuses
  outside the range in `in_range`'s sentence (`volume must be between 0 and 4, not 5`, `pan must be
  between -1 and 1, not 2`); a hand-written value outside is clamped where it plays. `nest` copies
  volume and pan from every source track EXCEPT the nest clip's destination (`front_track`),
  whose copy is unity and centre: the destination track still applies over the nest clip, so a
  selection taken off one track sounds the same nested. (Mute is copied from every track, the
  destination's too, because muting twice is muting once; a fader applied twice is not.) A
  selection's clips from the OTHER source tracks then also get the destination track's volume and
  pan on top of their own, as they already get its mute. `unnest` keeps neither on the way out,
  as it keeps no mute: the clips land on the timeline's own tracks.
- **AU-103 — Volume is an envelope term after mute, at every stage.** It multiplies each stage's
  gain in `audio.rs` exactly where the track's mute zeroes it — the stage per track, the container
  per depth — so a nested clip's sound is scaled by its own track's volume and by every enclosing
  nest clip's track's. Solo and mute precedence are unchanged. Being in the envelope, the live
  meter, the timeline bar's bars and Remove Silences hear it; Normalize, the Loudness read-out and
  the clip limiter do not (they read the clip, AU-11, AU-22), so a track at ×4 can take a limited
  clip past its ceiling.
- **AU-104 — Pan is a balance by `AudioPanLaw`, after an enclosing nest's fold and before the clip
  limiter.** Each audio segment of the plan carries `track_pans`: the pans of the tracks its voice
  passes through, innermost first, clamped to ±1, zeros dropped, the key absent when none remain.
  A stage whose nest clip's base `audio.mono` is true clears the pans collected inside it, since
  that fold flattens them. The tap applies the product of the pans' constant-power pairs to
  channels 0 and 1 after the clip's own pan and an enclosing nest's fold, and before the limiter;
  it is skipped at unity, so an untouched project's samples stay bit-identical, and a segment with
  `track_pans` gets a tap even when no clip asks for DSP. A track pan has no effect on a mono
  source (its composition track has one channel, as a clip pan has none). A nest CLIP's own pan
  still reaches nothing; only track pans travel, through the plan.
- **AU-105 — The chrome.** A fifth header switch, `slider.horizontal.3` (fallback "V"), lit when
  a track's volume is not 1 or its pan not 0, opens a popover on the track: Volume in dB, −60…+12
  (the floor reads "Off" and writes 0; quick picks −12, −6, −3, 0, 3, 6) and Pan −100…100 (quick
  picks −100, −50, 0, 50, 100, writing `pan / 100`), each a slider and a field, and Reset. A drag
  is one undo step ("Track Volume", "Track Pan"); a field commit is one, and Reset is "Reset Track
  Mix". Track ▸ Volume and Pan… (no key) and the header's context menu open the same popover on
  the current track. Agents use `set_track {volume, pan}`: no new op, tool or FFI export.
- **AU-106 — The proof.** `audio_ap10_proof.py`: export rows F1–F5 (fader arithmetic: track,
  track × clip, inner × outer through a nest, the nest's unchanged level, a muted track at ×4),
  P1–P5 (pan: the law, inner × outer, a folded nest, a mono source, clip × track), U1 (one undo
  step, the read-back, no keys at defaults), V1 (the live meter against the export), and probe rows
  B1–B4 (the balance, the chain order, `isInert`, `TrackMixLevel`); ten mutants, each killed by a
  named row or `core/tests/track_mix.rs`; manual check SE-33 for the popover's feel.

AU-107…AU-109 are AP10 part 2a's (stems; survey A11), recorded before its code. Part 2 is built
in two: 2a labels the plan and writes stems; 2b (track and bus dynamics, the master chain, the
preview's statement) records its decisions from AU-150.

- **AU-107 — The plan labels its audio tracks.** Each `audio_tracks[]` entry is `{"id", "track",
  "segments", "ramps"}`: `track` (u32) is the id of the `Project::tracks` entry whose walk in
  `assign` placed it, so a nest's contents carry the nest clip's track. Written always; the plan
  is not persisted, so there is no format bump. Swift keeps the map composition track → timeline
  track per build (`BuiltComposition.audioOwners`), the family split by source format included:
  a composition track never carries two top-level timeline tracks (S3 Q1), so a selection by
  timeline track is a selection of whole composition tracks.
- **AU-108 — Stems (AU-101's).** (a) On the three audio rows only (`audio_m4a`, `audio_wav`,
  `audio_aiff`, whose presets list `stems: ["tracks", "names"]`); a movie row refuses (`<id> has
  no stems; stems applies to audio_m4a, audio_wav and audio_aiff`), and a value but the two words
  is refused by name on any row. (b) `tracks`: one stem per heard timeline track; `names`: heard
  tracks whose trimmed names match are one stem, named by the first's spelling as typed (not
  rewritten to NFC), and an unnamed track is its own. Names match when equal once each is
  decomposed (NFD), lowercased and recomposed (NFC) — Unicode-equivalent, ignoring case — so
  spellings APFS stores as one file name (a precomposed and a decomposed é; ǰ and J + combining
  caron) are one name (amended 2026-11-09, #394, the owner choosing the `unicode-normalization`
  crate). Heard = has a plan audio track labelled with it and is not `silenced` (mute, solo)
  among the timeline's tracks; none heard is refused (`stems: no track is heard, so there is no
  stem to write`). Order: timeline order of each stem's first track. (c) A name is the trimmed
  track name, else `Track N` (N = index + 1, the header's label), `/` and `:` replaced by `-`; a
  name equal to an earlier stem's under (b)'s comparison (amended 2026-11-09, #394) gets
  ` (Track N)`, and one still equal to an earlier stem's ` (Track N, 2)`, ` (Track N, 3)` and on,
  the first no earlier stem holds, so no two stems share a file. The settings end with `stems: [{name, tracks}]` only when asked. (d) Files
  `<mix name without extension> - <name>.<mix extension>` beside the mix; an existing file at a
  stem's path is replaced without asking (the save panel asks only about the mix), except that a
  stem path naming one of the project's media files (symlinks resolved, case-insensitive) refuses
  the job before any stem file is touched, with `ExportStemsPipeline.SourceCollision`'s sentence
  (`The stem “<file name>” would replace media this project uses; export under another name.`);
  the guide says both. (e) **Pre-master:** a stem is its tracks' sub-mix exactly as the mix plays
  them (clips, envelope, ducks, track volume and pan, taps), with no loudness gain and no master
  limiter (`ExportAudioMaster(limits: false)`), rounded once at the job's depth and clipped only
  at full scale — so the stems sum to the mix within rounding wherever the master neither gains
  nor limits; the guide says so. (f) One job: the mix, then each stem in order, each from a fresh
  build of the same plan on the export's key (fresh taps, `ExporterLoudness.swift`'s reason)
  reading only its composition tracks, on one serial queue `com.kgalligan.framejob.export.stems`;
  progress is `(finished + current) / (1 + N)` of the write's share; a failure or a cancel leaves
  nothing (the pipeline removes the mix and each stem it finished); the line reads "Exported
  “Mix.wav” and 3 stems."; the `export_status` result lists each stem's `{name, tracks, path}`.
  (g) Not measured: the loudness report is the mix's.
  **Amended by #470** (docs bugs b3): (f)'s "leaves nothing" means nothing the job wrote. A mix the
  job has not yet replaced stays, so the source collision that stops a job before writing leaves
  an existing mix as it was.
  **Amended by #531** (ai-docs b2): the mix and each stem are written to hidden siblings and
  renamed over their paths only when every write has succeeded, the stems first, so a failure or
  a cancel at any point leaves an existing mix and existing stem files as they were.
- **AU-109 — The proof, and part 2b.** Part 2a's proof is `audio_ap10b_proof.py`: S1–S8 (two
  tracks' stems summing to the mix within 2 LSB at 24 bits, `names` grouping, a loudness target
  leaving every stem byte-identical, mute and solo, a real recording's stem against the soloed
  export, a stem's peak above the master's ceiling, the refusals, a source collision), C1 (a
  cancel inside the last stem leaving nothing) and probe rows B1–B2 (the unlimited master, the
  file names, the summary and the collision test); seven mutants, each killed by a named row or
  `core/tests/export_stems.rs`; manual check SE-36. Part 2b (track and bus dynamics exact in the
  export through sub-mixes summed before the master, approximate in the preview and stated, the
  master chain's decision) records its decisions from AU-150, the first block no phase holds
  (AU-110… are AP11's).
