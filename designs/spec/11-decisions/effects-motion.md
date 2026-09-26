# Spec §11 — decisions: Transitions and motion (road map 5)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **R5-1 — Effects are closed vocabularies, never a runtime.** Every
  transition kind and motion preset is an enum variant or a struct the core
  range-checks, the recipe carries, the MCP catalog mirrors and the one
  compositor draws. There is no package format, no user shader, no
  expression language — which is why neither road map 5 phase adds a Metal
  pipeline.
- **R5-2 — A transition's sound is a constant-power crossfade, on by
  default for NEW transitions and absent from old files.** The overlap a
  person adds a transition at is two different moments — a Remove Silences
  cut, a jump between takes — which is uncorrelated material, where
  constant power holds the level and equal gain dips 3 dB. A version-6 file
  has no `audio` key and sounds exactly as it did; every transition the
  core mints from version 7 on says `audio: true, curve: ease_in_out`. One
  constructor, `Transition::minted`, is the only place those two values are
  written.
- **R5-3 — `add_transition` builds the overlap from handles, clamps the
  duration, and never moves a third clip.** A shorter transition is the
  same edit at a size the media allows; a gap closed part-way
  (`close_gap`'s refusal) is a different edit. Not being at a hard cut is a
  wrong ARGUMENT (`Err`), because the op is pointed at one cut by a caller
  who meant that cut — unlike `roll`, which a drag can reach at any edge;
  having no handle is a domain refusal (`Outcome::Refused`, §5.5 — it
  says so in its own sentence since road map 7's D2·3).
  **Amended 2026-09-16, by the user: when there is no handle, OFFER to
  shift.** Two whole files placed back to back — the most common screencast
  cut — have no handle on either side, so the rule above left Clip ▸
  Transition ▸ with nothing to do but refuse. `add_transition` gained
  `ripple`, and the refusal sheet a button that sends it: the incoming clip
  and everything at or after the cut on every unlocked track slide left, the
  timeline gets shorter, and the tracks stay in sync (the user chose
  "everything after", over "the rest of this track" and "just the clip").
  The rule above still holds for the default form, which is still what the
  menu tries first: a third clip moves only when a person has been told it
  will and said yes, or an agent passed `ripple` by name.
- **R5-4 — Motion is a presentation term.** `video.motion` is stored in the
  model and drawn by the recipe, but `evaluate_clip`, `get_project`, the
  inspector's fields and every edit read the clip un-moved. It is the
  second place the recipe draws what the model does not say — the first
  being the forced `normal` blend under a transition (§7.3). It is not an
  animation target: an action cannot animate it, and a file that tries is
  drawn with the base motion.
- **R5-5 — Motion is a pure function of clip time.** No seed, no wall
  clock, no previous frame: `render_frame` at a tick is byte-identical run
  after run, preview and export agree, and two clips with the same preset
  at the same clip time are displaced identically.
- **E2-27 — A zero-duration edge is configured but inactive.** Zero stays
  legal and stored for In and Out, as D7-3 requires. The timeline draws no
  wedge for it. The inspector keeps its kind selected and its actual zero
  duration editable, while its summary and a selection-aware note disclose
  inactivity. Clip ▸ Motion keeps the stored kind checked and annotates its
  title when all or some matching selected edges are inactive. Increasing
  Duration reactivates that same preset; None or Reset removes it. Choosing
  another kind preserves the stored duration, including zero; an absent slot
  still starts at the existing 0.5 s default. This is presentation only:
  the core's render-time motion contract and R5-4/R5-5 do not change.
