# Reelcut — road map 2: beyond the spec

**Status: ALL TEN PHASES ARE DONE** — §1's table below carries the commit of
each, which is the one place they live. There is nothing here left to pick up;
what a next road map would be for is in §4, "Considered and left out".
Spec §10's three milestones are done
(`roadmap-1.md` records how each was proved). This is the plan for
what a capable editor still lacks, found by reading the op table, the menus,
the key map and the code against the question "what does a cutter reach for
and not find". It is sized for **several sessions**: ten phases, each one to
two sessions, each closable on its own and each ending in evidence.

Companion relations, unchanged: `reelcut-design.md` stays normative for the
schemas (§5), the op table (§6) and the architecture (§7) — **a phase that
adds an op or a field updates §5.2 / §6 as it lands**, exactly as it updates
`edit.rs`'s module doc, `ReelCore.swift`'s builders and `AgentCatalog.swift`.
Phase 1 found one mirror this list forgot: **spec §7.10's Rust module map**,
which `core/CLAUDE.md` calls "the same list" — so a phase that adds a MODULE
updates it too, not only a phase that adds an op. A phase's record is written
into its section in §2 when its proof exists; the `CLAUDE.md` files carry
rules and maps only, never a status paragraph (2026-09-17).
`roadmap-1.md` is the record of M1–M3 and its "known limits" list
still stands.

## 0. Rules every phase inherits

These are the project's standing rules, restated only where a phase below
leans on them. `CLAUDE.md`, `core/CLAUDE.md` and `app/CLAUDE.md` are the
full text.

- **A new op is a JSON op through `rc_project_apply`.** It touches `edit.rs`
  (the enum, `OP_NAMES`, the module-doc table), a `impl Project` block in a
  module of its own concern, `ReelCore.swift`'s typed builder,
  `AgentCatalog.swift` + a handler with a comment naming the UI path, and
  spec §6. The header changes only when a phase adds an `rc_*` export
  (Phase 7's recipe options and Phase 9's scoped handle are the two).
- **A persisted field bumps `RC_FORMAT_VERSION`** in `format.rs` and the
  header, with a serde default so every earlier file opens, and a
  `schema_vN.rs` test that opens the previous version's fixture. One bump
  per phase that persists something (v3 … v6 below). **A field lands in the
  same phase as the thing that renders it** — a field a file can carry and
  no renderer honours is a lie in the file.
- **Every user-visible edit gets an MCP mirror**, and the startup parity
  check enforces it. A gesture that is only a `move_clip` (nudge) needs
  nothing; a composite the UI offers as one command (blurred background,
  zoom back, normalise clip) gets a tool that performs the same composite.
- **A file at the size cap gives something up BEFORE it takes anything
  on.** Five phases have now paid that rule rather than argued with it:
  phase 0 took `model.rs` from 1329 to 939 (`model_query.rs`), phase 2 to
  462 (`model_props.rs`) and moved `edit_props.rs`'s range checks out
  (`props_check.rs`), phase 3 cut the region vocabulary out when
  `video.obscure` pushed `model_props.rs` to 633 (`model_regions.rs`),
  phase 5 moved the override reading out of `export.rs` — about 120 lines —
  BEFORE adding two rows to it (`export_overrides.rs`), and phase 6 paid
  TWICE: `model_props.rs` gave up the text vocabulary (`model_text.rs`,
  252) and `LayerRenderers.swift` gave up the text machinery
  (`LayerRenderersText.swift`, 577) before either took a new field on.

  **Phase 6 also learned what the rule does not buy.** The cut landed
  `model_props.rs` at 402 exactly as planned, but version 6's two keys cost
  198 lines rather than the ~135 estimated — five types, a constant, and
  the doc density this codebase demands — so it is back at **600, ON the
  line, and takes nothing further without a cut of its own.** An estimate
  of what a field costs here is worth about two thirds of the truth;
  budget the cut against the pessimistic number.

  Over the ~600 cap today, named so a phase picks its cut rather than
  discovering the debt: `edit_clip.rs` 1252 — no new op goes in it —
  `edit.rs` 764, `edit_track.rs` 674, and `recipe.rs`, `model_props.rs` and
  `edit_paste.rs` all exactly at 600. `edit.rs` is the one the cap cannot
  govern: its module doc IS the op table, so it grows a row per op by
  design. **`recipe.rs` is the one phase 7 walks into**, since its "Where"
  names it for the recipe options. The Swift side carries its own, and
  SIX of the eight below grew this phase: `ProjectSnapshot.swift`
  2255 → 2484, `ReelCore.swift` 1945 → 2076, `InspectorPane.swift`
  1582 → 1638, `AgentCatalog.swift` 1414 → 1498, `VideoPane.swift`
  1253 → 1465, `Compositor.swift` 1184 → 1311 and
  `AgentServer+Clips.swift` 1036 → 1183, against `TimelineView.swift` 1540,
  `Transcriber.swift` 934 and `AudioDSP.swift` 890, which did not.
  A phase that adds a property crosses most of that list, which is the
  argument for paying a cut on the way through rather than at the end.
  `core/CLAUDE.md` and `app/CLAUDE.md` hold the running list and name the
  next cuts.
- **Frozen files** (`EditorViewController.swift`, `TimelineView.swift`,
  `PreviewCanvasView.swift`, `AgentServer.swift`,
  `InspectorViewController.swift`) take wiring only; each feature below
  names its extension file.
- **Proof is driving the built binary over MCP** and comparing
  `render_frame` output or measured audio, plus black-box core tests against
  an oracle. Each phase's "Proof" list is its exit criterion.
  **The script goes in `tools/proof/`** as `phase<N>_proof.py`, over the
  dependency-free MCP client phase 1 left there, so a proof can be re-run
  after a later phase rather than believed on the strength of a paragraph.
  A frame claim is a BYTE comparison of two PNGs or it is not a proof; a
  check that would pass against a build where the op did nothing is not one
  either, and phase 1's review found two of those in its own script.
  **The way to know a check can fail is to make it fail.** Phases 3 to 6
  built deliberately broken binaries and ran the script against each —
  seven of them for phase 5, which is how that phase learned its proof had
  to measure the written FILE rather than read the app's own report: a
  build with the loudness gain dropped still echoed −14.0 LUFS over a file
  measuring −6.7, and every report-reading check passed. A proof that has
  never failed is a claim, not a measurement.

  **Phase 6 is the argument for doing it, because two of its seven mutants
  SURVIVED — and both were the checks the phase had specified as the ones
  that would catch exactly those bugs.** A proof reviewed by eight readers,
  passing every check it had, was blind to a double-blending pipeline and to a shadow
  mask taking the wrong pipeline state. One was a hole (an opaque
  destination forces the composite's alpha to 1, so the "partial opacity"
  fixture could not see it); the other was a claim that was simply FALSE
  and had been repeated into three documents. Neither reading nor reviewing
  found them; only breaking the binary did.

  Three practical rules came out of that run, all of them cheap and none of
  them obvious:
  1. **Restart the app between mutants.** The proof drives a RUNNING
     process, so a harness that rebuilds without relaunching scores the
     clean result every time — the first mutant reported 160/160 for a
     build with the feature deleted. A mutation harness that does not
     restart gives a false all-clear on every mutant it runs.
  2. **Check that the mutant mutates.** Two of phase 6's did not, at first,
     and a no-op mutant reads exactly like a weak check — one line sat
     above an early `return` and Metal's default blend factors turned out
     to be the identity.
  3. **A crash is a worse detection than a failure.** One mutant aborted
     the script with a traceback instead of failing a named check, so every
     later section went unrun. Assert the precondition, then act on it.
- **The baseline** is `make test` green, `make lint` clean and
  `make typecheck` at 0 errors / 4 deliberate warnings. A phase leaves it
  there.

**Session protocol.** A session picks one phase (or half of one), reads its
section here and the two side `CLAUDE.md`s, lands the work, runs the proof,
then updates: the status table below and the phase's record in §2 (never a
status paragraph in a `CLAUDE.md`, which hold rules and maps only), the
spec's §5.2 / §6 / §7.10 / §9 for anything they mirror, and the README's
feature bullets. Unfinished halves are written down here under the phase,
not left implicit.

**And then reads the change back adversarially, before committing.** Phase 1
did, and it found five real defects in work that already had 244 green tests
and a 63-check MCP proof behind it — including one that made every overwrite
of an imported still a silent no-op on a 29.97 timeline, and one that had
the bare-⌫ menu item eating Delete out of every text field. The shape that
worked: one reader per dimension (correctness, the core's rules, the app's
rules, the gestures, the MCP mirror, the docs), then every finding put to
sceptics told to refute it, then a regression test for each survivor that
fails without the fix. Green tests prove the cases someone thought of.

Six phases have now run it and it has never come back empty: five real
defects in phase 1, six in phase 2, six in phase 3, twelve in phase 4, ten
in phase 5, and in phase 6 **forty-five survivors out of fifty-two** put up
by eight readers against eight sceptics — the largest yet, on the largest
phase. Two of phase 3's, one of phase 5's and one of phase 6's were blockers
that a hundred green checks had walked past; phase 6's was a PICTURE command
that ducked the whole mix, invisible to every frame comparison including the
one the road map had specified for it.

Three things about the shape were learned rather than designed. **Route a
fix by the file it ROOTS in, not by the dimension that reported it**: phase
3 handed five survivors to fixers who did not own the file and needed a
second round to close them. **Tell the readers what is already known** — the
standing limits, the deliberate decisions, the debts — so their attention
goes to what nobody has looked at rather than to what everyone has. And
phase 6 added the third: **the fixers will move the source of a mirror and
cannot reach the mirrors.** Its fixer changed `edit.rs`'s op table — legally,
inside its own lane — and left `AgentCatalog.swift` advertising the old
scale and `ReelCore.swift` documenting a refusal that no longer existed. A
fix wave needs a lockstep pass after it, by someone who owns all four
copies, and the orchestrator is the only one who does.

## 1. Status

| Phase | Theme | Sessions | Schema | Status |
|---|---|---|---|---|
| 0 | Groundwork | ½ | — | **done** 2026-09-06 (`febb324`) |
| 1 | Cutting moves | 1–2 | — | **done** 2026-09-06 (`febb324`) |
| 2 | Clip identity | 1 | v3 | **done** 2026-09-07 (`ccc5c34`) |
| 3 | The screencast trio | 2 | v4 | **done** 2026-09-07 (`3a64d85`) |
| 4 | Words | 2 | v5 | **done** 2026-09-08 (`17b80ba`) |
| 5 | Sound | 1–2 | — | **done** 2026-09-08 (`4abad43`) |
| 6 | Looks | 1–2 | v6 | **done** 2026-09-08 (`9d02cc6`) |
| 7 | Output | 1–2 | — | **done** 2026-09-09 (`488e55d`) |
| 8 | Viewing and finding | 1 | — | **done** 2026-09-09 (`5083fde`) |
| 9 | Inside the nest | 2 | — | **done** 2026-09-10 (`2373567`) |

Order is by value over dependency. Phases 1–3 pay back first and share
nothing that later phases need; 6 depends on 3's list-interpolation rule; 9
is last because it is the largest and touches every op at once. Any other
order works if that one dependency is kept.

**What phases 0–6 left behind for the rest**, so no later phase
invents a second one:

| | |
|---|---|
| `core/src/model_query.rs` | the three source-window measurements — `source_head`, `content_length`, `source_length` — plus the lookups and `validate`. Any op that clamps against a media clamps against these. |
| `edit_clip.rs::whole_media_length` | how long a clip showing the whole of a media is, snapped. `add_clip`, `insert_clip` and `overwrite_clip` share it. |
| `time.rs::snap_up_to_frame` / `snap_down_to_frame` | directional frame snapping, for a clamp BOUND — which cannot be rounded to the nearest frame without letting a caller past what it protects. |
| `edit_time.rs::ordered_range` / `clear_range` | "put a range in order" and "empty it on every unlocked track", shared by `lift_range` and `ripple_delete_range`. Phase 3's `ripple_delete_ranges` is a loop over the second. |
| `ProjectDocument.targetTrack` | the one rule for "which track does a command with no track argument act on": the first selected clip's, else the front-most. Phase 6's background commands turned out NOT to want it — a backdrop goes on a NEW track at index 0, which is the only place "behind everything" is true whatever the stack holds — so it is still waiting for its second caller. |
| `ProjectDocument.selectedMedia` | the Media tab's selected row, clamped like the other view state. Phase 8's Media-tab work builds on this rather than adding another. |
| `EditorViewController+Edge.swift` | carries an `extension TimelineView` as well as the controller's, which is how a gesture is added without touching the frozen view. Phases 3 and 9 need the same trick. |
| `tools/proof/` | the MCP client, the per-phase proof scripts, and `harness/` — the offscreen chrome renderer, for any claim about what the chrome SHOWS. |
| `ClipLabel.swift` | the marker-colour vocabulary — six names, their order, display names and inks — spelled once. A marker, a label, or anything else that carries a colour NAME reads it. |
| `Project::check_group` (`edit_props.rs`) | the range check for ONE property group of one clip, what a patch and `paste_attributes` both run. A composite that writes a group runs it too. |
| `audio.rs::silenced` | muted, or soloed-out within a container's track set. Any later per-track audio switch joins it rather than adding a second read of `track.muted`. |
| `TimelineView+Rename.swift` | the second `extension TimelineView` precedent (after `+Edge.swift`'s), and the shape for adding an in-place editor to the frozen view: the hook in the frozen file, the field in the extension. |
| `AgentServer+Arguments.stringsArg` | an optional list of strings from a tool call, a lone string counting as one. Phase 4's caption options and phase 7's export options want it. |
| `actions.rs`'s LIST rule | an end patch interpolates a list per index when the lengths match and each pair of entries agrees on its discrete fields, and switches at the end otherwise — the crate's rule, not one list's, and confined to list ENTRIES so no named object's animation changed. Phase 6's filter work is the one that asked for it; anything else that adds an array of objects gets it free. |
| `model_regions.rs` | the ONE region frame — `x`/`y` a CENTRE in source pixels from the cropped rect's centre, `width`/`height` its size — and the one `SpotShape` every region is drawn with. A later region joins these rather than declaring a second frame or a second two-shape enum. |
| `edit_zoom.rs`'s placement equation | the solve from a rectangle in that frame to an action's `scale`/`x`/`y`, rotation and crop included, with the scale clamped before the offsets follow it. Phase 6's `fill_scale` took the clamp-before-the-offsets rule from it; any later "zoom to selection" cites the whole equation rather than re-deriving it. |
| `SilenceDetector.Input.read` | the seam that takes a snapshot, a plan, a selection and the peak files off the document ONCE, after which everything is arithmetic over values — which is what lets a sheet re-detect synchronously and an agent run the same code. Phase 5's meters and phase 8's search want the same shape. |
| `TimelineView+Candidates.swift` | the third `extension TimelineView`, and the precedent for adding a WASH under the clips: a stored property with a `didSet`, two one-line draw calls in the frozen file, the bodies outside it. An overlay view cannot do it — the ruler fills its own bounds opaquely first. |
| `EditorViewController+ZoomRegion.swift` / `CanvasRegionView` | the second modal canvas mode, and the shape of one: an overlay whose PRESENCE is the mode, one-line closures back to the controller, a key that TOGGLES (an overlay that has lost focus cannot be dismissed by Esc), and an auto-close beside `syncChromaEyedropper`. Installed through `armCanvasMode`, which ends every OTHER armed mode first — a third mode inherits that by being installed at all, where each arming path remembering the others was the review's defect. |
| `AgentServer+Arguments.rangesArg` / `nestedNumberArg` | a list of `[from, to]` pairs and a number one level down, each named by its path and each snapped through the same helper the scalar readers use. |
| `CaptionLayout.swift` | cues in, ops out: the frame grid, the abutting trim, the Caption preset and the new front-most track, plus `Problem`'s producer-spelled `tag`. Anything that makes captions — a file, a transcript, phase 8's search-and-caption if it ever exists — ends here rather than laying clips out itself. Its `CaptionCues` neighbour holds the four cue RULES, which only a producer inventing line breaks calls. |
| `recipe.rs`'s `Reveal` | the shape of "a per-frame number the core computes for the platform to draw": derived from the model and a clip time and from nothing else, emitted unconditionally so an absent key never means two things, carried by NAME not by ordinal, and folded into the layer's content hash because Swift's texture cache keys on that hash alone. Any later per-frame value the renderer needs joins this rather than inventing a second channel. |
| `tools/proof/harness/`'s settle capture | the harness writes a PNG only when two consecutive captures are byte-identical. A fixed spin count was a guess about how long the last relayout takes, and this is the answer to the question instead. It is NOT what makes a render reproducible, and phase 4's gate is where that was learned: a settle cannot separate two STABLE layouts, and the bistability under it was an ambiguous constraint in `InspectorPane.swift` (the row below). Both are wanted; only one of them is the determinism. |
| `InspectorPane`'s 249 | a pane's low-priority bottom pin sits ONE below `.defaultLow`, because an `InspectorSection` keeps the default 250 and a TIE let the solver stretch a section instead of moving the pane's bottom — an ambiguity with no wrong answer to report, decided per PROCESS. Any later constraint that competes with a subview's own hugging needs the same one-point gap, and the symptom to recognise is a proof that scores differently on identical input. |
| `MediaPeaks.swift` | the ONE way to ask the waveform cache about a source window: the bucket size, the project→source tick mapping taken from the plan segment's own resolved rate, the floor for the index, and the reversed MIRROR about the media's model duration. `SilenceDetector` and `AudioNormalize` both call it; a third caller joins them rather than copying, which is what the app's two disagreeing project→source conversions are the warning about. |
| `AudioNormalize.swift` | the shape of a UI command whose ARITHMETIC has to be provable: a value type, measurements in and ops out, called identically by a pane button and an MCP tool, with per-job failures reported under `skipped` rather than thrown. `CaptionLayout` is the same shape for captions; phase 7's Save Frame… can be a third. Phase 6's Add Background… was expected to be one and turned out not to need it: the arithmetic went into the CORE as an op (`edit_background.rs`), which is the other answer whenever the derived values are core vocabulary rather than platform measurements. |
| `Loudness.swift` | measurement with NO AVFoundation in it — plain buffers in, a value type out — which is what lets a meter be checked against synthesized tones rather than a fixture file, and what lets the export own the question of where the samples come from. Any later analysis (a phase-8 waveform search, a second loudness scale) belongs on those terms. |
| `LevelMeter.swift` | a raw measurement crossing from a real-time thread, and the ballistics kept OUT of it: the model publishes what was measured, a view owns hold and decay, and a proof asserts on the model. It is also the app's one `import Synchronization` and the argument for when a lock-free publish is the right answer (a render thread that may not lock and may not allocate). |
| `Compositor.metal`'s `blendPremultiplied` | the ONE home of a blend FORMULA — the core says which mode, nothing in it computes a colour. It keeps the destination-ALPHA term rather than assuming an opaque canvas, which is phase 7's ProRes 4444 inheriting a correct formula instead of a wrong one; and the rule beside it is the trap: a programmable-blend pipeline MUST be built with fixed-function blending disabled, Metal builds one either way without complaining, and the double blend is invisible at alpha 1. |
| `MetalRenderer.pipelineState(gather:blend:)` / `maskState` | two INDEPENDENT specializations of one fragment stage, so four layer states and not a hierarchy — and the shadow's mask pass takes the gather one WITHOUT the blend, because a mask asks about the layer's SHAPE, which no blend mode changes. That separation is DEFENSIVE and not load-bearing, which the mutation run established against every document that had said otherwise: a `multiply` over the cleared mask is NOT 0, because the premultiplied composite's `(1 - ab)·src` term reduces the whole formula to `src` at `ab` = 0 for all eight modes. Keep it — it costs nothing, it names what the mask pass means, and a formula without that term would make the hazard real — but do not restate the vanishing shadow as a bug it holds back. A third specialization joins this rather than branching inside the shader; anything else that draws a layer's SHAPE rather than its ink takes `maskState`. |
| `recipe.rs`'s forced `normal` | the precedent for the recipe OVERRIDING a model value rather than only evaluating it, and the two tests it has to pass: everything that draws reads one description, and the rule is provable by a core test reading a layer at a tick. The visible cost is stated where it lands — the inspector shows the model's value while an overlap draws `normal` — because a rule that makes two honest readings disagree has to say so. |
| `edit_clip.rs::fill_scale` | Fit's sibling, and the three differences one sentence explains: Fit is a rescue and Fill is a requirement, so it ignores `canvas.fit_new_clips`, scales UP as readily as down, and clamps to `SCALE_MAX` at the source rather than leaving a caller to. Anything that must leave no canvas showing calls it. |
| `edit_background.rs`'s "what a copy does NOT keep" | the five things a derived clip drops and why each one is a wrong picture or a wrong SOUND if it is carried — the audio switch first, because it is INVISIBLE in a still frame and every frame proof passes with it wrong. Any later op that clones a clip somewhere else starts from that list. |
| `InspectorBinding.editedList` | the list a WRITE of a list-valued key must be built from and measured against: the ACTION's own end list where there is one, the clip's base list otherwise — never the evaluated one every `read:` uses. Two defects came out of the one-line version of this; a third list-valued property joins it rather than reading `videoProps` directly. |
| `AgentServer+Clips.gradientArg` | the shape of a hand-built reader for a nested object in a patch, and what it buys: a misspelt key inside `gradient` is refused BY NAME, which `shadow`, `chroma`, `obscure` and `animation` cannot manage because they go through the generic decoder. A new nested object that matters is worth reading by hand. |

## 2. Phases

### Phase 0 — Groundwork

*Half a session. Makes room; changes no behaviour.*

- **Split `model.rs`.** Move the `// ---- lookups and invariants` section
  (id allocation, `clip`/`track`/`media`/`marker` lookups, `validate`) into
  `core/src/model_query.rs` as `impl Project` blocks, and the
  `// ---- serde defaults` section with it. `model.rs` drops to about 900
  lines of type declarations, which is what it was meant to be, and
  Phases 2, 3, 4 and 6 can add their fields without breaking the
  "take something out first" rule.
  **Landed** as `core/src/model_query.rs` (408 lines: `Project::new`, the
  five id lookups, `allocate_id`, `clips_on`, `clips_on_track`, `duration`,
  `source_length`, `is_missing_media`, `validate` and its nesting walk);
  `model.rs` is 939. **One deviation: the serde defaults stayed.** A
  `#[serde(default = "…")]` function is what an absent key MEANS, which is
  schema, and moving 43 lines would have cost seven fully-qualified
  `crate::model_query::…` paths and put `default_one()` in a module about
  lookups. The size goal was met without them. When the schema does outgrow
  the cap again — Phases 2, 3, 4 and 6 add about 145 lines between them —
  the next cut is the §5.2 property types into a `model_props.rs`, which is
  now written down in `core/CLAUDE.md`.
- **README.** The "Inspector" bullet still describes six pinnable tabs and
  the tool count says 50; the chrome cleanup made it three tabs and the
  catalog is 57. Fix both, and leave the counts in ONE place each so the
  later phases update one line.
  **Landed**: the Inspector bullet and the layout table now say three tabs
  and name the section factories; the tools section names the ops but no
  longer counts them — the count is `rc_op_names`' length and the catalog's,
  which the startup parity check already compares, so a phase that adds an
  op updates no number here. `import_captions`, `consolidate_media` and
  `set_selection` were missing from the app-state table and are in it.
- **Key-map ledger.** Add the proposed keys from §4 of this document to
  spec §9 as a "proposed" block, so a phase that binds a key checks it
  there and promotes the row.
  **Landed**: spec §9 carries a second table, "Proposed, not yet bound",
  with the phase number on every row. No conflict with the bound table was
  found; `,` `.` `Z` and ⌥⌘E / ⇧⌘P / ⇧⌘R / ⌥⌘V / ⌘↓ / ⌘↑ are all free.
- **Decide the `async` allow-list question** for Phase 4 (Speech) now, so
  that session does not open with a rules debate. Recommendation: the
  callback API, no new exception.
  **Decided, as recommended**, and written into spec §11 and `app/CLAUDE.md`
  so it is not reopened: `SFSpeechRecognizer`'s callback API is complete for
  a transcription, so `Transcriber.swift` uses it. `SpeechAnalyzer` is
  `async`-only and would earn the argument again — but only when the
  deployment target moves, and then as one more named file.

**Proof.** `make test`, `make lint`, `make typecheck` at baseline;
`rc_op_names` unchanged; the v2 fixture opens; `git diff --stat` shows
`model.rs` shrinking by what `model_query.rs` gained.

**Proved** on 2026-09-06: `make lint` clean, `make test` 222 passed / 0
failed (the schema-v1 and schema-v2 fixture tests among them), `make
typecheck` 0 errors and the same 4 AVFoundation deprecation warnings.
`edit.rs` was not touched, so `OP_NAMES` is the same 43. `git diff --stat`:
`model.rs` −403, `model_query.rs` +408 (the difference is the new module
doc and its imports).

---

### Phase 1 — Cutting moves

*One to two sessions. No schema change. Six ops, two gestures, three keys.*

The op table has trim, split, ripple and insert-time, and lacks the four
moves a cutter makes between them. All six below are placement ops; none
goes in `edit_clip.rs`.

| Op | Arguments | Semantics |
|---|---|---|
| `slip` | `clip: u32, delta: ticks` | Moves the source window under a fixed clip: `in += delta × speed`, start and duration unchanged. Clamped so `in ≥ 0` and `in + duration × speed ≤ media duration`; a delta the clamps reduce to nothing is `None`. A `still` moves its `at` instead. Any other source is an `Err` (the non-media rule). Actions are clip-relative and do not move. |
| `roll` | `clip: u32, to: ticks` | Moves a hard cut: the clip's start and its predecessor's end both become `to`. The predecessor is the clip on the same track that ends exactly at `clip.start`; with no such clip, or with an overlap (a transition's length is `set_transition_duration`'s job), refuses. Clamps to the predecessor's source tail, this clip's source head, and one frame on each. Front trim semantics for this clip (`in` follows), plain end trim for the predecessor. |
| `lift_range` | `from: ticks, to: ticks` | `ripple_delete_range` without the close: every unlocked clip is split at both bounds and the middles removed; nothing moves, markers stay. A reversed range is the same range. |
| `close_gap` | `track: u32, at: ticks` | The empty span on `track` that contains `at`, bounded by the nearest clip ends on that track. Shifts every unlocked clip on every track whose start ≥ the gap's end left by the gap's length — `ripple_delete`'s shift with the gap as the span, straddlers on other tracks staying put. **Refuses** when a shifted clip would break the overlap rule; deciding in-phase whether to clamp to the largest closable amount instead is allowed, but the rule is to close fully or not at all. No clip after the gap is `None`. |
| `insert_clip` | `track: u32, media: u32, at: ticks` | The insert edit: on `track`, a clip strictly containing `at` is split first; then `insert_time(at, media duration)`; then `add_clip`. One op so it is one undo step and one tool. |
| `overwrite_clip` | `track: u32, media: u32, at: ticks` | The overwrite edit: clears `[at, at + media duration)` **on `track` only** (split at both bounds, remove the middles), then `add_clip`. Other tracks are untouched. |

**Not ops.** *Nudge* is `move_clip` by ±1 frame on `,` / `.`, ±10 with ⇧
(read `charactersIgnoringModifiers`, since ⇧, is `<`); the overlap rule's
refusal beeps. *Select all on track* is view state: ⌥-click a track header,
and Edit ▸ Select All on Track for the selected clip's track.

**Gestures** (session structs in `TimelineSessions.swift`, logic in
`EditorViewController+Edge.swift`): **⌥⇧-drag a clip body = slip** (⌥ alone
duplicates; ⇧ turns the ⌥ gesture into its keep-the-neighbours cousin) with
the filmstrip scrolling under the cursor; **⌥⇧-drag an edge = roll** (⌥
alone rate-stretches), with the neighbour's edge drawn moving too. Both are
one undo step through the live-edit trio. *Lift*: ⌫ with an in/out range and
nothing selected (the ⌘⌫ path in `EditorViewController+Timeline.swift` is
the template). *Close gap*: double-click an empty lane span, and Clip ▸
Close Gap when the playhead is in one. *Insert / overwrite*: Edit ▸ Insert
at Playhead / Overwrite at Playhead for the Media tab's selected item, the
Media list's context menu, and ⌥-drop / ⇧⌥-drop from the list onto a lane
(decide the modifiers in-phase; only ⌥ alone is taken, by duplicate).

**Where.** `core/src/edit_edge.rs` (slip, roll), `edit_time.rs` (lift_range,
close_gap — it is the ripple family's home and has room),
`core/src/edit_insert.rs` (insert_clip, overwrite_clip); `edit.rs`;
`core/tests/edge.rs`, `core/tests/insert.rs`. Swift: `ReelCore.swift`,
`AgentCatalog.swift`, `AgentServer+Clips.swift`, `TimelineSessions.swift`,
`EditorViewController+Edge.swift`, `MediaPane.swift` (menu + drop
modifiers), `AppDelegate.swift`, two `case` lines in the frozen key switch.

**What landed.** All six ops, both gestures, all three keys, and one thing
the plan did not foresee: the Edit-menu pair needs a media SELECTION, which
the app did not have. `ProjectDocument.selectedMedia` is now the fourth
piece of view state beside the playhead, the clip selection and the in/out
range — clamped by `clampViewState` like the others, set by
`MediaRowView.mouseDown`, drawn by the row, and stored on the DOCUMENT
because `MediaPane` is rebuilt whole whenever the media list changes.

Three deviations, all small and all deliberate:

- **`close_gap` and `insert_clip` both refuse on a locked `track`.** The plan
  did not say. For `close_gap`, its own clips are the ones that would not
  move, so closing a gap on a locked track by shifting every OTHER track is
  not what anyone asked for. For `insert_clip`, `insert_time` will not shift
  a locked track at all, so the room the op promises cannot be made there —
  and leaving that to `add_clip` to notice would have refused only where the
  locked track happened to hold something at `at`, and quietly added a clip
  to a locked track everywhere else. `overwrite_clip` deliberately does NOT
  refuse: the caller named the track, exactly as `ripple_delete` removes the
  clips it was given, and a lock decides only what may shift, which for an
  overwrite is nothing.
- **The overlap check after `close_gap`'s shift is per touched track**, not
  timeline-wide: a rule violation on a track nothing moved on is not this
  op's to report, and refusing over one would make a gap uncloseable for a
  reason the user cannot see.
- **`ripple_delete_range` was refactored onto the same two helpers as
  `lift_range`** (`ordered_range`, `clear_range`), so the two cut
  identically and differ only in the shift. The alternative was a second
  spelling of "split both bounds and drop the middles".

Two pieces of shared arithmetic moved rather than being copied:
`content_length` went from `edit_clip.rs` to `model_query.rs` and
`source_head` was extracted out of `trim_start`'s body, so the three
measurements of a source window — head, window, remaining — have one home
and a slip and a trim cannot disagree about where a media ends.
`whole_media_length` came out of `add_clip` for the same reason: the room an
insert opens is the room `add_clip` would have needed.

**Proof.**
- `slip` by `+d` then `−d` is the identity; a slip past the source head
  clamps and reports the clamp as `None` when nothing moved.
- `roll` keeps `predecessor.start` and `clip.end` fixed and the pair's total
  duration constant; `render_frame` at `to − 1` and `to` shows the two
  sources meeting there.
- `lift_range` leaves every clip start ≥ `to` unchanged and `render_frame`
  inside the range shows the background.
- `close_gap` moves the next clip's start to the gap's start and every later
  unlocked clip by exactly the gap; a locked track's clips do not move.
- `insert_clip`: the frame at `at + len` after equals the frame at `at`
  before, on every track; `overwrite_clip`: frames outside the span are
  byte-identical before and after.
- Each key and gesture is one undo step (`undo` over MCP restores the frame).

**Proved** on 2026-09-06, and again after the review round below. Core:
`make test` **251 passed / 0 failed** — 222 before, plus `core/tests/edge.rs`
(16), `core/tests/insert.rs` (10) and three in `edit_tests.rs` for
`lift_range` and `close_gap`. `make lint` clean, `make typecheck` 0 errors
and the same 4 AVFoundation deprecation warnings. The identity claims are
whole-document byte comparisons, not field checks: slip-and-back and
roll-and-back both reproduce the input JSON exactly.

App: driven over MCP against `make app`'s binary — **66/66 checks**, and the
script is in the repo at `tools/proof/phase1_proof.py` so it can be re-run
after a later phase rather than believed on the strength of this paragraph.
The catalog is 63 tools and the startup parity check passed. Every frame claim is a byte comparison of `render_frame`
PNGs against ffmpeg-generated test cards:

- Slip: the frame at 3 s after a `+2 s` slip is byte-identical to the frame
  that was at 5 s; there and back is byte-identical to the start; the window
  travels exactly the 4 s a 6 s clip of a 10 s media has, and then reports
  no change.
- Roll: the frames at 6 s − 1 frame and at 8 s are byte-identical before and
  after — **a roll moves the cut, not the film** — while the frame at
  8 s − 1 frame changes, because that is the tick the cut crossed. The
  pair's outer edges and total length are unchanged; `undo` restores the
  frame. A roll across a gap changes nothing.
- Lift: the clip after the range is untouched and its frame is byte-identical;
  the range renders as the canvas background, byte-identical to a span that
  was always empty. The same range through `ripple_delete_range` moves that
  clip, which is the whole difference between the two.
- Close gap: the next clip lands on the gap's start, a locked track's clips
  do not move, and the three refusals (no gap, a time on a clip, a locked
  track) all report no change.
- Insert: the frame at `at + len` after is byte-identical to the frame at
  `at` before, on the destination track AND on another one; a straddler on
  another track is neither cut nor moved.
- Overwrite: frames before the span and on other tracks are byte-identical,
  the frame inside it is the new clip, and no other track moved at all.
- Every op is one undo step: `undo` restores both the placements and the
  frame bytes.

Not machine-checked, for the reason spec §10 gives about steps 6 and 8: the
two ⌥⇧ drags, the `,` / `.` nudge, the ⌫-with-a-range lift, the empty-lane
double-click, the ⌥-click on a track header and the ⌥ / ⇧⌥ drop are
event-driven UI. Their ops are proved above and their wiring typechecks; a
person at the machine is what is left.

**Reviewed, and five real defects fixed.** The change was then read by a
fan-out of reviewers — correctness, the core's rules, the app's rules, the
gestures, the MCP mirror and the docs, one per dimension — with every
finding put to three sceptics prompted to refute it. Thirty-one survived.
The five that were code, each now covered by a test that fails without the
fix:

1. **`whole_media_length` handed back an unsnapped constant.** Five seconds
   is 3 000 000 ticks, and 3 000 000 is not on the frame grid of a rate that
   does not divide the timescale — at 30000/1001 it is 3 003 000. So an
   image with no duration of its own made `overwrite_clip` clear a span that
   missed the fragment `split_clips` had just cut, the fragment survived,
   the new clip landed on top of it, and the overlap rule refused the whole
   op: **every overwrite of an imported still on a /1001 timeline was a
   silent no-op**, and every insert of one opened a hole a sliver wider than
   the clip it placed. `MediaImporter` writes `duration: 0` for every image,
   so this was the ordinary case, not a corner.
2. **`slip` answered `Ok(None)` for a text clip** when the delta rounded to
   nothing, because the zero-delta short circuit ran before the source-kind
   check — the one answer the non-media rule exists to stop the MCP agent
   being given.
3. **`roll` clamped a snapped `to` to UNSNAPPED bounds.** Both source bounds
   are floored divisions by a clip's speed, so a clamped roll could write a
   sub-frame time into two clips at once. `time.rs` gained the directional
   pair a bound needs — `snap_up_to_frame` and `snap_down_to_frame` — since
   a lower bound rounded to the nearest frame lets a caller past what it
   protects.
4. **`insert_clip` did not check the destination lock**, so an insert at a
   point where the locked track happened to be empty succeeded, adding a
   clip to a locked track and rippling every unlocked one.
5. **The bare-⌫ menu item had no "text is being edited" guard.** The item is
   a modifier-less key equivalent, which AppKit resolves ahead of the first
   responder; `AppDelegate`'s own comment on it asks for exactly this guard
   and nothing had ever supplied one. Widening the item to "selection OR
   range" made it worse, so the guard went in.

The rest were a snap guide computed and never drawn (a roll was the one
snapping gesture with no snap line), `selectedMedia` missing from the two
view-state resets on the read path, the row menu and the Edit menu
targeting different tracks under the same name (`targetTrack` moved to
`ProjectDocument`, so there is one rule), four doc statements that had gone
false, two handler comments naming selectors that do not exist, and seven
gaps in the tests: `roll` was never run at a speed other than 1, never on a
sourceless pair, `close_gap`'s and `insert_clip`'s lock guards were both
satisfied by a different code path, `overwrite_clip` on a locked track was
untested, `close_gap`'s `set_gained_transitions` branch was never taken, and
two of the MCP proof's cross-track frame checks were hashing a flat green
picture, which is the same at every time and could not have failed.

---

### Phase 2 — Clip identity

*One session. Schema v3: clip name, clip label, track solo.*

A clip has no name of its own — the strip shows its media's file name —
and there is no way to mark one. Solo is the one track switch missing.

**Schema.** `Clip.name: Option<String>` (absent → today's fallback);
`Clip.label: Option<String>` using the marker colour vocabulary;
`Track.solo: bool`. `RC_FORMAT_VERSION` 3.

**Correction to the plan, found while reading for phase 1:** the one
fallback is NOT in `ClipKindStyle`. It is
`ProjectSnapshot.name(of:)` — "the nest's name for a nest clip, the media
file name where there is one, else the kind" — and all three readers already
route through it (`TimelineClipDrawing`, `TimelineBar`'s selection block,
`ClipPane`'s header). So `Clip.name` goes at the HEAD of that one function
and nothing else changes. `ClipKindStyle` owns the kind WORD and the tint,
which is a different question and stays where it is.

| Op | Arguments | Semantics |
|---|---|---|
| `set_clip` | `clips: [u32], name?: string \| null, label?: string \| null` | Sets or clears (`null`) the name and label; omitted keeps. `None` when nothing changes. Lives in `edit_props.rs`. |
| `set_track` | gains `solo?: bool` | In `audio.rs`, when any top-level track is soloed every non-solo track is treated as muted. Audio only; the picture is unaffected (solo is a mixing word). Inside a nest the nest's own tracks follow the same rule among themselves. |
| `paste_attributes` | `clips: [u32], payload: object, groups?: [video \| audio \| text \| shape]` | Takes the payload's FIRST clip (the Copy payload of `edit_paste.rs`) and merges its props onto each target for the groups named (default: every group the source has and the target can take). Video and audio paste whole, transform included; text pastes everything but `content`; shape pastes everything but `kind`, `width`, `height`, `from`, `to`. Speed, enabled and actions do not travel. Lives in `edit_paste.rs`. |

**UI.** Rename: double-click the name strip in the timeline (an inline field
in a `TimelineView+Rename.swift` extension), the Clip tab's header name
becomes editable, Clip ▸ Rename… (⇧⌘R). Label: a 6 pt dot at the right end
of the name strip and a Clip ▸ Label submenu. **The tint stays the kind's**
— the label is a badge, never a tint override; the redesign's rule that the
colour says the kind is what made clips tell apart. Solo: an `S` toggle in
the track header beside eye / speaker / lock, Track ▸ Solo. Paste
Attributes: Edit ▸ Paste Attributes (⌥⌘V) over the existing
`com.kgalligan.reelcut.clips` pasteboard type in
`EditorViewController+Clipboard.swift`.

**Where.** `model.rs`, `format.rs` + header, `edit_props.rs`,
`edit_paste.rs`, `edit_track.rs`, `audio.rs`; `core/tests/schema_v3.rs`,
additions to `edit_tests.rs` and `paste.rs`. Swift: `ProjectSnapshot.swift`
(the fallback, and the `Codable` mirror of the two new clip fields),
`TimelineClipDrawing.swift` (the label dot on the name strip),
`TimelineView+Rename.swift`, `ClipPane.swift`, `TimelineBar.swift`,
`EditorViewController+Clipboard.swift`, `AppDelegate.swift`, the catalog and
`AgentServer+Clips.swift` / `+Tracks.swift`. `ClipKindStyle.swift` is NOT on
the list — see the correction above.

**What landed.** All of it — the three fields at version 3, the two ops
and the `solo` argument, the four UI surfaces and their mirrors — plus
the following, where the code differs from the table above or settled
what it left open:

- **`set_clip` takes a patch**, `{clips, patch: {name?: string | null,
  label?: string | null}}`, not the table's two top-level arguments. The
  op envelope's rule (`edit.rs`) is that an absent optional and an
  explicit `null` mean the same thing, and the crate has no tri-state
  argument idiom — while a patch already has exactly the one wanted
  (absent keeps, `null` clears) and the Swift side already had `T??`
  patches and `patchArg`. So it is the fifth patch op, in `edit_props.rs`
  beside the other four. Inside the patch an EMPTY string clears too,
  after the trim a name gets, because an unnamed clip is `None`, not
  `""`; an unknown key is an `Err`, checked before the clip ids, so it is
  refused even with an empty selection.
- **`paste_attributes` replaces a group whole, never merges**: "make this
  look like that" is the gesture, and a merge would leave the target's
  shadow under a source that had none. What a target keeps is what makes
  it the clip it is: a text clip's `content`; a shape's `kind`, `width`,
  `height`, `from`, `to`. `audio.muted` and `keep_pitch` travel with the
  audio group — properties like opacity — and `keep_pitch` only acts when
  the speed is not 1, which does not travel; neither do `enabled`, the
  actions, the transition, the source, the name or the label. `groups`
  absent means every group BOTH sides have, silently skipping the rest; a
  NAMED group the payload clip lacks (`payload clip has no audio
  properties`) or a target lacks (`clip 30 has no audio properties`) is
  an `Err`, all-or-nothing, because a caller who asked would otherwise
  never learn it did not happen; an empty explicit list is `None` in the
  core and a refusal by name over MCP. Each copied group then passes the
  range checks a patch does (`Project::check_group`, which checks only the
  group that was replaced), so a hand-written payload cannot smuggle in a
  value the inspector would refuse. Only ONE payload clip's four groups
  are read — the EARLIEST (at one start the front-most, then the lower
  id), which the review changed from the array's first, since that is
  Copy's creation order and invisible to the user; its ids, media rows
  and nests are irrelevant and nothing is minted.
- **Solo: mute wins, and a solo with nothing audible still silences.**
  `silenced(set, track) = muted || (set.any(solo) && !solo)` in
  `audio.rs`, judged per container in `Voice::of` (the timeline's tracks
  at depth 0, `inside[d − 1].nest.tracks` at depth d), an envelope like
  mute — the segments stay in the plan, `plays_audio` and `assign` are
  untouched, so a solo toggle changes ramps only. The rule is on the set,
  not on what plays, which is what a mixer's button does; and
  `plan_text()` of "solo A" is byte-identical to "mute every track but
  A", which is the string the composition rebuild is keyed on.
- **`nested_track` copies `solo`** as it copies hidden/muted/locked, so
  what played before nesting plays after, judged inside among the nest's
  own tracks. One consequence to know — a limit, not a bug: the nest clip
  lands on the selection's front-most source track, so a solo on a
  NON-front-most selected track stays behind on the emptied timeline
  track and then silences the whole nest, which is what moving that clip
  to an unsoloed track would do too, since a solo belongs to its track.
  `unnest` carries no track flag back out, as it never did for `muted`.
- **Two cuts under the size rule**, done before the fields went in:
  `model_props.rs` (the §5.2 property types, 531 lines, re-exported
  whole by `model.rs`, which went from 939 to 462) and `props_check.rs`
  (`edit_props.rs`'s range-check section, cut when `set_clip` and
  `check_group` took that file over the cap). Both are in spec §7.10 and
  `core/CLAUDE.md`.
- **The Clip tab's header field is the clearing path.** The shared inline
  editor `TimelineView` keeps for tracks and markers drops an EMPTY
  commit — right there, since those names cannot be cleared — so the
  strip's double-click and ⇧⌘R can rename but not clear. The header
  field (`ClipSelectionHeaderView`) shows the DISPLAYED name, own or
  fallback, and an emptied field on a named clip sends `{"name": null}`;
  on an unnamed one it sends nothing and the fallback is redrawn.
- **The mirror type-checks `set_clip`'s two keys itself.** `patchArg`'s
  round-trip guard cannot refuse a wrong-typed value for a `String??`
  field — `{"label": 7}` decodes as a CLEAR and passes — so
  `checkClipPatchTypes` runs after it and refuses with `patch.label must
  be a string, or null to clear it.` The gap is `nullable()`'s, not that
  one field's: it still exists for the other nine `T??` patch fields
  (`VideoPatch.shadow` / `chroma` / `reflection` / `spotlight`,
  `AudioPatch.duck` / `compressor`, `TextPatch.outline` / `backdrop` /
  `width`), where on an object-valued one a wrong type CLEARS the
  effect — unfixed. The label's VALUE is not policed, by the
  `Marker.color` policy; `ClipLabel.swift` is the vocabulary's one home,
  and the catalog's description reads the six names from it.

**Proof.**
- A v2 fixture opens; every clip's displayed name is unchanged (the fallback
  is the old behaviour); write-read round-trips `name`, `label`, `solo`.
- A renamed clip shows its name in the three places at once — selection
  block, Clip header, name strip — in an offscreen render.
- A two-track project with one track soloed exports audio identical to the
  other track muted (sample-for-sample).
- `paste_attributes` leaves the target's props equal to the source's for
  the named groups and byte-identical elsewhere; one undo step.

**Proved** on 2026-09-07, and again after the review round. Core: `make
test` **284 passed / 0 failed** — 251 before, plus `core/tests/schema_v3.rs`
(8) and additions to `edit_tests.rs` (+7), `paste.rs` (+10, two of them
from the review), `evaluate_tests.rs` (+4) and `nest.rs` (+4). `make lint`
clean, `make typecheck` 0 errors and the same 4 AVFoundation deprecation
warnings. The solo claims in the core are hand-written ramp tables, and
`plan_text()` of "solo A" equals "mute every track but A".

App: driven over MCP against `make app`'s binary — **85/85 checks**,
`tools/proof/phase2_proof.py` (84 from the provers, plus a `set_track`
rename through the client's `call_with` from the review), re-run against
the reviewed build, with `phase1_proof.py` still at 66/66 beside it; the
catalog is 65 tools and the startup parity check passed. Every frame claim
is a byte comparison of `render_frame` PNGs and every audio claim a
sample-for-sample comparison of `audio_m4a` exports decoded to PCM:

- Schema: a saved `project.json` is version 3, every clip object ends
  `name` then `label` and every track `solo`; a byte copy of the package
  opened from disk reads them back; a hand-made version-2 fixture opens,
  reports version 3 and reads `null` / `null` / `false` everywhere.
- `set_clip`: `null`, `""` and a blank string all clear; a padded name is
  trimmed; identity, an unknown key and a wrong-typed `label` or `name`
  are refused by name and leave the clip unchanged; a top-level `name`
  with no patch is refused; a split carries name and label to both halves.
- `paste_attributes`: onto two targets, the video and audio groups equal
  the source's, the text's `content` and the eleven keys outside the four
  groups are byte-identical, and `undo` is one step that restores the
  whole document and the frame byte for byte.
- Solo: soloing the back track of a two-tone project exports
  sample-for-sample equal (0 of 477,056 samples differ) to muting the front
  track and to a project holding only that tone; soloed and muted together
  is digital silence, equal to muting both; the frame over a picture track
  is byte-identical before and after a solo. Two exports of the unchanged
  project decode byte-identical, so no tolerance was needed — the M3
  wobble is confined to duck edges.

Offscreen: `tools/proof/phase2_chrome.py`, **26/26**, over
`tools/proof/harness/` with six hand-written one-text-clip packages, every
claim a pixel diff of two renders measured against rectangles from the
layout constants:

- Two renders of one package are byte-identical, and a version-2 file
  renders byte-identical to its version-3 spelling.
- A rename changes exactly three pixel clusters, one inside each of the
  selection block, the Clip header and the name strip, and nothing outside
  them.
- A label changes the strip's right end and the header's right end,
  nothing outside the lanes and the header, and not the body's centre
  pixel (the tint stays the kind's); the same clip labelled red differs
  from blue only at those two ends, where the changed pixels read bluer
  under blue and redder under red — the label's VALUE reaches both dots,
  which a one-ink build (tried) fails.
- A solo changes pixels only inside the track header column, within ±1 pt
  of the headphones box.

Still owed by a person at the machine — event-driven UI a still frame
cannot answer: (1) double-click a clip → the field appears over its strip
with the current name, Enter commits "Rename Clip" and all three places
update; (2) the Clip-tab header field commits on Tab or click-away,
emptying it on a named clip returns the fallback in one undo step, and on
an unnamed clip nothing happens and nothing beeps; (3) the field's 12 pt
semibold text sits acceptably in its 20 pt box; (4) ⇧⌘R scrolls a far-off
clip into view before the field opens, clear of the header column and the
ruler; (5) the headphones toggle's box and tint match the other three at
S/M/L; (6) Track ▸ Solo's checkmark tracks the header; (7) Label ▸ Blue
puts the dot on the strip AND in the header, the checkmark moves, None
clears both; (8) ⌥⌘V after ⌘C of a styled clip changes another clip's look
and beeps when the two share no group; (9) a zoom or a resize while a
rename field is open moves the field with its clip and keeps what was
typed, and ⌘⌫ or the timeline bar's Delete under an open field closes
it with no rename sent and no sheet.

**Reviewed, and six real defects fixed.** The change was read by eight
readers — correctness, the core's rules, the audio rule, the app's
rules, the gestures and menus, the MCP mirror, the docs and the proofs
— who returned 71 findings; every one was put to three sceptics told
to refute it, and 30 survived. The six that were code, each now covered
by a test or a proof check that fails without the fix where one can be
written:

1. **The strip rename pinned the fallback as the clip's own name.** The
   field opens showing what the strip shows, and an unchanged Enter
   sent that back as `set_clip {name}` — an undo step and a dirty
   document for an accidental double-click, and a text clip's strip
   frozen at the words it had. The shared editor now drops an
   UNCHANGED commit as well as an empty one, for all three renames.
2. **The Clip-tab header field stayed blank after a clear.** A field's
   `refresh` is skipped while its field editor is attached, which it
   still is inside `controlTextDidEndEditing` — after Return or Tab
   AppKit even re-attaches it — so every refresh the commit ran was
   skipped and the field showed what was typed while the strip showed
   the fallback. `InspectorNameField` re-reads the model as the commit
   ends; app/CLAUDE.md records the pitfall beside the other one.
3. **Deleting the clip under an open rename field sent the rename to
   the dead id** and put up the core's refusal in a sheet after a
   delete that had succeeded. Every rename now hands `beginRename` a
   `relocate` closure answering its field's rect under the CURRENT
   layout; `rebuildLayout` ends with `relocateRename()` instead of
   `endRename()`, so the field FOLLOWS its target through a zoom, a
   resize and any document change, and a relocator answering nil ends
   the field with its commit dropped. The old `endRename()` had also
   meant an agent's edit mid-typing folded the half-typed name into the
   agent's undo step.
4. **`beginRename` installed the new field before the first-responder
   handoff**, so the previous editor's commit — which rebuilds the
   layout — ran with the new field already in place. It blurs whatever
   else is being typed into first, and gives up if the window refuses
   the field.
5. **A double-click on the visible part of a long clip whose start was
   scrolled off opened the field out of view** — AppKit does not scroll
   a timeline to a field editor's caret. The field is clamped to the
   visible lanes.
6. **`paste_attributes` read the payload's FIRST clip**, which is Copy's
   storage order — creation order, neither timeline nor selection order
   and invisible to the user. It now reads the EARLIEST, ties to the
   front-most and then the lower id, and the test
   `the_look_comes_from_the_earliest_copied_clip` fails on the old code.

The rest: two core gaps closed with tests (an explicit `groups` list
RESTRICTS the copy; an unknown patch key is refused before the ids are
resolved), the waveform dimming under a solo as it does under a mute,
the chrome proof telling one label colour from another (a one-ink
build now fails it), `mcp.py` gaining `call_with` so a tool argument
spelled `name` can be sent, the harness pinning one more defaults key,
and a dozen doc statements that had gone false or were missing —
`RC_CAPS`, which four documents named and nothing defined, among them.

---

### Phase 3 — The screencast trio

*Two sessions. Schema v4 (`video.obscure`). The three features that make a
talking-head or screen-recording cut fast; all three sit on infrastructure
that exists.*

#### 3a. Remove silences

Detection is Swift's, from the waveform peaks the package already caches
(`cache/peaks/<media id>.bin`, f32 max magnitude per 10 ms bucket), read
through the reader `ProjectDocument` already holds for the waveform. The
cut is one core op so it is one undo step and one tool.

- `SilenceDetector.swift`: for the clips in scope, map each clip's peaks
  through `in` and `speed` to project time; a bucket is quiet below a
  threshold (default −40 dBFS); a quiet run shorter than the minimum
  (default 0.5 s) is kept; the survivors lose a padding (default 0.1 s) at
  each end. A span is silent only where **every** clip in scope is quiet
  — a music bed would otherwise defeat it — so the scope is the selected
  clips, else every unmuted audible clip, and the sheet says which.
- Op `ripple_delete_ranges {ranges: [[from, to], …]}` in `edit_time.rs`:
  normalises and merges the ranges, applies `ripple_delete_range`'s logic
  right to left, returns one project. Empty after merging is `None`.
- UI: Clip ▸ Remove Silences… → `SilenceSheetController.swift`: threshold
  (slider with the dB readout), minimum length, padding, scope popup, a
  live "23 cuts · removes 0:42" line, and the candidate spans shaded on the
  ruler and lanes in the in/out style while the sheet is up.
- MCP: `detect_silence {clips?, threshold_db?, min_length?, padding?}` →
  the ranges (app-state tool, off-main: it reads files), and
  `ripple_delete_ranges` as the op's mirror.

#### 3b. Zoom to region

The screencast zoom is an action on scale / x / y; the maths that turns a
rectangle into that end state belongs in the core, where §5.3's placement
already lives, so the canvas, the inspector button and the tool all get
the same numbers.

| Op | Arguments | Semantics |
|---|---|---|
| `add_zoom_action` | `clip: u32, at: ticks, duration?: ticks = 1 s, region: {x, y, width, height} \| null, fit?: "fit" \| "fill" = "fit"` | Adds an action at CLIP time `at` whose end patch scales the layer so `region` (SOURCE pixels from the cropped rect's centre, the spotlight's frame) fills the canvas by `fit`, and positions it so the region's centre lands at the canvas centre, through the clip's rotation. `region: null` is **zoom back**: the end patch is the clip's base `scale`, `x`, `y`. Same overlap refusals as `add_action`. |

- UI: `Z` (unbound today; ⇧Z is fit timeline) enters a region mode on the
  canvas — drag a rectangle over the selected clip, release to add the
  action at the playhead, Esc cancels — as a `ZoomRegionSession` in
  `CanvasSessions.swift` with its logic in
  `EditorViewController+ZoomRegion.swift` (the eyedropper extension is the
  template for a modal canvas session). The Actions section gains "Zoom to
  Region…" and "Zoom Back".

#### 3c. Obscure a region (blur / pixelate)

The spotlight's inverse: hide a face or a password field. The shader has
the region maths (spotlight) and the kernels (the blur / pixelate fold in
the sample stage); this joins them.

**Schema.** `video.obscure: [ { "shape": "rect" | "ellipse", "x", "y",
"width", "height", "feather", "kind": "blur" | "pixelate", "amount": 0..1 } ]`,
at most **four** (the uniform budget, as for filters), all geometry in the
spotlight's source-pixel frame so a region rides with its layer through
scale, move and rotation. `RC_FORMAT_VERSION` 4.

- **Interpolation rule for lists**, defined once in `actions.rs` and reused
  by Phase 6 for filters: an action's end patch interpolates a list per
  index when the lengths match and each entry's discrete fields (`shape`,
  `kind`) agree, and switches at the end otherwise.
- Shader: a pass parallel to spotlight in `Compositor.metal`; the uniform
  block gains four regions, and `Compositor.swift`'s field order changes in
  the same edit (the order is a contract checked only by reading both).
  `CompositorEffects.swift` holds the Swift side.
- Range checks in `props_check.rs`, clamps in `clamp_video`; `set_video`
  carries the patch, so no new op.
- Inspector: a VideoPane "Obscure" section — rows with shape, kind,
  amount, feather, numeric box, add / remove — and "Place on Canvas",
  which reuses the region drag from 3b with a different commit.

**Where.** `SilenceDetector.swift`, `SilenceSheetController.swift`,
`edit_time.rs`, `model.rs`, `format.rs` + header, `actions.rs`,
`edit_props.rs` / `props_check.rs`, `evaluate.rs`/`recipe.rs` (the clamp), `Compositor.metal`,
`Compositor.swift`, `CompositorEffects.swift`, `VideoPane.swift`,
`CanvasSessions.swift`, `EditorViewController+ZoomRegion.swift`, a new
`core/src/edit_zoom.rs` for `add_zoom_action` (placement maths is a concern
of its own), `core/tests/zoom.rs`, `core/tests/schema_v4.rs`, catalog and
handlers.

**What landed.** All three features, at version 4, with the two ops, the
tool, the shader pass and every path into them — plus the following, where
the code differs from the plan above or settled what it left open. Six of
them matter enough to read before touching the area:

- **`add_zoom_action` gained a sixth argument, `curve`**, which the table
  above does not have, defaulting to the eased-BOTH-ends form rather than
  `Curve::default()`'s linear. A screencast zoom that starts and stops
  abruptly is the one thing the feature exists to avoid, and adding the
  argument later would have meant a second op inside one gesture — which
  breaks the one-op-one-undo-step property the composite exists for. It
  reuses `set_action`'s argument name, enum and error strings, applied by
  composing `set_action` rather than by writing `slot.curve`.
- **The obscure shader stage runs at 4b, between the sharpen and the point
  filters** — not after them, which is where a pass "parallel to spotlight"
  would naturally have gone. It must come AFTER the sharpen, whose unsharp
  term is built from the raw texture and added on top, or a layer carrying
  both a sharpen and a region would have the hidden detail put straight
  back; and BEFORE the point filters, because a region replaces the colour
  with a second sample of the same texture, so a sample taken after them
  would show as an ungraded hole on a sepia or inverted layer. Between the
  two is the only correct place, and the region's colour is then graded,
  lit and filtered exactly like the picture around it. The argument is
  written into `Compositor.metal`'s order-of-operations comment, beside the
  one that says why the neighbourhood filters do not run in slot order
  either.
- **The widened interpolation discriminant applies to LIST ENTRIES only.**
  One reading of "each entry's discrete fields (`shape`, `kind`)" above was
  to widen the crate's generic object test; that would have changed
  SHIPPED behaviour, because `video.spotlight` is an object with a `shape`
  field and a spotlight animated rect → ellipse would have stopped
  interpolating its geometry until the last instant. So `ENTRY_DISCRIMINANTS`
  is reached only from the array arm (`lerp_entry`), the object rule still
  knows `kind` alone, and `core/tests/schema_v2.rs` pins both halves — the
  region case AND a regression test that fails the moment anyone moves
  `shape` into the object arm.
- **⇧ chooses fill during the canvas drag**, read at every mouse-dragged
  and mouse-up rather than latched at the press, and named in the hint pill
  and the button's tooltip. The band drags FREE, which is what makes `fill`
  meaningful at all, but nothing above said how a user chooses it; without
  this modifier `fill` would have been reachable only over MCP.
- **The sheet spells the removed total as a timecode** — "23 cuts ·
  removes 00:00:04:12" — through `ReelTime.format`, not the "M:SS" the
  plan's line sketches. `SpeedSheetController` does the same with the
  lengths it predicts, and a second spelling of a time in a sheet is
  exactly what that formatter exists to prevent.
- **A region's default kind is `pixelate` at amount 1**, not the blur a
  reader coming from `Filter` would expect, and its feather is 20 rather
  than the spotlight's 40. A filter has to be visible without destroying
  the frame; a region that only half hides has failed at its one job, and a
  blur at the shader's maximum radius is soft enough to read a large
  password field through. A face region is also smaller than a callout
  window, and a 40-pixel ramp on a 200-pixel box is mostly ramp. The rest
  of the defaults are the spotlight's own box, 480 × 270 centred, so the
  two region controls put the same rectangle on screen.

And the smaller settlements, each argued where it lives:

- **The singular delegates to the plural.** `ripple_delete_range(from, to)`
  is now `self.ripple_delete_ranges(&[[from, to]])` — one implementation
  per algorithm — and the guard on that claim is that `edit_tests.rs`
  gained 220 lines and lost ZERO, so every existing ripple test passed
  unedited.
- **`ZoomRegion` and `ZoomFit` live in `edit_zoom.rs`**, not with the model
  types: they are op ARGUMENTS and never reach a project file. Their range
  checks are ten local lines in `props_check.rs`'s exact wording rather
  than a widening of that module's private `finite` / `above`, for the same
  reason. And a region's own clamp went where `clamp_video` already lives,
  in `actions.rs` rather than beside the checks in `props_check.rs`: a
  check is about a value being written, a clamp about one being evaluated.
- **The zoom reads the clip evaluated at `at`, and zooms BACK to the base.**
  `at` is the frame the rectangle was drawn on, which is what makes the
  answer match what the user saw; the residual limit is that a rotation
  animated between `at` and `at + duration` is not tracked. A null region
  writes the clip's BASE `scale`/`x`/`y`, not the evaluated ones, because
  "zoom back" means back to where the clip started. `nest.rs`'s `rotate`
  was widened to `pub(crate)` and CALLED rather than restated.
- **A NaN `amount` clamps to 1, not 0.** Every other neutral in
  `clamp_video` is "changes nothing" or the type's default; for a region
  both readings point the same way, and a NaN that resolved to "hides
  nothing" would quietly publish the face the region was drawn over.
- **`model_props.rs` paid the size rule again.** `video.obscure`'s types
  took it to 633, so `Spotlight`, `SpotShape`, `ObscureRegion`,
  `ObscureKind` and `MAX_OBSCURE` went out to a new `model_regions.rs`
  (218) and it came back to 498. The cut is by CONCERN, not by line count:
  those five share one coordinate frame and one shape enum. The move's only
  textual change was three intra-doc links rewritten to the house's
  fully-qualified form, because their targets stayed behind.
- **The version-4 interpolation tests live in `schema_v2.rs`**, beside the
  filter cases that pin the same rule, with a paragraph in that file's
  module doc saying why a version-4 assertion sits in a file titled "what
  version 2 added".
- **No `MediaImporter.peaksExist` was needed.** `loadPeaks` already answers
  nil for a cache that is not on disk, and the detector records those media
  in `pendingMedia`, which the sheet names and re-runs on
  `.mediaCacheDidChange` — the same information with no new API and no
  second stat of a file about to be read.
- **`detect_silence` runs ON the main thread**, not off it as the plan's
  line says. `offMainTools`' criterion is "waits for something the main
  thread must deliver", not "touches the disk", and this reads a few
  hundred KB of peak files and does one arithmetic pass —
  `consolidate_media` and `import_captions` are the precedent. It also
  **does not clamp its three numbers** into the sheet's
  slider ranges: those are chrome, not model rules, and a tool that
  silently clamped would report a detection the caller did not ask for. It
  refuses only what is not a level or not a length, and echoes all three so
  a caller sees what ran. `rangesArg` likewise passes a REVERSED pair
  through untouched — the core orders every pair, and a reader that
  rewrote its argument would make what a caller reads back disagree with
  the call it made.
- **The Obscure section is six rows per region, not eight**, the centre and
  the size paired into one row each where the spotlight gives all four a
  row of their own, and it has no on/off checkbox because an empty list IS
  off — the filter stack's idiom, not the spotlight's. "Place on
  Canvas" is one button for the SECTION rather than one per row, because
  `InspectorViewController.onCommand` carries a selector and no index, and
  an index-carrying seam for one button would be the first of its kind.
- **`PreviewCanvasView.swift` was not touched**, though the plan listed it:
  everything the region mode asks of it is already internal, and the
  modal-overlay shape exists precisely so the frozen file gains no seventh
  stored session. The three `@objc` selectors are declared on the extension
  itself (`pickChromaKey`'s precedent), so the frozen controller gained one
  key case, one forward for Remove Silences and one validator arm — 21
  lines.
- **Stored regions are not drawn on the canvas** outside the modal mode: a
  blurred region is self-evident on the
  picture, unlike a spotlight's geometry, and drawing it properly means a
  new hit-test family for drag handles. `CanvasLayerBox.canvasPoint` and
  `canvasQuad` are written, unused, as the seed for that.
- **The band commits a RECT**, so an ellipse is reached only through the
  row's Shape popup afterwards. Deliberate — the band is a rectangle.

Three limits inherited rather than introduced, worth knowing before
chasing them: a PARTIAL entry in an end patch (`{"obscure": [{"amount":
1}]}`) interpolates smoothly and then, at the switch, takes
`ObscureRegion::default()` for every key it omitted, because `merge`
replaces a list rather than merging it — `video.filters` has had this since
M3; a pixelated region takes ONE raw sample, so on a layer that also
carries a global blur the blocks come out unblurred while the picture
around them is blurred (the coarser of the two is what hides), where a
blurred region combines in quadrature and is always at least as blurred as
its surroundings; and a reversed clip INSIDE a nest is analysed unmirrored
and cannot be named by the selection scope, because a nested clip has no id
`snapshot.clip(_:)` can look up — a mis-reading confined to the nest's own
span, which since the review's nest fix is a wall no candidate may enter
either way. A region on a slated (missing-media) layer
also does nothing, the posture the sharpen already takes.

**Proof.**
- Silence: a synthesised file with known quiet spans (`ffmpeg -f lavfi`
  sine with gaps) is detected within one bucket (10 ms) plus the padding;
  the export's duration equals the original minus the removed total; the
  frames either side of each cut are the frames that were either side of
  the span.
- Zoom: on a test-card clip, `render_frame` at the action's end shows the
  region's centre pixel at the canvas centre and the region's width equal
  to the canvas width (fit) ±1 px; zoom back returns a frame byte-identical
  to the base; each is one undo step; a rotated clip zooms to the right
  place.
- Obscure: pixels inside the region differ from the plain frame and pixels
  outside are byte-identical; pixelate at amount 1 yields flat blocks of the
  expected size; scaling the layer scales the region (measured centre
  offset); an action from amount 0 → 1 renders the midpoint between the two
  stills.

**Proved** on 2026-09-07. Core: `make test` **338 passed / 0 failed** — 284
before, plus `core/tests/schema_v4.rs` (12), `core/tests/zoom.rs` (32) and
additions to `edit_tests.rs` (+5), `schema_v2.rs` (+5) and the
`model_tests.rs` fixture. `make lint` and `cargo fmt --check` clean,
`make typecheck` 0 errors and the same 4 AVFoundation deprecation warnings,
`make app` building. The zoom's arithmetic is pinned by hand-computed
oracles rather than golden values: the whole cropped source under `fit` is
EXACTLY `min(cw/sw, ch/sh)` at the origin, which is the only thing tying
the core's maths to VideoPane's "Fit to Canvas" button; a quarter-width
region is scale 4 at −1920; a 90° clip answers 2.25 and (0, −1080) where
the naive formula would say 4 and (−1920, 0); a region wanting more than
the maximum clamps and takes its offsets from the CLAMPED value; and every
end-patch assertion checks the patch's keys are exactly `scale`, `x`, `y`,
so the op can never freeze a layer's angle for the span of a zoom. On the
cut side, two disjoint ranges in one `ripple_delete_ranges` equal the two
singular ops applied LATER RANGE FIRST as whole documents, and differ from
the same two applied earlier-first; two touching ranges leave the same
lanes as two singular ops but `next_id` exactly one lower — the merge is a
behaviour, not a tidy-up.

App: driven over MCP against `make app`'s binary, with the catalog at **68
tools** and the startup parity log EMPTY. A 320 × 180 region on a 640 × 360
clip under `fit` wrote the end patch `{scale: 2, x: 0, y: 0}`; a null
region wrote the base transform back under the undo name "Zoom Back";
`detect_silence` answered with −40 dBFS, 0.5 s, 0.1 s and the scope it
used; `[[1 s, 2 s], [3 s, 4 s]]` in one call turned a 5 s clip into three
1 s clips. Refusals are by name: a wrong-typed tick gives
`ranges[0][1] must be a time in ticks (600000 per second)` — `rangesArg`
snapping through the same path `timeArg` uses — and an absent `region`
gives a message that spells out that `x` and `y` are its CENTRE. The
regression proofs re-ran beside it: `phase1_proof.py` **66/66**,
`phase2_proof.py` **85/85** and `phase2_chrome.py` **26/26**, the last two
after phase 2's tool-count assertion became the floor its own comment
always said it should be (the EXACT count belongs to the newest phase's
script). The phase's own scripts go beside them in `tools/proof/` —
`phase3_proof.py` over MCP at **121/121** (91 when the phase first landed,
plus the thirty the review's fixes brought — eleven for the shader, and the
rest for the nest wall and the list-length rule), the review's own
`phase3_silence_scope.py` at **8/8**, and `phase3_chrome.py` at
**33/33** for the two claims the offscreen harness can answer: the
candidate wash (its α solved from two backgrounds and matched to
`DS.timelineCandidateShade`'s 0.24, not the range shade's 0.12) and the
Obscure section's summary and rows with the Clip tab open. The preview
well renders black offscreen, so nothing about the PICTURE can be proved
there and 3b's canvas drag cannot be photographed at all. Both needed two
new harness arguments — `candidateSpans` and `expandSections`, view state
no package carries, defaulting to `-` so every earlier caller renders the
bytes it always did.

Still owed by a person at the machine — the event-driven half no still
frame answers: (1) `Z` with a clip selected puts up the crosshair, a drag
paints the band with the resolved rectangle ghosted beside it, ⇧ switches
it to fill mid-drag, and release adds one action; (2) `Z` again, Esc,
moving the selection and arming the chroma eyedropper each end the mode,
and ⇧Z still fits the timeline;
(3) Clip ▸ Remove Silences… shades its candidates on the ruler AND the
lanes, the shading survives every control change and clears when the sheet
goes; (4) the sheet's *Selected clips* row is disabled when the selection
makes no sound, and the pending-peaks note names the file still being
analysed and clears when it lands; (5) "Place on Canvas" appends a region
where the band was drawn and greys out at four; (6) an obscured region
actually hides a face at 100 % zoom, which is the whole point and which
only eyes can judge.

**Reviewed, and six real defects fixed.** The change was then read by nine
readers — correctness, the core's rules, the shader, the detector, the
canvas gestures, the inspector, the MCP mirror, the docs and the proofs —
and every finding was put to three sceptics told to refute it; nine
survived. The six that were code:

1. **A blurred region ERASED a pixelated one it overlapped.** Both mixes
   took a fresh sample of the RAW texture and mixed it over the colour
   accumulated so far, so whichever ran second won outright — and the blur
   always ran second. A region at 5 % blur dropped over a full-strength
   pixelation put the face the blocks had destroyed back on screen,
   softened by a pixel: ADDING a region made the frame less hidden, which
   is the one thing this feature must never do. The fragment stage now
   measures each hiding as a length in source pixels times the mix it would
   be applied at, applies the greater ALONE, and gives a tie to the
   pixelate, which destroys where a blur only softens.
2. **A region that hides nothing forced its neighbour to full strength.**
   The two covers were the bare max of the slot masks, so a region at
   `amount` 0 — "there but hides nothing", as `model_regions.rs` documents
   it — pulled a neighbouring pixelation's cover to 1 inside its own box: a
   hard-edged square of 64-pixel blocks conjured by adding a region that
   hides nothing. A cover is now each slot's mask weighted by that slot's
   own strength over the strongest strength of its kind, which is
   continuous in `amount` where a "skip the empty slots" guard would have
   left a cliff between 0 and 0.001. Both fixes are covered by ELEVEN new
   byte comparisons in `phase3_proof.py`, part of why that script is
   **121 checks** and not the 91 it landed with.
3. **A silenced clip in the SELECTED scope proposed deleting itself.** A
   voice the mix has silenced reads quiet at every tick by construction
   (`level` short-circuits on a zero envelope) while still COVERING its
   span, so a muted music bed in scope answered with one cut across the
   whole song — and `ripple_delete_ranges` cuts every unlocked track, so
   that cut would have taken the audible voiceover under it away with it.
   `Input.defaultScope` chose that scope by itself, which made muting the
   music to hear the voiceover — the ordinary way anyone checks a mix — the
   way in. Both scopes now drop a silenced voice, `defaultScope` answers
   `audible` for a selection of them, and the sheet says so. The new
   `tools/proof/phase3_silence_scope.py` pins it at **8/8**; its two
   failing checks answer `[[padding, 10 s − padding]]` on a build without
   the fix, so neither can pass against one.
4. **Remove Silences proposed cuts INSIDE a nest.** The plan flattens a
   nest, so its audio segments carry the INNER clips' ids and a quiet run
   over a nest read like any other — but `Source::Nest` has no in point, so
   splitting a nest clip strands its tail instead of trimming it. A nest is
   now a WALL: its sound still counts toward the quiet test, because it is
   what the user hears, and no candidate may INTERSECT one. The limit that
   leaves is the one every edit inside a nest has (spec §4.4): the dead air
   in a nest is reached by un-nesting, cutting and nesting again.
   `phase3_proof.py`'s "3a — a nest is a wall" section is the check, over a
   fixture whose second copy of the quiet clip is nested.
5. **Appending a region while the playhead was inside an action was
   swallowed, then deleted.** The list rule interpolates per index only
   while the two lengths match, so a longer list written into an action's
   END patch is invisible for the whole span the user is looking at — the
   section does not even grow a row, since `structureSignature` counts the
   EVALUATED list — and the next write of that list replaces the end patch
   with the base list, without the new entry. A list write whose LENGTH
   differs from the clip's own now lands on the BASE props wherever the
   playhead sits; dialling a value inside an existing entry still animates,
   which is what the list rule is for, and `phase3_proof.py`'s "a list
   write inside an action: a LENGTH is not an animation" section holds both
   halves apart.
6. **Arming the chroma eyedropper did not end an armed region mode**, so a
   later canvas drag could commit a zoom or append a region nobody asked
   for. Both modes are installed through one `armCanvasMode` now, which
   ends every armed mode first, and a third inherits the rule by being
   installed at all. This is the one of the six no automated check reaches
   — two modal overlays and a mouse — so it is argued where it lives and
   added to the list a person must still work through, at (2).

The two that were documents: app/CLAUDE.md claimed `AgentServer.checkVideoEnums`
guards the chroma key's shape, which has no enum in it at all (a colour and
three numbers); and spec §6's `add_zoom_action` row listed the base
transform among what is read "from the clip evaluated at `at`", four
sentences before saying the zoom back writes the clip's base — only
rotation and crop are read evaluated, the zoom BACK's three numbers are the
STORED base, and the placement reads no transform of either kind, since the
`scale`/`x`/`y` it writes are absolute. Nothing in the tree reads
`designs/`, so no check can fail on a sentence; what pins the behaviour is
`core/tests/zoom.rs`'s `rotation_is_read_from_the_state_at_the_actions_start`
and `a_null_region_zooms_back_to_the_clips_base_transform`, and both halves
were measured again over MCP against the built binary — a zoom back placed
after an action that moves the layer writes the base three and not the
evaluated ones, and two clips differing only in their transform take the
same zoom for the same region.

Two limits were recorded rather than fixed, both older than this phase and
both now reachable through it. The instance **deadlocks somewhere past
forty open documents** — nothing closes one, there is no such tool — which
is four or five proof runs on one process; `tools/proof/README.md` measures
it and says to relaunch rather than read a hang as a failure. And on the
MCP path **a nested object inside a patch is decoded into a typed Swift
struct and re-serialised**, so a misspelt key inside one is DROPPED where
the core would have named it, and a known key the caller left out is sent
as its DEFAULT, which resets that field. `shadow` has behaved that way
since M3 and `obscure` inherits it; the core refuses both
(`deny_unknown_fields`, `core/tests/schema_v4.rs`), the agent's decoder
simply gets there first. `phase3_proof.py` prints it as a note beside the
checks rather than asserting it, since it is nobody's intended behaviour.

---

### Phase 4 — Words

*Two sessions. Schema v5 (`text.animation`). Captions in both directions,
and the text animations the spec promised.*

#### 4a. Auto captions

On-device speech recognition into caption clips, laid out exactly as the
SRT importer lays them out — a caption is an ordinary text clip, which is
what already makes burn-in free.

- `Transcriber.swift`: `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition = true` (gated on
  `supportsOnDeviceRecognition`; the language from the sheet), an
  `SFSpeechURLRecognitionRequest` over the media file, segments filtered to
  the clip's source window and mapped through `in` and `speed`. The
  callback API keeps the `async` rule intact (Phase 0's decision). When the
  deployment target reaches macOS 26, `SpeechAnalyzer` is the better
  engine and the swap is confined to this file.
- `NSSpeechRecognitionUsageDescription` in `project.yml`'s Info.plist
  properties, and `requestAuthorization` before the first run. An
  agent-driven app is never the active app, so the grant has to have been
  given once from the UI; the tool says so when it is missing.
- Cue building, shared with the importer as `CaptionLayout` (factored out
  of `CaptionImporter.swift`): ≤ 2 lines, ≤ 42 characters a line, ≤ 6 s a
  cue, at least one frame between cues; then the Caption preset on a track
  of their own, in one undo step (`applyEdit(_, ops)`).
- UI: File ▸ Generate Captions… → a sheet with language, scope (selection /
  in-out range / all), a progress bar and Cancel.
- MCP: `transcribe {clips?, language?, place?: bool = true}` → the cues,
  placed unless told not to. Off-main.

#### 4b. Caption export

`CaptionExporter.swift`: File ▸ Export Captions… picks a track (default:
the one whose clips are all text and which the importer or 4a made) and
writes `.srt` or `.vtt` — the same cues, a different header — with times
from ticks at millisecond precision. An imported SRT round-trips its cue
times exactly. MCP `export_captions {track?, path, format?: "srt" | "vtt"}`.

#### 4c. Text animations

**Schema.** `text.animation: null | { "kind": "typewriter" | "word_fade" |
"line_rise", "in": ticks, "out": ticks = 0 }` — reveal over `in` from the
clip's start, un-reveal over `out` before its end. `RC_FORMAT_VERSION` 5.

- Rust decides: `frame_recipe` gives the text layer a `reveal: f64` (0–1,
  with the direction) and the kind, computed from clip time, so an agent's
  `render_frame` and the export agree by construction. The recipe hash
  therefore changes per frame while animating; `LayerRenderers`' 64-entry
  LRU is enough for a one-second reveal at 60 fps.
- Swift draws it in `LayerRenderers.renderText`: the layout is always the
  FULL text's (the box must not reflow), and the reveal selects what is
  drawn — a glyph prefix (typewriter), per-word alpha with a stagger
  (word_fade), per-line rise and alpha (line_rise). The measured size the
  canvas overlay reads is the full text's.
- Inspector: a TextPane "Animation" section — kind popup, In, Out.

**Where.** `Transcriber.swift`, `CaptionLayout.swift`, `CaptionExporter.swift`,
`CaptionImporter.swift` (loses the layout it shares),
`TranscribeSheetController.swift`, `project.yml`; `model.rs`, `format.rs` +
header, `recipe.rs`, `LayerRenderers.swift`, `TextPane.swift`,
`AppDelegate.swift`, catalog and `AgentServer+Media.swift`;
`core/tests/schema_v5.rs`, recipe tests for `reveal`.

**Proof.**
- A fixture made with `say -o` and a known sentence transcribes to those
  words in order, each cue within ±0.3 s of where the word was spoken;
  Cancel leaves no clips.
- Import an SRT, export it: cue times identical; VTT differs only by header
  and separator.
- Typewriter at `reveal = 0.5` on a left-aligned single line has non-empty
  pixel columns only left of the midpoint; `reveal = 1` is byte-identical
  to no animation; the recipe at `clip.start + in` reports `reveal = 1`.

**What landed.** All three parts, at version 5, with the one schema key,
the two tools, the three drawing routines and every path into them — plus
the following, where the code differs from the plan above or settled what
it left open. Five of them matter enough to read before touching the area:

- **The recipe carries a THIRD computed key, `reveal_kind`**, which neither
  the plan above nor the phase's contract named. It is forced by the
  decision beside it: the recipe STRIPS `animation` out of the text
  description it hands over, because leaving it in would give
  `LayerRenderers` two accounts of the animation — the computed reveal
  (right) and the props (wrong, since nothing downstream has the clip time
  to evaluate them against) — and it is what keeps an unanimated clip's
  content hash byte-identical to what it was before version 5. With the
  description stripped, nothing else could say WHICH of three drawing
  routines to run: each kind is a different routine, not a parameter of a
  shared one. So a text layer's `source` object carries `reveal`,
  `reveal_phase` and `reveal_kind`, all three emitted unconditionally
  (`obscure`'s precedent: an absent key would mean two things), and the
  kind travels by NAME, so the recipe never depends on the enum's
  declaration order — which is why `TextAnimationKind`'s order, unlike
  `ObscureKind`'s, is not load-bearing.
- **Transcription reads EXTRACTED audio, not the media file.** The plan
  above assumes `SFSpeechURLRecognitionRequest` can read a project's
  `.mov`. Nothing in the framework's documentation promises it, its error
  vocabulary has a code for exactly that failure, and the question cannot
  be settled here: the grant needed to try it wants a frontmost app, which
  an agent-driven one never is. A design that works on the `say -o`
  fixtures and fails on every real clip is the worst failure shape
  available, so each job's SOURCE WINDOW is written to a temporary mono
  16 kHz WAV in `NSTemporaryDirectory()` — never in the package (spec
  §5.6) — and the recogniser is handed that. It pays twice besides: the
  work is bounded to what the timeline uses (a 20 s clip of a 30-minute
  recording is 20 seconds of recognition), and the mapping loses its `in`
  term entirely, becoming `clip.start + ticks(t) / speed`.
- **The four cue rules did NOT move into the shared layout.** The plan says
  they are "factored out of `CaptionImporter.swift`"; none of them was ever
  in that file. An SRT supplies its own line breaks, `text.width` does the
  wrapping at render time, and the importer bounds no cue's length — so
  moving them into `CaptionLayout` would have silently re-wrapped and
  re-timed every caption file that imports correctly today, and broken 4b's
  round trip outright. `CaptionLayout` therefore holds what the importer
  actually did (the frame grid, the collapsed-cue frame, the sort, the
  abutting trim, the drop-and-report, the new front-most track, the Caption
  preset) and the four rules live in `CaptionCues` beside it, called only
  by the producer that has to INVENT line breaks. The gap of at least one
  frame is the load-bearing one: it is what keeps the layout's trim pass
  from ever firing on a transcript, and a whole frame survives being
  snapped to the grid.
- **The one-minute ceiling is REPORTED, not worked around.**
  `SFSpeechRecognizer.h` says the framework stops tasks longer than a
  minute; the paragraph is written about the network service and nothing
  exempts on-device file recognition. Phase 4 does not chunk. When the last
  word lands more than two seconds before the end of the extract, the
  outcome carries a truncation with the second it stopped at, the sheet
  says so in words and the tool reports it under `truncated` with a note.
  A caption run that quietly stops at sixty seconds and says nothing is the
  failure this rule exists to prevent; chunking at the silences phase 3 can
  already find is the recorded follow-up, not this phase's work.
- **`transcribe` refuses the grant; the SHEET asks for it.**
  `SFSpeechRecognizer.authorizationStatus()` is a synchronous read, so the
  tool's refusal is instant and carries the fix — run File ▸ Generate
  Captions… once from the app — while `requestAuthorization` needs a
  frontmost app and would hold the handler open to its ceiling. It is
  `FFmpegRewrap.canAsk`'s question with `canAsk`'s answer. The ORDER of the
  handler's refusals is deliberate and is what makes the grant-less
  machine's behaviour provable: the caller's own mistakes (an id naming
  nothing, a scope with nothing audible) are answered first, then the
  grant, then the language — because a machine with no downloaded dictation
  models would otherwise answer "no languages" where the true answer is
  "you have not granted this yet".

And the smaller settlements, each argued where it lives:

- **No new op and no new Rust module.** 4c is carried by `set_text`'s
  patch and 4a places through `add_track` + `add_text_clip` as one grouped
  edit, so `OP_NAMES` is still 53 and spec §7.10's table needed no row.
  The reveal went into `recipe.rs` (331 → 567), which is now the file to
  weigh the next addition against.
- **`text.animation` has three keys and no curve.** The shape of the motion
  is already in the kind — a step per character, a stagger, a per-line
  offset — and easing between two arbitrary values is what the action
  system is for. A curve can be added later as a defaulted fourth key with
  no migration step, which is this crate's test for leaving a field out.
- **Overlapping phases degrade; they do not refuse.** With `in + out >
  duration` the reveal is the MINIMUM of the two ramps, so it stays in 0..1
  and a short clip simply shows a partial reveal. No range check bounds
  them against a clip: a range check is a fact about the vocabulary, and
  "these two numbers are too big for THIS clip" is a fact about a clip that
  a later trim could invalidate anyway. `props_check.rs` checks only the
  sign; the absurd values are caught where the reveal is CONSUMED.
- **Both halves measure against the CLIP's own duration**, never the
  instance's visible end — `layer()`'s existing rule for clip time — so a
  nest clip's edge cuts a nested caption off mid-reveal rather than making
  it un-reveal early, and one animation is measured on one clock.
- **The renderer gained a layout cache** (`LayerRenderers.layoutCache`,
  bounded like `sizeCache` and an order of magnitude tighter, since a
  `CTFrame` holds every glyph where a `CGSize` is two numbers).
  `renderText` used to build a SECOND framesetter over the string
  `measure` had already framed: two objects that had to agree, rebuilt on
  every frame of an animation. The key deliberately excludes the reveal, so
  "the reveal cannot reflow the layout" is structural rather than a rule —
  and `reveal = 1` is not merely equal to no animation, it takes the same
  single `CTFrameDraw`, which is what makes the byte-identity claim
  something other than a coincidence of the span machinery.
- **`word_fade` and `line_rise` reverse their stagger while LEAVING**, so
  the first word in is the first word out; reversing the amount alone would
  run the animation backwards and read as a rewind. That is what
  `reveal_phase` is carried for. The typewriter ignores the phase — its
  un-reveal is a shrinking prefix, which already IS the reverse of a
  growing one — and the backdrop stays at full opacity in every kind,
  because it is the readability plate rather than the words.
- **And because the stagger is what the phase names, `reveal_phase` is the
  ORDER the renderer draws in rather than a label on the amount** — which
  the review found, and which is now `Reveal::of`'s shape. The frame
  on which the phase turns is a frame on which the picture mirrors end for
  end, so it may only turn where the mirror is INVISIBLE, and the one
  amount at which it is, is 1. An animation that fits its clip has a
  plateau between its ramps to turn on, ties going to the arrival. A TENT
  does not: with `in + out > duration` the ramps cross BELOW 1, and the
  phase used to flip there, swapping a four-word cue's alphas from
  `[1, 1, .83, .33]` to `[.33, .83, 1, 1]` between two consecutive frames
  carrying the same reveal. A tent now keeps the phase it began in for the
  whole of its life — the arrival's, unless `in` is 0, which makes the clip
  nothing but a departure and leaves the stagger no arrival order to
  contradict. The limit that falls out of it is documented rather than
  fixed: a tent whose `in` is tiny but not zero reports `"in"` from its
  first frame to its last, while it is the departure holding the amount
  down. `the_phase_turns_only_where_both_orders_draw_the_same_picture`
  sweeps ten timings frame by frame and asserts the rule directly; a
  four-word `word_fade` is what it is written about.
- **`CaptionImporter` gained a refusal it did not have**: a file holding
  more captions than the project has room for is refused in the LAYOUT,
  naming the cue count and the room left, where `check_caps` would have
  refused it later with a message about clips that tells a caption user
  nothing. A transcript is refused the same way, by the same code.
- **The two tools went into a new `AgentServer+Captions.swift`**, not into
  `AgentServer+Media.swift` as the plan says — `AgentServer+Silence.swift`'s
  reason: neither is an op's mirror, both have a concern of their own, and
  the argument for how each is threaded belongs beside the code it
  explains. `transcribe` is in `offMainTools` (the Speech framework
  delivers its callbacks on an `OperationQueue` that defaults to the app's
  MAIN one, so a main-thread wait would deadlock as `import_media`'s probe
  would); `export_captions` is not, on `import_captions`' own argument in
  the opposite direction.
- **`srt` and `vtt` joined `AgentServer.replaceableExtensions`**, whose
  comment calls the set "the containers this app writes" — after 4b they
  are. Without them `export_captions {path: "talk.srt", format: "vtt"}`
  would have written `talk.srt.vtt`, the doubled name that set exists to
  prevent.
- **A cue's TIMES round-trip at every rate; the FILE is what needs a
  whole-millisecond frame.** Those are two claims and the phase first wrote
  them as one. `format_timecode` rounds ticks to the nearest millisecond,
  300 ticks at most, and `CaptionImporter.ticks(fromTimestamp:)` turns a
  whole millisecond back into exactly 600 × ms ticks — so the snap on the
  way back in is hunting for a frame boundary at most 300 ticks away, where
  half a frame is 10,000 ticks even at 30 fps. Every cue therefore lands on
  the tick it was written from, at 25, 30, 50 or 60 fps alike. What a
  whole-millisecond frame (25 and 50 fps) buys is byte identity with a file
  somebody ELSE wrote, and then only for a file whose times are already on
  the frame grid, since import snaps every cue to it and a 30 fps snap
  writes `00:00:04,120` back as `00:00:04,133`. The proof fixture is at 25
  fps for exactly that — its times are whole 40 ms frames, so the claim can
  be a byte comparison — and the SAME fixture is imported at 30 fps as the
  other half of it, where the file must not come back and a second trip
  through the grid must move nothing. A tolerance in place of the pair
  would have been a check that passes against a build where the exporter
  did nothing.
- **None of the three File-menu caption items takes a key equivalent.**
  §9's "proposed, not yet bound" table claims no row for phase 4, and a
  modifier-less menu key is resolved ahead of the first responder and would
  steal a letter the editor's own `keyDown` owns — the reason already
  recorded beside Remove Silences…
- **`model_props.rs` was left at 592** after `TextAnimation` and
  `TextAnimationKind`, under the 600-line cap but close enough to it to be
  the same warning phase 3 got — and this is where that warning was paid:
  phase 6 took the text vocabulary out to `core/src/model_text.rs` (252)
  before adding a field, so neither type named above lives in
  `model_props.rs` any more. What the cut bought is recorded in §0, along
  with what it did not. The text vocabulary was the obvious ~190-line concern to
  take out, the way `model_regions.rs` came out.
- **The offscreen harness now captures on SETTLE** — capture, spin,
  capture, write only when two consecutive captures are byte-identical. A
  fixed spin count is a guess about how long the last relayout takes, and
  this replaces the guess with the question's own answer. It is worth
  keeping on its own merits, and it is NOT what made `phase3_chrome.py`
  stop wobbling.
- **The wobble was an ambiguous constraint, and the fix is in the app.**
  The symptom was read correctly during the phase — the inspector's Actions
  pane sometimes at its intrinsic height and sometimes stretched, a render
  deterministic within a process and BISTABLE across processes, about two
  runs in five of `phase3_chrome.py` failing a check about something else —
  and the cause was guessed at wrongly: it was blamed on linking
  `Speech.framework`, and the settle capture was landed as the cure. It was
  not one. A settle waits for a layout that is still moving; both of these
  layouts had stopped. At the gate `phase3_chrome.py` still scored 29, 30,
  31 or 33 out of 33 on identical input, twelve harness renders of one
  package still gave two distinct PNGs (nine one way, three the other), and
  `SWIFT_DETERMINISTIC_HASHING=1` changed nothing. The real cause is in
  `InspectorPane.swift`: the pane's bottom pin was `.defaultLow` and an
  `InspectorSection` sets no hugging priority, so it keeps the default 250
  — a dead tie, in which "give the pane its content's height" and "stretch
  one section past its rows" cost the solver exactly the same and nothing
  chose between them. Dropping the pin to 249 makes the stretch strictly
  dearer, which is what the constraint's own comment always meant. Measured
  after: twelve identical renders out of twelve, and `phase3_chrome.py`
  33/33 five runs running. The lesson is the one the road map keeps
  relearning — a fix that is not measured against the symptom is a guess
  wearing a fix's clothes, and this one shipped a real improvement to the
  harness while leaving the defect it named untouched.
- **A section is not a section until `ClipPane.makeSections()` calls it.**
  `TextPane.animationSection` was written, documented and mirrored, and
  invisible in the app until the wiring was added after the gate — the
  second consecutive phase in which a pane's new group was defined and not
  called (`VideoPane.obscureSection` was phase 3's). Nothing type-checks
  the omission, so adding a section is two edits and the second is in
  another file. Recorded in app/CLAUDE.md as a pitfall.

Two limits worth knowing before chasing them, neither introduced here:
`animation` is a nested OBJECT in a patch, so it inherits the MCP
decoder's replacement rule — a key left out of it comes back as
`TextAnimation`'s default 1 s typewriter, not as what the clip had, which
is why the catalog's text-patch sentence says to send all three; and an
action's end patch can interpolate `in` and `out`, sliding an animation's
own timebase mid-reveal, which is legal, rarely wanted, and a caution
rather than a rule the ops enforce — where two animations naming DIFFERENT
kinds hold and switch whole at the end instead, §5.4's object rule.

**Proved** on 2026-09-08. Core: `make test` **358 passed / 0 failed** — 338
before, plus `core/tests/schema_v5.rs` (11) and nine recipe tests in
`evaluate_tests.rs`; `model_tests.rs`'s fixture grew the key and no test.
`make lint` and `cargo fmt --check` clean, `make typecheck` 0 errors and
the same 4 AVFoundation deprecation warnings, `make app` building, the
catalog at **70 tools** (53 ops, unchanged, plus seventeen app-state
tools) and the startup parity log EMPTY.

Honesty first about 4a: transcription needs a TCC grant a headless run
cannot obtain, so the proof asserts what it CAN. Without the grant,
`transcribe` refuses with the exact authorization message and places
nothing — that refusal is itself a check, and it is why the handler
answers the caller's own mistakes before it looks at the grant.

The cue BUILDER's rules are pure arithmetic over a word list, so they need
no recogniser and no grant — but for a while nothing ran them, and the
documents said otherwise. `CaptionCues` is Swift, and in the app nothing
reaches it until a recogniser has produced words, so the MCP proof cannot
call it at all. The one binary in the tree that links `app/Sources` outside
the app is the offscreen HARNESS, which is why the rules are proved there:
`tools/proof/harness/` grew a second mode (`harness cues <words.json>
<out.json>`, ADDED beside the render arguments rather than rearranging
them, so every earlier chrome script's argument positions still hold), and
`phase4_chrome.py`'s section 8 asserts the four rules over its answer at
their BOUNDARIES — a word longer than a line, a list of one word, a pause
longer than a cue may be, two words at the same instant, a line of exactly
42 characters, a cue of exactly 6 s, and the frame of gap surviving the
snap to the grid at two rates and five offsets from it — plus that every
word comes back once and none is invented, which all four rules together
would not catch. That section is not a picture, and it says so: it is in a
chrome script because the harness is, and it changes no render argument.

A fixture is at `tools/proof/media/speech.mov` — 5.2 s, a navy card over
`say`'s rendering of "The quick brown fox jumps over the lazy dog. Pack my
box with five dozen liquor jugs." — for the person who runs it with the
grant.

The phase's own scripts go beside the earlier phases' —
`tools/proof/phase4_proof.py` over MCP at **84/84**, and
`phase4_chrome.py` offscreen at **59/59**: the Animation section in the
Clip tab, its summary and its three rows, that a text animation changes
nothing else in the window, and section 8's cue builder. Nothing about the
PICTURE is claimed there — the preview well renders black offscreen, so no
reveal can be photographed. The earlier phases re-ran unchanged at
`phase1_proof.py` **66/66**,
`phase2_proof.py` **85/85**, `phase2_chrome.py` **26/26**,
`phase3_proof.py` **121/121**, `phase3_silence_scope.py` **8/8** and
`phase3_chrome.py` **33/33**.

Still owed by a person at the machine — the half no headless run reaches:
(1) File ▸ Generate Captions… with the grant given: the language popup
lists only on-device languages, the scope rows match the selection and the
range, the card turns into its own progress bar, Cancel leaves no clips,
and a clip whose speech runs past a minute says where it stopped;
(2) the three reveals in MOTION at 60 fps rather than as still frames —
the texture cache is keyed per reveal, so what a person is checking is that
playback does not stutter or freeze on a caption track;
(3) that a generated caption is legible over real footage in the Caption
preset, which is a judgement about type and not about pixels.

**Reviewed, and twelve findings fixed.** The change was then read by eight
readers, each with its own brief, who returned 27 findings; every one was
put to three sceptics told to refute it, and twelve survived. All twelve
were fixed, each now covered by a test or a proof check that fails without
the fix wherever one can be written. The nine worth reading before touching
the area:

1. **A tent's `reveal_phase` FLIPPED between two frames carrying the same
   reveal.** The word was written as a label on the AMOUNT — which ramp is
   holding it back — and `word_fade` and `line_rise` count their stagger
   from the other end while a layer is leaving, so the frame the phase
   turns on is a frame the picture mirrors on. Where the ramps meet at 1
   that mirror is invisible; where `in + out > duration` they cross BELOW
   1 and it is a visible jump with no change in the reveal behind it.
   `Reveal::of` now makes the phase the ORDER the renderer draws in and a
   tent keeps the one it began in — the settlement above states the rule
   and the limit that comes with it, and
   `the_phase_turns_only_where_both_orders_draw_the_same_picture` sweeps
   ten timings frame by frame, three of which are tents whose ramps cross
   on the way through and none of which the old rule survives.
2. **An outlined glyph at a partial alpha composited its fill and its
   stroke SEPARATELY.** `attributedString` sets a NEGATIVE `.strokeWidth`,
   which is Core Text's spelling of "fill and stroke", and
   `CGContext.setAlpha` applies to each of those two draws; the inner half
   of the stroke lands on ink the fill has already laid down, so at a
   reveal of 0.5 the outline sat at 0.75 and a black outline on a white
   word read as a heavy grey halo for the whole ramp, snapping to a crisp
   edge only at 1. Nothing before this phase could see it, because a text
   texture had only ever been faded WHOLE, in the shader, where the
   per-clip opacity meets the FINISHED pixels once. A partial line now
   draws inside a transparency layer, which is that same "once"; an opaque
   line skips it and takes the plain draw. The proof measures an outlined
   word whose outline is the canvas's own background colour, so a correct
   fade inks nothing the finished word does not — and the check would pass
   against a build that dropped the outline entirely, which is why it is
   paired with one that says the outline is there.
3. **One clip's failed extraction threw the whole transcription away.** A
   run is a LIST of clips and the extraction of any one of them can fail on
   a file whose audio track is shorter than its picture — which screen and
   phone recordings routinely are, trimmed into the tail where only
   pictures are left. Throwing there discarded every cue the earlier clips
   had already produced and named only the clip that failed: minutes of
   somebody's compute lost to one bad tail. A job's failure is now that
   job's problem, reported under `problems` with the run carrying on, and
   an empty run tells "no speech was recognised" apart from "the audio
   could not be read", because only one of those is a claim about the
   speaking. Cancellation stays a real throw: it means place nothing.
4. **Generate Captions transcribed a clip whose audio is switched OFF**, so
   Detach Audio doubled every caption. "Has sound" was asked of the MEDIA,
   and `enabled.audio` is the other half of the question — `audio.rs` gives
   such a clip no voice at all, so the timeline plays nothing for it. Detach
   leaves the picture clip with `enabled.audio` false and puts an
   audio-only twin with the SAME media, `in`, `start` and `speed` on the
   track below, so the ordinary way of getting at a recording's sound made
   the recogniser hear it twice, place two identical cues at one time, and
   then report the pile-up it had made as captions that had to be
   shortened. A clip with its audio off is now skipped with a reason.
5. **`NSPopUpButton.addItem(withTitle:)` REMOVES an existing row with the
   same title** before adding the new one — measured: three rows, two of
   them reading alike, come back as two. The Export Captions panel indexed
   its popup by `indexOfSelectedItem`, so two caption tracks a person had
   renamed alike (`edit_track.rs` accepts any name) would have written a
   DIFFERENT track's captions and reported the write as a success. The rows
   carry the track id in `representedObject` now, and `Candidate.menuTitle`
   spells the id into the title as well, so nothing is dropped and nothing
   is ambiguous to read.
6. **`add_text_clip` was the one text-patch door that never ran
   `checkTextEnums`.** `TextAnimationKind` decodes leniently on the Swift
   side and `patchArg`'s round-trip guard cannot see inside a `T??` field,
   so `{"animation": {"kind": "fade"}}` reached the core as a TYPEWRITER
   and the caller was told the clip they asked for had been made. It is the
   same hole `checkVideoEnums` closes for a filter, a spotlight and an
   obscure region, at the one door a text patch has besides `set_text` —
   and the check runs on the RAW object, since the decoded patch is where
   the misspelling has already become a typewriter.
7. **A misspelled language tag was answered with the grant.** Every
   `language` argument alike fell through to the authorization refusal on a
   machine with no grant, and to "this Mac has no model for that" on one
   with it — so a caller whose only problem was a typo was sent off to
   System Settings to download a language they may already have had. The question is two questions with two different
   fixes, and they are now asked on either side of the grant: whether the
   framework knows the tag at all is a model question, reads the same at
   every authorization status and is answered FIRST, with the tags it does
   know listed; whether this Mac has the on-device MODEL is a question
   about downloads and is asked after. The ordering is also what makes the
   grant-less refusals provable, which is the only part of `transcribe` a
   headless run reaches at all.
8. **`export_captions`' own description had the round-trip arithmetic
   backwards**, telling an agent a cue "can come back a frame away" at
   30 fps and so talking a caller out of a round trip that is in fact
   exact. The re-derivation is the settlement above; the tool now says that
   the TIMES survive at every ordinary rate and that the FILE is what needs
   a whole-millisecond frame, and `phase4_proof.py` checks the description
   against what its own 4b section measures, so the two cannot drift apart
   again.
9. **A check in the phase's own proof could not fail.** The `word_fade` and
   `line_rise` "half way through, it is neither the static frame nor the
   empty one" checks took their empty frame off the CLEARED clip, whose
   reveal is 1 at every t (`Reveal::WHOLE`) — so the blank was the
   fully-drawn frame and the check was one comparison written twice. Each
   kind's blank is now taken at reveal 0 with its animation SET, and the
   fact that the blank is flat and is not the static frame is itself
   asserted. A proof's own vacuity is the failure that costs a score its
   meaning, which is why it is listed with the code.

The rest were smaller and each is argued where it lives.

#### #36 — the canvas text editor grows as you type (2026-09-24)

kpgalligan/reelcut#36: typing into a text clip's in-canvas editor (the
double-click `NSTextView` of spec §4.2) wrapped the text inside a frame
that never changed, and the box jumped to its real size on commit. The
editor's frame was set once, from the box the clip had when editing began
(`editorFrame(for:)`), and again only when the canvas laid out; the text
view's own vertical resizing grew it DOWNWARD from the old corner as the
text wrapped.

**What landed.** `app/Sources/PreviewCanvasView+TextEditFrame.swift` (new):
`fitTextEditor(_:to:)` sizes the editor from `LayerRenderers.measuredSize`
over the clip's text with the typed string in place of its content, placed
by `canvasRect` exactly as `CanvasLayerBox.uncroppedRect` places it — the
measurement that sizes the box after apply, not a second one — with the
2-canvas-pixel margin the editor always had. Both resizable flags are off,
so the frame is the only authority; the wrap width follows the frame, less
a container inset of those 2 canvas pixels in view points and a
line-fragment padding of `LayerRenderers.textInsets` (the backdrop's
padding, the outline's overshoot) at the box's scale, which leaves exactly
the width CoreText lays the text in. `PreviewCanvasView.swift` (frozen)
keeps the wiring: `CanvasTextView` gains `onChange`, called from
`didChangeText` (every typed, pasted or deleted change); `beginTextEditing`
fits once, and `refitTextEditor()` — called from `onChange` and from
`layoutCanvas`, which used to reassign `editorFrame(for:)` (gone) — refits,
and reassigns the editor's font at the canvas's current scale, so a zoom
or a resize mid-edit rescales the glyphs with the wrap width (review nit 3;
unmeasured — no probe row zooms mid-edit). Key handling is untouched
(#37 owns Return and Esc). No core change, no FFI, no MCP mirror: the
committed op is the `set_text` it always was.

**Deviations.** Two, both inside the one function. (1) The container inset
was a fixed 2 pt; measured, with it an auto-sized "Hello " wrapped to two
lines inside a frame that was exactly its applied box, because the frame's
margin is 2 CANVAS pixels (about 1.2 pt at the probe's zoom) and the inset
took 2 pt back. It is now `2 × canvasScale`. (2) The 60 × 24 pt floor is
kept and still hung from the box's top, but widened from the edge the text
is ALIGNED to — the left edge for left, the right for right, about the
centre for centre — so a string shorter than the floor starts where it
renders. (The first cut centred the floor on both axes; the review found
that started a short left-aligned string (60 − w) / 2 pt early and a tiny
one (24 − h) / 2 pt high, and T3 below is the row that catches it: it
failed, 14/15, with the centred floor put back.) Right- and centre-aligned
strings under the floor are not measured.

**Measured.** `tools/proof/text_edit_proof.py` over its probe
`text_edit_probe.swift`, in the app's own window: **15/15** on the fix, exit
0. T3 opens the editor over "Hi", 12 px, auto-sized and left-aligned (a box
9.6 × 12.6 pt with its margin, under the floor — a CONTROL) and finds the
editor's frame hung from the box's top-left, 0.25 pt off against a 1 pt
tolerance; both T3 rows pass on the baseline too, which hung its floor from
that corner. T1 types " world, and more" after "Hello" (auto-sized, centred) and T2
" a longer sentence that must wrap twice" after "Wrap me" (700 px wide,
left, a 24 px backdrop), one key event at a time through `sendEvent`; each
typed prefix is then applied through the canvas's `onEdit` and the box the
canvas draws is compared. Worst frame deviation 0.00 pt over 16 keys (T1)
and 39 keys (T2), against a stated tolerance of 1 pt; the editor's line
count equals CoreText's at every key on both. CONTROLS, passing on both
trees: the font resolves, every key reached the editor, every prefix
applied, and the applied box moved (T1 218 → 916 px wide on one line; T2
185 → 593 px tall, four lines). `--baseline fe5fe0d` (`git archive`,
`-D HARNESS_REFERENCE_BUILD`, nothing compiled out) fails EXACTLY the four
fix rows and exits 0: worst deviation 493.06 pt (T1, the editor 134 pt
wide and 578 pt tall against a 553 pt-wide one-line box) and 122.61 pt
(T2); 16 of 16 T1 prefixes shown on more lines than rendered, and 13 of 39
T2 prefixes on a different count (each of the four printed on fewer). The probe registers `app/Resources/Fonts` itself:
without them the editor's `NSFont` and CoreText fall back to DIFFERENT
faces and their line breaks part — measured, one T2 row failed on the fix
for that reason alone before the fonts were registered.

**Limits, not fixed.** The editor still shows the text AS WRITTEN in the
clip's face at `size × scale`, clamped 8–300 pt, with no tracking and no
line spacing — its pre-existing font rule, kept as the issue asked. So its
FRAME is always the applied box, but its line breaks can differ from the
render for an UPPERCASE (`case`) text, a non-zero `tracking`, a
`line_spacing` other than 1, or a zoom that hits the clamp; and a rotated
clip still edits in an axis-aligned frame. Input-method composition
(marked text) is not measured. **Owed:** the look at the machine,
`designs/reelcut-remaining.md` §4. `app/CLAUDE.md`'s Canvas map entry
("frozen, 1121 lines") is now 1133 and does not name the new file — for the
orchestrator, which edits the CLAUDE.md files.

#### #37 — Return applies in the canvas text editor; Esc asks (2026-09-24)

kpgalligan/reelcut#37: in the in-canvas text editor a plain Return inserted
a newline and only ⌘Return applied, so the obvious key never left the
editor; Esc threw a changed string away without a word. Spec §11 K-2 is the
decision, written before the code, with §4.2's Text bullet and two §9 rows.

**What landed.** `app/Sources/PreviewCanvasView+TextEditKeys.swift` (new,
73): `TextEditKeyRoute` and the pure `TextEditKey.route(_:hasMarkedText:)`
— a key-down of Return (36) or keypad Enter (76) with none of ⇧ ⌘ ⌥ ⌃ is
`.apply` (⇪, fn and the keypad flag ignored), with any of them `.newline`,
Esc (53) `.escape`, anything else, a key-up or any key while an input
method holds marked text `nil` — and `PreviewCanvasView.escapeTextEditing()`:
an unchanged string (or no window) cancels at once; a changed one suspends
the editor's blur-commit and puts up an `NSAlert` sheet, "Apply your
changes to this text?", buttons added Apply (first, the default), Revert,
Cancel (its `keyEquivalent` set to Esc explicitly). The completion, guarded
by `textEditor === editor`, applies through `cancelTextEditing()` and then
`onGroupedEdit` (a sheet completion is not an AppKit event — app/CLAUDE.md's
undo pitfall), reverts through `cancelTextEditing()`, or on Cancel (and any
other response) restores the blur-commit and puts the caret back.
`PreviewCanvasView.swift` (frozen) **1133 → 1132**, wiring only:
`textEditor` is `private(set)`, `onGroupedEdit` sits beside `onEdit`,
`CanvasTextView.onCancel` is `onEscape` and is wired to
`escapeTextEditing()`, `keyDown` is a four-arm switch over the route
(`.newline` is `insertNewline(nil)`, so ⌃Return no longer inserts AppKit's
U+2028), and the class doc says so. `EditorViewController+Canvas.swift`
gains the one forward `onGroupedEdit → document.performGroupedEdit`. No
core change, no FFI, no MCP mirror: `set_text` is the apply, as before.

**Deviations.** One, in the probe, none in the product. The spec's A8 row
read Apply's `keyEquivalent == "\r"`; measured on macOS 26, `NSAlert`'s
first button (an `_NSAlertButton` over a hosting view) has an EMPTY
`keyEquivalent` and is instead the panel's `defaultButtonCell`, which is
what Return presses. A8 reads `sheet.defaultButtonCell === apply.cell`;
Cancel's key equivalent is read as specified (`"\u{1b}"`, set by the
product). A Return could not be DRIVEN into the sheet to prove the press:
under `.prohibited` the sheet never becomes key, and a Return sent through
its `sendEvent`, `NSApp.sendEvent`, `performKeyEquivalent` or `keyDown`
pressed nothing (measured, each one). The buttons are pressed with
`performClick`. A K1 row for fn Return and one for Esc with marked text
were added beside the spec's list.

**Measured.** `tools/proof/text_apply_proof.py` over its probe
`text_apply_probe.swift`: **27/27**, exit 0 — two structural checks, 13 K1
route rows, A0–A11 in the app's own window over one text clip "Hello".
A1: "!" then Return → content "Hello!", editor gone, `canUndo` false → true,
one `undo()` → "Hello", `canUndo` false. A2: Return unchanged → editor gone,
no undo step. A3–A6: ⇧/⌘/⌥/⌃Return → the editor open with "Hello\n". A7
(CONTROL): Esc unchanged → editor gone, no sheet. A8: "!" then Esc → a sheet
with Apply, Revert, Cancel, Apply the default button, Cancel on Esc. A9:
Cancel → sheet gone, editor open with "Hello!", the field first responder,
a typed "?" lands ("Hello!?"). A10: Revert → editor gone, "Hello", no undo
step. A11: Apply → editor gone, "Hello!", one undo step. A0 (CONTROL): the
editor opens as first responder. `--baseline 6e2c7da` (K1 compiled out)
fails EXACTLY A1, A2, A4, A6, A8, A9, A10, A11 and exits 0, as predicted:
A1 left the editor open with "Hello!\n", A2 with "Hello\n", A4's ⌘Return
committed and closed the editor, A6's ⌃Return inserted U+2028, and A8–A11
found no sheet (Esc cancelled). A3 (⇧Return) and A5 (⌥Return) PASSED on the
baseline — AppKit's own `insertNewline:` / `insertNewlineIgnoringFieldEditor:`
already put "\n" there. `text_edit_proof.py` 15/15 and
`space_key_proof.py` 28/28 after the change.

**Limits, not fixed.** Return and Esc pressing the sheet's buttons from the
keyboard are READ (the default button cell, Cancel's key equivalent), not
driven — see Deviations; the look at the machine is
`designs/reelcut-remaining.md` §4. Input-method composition is covered by
the route's K1 rows only (marked text → not routed); no composition was
driven. No `--mutant` mode: that Apply goes through `performGroupedEdit`
rather than `applyEdit` is read in the code, not caught by a row. The Text
tab's `InspectorTextArea` keeps its own keys (Return a newline, ⌘Return a
commit), as K-2 records. **Owed:** the §4 look at the machine. `app/CLAUDE.md`'s Canvas map entry
now names `PreviewCanvasView+TextEditKeys.swift` and the frozen file's new
count (1132) — applied by the orchestrator after review (verdict pass, one
prose nit, also applied).

---

### Phase 5 — Sound

*One to two sessions. No project-schema change — mono already persists,
and the export additions live in the core's export table, not the file.*

- **Mix to mono.** `AudioProps.mono` is in the schema and ignored. Fold
  L+R → (L+R)/2 on both channels in the `AudioDSP` chain, so a track whose
  clips ask for it gets a tap and one that does not stays bit-identical.
  Default false, so no existing project changes sound.
- **Meters.** A second, read-only `MTAudioProcessingTap` per composition
  track created with `kMTAudioProcessingTapCreationFlag_PostEffects` (the
  DSP tap is `PreEffects`, ahead of the fader, and cannot see the mix
  level), publishing peak and RMS per channel at ~30 Hz to a `LevelMeter`
  model. The per-track peaks are summed for display — honest enough for a
  meter, and the writer measures the true mix on export. Placement: a
  two-channel meter at the right end of the timeline bar (the bar already
  holds the view-of-timeline controls; the toolbar keeps its four things)
  — decide in-phase against the design handoff's metrics.
- **Normalise clip.** An Audio-section button: the clip's peak over its
  source window from the peaks cache → `volume` that puts it at −1 dBFS
  (clamped to the model's 4×) → `set_audio`. MCP `normalize_clip {clips,
  peak_db?: -1}` as the composite's mirror.
- **Loudness on export.** `Loudness.swift`: BS.1770-4 integrated loudness
  (K-weighting, 400 ms blocks, −70 LUFS absolute and −10 LU relative gates)
  and true peak at 4× oversampling — about two hundred lines, checked
  against a reference tone. The export sheet gains "Loudness: Off /
  −14 LUFS (streaming) / −16 / −23 (broadcast) / Custom" and a −1 dBTP
  ceiling; the export is then two passes — measure the mix, then write with
  the gain `target − measured`, capped so true peak stays under the ceiling
  (gain only; the sheet says "no limiter"). The gain applies in
  `ExportWriter`'s audio path — export-only by definition, so the
  preview/export tap-sharing rule is not touched. Core:
  `export_settings` gains `loudness_lufs` and `peak_dbtp` overrides,
  validated like the bitrates and echoed in the resolved settings; the
  `export` tool takes the same keys. The final progress line reports
  "Peak −1.0 dBTP · −14.0 LUFS" on every export, normalised or not.
- **WAV and AIFF.** Two rows in `export.rs` — `audio_wav`, `audio_aiff`,
  LPCM 16- or 24-bit — with `audio_m4a`'s size rows; `ExportWriter` already
  writes LPCM for ProRes and needs only the file type.

**Where.** `AudioDSP.swift`, `AudioTap.swift`, `LevelMeter.swift` (model +
view), `Loudness.swift`, `ExporterWriter.swift`, `Exporter.swift` (the
two-pass pipeline), `ExportSheetController.swift`, `AudioPane.swift`,
`TimelineBar.swift`, `export.rs`, `ReelCore.swift` (`ExportSettings`),
`AgentServer+Render.swift`, catalog; `core/tests/export.rs` additions.

**Proof.**
- A mono export's left channel equals its right sample-for-sample; with
  `mono` off the export is byte-identical to before this phase.
- The meter reads −20 dBFS ±0.5 dB on a −20 dBFS tone.
- `Loudness.swift` measures the EBU reference fixture within ±0.1 LU; a
  normalised export lands within ±0.5 LU of the target and its true peak
  never exceeds the ceiling; with Loudness off the export is byte-identical
  to a pre-phase export of the same project (the known duck-edge
  non-determinism means: a fixture without a duck).
- `ffprobe` reports 48 kHz PCM for the WAV and AIFF rows.
- Normalise clip leaves the clip's peak at −1 dBFS ±0.1 in an export.

**What landed.** All five parts, with no project-schema change (version 5
stands; `mono` had been in the file since M1 and ignored), NO new op
(`OP_NAMES` is still 53), one new tool (`normalize_clip`, so the catalog is
71), two new preset rows and two new export overrides — plus the following,
where the code differs from the plan above or settled what it left open.
The first one is the phase's headline and is not a detail:

- **The road map's meter cannot be built, and this is what replaced it.**
  It asks for "a second, read-only `MTAudioProcessingTap` per composition
  track created with `kMTAudioProcessingTapCreationFlag_PostEffects` (the
  DSP tap is `PreEffects`, ahead of the fader, and cannot see the mix
  level)". The diagnosis is right and the remedy does not exist.
  `AVMutableAudioMixInputParameters` has exactly ONE `audioTapProcessor`,
  and `MTAudioProcessingTap.h` requires that either the PreEffects or the
  PostEffects creation flag be set and not both — so a track already
  carrying the DSP tap cannot carry a second one, and there is no other
  attachment point on an audio mix input. The two ways out both cost more
  than the meter is worth: moving the DSP tap to PostEffects would put the
  compressor BEHIND the fader and change how every existing project with a
  compressor sounds (spec §4.3 documents the channel-strip order as a
  promise, not an implementation detail), and giving the meter a second
  composition of its own would mean a second decode running beside
  playback for a 12 pt bar.
  **So the meter reads the tap that already exists and multiplies by the
  plan's envelope.** The tap is PreEffects and sees the samples before
  volume, the fades and ducking; the envelope at that tick is exactly what
  `CompositionBuilder` hands AVFoundation as volume ramps. The displayed
  number is therefore COMPUTED rather than observed — and it is exact
  rather than approximate, which is the part worth being clear about: the
  ramps multiplied in are the same ramps AVFoundation is applying to the
  same samples, so this is not an estimate standing in for a measurement.
  It is also not a new idea in this app: `SilenceDetector` (phase 3)
  already established the rule that a peak is pre-fader and the level you
  want is peak × envelope, and `audio.rs` expresses mute and solo as a ZERO
  envelope, so a muted or soloed-out track reads silent on the meter for
  free and with no second Swift copy of `silenced`. What it costs is one
  honest limit, recorded rather than hidden: anything AVFoundation does to
  the mix DOWNSTREAM of the ramps — the sum of several tracks into one
  output, any headroom the mixer itself applies — is not in the number, so
  the meter is the sum of the tracks rather than a measurement of the
  device. The writer measures the true mix on export, which is 5d's job,
  and that is the second reason 5d reports on every export.
  Say all of this where the meter is built; `LevelMeter.swift`'s header
  does, at length, because the next reader will otherwise "fix" it back
  toward a tap that cannot be created.
- **Metering is a PLAYBACK build alone.** `CompositionBuilder.build` gained
  `metering: Bool = false`, passed true by `Playback.startRebuild` and by
  nothing else. Two consequences, both wanted: every export and every
  `render_frame` builds exactly the audio path it built before the meter
  existed, which is what lets 5a's byte-identity claim be about the mono
  fold and nothing else; and a metering build taps EVERY audio track,
  including the inert ones that carry no tap today, because a meter that
  lights only on the tracks that happen to carry a compressor is worse than
  no meter. The 30 Hz push is a run-loop `Timer` armed and disarmed by the
  rate KVO — not the periodic time observer, which fires only while time is
  MOVING and would freeze a meter at its last lit value the moment playback
  stopped instead of letting it fall to silence.
- **The meter goes left of the zoom cluster, not last, and carries no
  divider** — and both are arithmetic rather than taste. Placing it after
  S/M/L would shift the zoom cluster and the size control 130-odd points
  left, and both are two phases of muscle memory old; here the meter takes
  the existing spacer's own priority-1 hugging and absorbs slack up to a
  cap, so nothing that shipped moves at any window width. The divider is
  refused because the row's fixed content measures 880 pt against a 900 pt
  minimum window: one more stack gap makes 892 and a divider's second gap
  plus its hairline makes 905, which is broken constraints at the minimum
  window that nothing in this project asserts on and no proof would catch.
  Starved below 40 pt the meter draws NOTHING rather than a scale nobody
  can read — `TimelineSelectionBlock`'s own `guard textWidth > 8`.
- **The model publishes a raw measurement; the view owns the ballistics**,
  which is what lets the phase's proof assert on a NUMBER rather than
  photograph a window — the harness has no player, so a pixel claim about a
  live meter is not available at all. It also decided what the meter does
  NOT get this phase: no numeric readout, no tooltip, no View-menu toggle
  and no persisted key, each of which costs width, tracking-area churn, a
  spec §9 row or a defaults key the harness would have to pin. What it does
  get is one resting appearance, always drawn, with no free-running
  animation — the 30 Hz tick starts on a non-silent reading and invalidates
  itself once everything has fallen to the floor — because the harness
  writes a PNG only when two consecutive captures agree and anything that
  animated for ever would hang the instrument.
- **The app's first `import Synchronization`, and it is confined.**
  `LevelMeterSink.publish` runs inside the tap's process callback on
  AVPlayer's real-time render thread, where `AudioDSP.swift`'s stated
  discipline holds: nothing locks and nothing allocates. A lock can block
  on a lower-priority thread that holds it and a `main.async` allocates,
  and both fail the same way — an occasional glitch nobody can reproduce.
  So the sink is two 64-bit words written and read with relaxed atomic
  stores: wait-free, no allocation, no ordering the render thread waits on.
  Every other cross-thread value in `app/Sources` stays an `NSLock` or a
  main hop, and the exception is recorded in app/CLAUDE.md beside `async`
  being confined to `MediaImporter.swift`, because it is the same class of
  rule.
- **The mono fold goes after the compressor and BEFORE the pan**, and the
  order is forced. After a pan the fold is algebraically self-cancelling —
  `(g_L·x + g_R·x)/2 = ((g_L+g_R)/2)·x` — so the pan would silently
  degrade into a gain change and the control would read as broken. It sits
  after the noise reducer and the compressor because the chain is
  documented as a channel strip acting on the source as recorded, and
  because that makes `AudioPane`'s Mix section (which holds `mono` and
  `pan` together) literally the DSP order, which the pane already claims
  for the other three. It averages EVERY channel into all of them with an
  early return below two — the guard the pan already uses, and for the same
  reason: the tap is handed the composition track's channel count, so a 5.1
  source gives 6 and folding only 0 and 1 would produce something that is
  neither mono nor the original.
- **Two documents were half-true until this landed.** A pan on a
  mono-folded clip is a TRUE pan rather than a balance, which is the honest
  description and arguably the better behaviour (spec §4.3 says so now);
  and spec §7.2's sentence calling `mono` "a per-segment flag Swift applies
  with `AVMutableAudioMixInputParameters` where possible" described
  something that API cannot do — it applies gain over time and cannot
  combine channels — while the plan carried no such flag either. `mono`
  rides `AudioClipDSP` beside pan, the compressor and noise reduction,
  keyed by clip id, and the rebuild it needs comes free because `Playback`
  already treats a different `audioDSP` as structural.
- **Normalise REPLACES `audio.volume` and always writes BASE props.** The
  peaks cache is pre-fader, so the measured peak knows nothing about the
  clip's current volume; multiplying would compound every previous press,
  where replacing makes the command idempotent (a second press comes back
  as "made no change", which is that working). And it writes the base level
  even when the playhead is inside an action, unlike every other control in
  the inspector, because normalise is a statement about the WHOLE clip
  rather than about one instant — honouring the playhead would make one
  button mean two things depending on where the head happened to be. The
  limit is recorded rather than fixed: a clip whose volume is animated is
  normalised underneath and then overridden for the action's span, and both
  the tooltip and the tool description say so. `muted` is left alone — a
  mute is a switch, not a level — and each clip of a selection gets its own
  gain, because matching levels ACROSS a selection is a different feature
  and should be asked for by that name.
- **The source window comes from the PLAN segment, and that is one test
  doing the work of six.** It is the window that actually plays, already
  clamped to the file and speed-resolved, and "there is no audio segment
  for this clip" correctly refuses every case that should be refused: no
  media, missing media, media with no audio track, `enabled.audio` false
  anywhere up the chain, a still, and a clip inside a nest (whose segment
  is named by the INNER id, which no op could address anyway). Deriving the
  window from the clip snapshot would have needed five separate guards to
  reach the same place and would have got the reversed and missing-media
  cases subtly wrong. The other refusals are by NAME and per job: a clip
  whose peaks are not on disk yet is never normalised against a missing
  cache, a peak of exactly 0 is silence rather than something quiet, and in
  a multi-clip call one job's failure is one job's problem — the rest are
  normalised and the failures come back under `skipped`, `transcribe`'s
  posture. The 4× clamp still applies, so a clip peaking below about
  −13 dBFS cannot reach −1: it is normalised as loud as it goes and the
  result reports where it landed, because refusing would be worse than
  doing the thing and doing it silently would be worse than saying so.
- **The loudness measurement runs on EVERY export that has sound, and that
  doubles an audio-only export's wall time.** The road map asked for it
  outright — "the final progress line reports 'Peak −1.0 dBTP ·
  −14.0 LUFS' on every export, normalised or not" — and it is worth
  writing down as a decision rather than leaving it to be discovered by
  someone timing an
  M4A. Reporting what actually ran is `detect_silence`'s posture and is
  what makes the ±0.5 LU claim checkable over MCP at all; the alternative,
  echoing back the target that was requested, is not a measurement. The
  price is one extra decode of the mix: about a tenth of a picture export's
  wall time (`measureShare` 0.1), and roughly a doubling of an audio-only
  one's (0.5), which is why the progress sheet says "Measuring loudness…"
  through pass 1 rather than sitting at 0 under a label claiming it is
  writing. GIF and APNG measure nothing — those containers hold no audio
  track, the same fact the core reports as `audio: false`.
- **The measurement builds its own composition and reads FLOAT.** An
  `AVAudioMix` copy shares the `MTAudioProcessingTap` its input parameters
  hold, and a tap carries per-instance state (the compressor's envelope,
  the noise reducer's delay line), so two readers over one mix would
  interleave into one tap's state; sequential use survives on a reset
  heuristic, and a second build costs one more pass on the build queue and
  removes the argument entirely. Int16 SATURATES, so a mix hotter than
  full scale — exactly the material loudness normalisation exists for —
  would be measured clipped and its true peak pinned at 0 dBTP by the
  decode rather than by the signal. Nothing in the tree had asked an
  `AVAssetReaderAudioMixOutput` for float before, so the request is MEASURED
  with `canAdd` and a 16-bit fallback is recorded rather than discovered as
  a wrong number. Measured on macOS 26.5.1: the float request is accepted,
  and the fallback has never been taken.
- **And the limit that falls out of the two domains, which belongs in the
  write-up rather than in a comment nobody reads.** The measurement is
  float and therefore honest about a mix over full scale, but the WRITE
  pass decodes to Int16, which saturates BEFORE the gain is applied — so a
  mix that clips is measured correctly, normalised down, and STILL CLIPPED
  in the file. The gain cannot undo the decode. Turning the hot clips down
  is the fix; the ceiling only stops the gain pushing a mix INTO clipping,
  it cannot pull one out. Widening the write path to float is a real
  change (it is the same dictionary every other preset's encoder consumes)
  and is a separate piece of work, not a line of this phase.
- **A bare `peak_dbtp` is REFUSED, where the scout recommended accepting
  it.** The scout's argument was the table's own rule — every other
  override is independent, accepted by formats that cannot use it, and
  never coupled to another key — and it is a good argument that loses to a
  better one. The design is gain-only with no limiter, so the ceiling
  exists solely to cap a gain that a TARGET computed; with no target there
  is no gain, and "turn the programme down until its peak fits" is peak
  normalisation, a different feature nobody asked for. Accepting the key
  would make it the first in the table accepted, echoed in the resolved
  settings, and silently inert — which the crate has no precedent for and
  no way for a caller to notice. So it is an `Err` naming the pair, and
  `export_overrides.rs` states and argues the exception where the reader
  lives.
- **"16- or 24-bit" is 16-bit only.** The road map's WAV/AIFF bullet offers
  both; 24-bit would mean widening the DECODE settings the mix is read
  through, and that dictionary is what every other preset's encoder
  consumes — a silent format mismatch there is a file of noise rather than
  an error. It is deferred deliberately, and when it comes it is a request
  (an `audio_bits` override beside the bitrates) rather than a row, because
  a depth that doubles the table is a knob wearing a preset's clothes. It
  needs measuring first.
- **The two LPCM rows carry a NON-NULL `avf_preset`**, which changes what
  that field means. A null one is the ImageIO writer's cue — a null-preset
  row is handed to `ImageSequenceWriter`, which refuses an unknown
  container as `.fileTypeUnsupported`, so a WAV would fail with a
  GIF-shaped error — and AVFoundation publishes no `AVAssetExportPreset`
  for LPCM. So the rows repeat `audio_m4a`'s name, the closest true
  statement available ("an audio-only file AVFoundation writes"), and the
  field now means ONLY "AVFoundation can write this row": a record, never
  an instruction. Spec §7.8, the header and `core/CLAUDE.md` all say so,
  and a test asserts the two new rows are not image sequences.
- **`export.rs` gave something up before it took this on.** It stood at 578
  against the ~600 cap and phase 5 owed it two container variants, two
  preset rows, a decibel validator, two override reads and two echo lines —
  about 690. `describe`, the overrides object and every per-type reader went
  out to a new `core/src/export_overrides.rs` (266) and `export.rs` came
  back to **579** with the additions already in it. The cut is by CONCERN,
  `props_check.rs`'s own reason: how a value is SPELLED and what makes it a
  refusal is a fact about the vocabulary, where the table and the resolution
  are `export.rs`'s. `describe` was never an export function at all — five
  modules import it for their own messages — so `export.rs` re-exports it
  and not one of them changed. Spec §7.10's module table and
  `core/CLAUDE.md`'s module list gained the row, which is phase 1's lesson:
  a phase that adds a MODULE updates the map too.
- **No new op, no schema bump, and one new tool.** 5a is a Swift-side fold
  of a field that already persists, 5b touches no model at all, 5c composes
  `set_audio` (so `normalize_clip` is a composite the UI offers as one
  command — the rule that gave `add_zoom_action` a tool, applied to a case
  that needed no op because the composite is one op per clip), and 5d/5e
  live in the core's export table rather than in the project file. So
  `RC_FORMAT_VERSION` stays 5 and `OP_NAMES` stays 53.

**Proved** on 2026-09-08. Core: `make test` **368 passed / 0 failed** — 358
before, plus ten in `core/tests/export.rs` (20 → 30); `export_size.rs`
grew the two rows into its existing cases and no test. `make lint` and
`cargo fmt --check` clean, `make typecheck` 0 errors and the same 4
AVFoundation deprecation warnings, `make app` building, the catalog at
**71 tools** (53 ops, unchanged, plus eighteen app-state tools) and the
startup parity log EMPTY. Phases 1–4 re-ran unchanged at `phase1_proof.py`
**66/66**, `phase2_proof.py` **85/85**, `phase2_chrome.py` **26/26**,
`phase3_proof.py` **121/121**, `phase3_silence_scope.py` **8/8**,
`phase3_chrome.py` **33/33**, `phase4_proof.py` **84/84** and
`phase4_chrome.py` **59/59**.

The phase's own scripts go beside them — `tools/proof/phase5_proof.py` over
MCP at **88/88** and `tools/proof/phase5_chrome.py` offscreen at **81/81**,
the second run twice for byte identity. The chrome script splits where the
phase does: sections 1–7 (forty-five checks) are the one thing phase 5
DRAWS, each a byte comparison against a reference build of the tree one
commit before `LevelMeterView.swift` existed — scoped to the TIMELINE BAR,
because that reference tree ages and a whole-window comparison would fail
the first time phase 6 adds an inspector section, with the meter untouched;
section 3b stages that future with a moved playhead, and the five chrome
mutations were re-measured at the new scoping to show it costs nothing —
section 8 (twenty-three) is the meter's reading over the harness's
third mode, which is not a picture at all, and section 9 (thirteen) is the
export GAIN over a fourth instrument again: a probe compiled from
`app/Sources/Loudness.swift` alone, which has no AVFoundation in it, so
`ExportLoudness.resolve` takes a measured programme as four numbers and the
−1 dBTP ceiling can be SWEPT — two hundred true peaks a thousandth of a
decibel apart, every resolved gain landing at or under the ceiling where a
round-to-nearest quantisation would put ninety-two of them over. What they show is §8 of the phase's
contract: a mono export whose left channel equals its right sample for
sample, and byte identity with a pre-phase export when `mono` is off; the
meter's published MODEL reading −20 dBFS ±0.5 dB on a −20 dBFS tone (not
pixels — the harness has no player, so the only photographable claim about
the meter is its resting state and that it moves nothing else in the bar);
a normalised clip's peak landing at −1 dBFS ±0.1 in an export, a clip under
the 4× clamp reporting where it actually reached, and the two refusals by
name; `Loudness.swift` measuring a fixture the script authors within ±0.1
LU, a normalised export landing within ±0.5 LU of its target, and byte
identity with a pre-phase export when Loudness is off; and `ffprobe`
reporting 48 kHz PCM for both new rows, the WAV and the AIFF of one project
decoding to identical PCM, and neither being routed to the image-sequence
writer. Two tolerances are deliberately looser and the reason belongs in
`tools/proof/README.md` beside the duck-edge note: **true peak gets ±0.3 dB
plus two invariants** (true peak ≥ sample peak, and a 45° fs/4 sine reads
at least 2.5 dB above its sample peak), because a 4× oversampler can miss an
inter-sample peak between its own output instants — the standard's Appendix
1 puts the under-read at up to 0.554 dB at 0.45 × fs — and because the
standard's own interpolation table has 0.25 dB of ripple between its four
phases, transcribed verbatim rather than normalised so it can be checked
against its source. Measured against analytic tones this meter reads at
most 0.2 dB HIGH and never low, and `ffmpeg -af ebur128=peak=true` reads
half a decibel away from it at fs/4, so a proof comparing the two needs
about ±0.7 dB there. And the standing limit applies to every byte-identity
fixture in the script: audio export is not bit-deterministic near a duck
ramp edge, so each of them must be duck-free and fade-free.

Still owed by a person at the machine — the half no headless run reaches:
(1) the meter IN MOTION, which is the only thing that can show the
ballistics are right and that a 30 Hz read of a 12–20 Hz buffer rate does
not read as a stutter; (2) that a mono-folded clip sounds mono and that a
pan across one sweeps rather than balances, which is a judgement about
sound and not about samples; and (3) that a −14 LUFS export sits at the
same apparent level as commercial material, which is the whole point of
normalising and is not a number.

#### #34 — mixed audio formats on one track (2026-09-24)

kpgalligan/reelcut#34: an AAC clip (`.m4a`) then a WAV on ONE timeline
track previewed silent from the WAV on, and the WAV on a second track
played. `CompositionBuilder.fill` put every segment of a plan audio track
into one composition track; `insertTimeRange` accepts an AAC segment then an
LPCM one, and the track carries two format descriptions. The preview's build
is the one metering build (`Playback.startRebuild`), every audio track gets
an `MTAudioProcessingTap`, and an `AVPlayerItem` over a tapped track that
changes format does not play. The export's reader (untapped) always did.

**What landed.** `app/Sources/CompositionBuilder+AudioTracks.swift` (new,
the audio half of `build`: `AudioFormatSignature`, `AudioFamily`,
`audioFormatSignature(of:)`, `placeholderTrackID`, `firstExtraTrackID`,
`resolveSource`, `audioFamilies`, `addAudioTracks`); an audio plan track
becomes one composition track per distinct source stream description, the
first keeping the plan's id and later ones taking ids past every plan id and
the placeholder's (spec §11 R2-1). A same-format track is one family with
the plan's id and all its segments, the composition it always was. First as
a PURE MOVE, gated alone (`make typecheck`, `make app`,
`preview_validity_probe.py` 24/24), then the families.
`CompositionBuilder.swift` 601 → 577 lines; `AudioTap.swift` 595 → 595
(`AudioTrackDSP.init(segments:parameters:)`). No core change, no FFI, no
format bump: the plan is byte-identical.

**Measured.** `tools/proof/mixed_audio_probe.py` **37/37** on the fix, with
section 4 RUN (output device: AirPods Max). Its player rows on the fix:
`mixed` at 0.5 s before 0.500 → after 1.207 s, peakLeftDB −20.9; `mixed` at
3.5 s 3.500 → 4.191 s, −21.1; CONTROL `split` 3.500 → 4.255 s, −21.1;
CONTROL `same` 3.500 → 4.206 s, −20.8; all silent after pause. Over the
baseline tree (`git archive 632b26f app/Sources`, `--sources`) **31/37**,
failing by name: section 1 (1001 carries two descriptions, AAC and LPCM);
section 2's `mixed` ids `[1001]`, `three` ids `[1001]` and `three`'s 1001
holding four segments; and section 4's `mixed` at 0.5 s and at 3.5 s — the
**STALL form**: before 0.500 → after 0.500 s and 3.500 → 3.500 s, peakLeftDB
−200 (silent), no tap output at all. Both CONTROLs passed on the baseline
(`split` 3.500 → 4.225 s, −21.1; `same` 3.500 → 4.203 s, −20.8), so the
failing `mixed` rows are the defect and not the host. Section 3 passed on
the baseline and `tools/proof/mixed_audio_proof.py` is a regression guard
that would pass there too, because the export path was never the defect:
**13/13** over MCP (the WAV exports at −24.08 dBFS against the file's
−24.08). Regression runs on the fix: `phase2_proof.py` **86/86**,
`phase5_proof.py` **88/88**; `make test` 827 passed; `make lint` clean;
`make typecheck` 0 errors, 7 warnings.

**Deviations from the spec's numbers, each measured on both trees.**
(1) Section 4's clock threshold is 0.4 s, not 0.8 s: on this host's
Bluetooth output the player's clock starts 0.45–0.6 s late, and the CONTROLs
moved 0.70–0.76 s in 1.2 s, so 0.8 failed every row on the fix and both
CONTROLs on the baseline; the stall moves 0.000 s. (2) `mixed` against
`split` (probe section 3, proof row) leaves out 3.000–3.026 s (the measured span, 3.0000208–3.0249896 s, rounded up): the plan
track's envelope steps 0 → 1 at the WAV's start, that step is on `mixed`'s
WAV track (its plan track's ramps, gap included) and not on `split`'s, and
AVFoundation's mix smooths it over 1200 frames — max |Δ| 2855 there on BOTH
trees, 0 everywhere else. (3) `same`'s "one format" is one stream
description, not one format description: two AAC files are two
descriptions of one format on both trees. Cross-tree, the fix's `mixed`
decodes against the baseline's at max |Δ| 2 — the same AAC wobble `same`
shows between two processes with an unchanged composition.

**Recorded, not changed.** A 44.1 kHz WAV on a track of its own reads
10.9886 s of an 11 s composition on BOTH trees (measured with the probe's
decode over a two-track package); `three`'s 44.1 kHz family is now such a
track, so its decode is 11 ms short where the baseline's heterogeneous
track read 10.9988 s, and that clip's resampling phase differs by about two
frames — every window still loud. A reversed clip's source is
`ReverseRenderer`'s `.mov`, whose format may found a family of its own. And
`AudioTrackDSP.usesNoiseReduction` is now per family, so a noise-reduced clip
alone in its family delays only itself, as it would on the workaround's
second track.

**Owed.** Section 4 was measured on a Bluetooth output only; a run on the
built-in speakers would show the clock threshold's margin there. A person at
the machine has not LISTENED to the fixed preview (the meter and the clock
are the probe's evidence). The meter's sink holding its last buffer across
empty time is pre-existing and not this issue. `app/CLAUDE.md`'s map entry
`CompositionBuilder.swift (+InstructionRanges)` gains `+AudioTracks` —
applied by the orchestrator after review.

**Review** (litecode, verdict pass, no blockers). Three nits, applied by the
orchestrator: the `ADVANCE` comment's CONTROL range corrected to the printed
0.70–0.76 s; the left-out envelope span narrowed from 3.000–3.050 s to
3.000–3.026 s (the measured span rounded up); and `audioFamilies` now puts a
zero-length segment in family 0 rather than letting it found a family —
`fill` skips such a segment, so it would have added an empty composition
track. After them: `make typecheck` 0 errors, 7 warnings; `make app` built;
`mixed_audio_probe.py` **37/37**; `mixed_audio_proof.py` **13/13**.

---

### Phase 6 — Looks

*One to two sessions. Schema v6 (`video.blend`, `shape.gradient`).*

- **Blend modes.** `video.blend: "normal" | "multiply" | "screen" | "add" |
  "overlay" | "darken" | "lighten" | "difference"`. The app is Apple
  Silicon only, so the fragment shader can read the destination through
  framebuffer fetch (`[[color(0)]]`) and every mode is one formula on
  premultiplied (src, dst) in the layer pass — one uniform, one code path,
  no ping-pong target. (Fixed-function factors would cover only multiply,
  screen and add; one path beats two.) The transition partner blends
  normal. A nest clip does not take a blend — its layers are flattened, and
  blending the group would need the offscreen pass the flattening avoids
  — so `set_video {blend}` on a nest clip is an `Err` naming that.
  Inspector: a Blend popup in the Transform section beside Opacity.
- **Gradient fills.** `shape.gradient: null | { "kind": "linear" |
  "radial", "stops": [{ "at": 0..1, "color": [r,g,b,a] }], "angle": deg }`,
  drawn by `LayerRenderers.renderShape` with `CGGradient` and taking
  precedence over `fill` when set. The canvas background stays a colour:
  a full-canvas gradient or image is a shape or image clip on the back
  track, and **Clip ▸ Add Background…** makes exactly that — a
  canvas-sized rectangle, or the chosen image, on a new track at index 0.
- **Blurred background fill** (the vertical-repurposing move). Clip ▸ Add
  Blurred Background: a composite over existing ops — a new track at
  index 0, the clip's payload `paste`d onto it at the same start, then
  `set_video` with Fill scale, `x`/`y` 0, crop cleared and
  `filters: [{blur, 1}]` — in one undo step. MCP `add_blurred_background
  {clip}` mirrors the composite.
- **Filters as action targets.** Phase 3's list rule LANDED and does make
  `filters` interpolate per index — read it in `actions.rs` before writing
  against it, because the widened `{kind, shape}` discriminant is confined
  to list ENTRIES, deliberately, so that no named object's animation
  changed. This phase lets `set_action_end` carry them and
  the Filters section write through `InspectorBinding` while the playhead
  is inside an action, as every other section does. `clamp_video` already
  bounds them.

`RC_FORMAT_VERSION` 6.

**Where.** `model_props.rs` — NOT `model.rs`, which has held only the
schema's shape since phase 2 — plus `format.rs` + header, `props_check.rs`
(range checks for the new fields), `actions.rs`, `Compositor.metal`,
`Compositor.swift`,
`CompositorEffects.swift`, `LayerRenderers.swift`, `VideoPane.swift`,
`ShapePane.swift`, `EditorViewController+AddClips.swift` (the two
background commands), `AppDelegate.swift`, catalog and handlers;
`core/tests/schema_v6.rs`, action tests for the list rule.

**Proof.**
- Multiply of 50 % grey over 50 % grey measures 25 % ±1/255 at the centre;
  screen 75 %; add clamps at white; `normal` is byte-identical to before.
- A linear gradient 0 → 1 across a box measures monotonic per column and
  hits the stop colours at its ends.
- Add Blurred Background renders byte-identically to the same three ops
  applied by hand over MCP.
- An action from `blur 0` → `blur 1` renders at its midpoint byte-identical
  to a static `blur 0.5` (with `ease` linear).

**What landed.** All four parts, at schema version 6 (`video.blend` and
`shape.gradient`, both defaulted, no migration step), TWO new ops
(`OP_NAMES` 53 → **55**) and two new tools (the catalog is **73**) — plus
the following, where the code differs from the plan above or settled what
it left open. **Seven deviations, and the first is not a detail about
mechanism but about what this phase actually did:**

- **6d was already shipped, and this phase did not write it.**
  `set_action_end` has carried `video.filters` since M3 (`a4bedf1`),
  phase 3's list rule already interpolates them per index, `structural`
  already routes an add or a remove to the base props (`3a64d85`), and
  `core/tests/schema_v2.rs` already carried green tests for it under its
  own `// ---- interpolation ----` banner. So the honest description of
  6d's session is PROOF, two residual defects and one refusal made loud,
  and it is written that way here on purpose: a phase
  that quietly claims code it did not write is worse than one that
  reports a short session, and the next reader who takes "filters as
  action targets" for a phase-6 feature will go looking for a commit that
  does not exist. What the phase owed was the road map's own oracle — an
  action `blur 0 → blur 1` rendered at its midpoint byte-identical to a
  static `blur 0.5` — and these three, which 6d is what makes reachable:
  - **Editing ONE filter inside an action re-pinned every other filter's
    end value.** `filtersSection` built its array from
    `binding.videoProps.filters`, which INSIDE an action is the EVALUATED
    list, and `actions.rs`'s `merge` replaces an array whole rather than
    entry by entry. With a base of `[blur 0.2, sepia 0.3]` and an end
    patch of `[blur 1.0, sepia 0.3]`, dialling the sepia at the midpoint
    re-sent the blur at 0.6 and its ramp was silently flattened. The fix
    is `InspectorBinding.editedList`: a write reads the list it is about
    to REPLACE — the action's own end `filters` where the end patch
    carries one, the clip's base list otherwise — while every `read:`
    stays on the evaluated value, so the section still shows the
    playhead's picture.
  - **`structural` was one action short of true.** Its doc said "nothing
    the inspector does can put a different length into an end patch", and
    with TWO actions on a clip and the earlier one's end patch changing
    the filter COUNT, the evaluated list at a playhead inside the second
    is longer than the base — so comparing a new length against the base
    classified an ordinary dial as structural and rewrote the clip's BASE
    stack, changing every frame before the first action. Not reachable
    from the UI alone (a length change always goes to base, which is the
    guarantee); reachable from MCP or a hand-written file. Same three
    lines, same reader, and the sentence in the doc is corrected rather
    than deleted: with the pair in force the section can only write the
    length it can see, and nothing is promised about a length
    `set_action_end` put there.
  - **One refusal made loud rather than silent.**
    `{"filters": [{"amount": 1.0}]}` is the core's own documented idiom
    for "the same filter, more of it" and the most natural thing an agent
    will write. Over MCP it could not work: `FilterProps` has no
    optionals, so the decoder filled the missing `kind` with `blur`, a
    `sepia` base animated and then switched to a blur, and the caller was
    told it had worked (measured). `checkVideoEnums` now refuses an entry
    missing either key, naming the index — and `filters` joined
    `app/CLAUDE.md`'s list of nested objects the MCP decoder REPLACES,
    which is the one member of that family the list had omitted. The
    related wart is pinned as known rather than fixed: a partial entry in
    an end patch interpolates smoothly and then takes
    `FilterProps::default()` for every key it omitted at the switch,
    because `merge` replaces a list rather than merging it. Filters have
    had that since M3 and obscure regions since phase 3c.

- **The two background commands are CORE OPS, not app-side composites**,
  in a new `core/src/edit_background.rs` (508). The road map calls Add
  Blurred Background "a composite over existing ops" and its "Where" list
  names neither `edit.rs` nor a new core module; the argument was run both
  ways and the collating reader adjudicated it the other way, so it is
  worth carrying. Four things decided it. **The road map's own recipe
  cannot be built**: it says "the clip's payload `paste`d onto it", and
  `clipboardPayload` is `private` and writes no `nests` key, so a blurred
  background of a nest clip comes back refused — once the recipe has to
  change, the plan of record's authority on the MECHANISM is spent.
  **The replacement recipe loses the source window**: re-placing the media
  with `add_clip` gives the WHOLE media, so the backdrop of a trimmed clip
  shows different frames from the foreground and drifts out of sync, which
  is the one thing this feature may not do; repairing it means a
  `trim_start` and a `trim_end` in Swift over arithmetic the core owns.
  **`duplicate` is no way out either** — it lands its copy one selection
  span later on the SAME track, where it can collide with a neighbour, be
  refused, or silently acquire a cross dissolve for a reason the user
  never asked about. And **in the core it is `clip.clone()` with six
  VIDEO fields overwritten** — `scale`, `x`, `y`, `crop`, `filters` and
  `blend`, the last of them added by the phase's own review — over
  vocabulary the app lacks: the source's pixel
  size, `edit_clip.rs`'s new `fill_scale` and the `SCALE_MAX` clamp on it,
  which Swift's own fill arithmetic does not have and is already wrong
  past ×10 without. `insert_clip`, `overwrite_clip` and `add_zoom_action`
  are the standing precedent and they name the rule: **a composite becomes
  an op when composing it out of existing ops carries a constraint that no
  single half states**, and frame-exact sync with the source clip is
  exactly such a constraint.

- **`add_background` is a second op the road map did not name, and Add
  Background is a SUBMENU rather than one dialog.** The road map has Add
  Background… making "a canvas-sized rectangle, or the chosen image, on a
  new track at index 0" and gives no op for it, which would have left the
  colour plate as app-side clip-building beside a core op that does the
  same work for the blurred copy. It is one op with three optional
  arguments instead (`media`, `color`, `duration`), and its no-argument
  form is exactly what the menu's Solid Color row sends. The menu follows:
  Solid Color takes no dialog at all — hence no ellipsis — because a plate
  is re-coloured afterwards in the Shape section's own Fill row, which is
  also how phase 6b's gradient becomes reachable for a background, since
  the whole argument for keeping the canvas background a colour is that a
  full-canvas gradient is a shape clip on the back track. Image… is a
  standard `NSOpenPanel`, and its two ops go through ONE `applyEdit` list,
  the app learning the minted media id the way `makeProject(around:)`
  already does: apply `add_media`, read `snapshot.media.last`, build the
  second op. Applying the same op to the same base mints the same id every
  time — `next_id` is a single counter — which is what makes
  simulate-then-apply sound, and this is the first use of that technique
  outside `makeProject`.

- **The CORE forces `normal` under a transition, not the renderer.** The
  metal scout put the rule in the shader, which is where it looks like it
  belongs. The outgoing half of a dissolve carries a weight correction
  that is the exact algebraic INVERSE of the fixed-function destination
  factor its incoming partner is about to apply, so a non-normal blend on
  either half invalidates it — and `add_clip` onto an overlap gives the
  new clip a `cross_dissolve` BY DEFAULT, so that wrong picture is a
  minute away from anyone trying the feature. `recipe.rs::layer` emits
  `"normal"` for any layer whose `transition` is non-null, for phase 4's
  `Reveal` argument read again: everything that draws a frame reads one
  description, so preview, `render_frame` and both export writers cannot
  disagree — and it is the only version PROVABLE the way this project
  asks, because a core test can read the layer's `blend` at a tick inside
  the overlap where the shader's version needs a byte comparison of two
  PNGs. The consequence is stated out loud in three places, since from
  either side alone it reads as a bug: **the recipe's `blend` is what
  DRAWS, and the inspector reads the MODEL's value through `clip_state`**,
  so during an overlap the popup says `multiply` and the frame composites
  `normal`. Both are honest — the clip multiplies, and this frame does
  not.

- **The nest refusal fires on a non-normal MERGED value only.** The road
  map says `set_video {blend}` on a nest clip is an `Err` naming that, and
  taken literally that refuses any MENTION of the key — which would fail
  an all-or-nothing `paste_attributes` of an ordinary look onto a nest
  clip, over a value that changes nothing, because a paste replaces the
  video group WHOLE. So `{"blend": "normal"}` on a nest clip is the
  identity and answers `None`, and one `check_blend` in `edit_props.rs`
  (not `props_check.rs`, whose stated concern is the vocabulary and which
  never sees a clip) serves both the patch path and `check_group`, so the
  two give the identical sentence. The op check is not the whole story:
  `set_action_end` validates nothing beyond "is it an object", so
  `clamp_video` gained an `is_nest` argument and forces `BlendMode::Normal`
  in the evaluator, which closes the recipe, `clip_state` and both export
  writers at once — something no per-op check can do. A blend on a clip
  INSIDE a nest is ALLOWED and blends against the canvas below the WHOLE
  nest. It is the FOURTH item in `nest.rs`'s `Frame` doc, beside the two
  that were already there — a nest clip's opacity multiplying each inner
  layer separately, and only the innermost `clip_rect` surviving — and the
  third, which had been true since M3 with nothing recording it: a nest
  clip's OWN per-pixel properties reach no layer at all. Spec §5.3 carries
  the same four.

- **The default plate is WHITE, not black.** The canvas background is
  already black, so a black rectangle is a command that appears to do
  nothing — the worst first impression a menu item can make. White is
  visible, it is the neutral plate, and it is the IDENTITY for `multiply`,
  which is the mode a person tries first and the one that renders black
  over the default canvas with nothing under it.

- **`model_text.rs` is the cut `model_props.rs` paid, not the shape
  vocabulary.** The file stood at 592 against the ~600 cap and phase 6
  owed it two property families, so it gave something up BEFORE it took
  anything on — `core/CLAUDE.md`'s rule, and the cut both that file and
  this road map had named in advance. The text vocabulary went out
  (`TextProps`, `TextAlign`, `TextVAlign`, `Outline`, `Backdrop`,
  `TextAnimation`, `TextAnimationKind`), 252 lines, re-exported whole so
  not one `crate::model::X` or `crate::model_props::X` path changed, and
  the seam is nameable: text is the one property group the model cannot
  MEASURE, because only the platform can lay a string out and the size
  comes back the other way through a cache. The shape vocabulary was the
  alternative and was refused: it leaves about 27 lines of headroom, and
  `Gradient` belongs beside the `ShapeProps` that holds it. `model_props.rs`
  is at **600** with phase 6's additions in it — AT the line, so it takes
  nothing further without another cut, which is the same warning phase 3
  handed phase 6.

Beside the deviations, five things the next reader needs and one measured
number:

- **The shader refactor came first, alone, and the proofs were re-run
  before the blend uniform existed.** Metal cannot call one `fragment`
  function from another, so the whole body of `reelcut_layer_fragment`
  moved into a `static inline layerColorPremultiplied` helper and both
  entry points forward to it — the plain one returning its colour for the
  fixed-function stage, `reelcut_layer_blend_fragment` reading the
  destination through `float4 dst [[color(0)]]` and combining it itself.
  Both keep the `kGatherFilters` specialization, so there are FOUR layer
  pipelines and the shadow's quad is the fifth. A 1-LSB drift in the plain
  path was the phase's second-biggest risk, and landing the refactor by
  itself is what makes its absence attributable: every `render_frame` byte
  comparison in phases 1–5 passed before a line of blend code existed.
- **Blending is DISABLED on the two blend pipelines, and nothing in the
  toolchain enforces it.** Metal builds a programmable-blend pipeline with
  fixed-function blending still on — no error, no validation warning, no
  log — and at alpha 1 the double blend is invisible, because
  `oneMinusSourceAlpha` is 0. **What decides that is the DESTINATION's
  alpha and not the layer's, and this phase got it backwards first.** The
  fragment stage returns the finished composite, whose alpha is
  `as + ab·(1 - as)`; over an OPAQUE destination that is 1 whatever `as`
  is, so a half-opacity layer over an opaque backdrop shows nothing either.
  The check written for the job — a translucent LAYER over an opaque
  backdrop — therefore **passed against a build with the guard deleted, as
  did every other check in the script**, because every other fixture puts a
  full-canvas opaque card underneath and all of them were blind to it too. What catches
  it is a translucent DESTINATION plus a source that does not cover it:
  the alpha then reads 223 where it should read 191, while the colour moves
  by two. `phase6_proof.py`'s section 6b is that check and is the only one
  in the script that reads the alpha channel. **The mutation run is the
  only reason any of this is known**, and the script's own `blended`
  docstring had stated the alpha rule two hundred lines above the check
  that depended on getting it wrong. The uniform cost was zero bytes:
  `reserved0` became `blendMode`, the block stays 104 floats / 416 bytes,
  and the padding tail is TWO floats now rather than three.
- **`maskState` takes the layer's gather specialization WITHOUT its blend,
  and it is DEFENSIVE rather than load-bearing — which the mutation run
  established against every document that had said otherwise, this one
  included.** The claim everybody made, from the scouting pass through the
  builder's doc comment to `app/CLAUDE.md`'s rule two, was that a shadow's
  silhouette pass draws coverage into a texture cleared to transparent
  black, so a `multiply` over that empty destination is 0 everywhere and a
  blended layer's shadow silently vanishes. **It does not.** That is true of
  a naive `src · dst` and false of the premultiplied composite the shader
  actually runs, whose `(1 - ab)·src` term carries the source through an
  empty destination untouched: at `ab` = 0 the whole formula reduces to
  `src` exactly, for all eight modes, `add` included — the same property
  that lets a corner radius and a nest's clip rectangle work, read from the
  other side. A build that passes `state` here renders every shadow
  correctly and fails NOTHING. The separation stays because it costs
  nothing, because it names what the mask pass means, and because a future
  formula without that term would make the hazard real; it is not holding a
  bug back today, and no document should say it is. The shadow's own DRAW
  stays fixed-function source-over whatever the mode, because a shadow is
  light falling on the backdrop and not the layer's ink; and the REFLECTION
  goes the other way and inherits the blend, since it is part of the layer. All three are written into `encodeShadow`'s and
  `encodeReflection`'s docs.
- **The compositor blends in the ENCODED sRGB space, deliberately**, and
  the sentence stands in three places — `Compositor.metal`'s
  order-of-operations comment, `phase6_proof.py`'s docstring and spec
  §7.5 — because it is the one thing about this compositor a competent
  reader will try to "fix". Nothing in the pipeline uses an `_srgb`
  format, so every stage works on stored 8-bit values and so does the
  blend; "multiply of 50 % grey over 50 % grey is 25 %" is a statement
  about ENCODED values and is false in linear light, where the answer is
  about **61**/255 — three steps below the 64 the encoded multiply gives
  (60.95 against 64.25 unrounded), which is three times the ±1/255 every
  blend check allows itself, so the two readings cannot both pass. Getting
  that number wrong in one copy of a sentence declared to stand in three is
  its own warning: the sentence exists to stop a reader "fixing" the
  shader, and a reader who checks the arithmetic and finds it off stops
  believing the sentence. Wrapping the blend in a linearise/encode pair
  would change every blended pixel, break the proof's measured numbers and
  make the compositor disagree with itself, since the grade, the filters
  and the transitions have all worked in encoded space since M1.
- **A gradient is painted by CLIPPING to the path**, not through a
  transparency layer — and the measurement under that decision is the
  scout's re-taken, because the scout's did not hold. A one-colour opaque
  gradient is byte-identical to `fillPath()` wherever a pixel is FULLY
  COVERED — a rectangle on integral bounds, at 0°, 45°, 137° and radial
  alike, not one component differing — and within one LSB wherever it is
  not: 200 of a 64 × 64 ellipse's 4096 pixels, every one of them on the
  antialiased edge and none of them opaque, plus every pixel of a
  translucent plate, plus every pixel of a colour 8 bits cannot hold,
  because `CGGradient` DITHERS. The clause that did not survive is "the
  antialiased edge included"; the CONCLUSION does, and it is the one the
  decision rests on — a transparency layer buys a full-size buffer and a
  rounding step of its own and would not close that last LSB either. The
  consequence for a later phase is stated where it lands
  (`LayerRenderers.paint`'s doc): a proof that wants a BYTE comparison out
  of a gradient has to ask it of a rectangle on integral bounds in a colour
  of the form k/255, which is what G1 asks and why every fill in that
  fixture is one. A linear ramp projects the box onto its direction, so the
  end stops land exactly on the box's edges at EVERY angle; a radial one is
  the inscribed ellipse for both area kinds; the stroke keeps
  `stroke.color`, since a stop's opacity is its own alpha and the swatch
  panel already edits it; and the texture key needed nothing, because
  `recipe.rs`'s `Source::Shape` arm hashes `json(&shape)` WHOLE and the
  gradient rides inside it — the phase-4 text lesson arriving already
  answered, and still proved by measurement rather than by reading.
- **What a blend costs**, measured on the same layer and the same way M3's
  effect costs were: against a baseline reproducing at 0.293–0.295 ms,
  `add` 0.02 ms, `multiply`, `darken` and `difference` 0.07, `screen`
  0.08, `overlay` 0.09. Most of that is the FORMULA and not the tile read —
  the same blend pipeline asked for `normal`, which reads the destination
  and takes the early return, costs 0.02, exactly what `add` costs, and
  `add` skips the divisions too. So a destination read is 0.02 ms and the
  un-premultiply pair plus the mode is the other 0.05, which is worth
  knowing before anyone tries to save a reciprocal by assuming an opaque
  destination.

Two size payments and one sweep, none of them the phase's feature and all
of them its work:

- **`LayerRenderers.swift` paid before it took the gradient on**, like
  `model_props.rs`: 845 lines, with the text machinery — the layout
  caches, the attributed string and the three reveals — out to a new
  `LayerRenderersText.swift` (577), leaving 467 with the gradient already
  in it. **The two background handlers went into a new
  `AgentServer+Background.swift` (89)** rather than into
  `AgentServer+Clips.swift`, which is long over any cap and grew this
  phase anyway, to 1183, for the gradient reader and the two new enum
  checks.
- **The version sweep has a trap, and it is one bump older than this
  phase.** `{"version": 6}` was the tree's "too new, refuse" fixture in
  `schema_v3.rs` and `model_tests.rs`; the moment `RC_FORMAT_VERSION`
  reached 6 those three tests stopped testing the gate and started
  testing that a current file opens. They are at **7** now, and the
  comment beside each says "one past the current version" rather than
  naming a number, so the next bump does not have to rediscover it. Two
  other sites were not substitutions either: `schema_v3.rs`'s gate
  hard-codes both numbers inside a literal message string, and
  `schema_v4.rs` asserted BY LITERAL TEXT that `obscure` closes the video
  object, which appending `blend` falsifies by design — that assertion
  moved to the pair rather than being deleted, because what it is really
  pinning is that a new key lands at the END, which is what the whole
  append-only rule rests on. The same correction was made in
  `tools/proof/phase3_proof.py`.
- **One correction to this phase's own contract, found by the builder who
  wrote the shader.** Its check B2 — "overlay with a base of 64, expecting
  96" — is exact only for a **192** source (2 × 0.753 × 0.251 = 0.378 →
  96); a 128 source over a 64 base gives 64, which is arithmetically right
  and a WEAK check, because 64 is also what an unblended backdrop reads.
  The fixture is 192 over 64.

- **The inspector says what the trap is, and only when it is live.** Every
  mode but `normal` is a function of two colours, so a layer with nothing
  behind it over the default black canvas either reads black (`multiply`,
  `darken`, `overlay` all collapse against 0) or changes nothing at all
  (`screen`, `add`, `lighten`, `difference` are the identity against 0) —
  and neither looks like a mode that is working. The Transform section's
  note is COMPUTED: it appears only when the canvas background really is
  black and nothing visible really is behind the clip, and it names which
  of the two failures is on screen. The popup's tooltip carries the whole
  of it and the answer, which is Clip ▸ Add Background. The action note
  still outranks it — where an edit LANDS matters more than what it looks
  like — and `blend` is an ORDINARY animatable key, deliberately not one
  `structural` pulls out: `structural`'s own doc already settles the
  identical case for a filter's `kind`, and that function stays about
  LENGTH alone.

**Proved** on 2026-09-08. Core: `make test` **436 passed / 0 failed** — 368
before, plus 17 in a new `core/tests/schema_v6.rs`, 41 in a new
`core/tests/background.rs` (34 at the landing and 7 more from the review —
one per behavioural fix, each mutation-checked), 6 in `evaluate_tests.rs`
(the recipe's `blend`, the transition rule frame by frame, a nest clip
evaluating to `normal` however the blend got there, and that a `shape` end
patch is STORED and INERT, which is the claim two documents had wrong) and 4
in `schema_v2.rs` — which is where 6d's
tests go, under that file's existing `// ---- interpolation ----` banner and
NOT in `schema_v6.rs`, because the filter list is version 2's feature and
`schema_v6.rs` has to stay honest about the two keys version 6 actually
adds. `make lint` and `cargo fmt --check` clean, `make typecheck` 0 errors
and the same 4 AVFoundation deprecation warnings, `make app` building, the
catalog at **73 tools** (55 ops plus the eighteen app-state tools) and the
startup parity log EMPTY.

Phases 1–5 re-ran unchanged at `phase1_proof.py` **66/66**,
`phase2_proof.py` **85/85**, `phase2_chrome.py` **26/26**,
`phase3_proof.py` **121/121**, `phase3_silence_scope.py` **8/8**,
`phase3_chrome.py` **33/33**, `phase4_proof.py` **84/84**,
`phase4_chrome.py` **59/59**, `phase5_proof.py` **88/88** and
`phase5_chrome.py` **81/81** — and the one worth naming is the first
group, because **every `render_frame` byte comparison in them passed after
the fragment stage was refactored into a shared `static inline` helper**,
which is what says the plain layer path did not drift by a bit. That is
attributable only because the refactor landed ALONE and the proofs were
re-run before the blend uniform existed. Four of those ten scripts changed
in this phase and none of them by a check: nine `RC_FORMAT_VERSION`
assertions went 5 → 6, `phase3_proof.py`'s "obscure is the LAST key of
every video object" became "obscure, then blend" (falsified BY DESIGN, and
what it pins is that a new key lands at the END), and `phase5_proof.py`'s
exact tool count became a floor, exactly as phase 4 handed it to phase 5.

The phase's own scripts go beside them — `tools/proof/phase6_proof.py`
over MCP at **167/167** and `tools/proof/phase6_chrome.py` offscreen at
**70/70**. They split where the phase does, and the split is sharper here
than anywhere: **phase 6's two features are PIXELS**, and the offscreen
harness can photograph neither, because `build.sh` never compiles
`Compositor.metal` and the preview well renders black with no drawable. So
every claim about a blend or a gradient is the MCP script's, and what is
left offscreen is the chrome around them — which is not a small half: the
Blend row's position by arithmetic over the layout constants, the computed
note appearing and being suppressed by each of the four things that should
and should not, the Gradient section's height per stop, the 0.42 disabled
alpha SOLVED twice out of two different aligned pairs rather than read off
a token, and — through a probe it compiles for the purpose, because a menu
is never drawn into a window — the two Clip-menu items, the submenu's two
rows, the absence of a key equivalent and the validator's answers over four
selections.

What the MCP script claims, and the three decisions inside it worth
carrying: **the fixture is scored, not assumed** (a canvas at exactly
128/255 grey read back as 128, then 64 and 192, so a drifting pipeline
fails by NAME and the blend checks are not blamed for it — there is no
headroom left in the ±1/255 tolerance, since `round(128 × 128 / 255)` is 64
against 63.75); **every blend expectation is written twice**, once as the
formula over the two MEASURED card bytes and once as the road map's literal
64 / 192 / 255, so a wrong formula fails both and a drifted fixture fails
only the second; and **the fixture is SHAPE CLIPS**, two full-canvas cards
on two tracks with no media at all, which is what `video.blend` belonging
to the layer rather than to a source kind buys. One of its checks exists because of one
line of Swift and nothing else would notice it: a blended layer over a
TRANSLUCENT destination (section 6b), which is the only fixture in the
script that fails when the blend pipelines are built with fixed-function
blending left enabled. The two checks that were WRITTEN for that job and
cannot do it are recorded above, because both survived their mutant: the
partial-opacity one, which is blind because an opaque destination forces
the composite's alpha to 1; and the SHADOW one, which is blind because a
blend over the cleared mask reduces to the source exactly. Overlay is measured at **192 over 64 expecting 96**, not at 128
over 128: at 128 the branch condition sits on the knife edge (128/255 =
0.50196 takes the screen half and gives 128.498, rounding either way
depending on where the comparison is written), and 96 is a number an
unblended backdrop cannot produce where 64 is. And 6c's audio is a
**sample-for-sample PCM comparison**, planned from the start, because the
road map's own check for it — "byte-identical to the same ops applied by
hand" — passes with the bug present on BOTH sides: a blurred copy that kept
its audio is inaudible in a still frame and doubles the recording in the
mix.

**The mutants, and what they found.** Seven were run against the built
binary, each as a real `make app` and a fresh process — and the harness
itself had to be fixed first, which is the finding worth carrying forward:
the proof drives a RUNNING app, so a mutant that rebuilds without
restarting the process scores exactly what the clean build scored. The
first run reported a CLEAN SWEEP for a build with `u.blendMode` deleted.
**A mutation harness that does not restart the app gives a false all-clear
on every mutant it runs.**

| mutant | verdict |
|---|---|
| `u.blendMode` never written | 28 checks fail |
| the core's transition-forces-normal rule deleted | 2 fail — the two overlap comparisons, with the two "the MODEL still says `multiply`" lines staying green, which is what tells this from a model-side mutant |
| the gradient dropped from the shape texture cache key | 11 fail |
| `add_background`'s default plate turned black | 2 fail |
| `enabled.audio` left TRUE on the blurred copy | 6 fail — **after** the script was fixed; see below |
| fixed-function blending left ENABLED on the blend pipelines | **SURVIVED every check** — the hole was the proof's, not the build's; section 6b is the answer |
| `maskState` left as `state` | **SURVIVED every check** — not a hole; the claim was wrong |

**A verdict here is named checks and never a fraction**, and that rule was
bought rather than assumed. The two survivors were measured against two
DIFFERENT lengths of `phase6_proof.py` — 160 checks when the blending guard
was run, 163 once section 6b had answered it, 167 as the phase closed — so
the two fractions this table carried while it was being written were both
stale before anyone read them, and a next session running the script would
have found four checks it could not account for. Against the script as it
stands the blending mutant fails section 6b's two ALPHA checks and nothing
else (measured on the mutant: the alpha reads 223 where it must read 191,
while the colour moves by two), and the `maskState` mutant fails nothing at
all. `phase6_proof.py`'s own 6b comment states the rule where the next
reader of a mutant verdict will hit it.

Three things came out of it that reading could not have produced. The two
survivors are written up above. The third: **`enabled.audio` was detected
as a TRACEBACK rather than as a failing check.** The section switches the
copy's audio back on to show its own identity is not a tautology, and under
that mutant the switch is already on, so the core answers "made no change"
and the client raises — aborting the script with every later section unrun.
It asserts the switch is off first now and tolerates the identity. A proof
that crashes on the bug it is hunting reports less than one that scores.

Two mutants were themselves wrong before they were right, which is worth
saying because a bad mutant reads exactly like a weak check. Enabling
fixed-function blending by setting `isBlendingEnabled = true` is a NO-OP:
the line sits above `guard blending else { return descriptor }`, so the
four factors are still skipped, and Metal's defaults are `one`/`zero` —
the identity. And the first version of section 6b landed exactly on a
rounding boundary (`127.5 + ab·255/2` is a half for an even backdrop byte),
which is the hazard this script's own docstring warns about for the colour
channels; it is within one now, which costs nothing when the value being
excluded is thirty-two away.

Still owed by a person at the machine — the half no headless run reaches:
(1) that a blend mode looks like the mode it names on real footage rather
than on flat cards, which is a judgement about pictures and not about
bytes; (2) that a gradient's ramp is smooth on screen rather than banded,
which an 8-bit canvas can genuinely get wrong and no per-column
monotonicity check would catch; and (3) that Add Blurred Background reads
as the screencast look it exists for — the right blur at the right scale —
which is taste, and the one number in it (`filters: [{blur, 1.0}]`) is a
default somebody should sit with before it is treated as settled.

---

### Phase 7 — Output

*One to two sessions. No project-schema change; the export table and app
state.*

- **Save Frame.** File ▸ Save Frame… (⌥⌘E) → save panel, PNG / JPEG /
  HEIC at document size, through `Exporter.renderFrame` — the one path.
  `EditorViewController+SaveFrame.swift`. MCP: `render_frame` gains
  `path?` so an agent can name the file.
- **ProRes 4444 with alpha.** A `prores_4444` row in `export.rs` (MOV; the
  writer already maps the codec in `ExporterWriter.codecType(for:)` and nothing
  can ask for it), with `alpha: true` in the resolved settings whenever the
  canvas background's alpha is below 1. `ExportWriter` reads BGRA with
  alpha and writes `AVVideoCodecType.proRes4444`; the compositor already
  clears to the premultiplied background, so alpha 0 clears transparent.
  The Document tab's background well gains an alpha slider (or a
  "Transparent" switch). Confirm APNG keeps alpha on the same canvas.
- **Timecode burn-in.** An export option, never a preview one. The core
  appends the layer, so preview-vs-export stays one description:
  `rc_project_frame_recipe_opts(handle, t, opts_json)` — a new export, so
  header and `ReelCore.swift` move in lockstep — takes
  `{"burn_in_timecode": true}` and adds a text layer (mono face,
  bottom-centre, backdrop) whose `content` is `time.rs`'s `format_timecode`. The
  export pipeline passes the option through `RecipeSource`; the `export`
  tool takes `burn_in_timecode`. The per-frame recipe hash churns the text
  texture cache, which is fine at export speed.
- **Remembered settings and user presets.** The sheet reopens on the last
  choice (UserDefaults); named user presets are a name → overrides map in
  `~/Library/Application Support/Reelcut/ExportPresets.json`, resolved by
  the core's `export_settings` like any overrides, so the core never learns
  about them. A Preset popup at the top of the sheet with Save… / Delete.
  The `export` tool stays on the core's vocabulary.
- **Export queue.** `ExportQueueController.swift`: the sheet's "Add to
  Queue", Window ▸ Export Queue, sequential jobs each holding an immutable
  project handle (so later edits do not change a queued job), per-row
  progress and Cancel. Last in the phase; drop to the next session if the
  rest ran long.

**Where.** `EditorViewController+SaveFrame.swift`, `export.rs` — whose
override reading is `export_overrides.rs`'s since phase 5, and which is at
579 against the cap — `ExporterWriter.swift`, `Exporter.swift` (beside
`ExporterLoudness.swift` now, and note the export is TWO passes when a
loudness target is set), `DocumentPane.swift`, **`recipe.rs`, which phase 6
left at exactly 600 and which therefore PAYS FIRST — the recipe options are
the field this phase adds to it**
+ `ffi_query.rs` + header + `ReelCore.swift` (the recipe options),
`ExportSheetController.swift`, `ExportPresetsStore.swift`,
`ExportQueueController.swift`, `AgentServer+Render.swift`, catalog;
`core/tests/export.rs` and a recipe test for the burn-in layer.

**Proof.**
- Save Frame's PNG is byte-identical to `render_frame` at the same `t`.
- A ProRes 4444 export of a transparent canvas with one small clip:
  `ffprobe` reports an alpha pixel format and a corner pixel decodes with
  alpha 0; the clip's pixels are unchanged from the opaque export.
- The recipe at `t` with the option carries a text layer whose content is
  the document's timecode for `t` (core test); the burnt-in frame differs
  from the plain frame only inside the caption's box.
- Quit and relaunch keep the last export choice; a saved preset reproduces
  the same resolved settings JSON.
- Two queued jobs produce files identical to two single exports.

**What landed.** All five parts, with NO project-schema change (version 6
stands), NO new op (`OP_NAMES` is still 55) and NO new tool (the catalog is
still **73**) — the first phase whose whole surface is new ARGUMENTS on
tools that already existed, which is why phase 6's `TOOLS = 73` assertion
needed no edit. One new FFI export, three files that paid the size rule
first, and **170 new checks** (169 at the landing; the adversarial review
added one).

**Three cuts before a line of feature code**, and phase 6's lesson about
budgeting them against the pessimistic number held: `recipe.rs` 600 → 381
with its text machinery in a new `core/src/recipe_text.rs` (456 with the
burn-in in it); `export.rs` 579 → 222 with its table in a new
`core/src/export_table.rs` (509); and `ExportSheetController.swift`
1114 → 450 into `ExportSheetOptions.swift`, `ExportSheetResolve.swift` and
`ExportProgressSheetController.swift`. All three were PURE MOVES, landed
and gated alone — 436 tests, 0 typecheck errors, the same four warnings —
so anything that moved afterwards is attributable. Two more files paid it
mid-phase without being asked: `Exporter.swift`, which was AT 600, gave up
`ExporterSettings.swift` (127) before taking its `RecipeOptions` argument,
and `ExportSheetController.swift` gave up `ExportSheetPresets.swift` (242)
when the preset row would have put it 150 over.

**Save Frame (7a)** is File ▸ Save Frame… ⌥⌘E, and the shape is the point:
`app/Sources/FrameWriter.swift` is a value type — **a CGImage and a format
in, a written URL out**, with no panel, no document and no AppKit view in
it — that BOTH the panel and `render_frame` call. That is what makes "Save
Frame's PNG is byte-identical to `render_frame`'s" true by construction
rather than by luck, and construction is the only thing that can carry it:
a save panel cannot be driven over MCP or put up offscreen, so the road
map's proof line above is unreachable as a MEASUREMENT and stays so — the
move made it true, not testable. Say that plainly wherever the proof is
described, because "Save Frame ≡ `render_frame`" as a section title reads
as a comparison somebody ran. What the scripts do reach is
`render_frame`'s two SPELLINGS writing byte-identical files
(`phase7_proof.py` section 2) and `FrameWriter` called directly on a
synthetic card (`phase7_chrome.py` section 2); neither touches
`renderAndWriteFrame`, which is private. PNG keeps a NIL properties dictionary; **JPEG flattens onto BLACK**
at quality 0.9, deliberately and out loud, because 7b makes a transparent
canvas reachable in this very phase; HEIC is `UTType.heic` (`public.heif` is
not registered here). `render_frame` gained `path`, `format` and
`burn_in_timecode`, and `replaceableExtensions` gained `png`, `jpg`, `jpeg`,
`heic` and **`gif`** — the last fixing a pre-existing bug where
`export {path: "x.gif", preset: "apng"}` wrote `x.gif.png`.

**ProRes 4444 (7b)** is a `prores_4444` row and an `alpha` key in the
resolved settings, and TWO of the road map's sentences about it were wrong.
"`alpha: true` whenever the canvas background's alpha is below 1" would put
`alpha: true` on an H.264, a GIF and a WAV, because `export_settings` emits
one flat object for every row — so **`alpha` is a per-row CAPABILITY**,
"this encoding carries an alpha channel", on `audio`'s own precedent ("a
fact about the CONTAINER rather than a decision about the project"). And
"the Document tab's background well gains an alpha slider" describes work
that was already shipped: `NSColorPanel.shared.showsAlpha` is set app-wide,
the swatch draws a checkerboard and `DocumentPane.colorName` already printed
"Transparent", so a person could set a transparent canvas before this phase
began. What landed instead is a conditional NOTE in the Document tab, which
appears only when the background goes translucent and names the rows that
can keep it. **No Swift writer change was needed at all** —
`codecType(for:)` already mapped the codec and the reader already asked for
32BGRA — which a spike established before any model code, along with the
half nobody had checked: that alpha survives
`AVAssetReaderVideoCompositionOutput` with a custom compositor, which is the
path the exporter actually uses.

Two things about `alpha` were found by MEASURING rather than reasoning, and
both changed the code. **`apng` carries alpha too** — it was written
`false`, and an APNG of a transparent canvas decodes `pix_fmt=rgba` with its
corner at alpha 0 — while `gif` stays false although a GIF can also show a
transparent pixel: APNG has a real fourth channel and a pixel may be any
fraction of opaque, a GIF nominates ONE palette index and has no partial
value to store, so a flag saying yes to both would license the sheet to
promise a translucent GIF. And **a ProRes 4444 export at a PADDED size wrote
INVERTED alpha** — a 320 × 180 transparent canvas at 240 × 240 came back
with the picture at alpha 0 and the letterbox bars at alpha 255 — while any
same-aspect resize, up or down, is correct at every pixel. So
`ExportWriter.checkAlphaSurvivesTheSize` REFUSES the aspect change by name
rather than writing a file that is silently wrong in the one respect the row
exists for; only a hand-typed Custom size can reach it, since every row of
the Size popup is already fitted to the document's aspect. The other alpha
row needs no guard and must not grow one: `apng` takes the ImageIO path,
which FITS instead of padding (240 × 240 asked of a 16∶9 canvas writes
240 × 135).

**The burn-in (7c)** is a RECIPE option, never an export override —
`export_overrides.rs` ignores an unknown key silently, so one sent through
`rc_export_settings` would vanish and the tool would report success on an
un-burnt file. It travels three ways, and the third is not belt-and-braces:
the new FFI export `rc_project_frame_recipe_opts`, per-KEY options on
`RecipeSource`, **and a parameter on `Exporter.renderFrame`** — because GIF
and APNG never go through `ExportWriter` at all (`ImageSequenceWriter`
calls `renderFrame` per frame, registering its own key), so plumbing the
option only through the export's key would leave every image-sequence export
silently un-burnt. The layer is appended LAST (topmost) so an un-optioned
`frame_recipe` is byte-identical by construction; it emits all twenty layer
keys and all six source keys through a factored `RecipeLayer` skeleton that
`Project::layer` now shares, and the refactor was proved byte-identical
against a `git worktree` at pre-cut HEAD over eleven ticks of a project
carrying transitions, an animated text clip, a gradient, an action and a
nest. Three readings are correct and are stated where a reviewer would
otherwise file them as bugs: the placement is a FRACTION of canvas height
(0.44) with `valign: middle`, not a bottom margin, because the core stores
no measured text size and by standing rule never will; the timecode is
NON-DROP, so a 29.97 burn-in reads about 3.6 s behind wall clock at an hour,
which is the definition the toolbar already displays; and it shows PROJECT
time on an in/out range export, so a range starting at 00:00:10:00 writes a
file that begins at 00:00 carrying a burn-in reading 00:00:10:00 — which is
what a review copy should do.

**Remembered settings and presets (7d)**, and the road map's central claim
here could not be built. It says user presets are "a name → overrides map …
resolved by the core's `export_settings` like any overrides, so the core
never learns about them". The ENCODING is not an override — `rc_export_settings`
takes the preset id as a separate argument and `export_overrides.rs` has no
`preset` key and would drop one silently — and a resolved map cannot RESTORE
the sheet, because the Quality popup stores a bits-per-pixel TIER and derives
a bitrate at pick time while the Size popup stores a ROW ID: given back
`{width: 1920, height: 1080, video_bitrate: 8000000}` the sheet cannot tell
"1080p + High" from "Custom 1920 × 1080 + a typed rate", and re-applying an
absolute bitrate on a differently sized document silently changes what "High"
meant. **So a stored preset is the CONTROL CHOICES**, resolved through the
sheet's existing `overrides()`; the half of the sentence that stands is that
the core never learns about them, and `rc_export_settings` is untouched. The
restore ORDER is load-bearing and is the phase's most breakable app code: the
format is selected BEFORE `rebuildSizes()` (a programmatic `selectItem` sends
no action, so `formatChanged`'s guard will not fire), the size AFTER it (that
call ends with an unconditional `selectItem(at: 0)`) and by `ExportSize.id`
never an index, "Custom…" is chosen before the loudness field is filled, and
a remembered `in_out` degrades to "Whole project" on a document with no range.

**The queue (7e)** runs one job at a time from the MAIN thread with a FRESH
`Exporter` per job — a chain, not a pool, because `Exporter.export` is
main-thread-only and its run-loop timer must die on the thread that scheduled
it; the proof's `all-at-once` mutant showed the alternative, leaving job 1
orphaned in `.running` for ever, so **two concurrent `Exporter`s deadlock**.
`mediaURLs()` is captured AT ENQUEUE, because it resolves bookmarks and hits
the filesystem at call time and resolving at run would pick up a Relink… the
person did afterwards. `ExportQueueController` has **no AppKit in it** and
that is the design, not an accident: a queue window cannot be photographed
offscreen or driven over MCP, and adding a tool purely so a proof could exist
would be the proof deciding the product's API — so the controller is drivable
by a probe and the window is a pure reader. It gets **no MCP mirror** and the
doc says so in three places: the rule is that every user-visible EDIT gets
one, a queue edits no project, and an agent calling `export` N times in
sequence already has the capability.

**Measured.** `make test` **456** (436 before — `core/tests/recipe.rs` 15 new
and `core/tests/export.rs` 30 → 35), `make lint` and `cargo fmt --check`
clean, `make typecheck` 0 errors and the same 4 AVFoundation warnings,
`make app` building, the catalog at **73 tools**, `OP_NAMES` at 55, no
`RC_FORMAT_VERSION` move, and the startup parity log EMPTY on every launch.
The phase's own scripts are `tools/proof/phase7_proof.py` over MCP at
**92/92** and `tools/proof/phase7_chrome.py` offscreen at **78/78** (77 at
the landing; the adversarial review added one check and repaired another that
could not fail), and
phases 1–6 all prove unchanged against the final binary: 66/66, 85/85,
121/121, 8/8, 84/84, 88/88, 167/167 over MCP and 26/26, 33/33, 59/59, 81/81,
70/70 offscreen — `phase5_chrome.py`'s cross-build comparison among them,
which names phase 7 by name and is scoped to the timeline bar this phase
never touched.

**Mutation-tested to twenty-four mutants across the two scripts** — nine for
the MCP half, fifteen for the probe half — each a build of its own with the
app RELAUNCHED between them, and every mutant checked for actually mutating
before it was believed. Four results were worth more than the kills. A
`recipe_text.rs` given a hard-coded pixel `y` drew correctly on the 360-tall
fixture and at 0.646 of the frame on the 720-tall one, which is the whole
argument for rendering the burn-in section at TWO canvas heights. A
`FrameWriter` whose ADD call was handed `[:]` instead of `nil` SURVIVED, and
the finding is that it is a no-op on this OS: an empty dictionary and no
dictionary write byte-identical PNGs here (same sha256, same 5330 bytes, same
chunk list, across two processes), so no BYTE comparison could catch a
violation — while `[kCGImagePropertyDPIWidth: 144]` is caught by its `pHYs`
chunk. The rule stays `nil` as a forward-looking guard rather than as an
observation, because the next ImageIO owes us nothing, and the one assertion
that CAN see the difference is structural rather than pixel:
`phase7_chrome.py` reads `Format.destinationProperties != nil` and asserts
`[False, True, True]`. Say it that way in all four places — the review found
the stronger claim ("ImageIO writes different bytes for an empty dictionary")
still standing in `app/CLAUDE.md` and inside both proof scripts' own check
text, after `FrameWriter.swift` itself had already been corrected. A queue mutant that deleted the cancelled
job's `removeItem` SURVIVED, because `AVAssetWriter.cancelWriting()` already
removes its own part-file, so the check is worded as the OUTCOME and the
comment now says defence in depth rather than claiming a guarantee it does
not provide. And the probe's own driving found **a latent crash**:
`ExportWriter.cancel` reaching `reader.cancelReading()` before
`reader.startReading()` raises an uncaught exception that kills the process,
and the window is real because `Exporter.startWriting` calls
`progressHandler` between publishing the pipeline and starting it. No person
can reach it — a Cancel button is its own event — but the queue is a
programmatic driver and the next one will be too, so `cancel` is guarded on
`started` and `start` now honours a cancel that arrived before it.

Worth knowing, all measured: two ProRes 4444 exports of one unchanged project
differ in exactly SIX bytes when they land in different seconds (the movie
header's time fields, one-second resolution) and are identical within one
second, while H.264 is not byte-deterministic at all — which is why the
proof's byte claims are made over APNG; ffmpeg's ProRes decode reports the
compositor's PREMULTIPLIED values as straight while ImageIO un-premultiplies
PNG and APNG, so a colour comparison between the two formats is only safe
where alpha is 255; and AppKit BLANKS a duplicate key equivalent within one
menu, so a Save Frame on a bare ⌘E beside Export…'s would silently have no
shortcut at all rather than shadowing it.

---

### Phase 8 — Viewing and finding

*One session. No schema; view state throughout.*

- **Preview quality.** View ▸ Preview Quality ▸ Full / Half / Quarter
  scales the PLAYER's `AVMutableVideoComposition.renderSize` only; the
  compositor already draws to whatever target it is handed
  (`render_frame`'s `maximumSize` path proves it — check
  `renderContextChanged` is honoured), the `AVPlayerLayer` upsamples, and
  the overlay maps through `videoRect` so the handles do not move. Export
  and `render_frame` ignore it. Persisted in UserDefaults. Measure 4K on
  the compositor's timing log before deciding whether "Auto — half while
  playing, full when paused" should be the default.
- **Preview window.** View ▸ Preview Window (⇧⌘P) opens
  `PreviewWindowController`: a second `AVPlayerLayer(player:)` on the same
  player (a player drives any number of layers), no overlay, black
  surround, full-screen capable, frame autosaved so it stays on a second
  display. Transport keys forward to the editor.
- **Media tab search and sort.** `MediaPane.swift`: a search field (name
  contains), a sort popup (name, duration, added, kind), an "unused only"
  filter, and a "Reveal in Timeline" context item that selects the clips
  using that media. Spec §11 names a growing library as the trigger for
  revisiting the no-left-panel decision; this is the cheaper answer first.

**Where.** `Playback.swift`, `CompositionBuilder.swift` (render size for the
player's composition only), `PreviewWindowController.swift`,
`MediaPane.swift`, `AppDelegate.swift`.

**Proof.**
- Half quality drops the compositor's per-frame time (its own log) and a
  paused frame differs from full only by resampling; an export is
  byte-identical whatever the setting.
- The preview window shows the frame the canvas shows, at all times,
  because both are one player.
- Search narrows the list; Reveal in Timeline selects exactly the clips
  whose source is that media.

**What landed**, and where it departed from the plan above.

Three features, no schema change, **no new op and no new MCP tool** — the
catalog stays at 73, which is deliberate: search, sort and the filter are view
state (`selectedMedia` has never had a mirror either), Preview Quality changes
nothing an agent can observe, and Reveal is `set_selection`, which is already a
tool. Phases 6 and 7 assert `== 73` exactly and still pass.

*Two size tolls first and alone* (`b189ac3`): `AppDelegate.swift` 625 → 223
(`AppDelegate+Menus.swift`) before the View menu grew two items, and
`MediaPane.swift` 822 → 389 (`MediaRowView.swift`) before the pane grew a find
band. `MediaPane` then paid a SECOND toll mid-phase (`MediaPaneCommands.swift`)
— phase 6's warning arriving again, that an estimate of what a feature costs
here is worth about two thirds of the truth.

**8a — Preview Quality.** The road map's "Where" names `CompositionBuilder.swift`
and it is not touched at all. There is exactly ONE constructor of
`AVMutableVideoComposition` in the app, shared by the preview, both export passes
and the offline frame, so an argument there would leave the export one wrong
parameter away from the preview's setting; instead `Playback` `mutableCopy()`s
the built composition and overrides `renderSize` on the copy
(`ExportWriter.videoComposition`'s shape), which makes the export path
**unreachable** from the setting rather than merely unchanged by it. The size
always carries the canvas's EXACT aspect — `m · (w/g, h/g)` with `g = gcd(w,h)`
and `m = ceil(g/divisor)` — falling back to the next coarser exact size and
finally to Full for a coprime canvas, because the overlay maps every drag handle
through `AVPlayerLayer.videoRect`; odd render dimensions were measured LEGAL, so
the rule is about aspect and not about legality.
**The road map's proof line "half quality drops the compositor's per-frame time
(its own log)" could not be built and was dropped.** The log exists but emits
only after 120 frames in one `Compositor` instance, and `render_frame` builds a
fresh composition per call. Whether the preview is actually FASTER is unmeasured
and is a person's to check.

**8b — Preview Window.** The road map's parenthetical "a player drives any
number of layers" contradicts Apple's archived AVFoundation Programming Guide
("only the most recently created such layer will display"), so it was SPIKED
before anything was written: on macOS 26.5.1 two layers on one player, in both
creation orders, both return a non-nil `displayedPixelBuffer` with byte-identical
checksums, and releasing the second leaves the first displaying. The archived
guidance is stale and the road map is right. The spike's other finding is the
one to carry forward: **`isReadyForDisplay` and `videoRect` are useless as
instruments here** — a layer with no superlayer at all and a layer in a window
never ordered in both report `true` with a plausible rect, and
`displayedPixelBuffer` is the only property that discriminates.
Two deviations, both measured rather than argued. The window is an **`NSPanel`**,
because a titled `NSWindow` becomes key AND main and `NSApp.target(forAction:)`
for every editor selector then resolves to NONE — ⌘E, ⌘T, ⌘0 go dead while the
preview is focused. And retention is **one stored property on the frozen
`EditorViewController`**, not `document.addWindowController(_:)`, because AppKit
only asks a document about saving when the controller closing is the LAST one: a
probe with a dirty untitled document got a save sheet with one controller and,
with two, no sheet, a destroyed editor window and a document left open behind a
panel with nothing to edit in. That is a data-loss shape.

**8c — the Media tab.** The sort row is **"Import Order"**, not the plan's
"Added": nothing records when a file arrived, and a timestamp would be a
version-7 bump the phase is declared to avoid. The find band **never rebuilds the
pane** — `InspectorPaneView.rebuild()` removes every arranged subview and there
is no first-responder preservation in the inspector, so a field built inside
`makeSections()` loses its caret on the first keystroke; the pane hides and
re-orders the rows it already has, and `structureSignature` stays a statement
about the MODEL. Along the way the phase fixed a live defect it did not go
looking for: **"is this media used" was written out twice in Swift and both
spellings missed nests**, so removing a file used only inside a nest gave a bare
beep with no reason in it. It is one question with one answer now
(`MediaUsage.swift`), walking the nests the way the core's `every_clip()` does,
and Remove, the filter and `remove_media` all ask it.

**8d — the blocker the review found, and the lesson under it.**
`[[position]].xy` in the fragment stage arrives in DESTINATION pixels, and three
shader tests took it to BE canvas pixels: a nest's `clip_rect`, the drop shadow's
mask sample, and the outgoing dissolve's partner box. For the app's whole history
the two were equal — `CompositionBuilder` is the only other writer of
`renderSize` and always sets it to the canvas — so the assumption was true, was
written into three comments AND into `core/src/nest.rs` and spec §7.3, and was
invisible. Preview Quality made the destination smaller and it became a wrong
PICTURE: three quarters of a nest erased at Half and all of it at Quarter, a
shadow displaced to the corner or vanishing, a dissolve losing the weight
correction whose absence "dips the whole frame ~25 % dark at the midpoint".
`LayerUniforms`' two remaining padding floats became `canvasPerDestX/Y` (the
block is still 416 bytes and the tail is now EMPTY), `ShadowUniforms` went 8
floats to 12, and a non-positive ratio reads as 1 so a zeroed block renders what
it always did. **An invariant that holds because two numbers have always been
equal is not an invariant** — and phase 8a's own doc had already leaned on the
shadow mask being canvas-sized, but only to argue that it does not get CHEAPER.

**Measured.** `make test` 456 unchanged (no core change but two doc
corrections), `make lint` and `cargo fmt --check` clean, `make typecheck` 0
errors and the same 4 AVFoundation warnings, `make app` building, the catalog at
73 and the parity log EMPTY. `tools/proof/phase8_proof.py` **79/79** over MCP —
its headline is two INSTANCES of one binary, one launched
`-ReelcutPreviewQuality 2`, whose `render_frame` PNGs and `apng`/`gif` exports
are byte-identical — and `tools/proof/phase8_chrome.py` **144/150** offscreen,
the six being section 4's dispatch checks, which fail on their own PRECONDITION
because this machine's console is LOCKED and no process can activate. Phases 1–7
re-run unchanged: 66, 85, 121, 8, 84, 88, 167, 92 over MCP and 26, 33, 59, 81,
70, 78 offscreen — the last group AFTER the shader change, which is what says it
moved no render it was not meant to.
**Ten mutants across the two scripts.** Two survivors, both reported rather than
hidden: `MediaUsage.usesMedia` losing its nest walk is invisible to the MCP
script (no tool calls it — the chrome script kills it), and the panel's frame
RESTORE is dead code today for a reason worth keeping. The most valuable result
was a kill that did not happen at first: **`phase8_proof.py` as first written
scored a clean 65/65 against a build with 8a deleted outright.** Section 5 — a
probe reading the render size off a real `AVPlayerItem` — is what closes it, and
both numbers are in the script's docstring, because the survivor is the argument
for the probe. The aspect rule taught the same lesson from the other side: a
naive `w/2, h/2` PASSES on 1920×1080, 1280×720, 3840×2160 and 100×100 and fails
only on 999×666, 1001×667 and 1366×768, so the odd canvases are the check.
**Reviewed by seven readers against three sceptics each: 33 findings, 19
survived**, two of them unanimous blockers with the one root cause above. The
others worth knowing: forwarded bare keys ran editor EDITS while a sheet was
attached to the editor window (a sheet is WINDOW-modal, so the panel stays
key — the guard is in `handleEditorKey` now, where both windows inherit it);
⌘Z / ⇧⌘Z were DEAD while the panel was key, because `undo:` is not an editor
selector but one `NSWindow` implements itself, so the search stopped at the
panel's own empty manager — the controller is the panel's delegate now, and the
type doc's claim that "a panel keeps ⌘Z alive" was a measured falsehood; and the
Media tab's Relink… was the only one of three relink paths that never
regenerated caches, so a relinked file got no filmstrip, thumbnail or peaks
(pre-existing, fixed here).
Two limits recorded rather than fixed here: `ProjectDocument.selectedMedia` can
point at a row the filter has hidden, and `generateCaches`'s "a cache already
on disk is not rebuilt" was FALSE — measured, it re-decoded — which was a wrong
comment and wasted work, not a wrong picture. The second was closed after the
road map, by a completion marker that makes the sentence true
(`designs/reelcut-remaining.md` records it; `MediaCacheFiles.swift`'s
`CacheStamp` is the code).

#### #35 — Space toggles play wherever nothing is typing (2026-09-24)

kpgalligan/reelcut#35: a bare Space beeped instead of playing after an
inspector number field was committed. `OptionFieldControl.finishEditing`
(`OptionControls.swift:244`) ends every edit with
`window?.makeFirstResponder(nil)`, which leaves the WINDOW as first
responder; `NSWindow.keyDown` forwards to nothing and
`NSResponder.noResponder(for:)` beeps, so the key never reached
`EditorViewController.keyDown`, whose `case " "` was correct and
unreachable from that state. `TimelineView.endRename` already documented the
state and patched it for renames only.

**What landed.** `app/Sources/EditorWindow.swift` (new): `SpaceKeyRoute`,
`SpaceKey.route` — one pure function deciding a bare Space key-down BEFORE
dispatch — and `EditorWindow: NSWindow`, whose `sendEvent` toggles play
through `EditorViewController.playPause` on `.transport`, swallows `.held`
(an auto-repeat) and passes everything else to `super` (spec §11 K-1). Its
two inits only forward or refuse: the unavailable `init?(coder:)` alone
stops Swift inheriting `NSWindow`'s designated init, so the forwarding one
is declared beside it. `EditorWindowController.swift` constructs
`EditorWindow` — one word. No frozen file edited; `handleEditorKey`'s
`NSText` and `attachedSheet` guards stay for the preview panel's forward.
No core change, no FFI, no MCP mirror (playback is view state).

**Measured.** `tools/proof/space_key_proof.py` over its probe
`space_key_probe.swift`: **28/28** on the fix, exit 0. All eighteen S1 rows
pass (`SpaceKey.route`, pure), and S2a–S2g pass in the app's own window: S2a
from the window as first responder, Space plays (isPlaying true) and Space
again pauses; S2b a custom `NSView` first responder sees no keyDown and play
toggles; S2c the timecode field's field editor types the Space (string
`" "`, paused); S2d the canvas overlay's down leaves play alone and its up
toggles; S2e an `NSButton` first responder is handed the Space (its keyDown
sees it once); S2f an auto-repeat is swallowed; S2g the document's window is
an `EditorWindow`. `--baseline 1888069` (`git archive`,
`-D HARNESS_REFERENCE_BUILD`) fails EXACTLY S2a (isPlaying false after both
Spaces — the beep path) and S2b (keyDowns 1, the key walked the chain), as
predicted, and exits 0.

**S2e scores the hand-off, not the press.** As first written the row
asserted AppKit's own Space-press on the button (presses 1, play paused);
it failed on BOTH trees (presses 0), because a button presses on Space only
under Full Keyboard Access, which is off on this host
(`NSApp.isFullKeyboardAccessEnabled` false) — and with it off, by AppKit's
convention (not measured here), a click does not make a button first
responder, so the product does not reach that state. What the WINDOW decides is
that the button gets the key, so the row asserts that (a counting
`keyDown` override that calls `super`, count 1) on either host; FKA, the
press count and `isPlaying` are printed in the detail only. A row branched
on FKA was rejected: its FKA-on branch would never have run on any host,
and only the recording proof may skip a row for a host condition. The
press itself is `designs/reelcut-remaining.md` §4's hands-on check.

**Deviation from the spec's fixture.** The spec's package was one 6 s grey
shape card. Measured in a scratch probe: over a shape-only plan
`playerLayer.player` had NO `currentItem` (`Playback.startRebuild` drops
the item when the plan has neither a video nor an audio track), so `play()`
beeps and nothing toggles in any tree. The package keeps the card at 0–6 s
and adds 6 s of `tools/proof/media/A.mov` after it; the playhead starts on
the card. The proof also builds the app's `Compositor.metal` into a
`default.metallib` beside the binary (`mixed_audio_probe.py`'s
`build_shader`). The `.accessory` activation fallback was NOT needed: S2c
typed its Space under `.prohibited`.

**Owed.** The beep's absence and a button's Space press under Full
Keyboard Access, at the machine: `designs/reelcut-remaining.md` §4 carries
those checks and §5 the paragraph. `app/CLAUDE.md`'s "Dialogs and windows"
map entry gains `EditorWindow.swift` — applied by the orchestrator after
review 2 (verdict pass), with that review's two prose nits.

---

### Phase 9 — Inside the nest

*Two sessions. No schema. The largest item, last because it touches every
op at once — and the one the spec designed and left (§4.4).*

The block is that every op's clip argument resolves through
`Project::clip`, which sees the top level only. The fix is not to teach
every op about nests; it is to give the op a **scope**.

- **Core.** The envelope gains `scope?: u32` (a nest id). With a scope,
  `Project::apply` builds a **view project** — canvas = the nest's frozen
  size at the parent's fps and background, `tracks`/`clips` = the nest's,
  `media` and `nests` = the parent's, `markers` = none, `next_id` = the
  parent's — applies the op to it unchanged, and writes `tracks`, `clips`,
  `next_id` and any nests added or dropped back into the parent. Every op
  works inside a nest without an edit to it, `Project::clip` keeps its
  meaning, and undo is still one stack of parent handles. Ops with no
  meaning inside (`set_canvas`, the marker ops, `add_media`,
  `relink_media`, `remove_media`, `nest` of the whole scope into itself)
  are an `Err` naming the scope. Caps are the parent's, as today.
- **Reading inside.** `rc_project_scoped(handle, nest_id)` returns a new
  immutable handle for the view project — one new export, so header and
  `ReelCore.swift` move in lockstep — and the app plays, plans, renders
  and snapshots it like any project: the composition plan, the frame
  recipe and the timeline all come from the scoped handle, while every edit
  goes to the PARENT's handle with `scope` set. Nest-local time is
  `t − nest_clip.start`; a nest has no speed, so nothing else maps.
- **App.** `EditorViewController+NestScope.swift`: double-click a nest clip
  (or Clip ▸ Open Nest, ⌘↓; Clip ▸ Close Nest, ⌘↑) sets a view-state scope;
  the timeline and canvas show the scoped snapshot; a breadcrumb
  ("Timeline › Intro", click to go out) sits at the left of the ruler over
  the track headers, where the 22 pt row has room; the canvas shows the
  nest at its own frozen size with the outer transform NOT applied (a
  compound clip is edited on its own terms). The playhead maps in and out
  so the frame stays. Leaving re-selects the nest clip. Entering and
  leaving is not an undo step. `ProjectDocument.applyEdit` is unchanged;
  the scope rides in the op JSON.
- **MCP.** Every op tool takes `scope?`, checked like any argument
  (`AgentServer+Arguments.swift`); `set_scope {nest?}` mirrors the
  double-click so `render_frame` and `get_project` can look inside;
  `get_project` reports the scope with the playhead and selection.

**Where.** `edit.rs` (the envelope and the view/write-back), a new
`core/src/scope.rs` for building the view and merging it back, `ffi_query.rs`
+ header + `ReelCore.swift`, `core/tests/scope.rs`; Swift:
`EditorViewController+NestScope.swift`, `TimelineView` extension for the
breadcrumb, `Playback.swift` / `CompositionBuilder.swift` taking the scoped
handle, `AgentServer+Arguments.swift`, `AgentServer+Project.swift`, catalog.

**Proof.**
- For a table of ops (slip, trim, split, set_video, add_text_clip, delete,
  move_clip), "apply inside with `scope`, then `unnest`" equals "`unnest`,
  then apply at top level" on clip content, ids aside.
- A frame rendered inside equals the corresponding region of the outer
  frame when the nest clip is at the identity transform.
- Entering, editing, leaving is exactly one undo step per edit, and undo
  restores the outer frame.
- A file of every earlier version is untouched; `rc_op_names` is unchanged (scope is an envelope
  key, not an op).

**What landed**, and the five places the plan above could not be built as written.

No schema change (v6 stands), NO new op (`OP_NAMES` is still 55) and ONE new
tool (`set_scope`; the catalog is **74**, and phases 6, 7 and 8's exact `== 73`
assertions became floors in the same change). One new FFI export. Two size
tolls paid first and alone (`edbeb2e`): `AgentCatalog.swift` 1552 → 665 and
`ReelCore.swift` 2242 → 1446.

**(1) The envelope could not simply gain a key.** `Op` is internally tagged
with `deny_unknown_fields`, so a top-level `scope` is an unknown field for all
55 variants — measured against the shipped build before a line was written —
and `#[serde(flatten)]` is not the way round it, since serde does not support
the two together. `parse` was ALREADY a two-pass parse holding the envelope as
a `Value` to read `"op"`; it takes `scope` out in that same pass and answers an
`Envelope`. All 55 variants and `apply_op(&Op)` are untouched.

**(2) The view's `nests` could not be "the parent's".** Every clip of the
scoped nest would be inserted into `validate`'s one id set twice, so the FIRST
op inside a scope would be an `Err`. **And the obvious repair — filter the
scoped nest OUT — is also wrong**, which a failing test found and no reader
did: `check_clips` resolves every `Source::Nest` in EVERY container, so scoping
into a nest that ANOTHER nest shows leaves that other nest's clip naming a nest
the view has not got (`clip 172 in nest 170 refers to unknown nest 180`). The
answer is to KEEP the row and EMPTY its tracks and clips.

**(3) Caps are not "the parent's, as today".** `check_caps` sums the
timeline's with every nest's, and a view holds the nest's clips at top level
and the timeline's nowhere — so its totals are strictly LOWER and an op refused
at the parent's cap would be accepted inside a scope, surfacing at SAVE. Same
for depth: `check_nesting` starts every walk at level 1. Both are checked ONCE,
on the MERGED parent, which gives the phase its most surprising contract:
**an op can be perfectly valid inside the nest and the scoped apply still
returns `Err`.**

**(4) `media` was missing from the write-back**, and `paste` appends to it, so
a paste inside a scope would have named a media the parent has not got.

**(5) A nest DROP must never be applied from the view.** `unnest`'s
`nest_is_shown` asks `every_clip()`, which in a view cannot see the parent's
timeline clips, so un-nesting an inner nest a TIMELINE clip also shows would
judge it unused and leave that clip dangling. The merge takes the UNION and
collects orphans against the merged parent afterwards.

**And one entry deleted from the plan**: "`nest` of the whole scope into
itself" is not a case. `nest` mints a fresh id and puts the new clip INSIDE the
scoped nest, so nothing points at its own container; it is a legal extra level
bounded by `MAX_NEST_DEPTH`, and there is a test saying so. The refusal list is
the three marker ops, `set_canvas` and the three media ops — SEVEN names, and
`refused_inside` is an exhaustive 55-arm match so a later phase's op will not
compile until it is classified.

**The app.** `nestPath` is a PATH of (nest, clip) steps, not a bare nest id,
because a nest can be shown by TWO clips at two different starts. The scoped
handle is STORED and memoised (`ReelProject` memoises per handle, and ~78 read
sites would otherwise re-decode). One named accessor, `editedProject`, and the
flipped sites are enumerated — `project` still means the PARENT for save,
export, consolidate. `clampViewState` clears a dead scope FIRST, then the
selection, and the order is load-bearing. Double-click enters (a nest clip
loses rename-by-double-click; ⇧⌘R and the Clip tab's header field remain).

**Reviewed by six readers against three sceptics each: 34 findings, 13
survived.** Three were the same shape and are worth carrying forward as one
lesson: **a nest-local number spent as project time.** Save Frame rendered the
DOCUMENT at a nest-local playhead (a wrong picture, and it broke the one-writer
identity phase 7 built `FrameWriter` for); an in/out range set inside a nest was
spent by the export card as project time; and `add_marker`/`set_marker` over
MCP placed at a nest-local tick while the UI had already refused exactly that.
The rule now written down: **a producer reads the container it writes into**,
and a range belongs to the container it was set in and never leaves it —
refusing rather than mapping, because a nest clip is TRIMMED, so a mapped range
can name content that was never on screen. The captions group was the same
defect in four more files and is fixed.
Two others with teeth: a REVERT left `nestPath` and the memo pointing at a
discarded document — worse than it read, since every subsequent edit was then
refused with `no nest with id N` — and the breadcrumb was invisible whenever
the timeline was scrolled vertically, because the header column sat ABOVE the
floating ruler. That z-order was wrong for EIGHT PHASES at the top level too:
scrolled, the corner showed the top sliver of a track header. No proof script
could see it, because every harness render is at scroll 0.

**Measured.** `make test` 456 → **494**, `make lint` and `cargo fmt --check`
clean, `make typecheck` 0 errors and the same 4 AVFoundation warnings,
`make app` building, the catalog at 74 and the parity log EMPTY.
`tools/proof/phase9_proof.py` **184/184** over MCP and
`tools/proof/phase9_probe.py` **48/48** against a probe compiled from the whole
of `app/Sources` (the op envelope, `isDocumentLevel` and `NestScope`'s
arithmetic have no caller a running binary can reach). Phases 1–8 all re-run
unchanged: 66, 85, 121, 8, 84, 88, 167, 92, 79 over MCP and 26, 33, 59, 81, 70,
78, 150 offscreen. Those are the gate's numbers, kept as history; two of the
review wave's fixes shipped with only an untracked instrument each and have a
tracked proof now — the marker-scope refusal and `scopeLanding` as
`phase9_proof.py`'s section 9 (**214/214**, its two mutants 209/214 each), and
the corner photographed SCROLLED by `phase9_chrome.py` (**62/62**, three
mutants at 52, 57 and 55 of 62).
**Twenty-four mutants across the two halves** — 15 in the core wave, 9 in the
proof — with two survivors, both reported. The core's survivor is equivalent (a
view carrying the parent's markers changes nothing the core can see) and the
MCP script then KILLED it, because `get_project` inside a scope reports the
view: a view somebody can look at is a contract. The proof's own survivor is an
honest gap — the merge's orphan rule bites only when `unnest` runs inside a
scope on a nest a timeline clip also shows, which the script does not stage,
and `core/tests/scope.rs` owns it. Two kills are worth repeating: the mutant
that gave the view the PARENT's canvas would have SURVIVED the region
comparison alone, because inner and outer then have the same size and the
comparison degenerates into a whole-frame identity — the render-size checks
beside it are what caught it; and the mutant putting the seam defect back is
caught not by a wrong picture but by an outright refusal, which is the shape a
guard should have.

---

## 3. Proposed keys and menu items

Checked against spec §9 for conflicts; a phase that binds one promotes its
row into §9.

Phases 1, 2, 3, 7 and 8's rows have been promoted into spec §9's bound table
and are struck from this one; what is left is what is still only a claim on
a key. Phase 3 took `Z` — bare, to arm and disarm the canvas region mode,
with ⇧Z still Fit Timeline. Phase 4 took NO key: its three commands are
File-menu items, and a modifier-less menu key is resolved ahead of the
first responder, so one would steal a letter the editor's own `keyDown`
owns. Phase 5 took no key either, for the same reason and one more: §9's
table below claims no row for it, and its one new command duplicates a pane
button that is already the everyday path. Phase 6 took none. Phase 7 took
⌥⌘E for File ▸ Save Frame… — Export…'s letter under a second modifier —
and its row went into §9 and out of here; Window ▸ Export Queue and the
export sheet's own new controls take no key at all. **Phase 8 took the ⇧⌘P
this table claimed for it**, for View ▸ Preview Window, and it is a TOGGLE
rather than an opener — the item carries a checkmark, so one key both opens
the window and puts it away, which is what Snapping and Safe Areas do with
theirs. Its neighbour View ▸ Preview Quality ▸ took none, for the reason
phases 4, 5 and 6 all record: every bare letter belongs to the editor's own
`keyDown`, and a modifier-less menu key is resolved ahead of the first
responder.

| Keys | Action | Phase |
|---|---|---|
| ⌘↓ / ⌘↑ | Open / close nest | 9 |

Menus. **Landed in phase 1**: Clip ▸ Close Gap, and Edit ▸ Insert at
Playhead / Overwrite at Playhead / Select All on Track. There is no Edit ▸
Lift item and there should not be — a lift is what ⌫ does with a range and
nothing selected, so it is the Delete item's other half rather than a
second row saying almost the same thing. **Landed in phase 2**: Clip ▸
Rename… and Label ▸ (the six colours, each with its swatch, then None),
Edit ▸ Paste Attributes, and Track ▸ Solo — no key, a checkmark for the
current track, the header's S being the everyday path. **Landed in phase
3**: Clip ▸ Remove Silences…, with no key equivalent and in the cutting
group beside Close Gap. Zoom to Region and Zoom Back got no menu items on
purpose — `Z` and the Video sections' two buttons are the paths, `C`'s
crop mode being the precedent for a bare-key canvas mode. **Landed in
phase 4**: File ▸ Generate Captions… and File ▸ Export Captions…, both
without a key equivalent and both directly under Import Captions…, so the
three caption items read in the order a caption track comes into being and
leaves again. **Landed in phase 5**: Clip ▸ Normalize, no key equivalent
and beside Detach Audio, because those two are the Clip menu's only sound
commands. It duplicates the Audio section's own Normalize button
deliberately — a command reachable from a pane alone can be lost (Add
Shape's lesson), and a menu item is what gives the `normalize_clip`
mirror a UI path to name.

**Landed in phase 6**: Clip ▸ Add Background ▸ (Solid Color · Image…) and
Clip ▸ Add Blurred Background, in a group of their own after the Transition
submenu because neither edits the selection — both put a clip on a new
back-most track. Add Background is a SUBMENU rather than the road map's one
dialog: its two rows are two commands and not two settings of one, since
Solid Color takes no dialog at all (hence no ellipsis) and is re-coloured
afterwards in the Shape section's Fill row, which is also how a full-canvas
gradient is reached, while Image… is a standard open panel. Neither takes a
key equivalent, for the reason phases 4 and 5 record: every bare letter
belongs to the editor's own `keyDown`, and a modifier-less menu key is
resolved ahead of the first responder.

**Landed in phase 7**: File ▸ Save Frame… (⌥⌘E), directly under Export… with
no separator between them because a still and a movie are the same command
asked of two containers; and Window ▸ Export Queue, with no key equivalent
and `isExcludedFromWindowsMenu` set on its window, or AppKit lists it twice.

**Landed in phase 8**: View ▸ Preview Quality ▸ (Full · Half · Quarter) and
View ▸ Preview Window, in a group of their own after a separator below
Timeline Track Height, because both are about the PREVIEW where everything
above them is about the editor's own panes. The submenu is built from
`PreviewQuality.allCases` and tagged with its raw values, so the menu cannot
list a quality the enum has not got; only Preview Window takes a key.

**Landed in phase 9**: Clip ▸ Open Nest (⌘↓) and Clip ▸ Close Nest (⌘↑), in
the grouping group beside Group / Ungroup, as two items rather than one toggle
— a person reaching for ⌘↑ wants OUT, and a toggle makes them read the menu to
find out which way it will go. Double-clicking a nest clip enters it too, which
costs a nest clip its rename-by-double-click (⇧⌘R and the Clip tab's header
field remain). Both items are validated DEAD while text is being edited, the
Delete pair's precedent: carrying a modifier does not keep a menu key off the
first responder — every main-menu equivalent is offered the key-down first —
and without the guard ⌘↑ in an inline rename would leave the nest and discard
the open field.

Nothing is still to come. Every row of this table has been promoted or
struck.

## 4. Considered and left out

Named so the next reader does not re-derive them.

- **Voice-over recording.** Spec §1 excluded screen and camera recording
  when this was written; road map 3 reversed the screen half and took the
  microphone with it — `ScreenRecorder` records a microphone to a second
  file beside the movie, with a meter, and lands it on its own track. What
  remains of this bullet is a PICTURE-LESS recording as its own command,
  which is a Source popup entry away and is left for whoever wants it.
- **LUTs (`.cube`).** Colour grading beyond per-clip controls is a non-goal.
- **Speed ramps.** `speed` is not an action target; a ramp is several plan
  segments at different rates, which `scaleTimeRange` can do but the model,
  the plan and the audio envelopes would all have to learn. Feasible, not
  asked for.
- **Motion blur, stabilisation, optical-flow retiming, auto-reframe.**
  Heavy pixel work or ML; outside the compositor's one-pass shape.
- **Multicam, plugins, other platforms.** Spec §1.
- **A left-hand media browser with bins.** Phase 8's search and sort come
  first; §11 says when to revisit.

## 5. What "done" means here

The same as before: the phase's proof exists as measured output from the
built binary and from black-box core tests, `make test` and `make lint` are
clean, `make typecheck` is at its baseline, the status table above says
"done" with the date and the commit, and the phase's record in §2, the
spec's tables and the README say what now exists.

Phase 1 added one clause to that, having learnt it the hard way: **the
change has been read back adversarially and what that found is fixed and
covered.** A phase is not done because its own tests pass — those test the
cases whoever wrote them thought of. It is done when someone has gone
looking for what they did not.

Phases 4 and 5 added a second: **the proof has been made to fail.** A
script nobody has broken on purpose is a script whose checks are untested,
and both phases found checks that could not fail — phase 4's own "blank"
frame was the fully drawn one — by going looking. Build the broken binary,
watch the check fail, restore, and say in the write-up which mutations you
ran.
