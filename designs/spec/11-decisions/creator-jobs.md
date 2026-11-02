# Spec §11 — decisions: Creator jobs (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map `designs/creator-jobs.md` builds the six bets of its survey,
`designs/creator-survey.md`, for people who record themselves talking: the words (TX), the cursor
and the recorder (CU), the camera cutout and layouts (CO), vertical versions and framing (VR),
finding clips (FC) and switching between cameras and audio tracks (SW), with the shared work (CJ).
Its IDs follow CJ-7: phase XXn records XX-n0…XX-n9, a zero phase XX-1…XX-9, and a bet with no zero
phase records its scope-level decisions here under its own prefix. Each was recorded before its
code. The series continues in `creator-jobs-2.md` past about 500 lines, that file in
`creator-jobs-3.md` past the same, and that one in `creator-jobs-4.md`.

- **CJ-1 — Every exclusion spec §1 and §2 name is lifted; lifting makes a thing allowed, not
  scheduled (owner, 2026-11-01: "Remove all explicit non-goals").** Lifted: multicam; grading beyond
  per-clip controls and GR-20, GR-27…GR-30; a plugin system and §1's "nothing else is scriptable";
  §1's clause keeping third-party Audio Unit hosting out; motion blur; stabilisation; optical-flow
  retiming; auto-reframe; ML or heavy pixel work outside the compositor's one pass; callouts and
  reconstructing afterwards what the recorder saw; any platform but macOS; §2's pointer effects,
  templates, publishing to YouTube or Vimeo and a stock-media library. What is built is what a road
  map builds; this one builds CJ-2's six bets. **Standing as current design until a phase amends one
  in writing, before its code:** G-1 (a graphic is a SOURCE, not an effect; nothing else is
  scriptable here), AU-2 (no third-party Audio Unit is hosted here), R5-1 (closed vocabularies),
  `recording.md`'s "a recording is ordinary media" (amended by CU-2). Risk accepted: the spec no
  longer says what Frame Job will not be, so a request that once met a non-goal now meets a road
  map's scope. The literal reading — GR-20, GR-27…GR-30, AU-2's and G-1's §1 clauses — confirmed
  by the owner (CJ0a's question 5, 2026-11-01); nothing on that list is built.
- **CJ-2 — Road map "creator-jobs" builds the survey's six bets, led by people who record themselves
  talking.** TX, CU and CO first (talking heads and screen tutorials), then VR and FC (shorts), then
  SW (podcasts), in the lanes and order of the road map's "Phases". The survey's next tier and "Not
  worth chasing" are not built here and are neither in nor out. Survey decisions 3, 5 and 8 are CJ0a's questions
  7, 8 and 4, each answered yes (owner, 2026-11-01); 10 is not a build question. A trial finding that reorders phases is
  recorded as an amendment of this entry.
- **CJ-3 — The key rule: a feature that needs a language model or a cloud model works only when the
  person's key for it is present; without it, every control that would send is disabled with a
  tooltip naming the key and where it is set, and every tool call that would send refuses in that
  sentence (owner, 2026-11-01).** The keys are the Anthropic key (AI-8, Settings ▸ Assistant) and
  the AssemblyAI key (R6-5, Settings ▸ Transcription). No on-device fallback: Apple FoundationModels
  is not used and filler detection stays AssemblyAI's (TR-7 stands). Not "significant AI" and never
  gated: Vision, Sound Analysis, Speech (`SpeechEngine`), Silero VAD and `AUSoundIsolation`.
  "Present" is a stored non-empty key or the proof's environment variable, in R6-5's order; validity
  never decides a control. A result already made with a key stays usable without one (R6-16, R6-21
  stand): the gate disables only what would make a new request, and a tool that answers from a cache
  without sending answers without a key. AI-1 stands: a Claude call is the helper's. One
  implementation, CJ1's `ModelKeys`, applied to the shipped features and every bet's. Risk accepted:
  a person with no keys sees greyed commands where they once saw a sheet that explained itself; the
  tooltip carries the explanation.
- **CJ-4 — The recorder may ask for Input Monitoring, opt-in (owner, 2026-11-01; amends
  `recording.md`'s first bullet).** Only the recorder panel asks, and only when the person turns on
  a capture that needs it (CU's Record shortcuts) and presses Record. `record_screen` reads the
  grant and refuses by name with the fix, as it does for Screen Recording and Microphone. Nothing
  asks at launch, nothing else listens to the keyboard, and no global hotkey is added here: it is
  not in the six bets, and `RecorderStatusItem`'s reason (it would need Input Monitoring or
  Accessibility) no longer rules it out, so it is filed as a candidate at the close. It is the
  recorder's fourth grant (Screen Recording,
  Microphone, Camera, Input Monitoring). What is captured is CU-7's. Risk accepted: an ad-hoc signed
  build loses the grant at every `make app`, so a proof skips its granted tier by name and the rest
  is a JOB row.
- **CJ-5 — The owner's trial: one real video per lead segment, cut alongside TX, against criteria
  fixed now.** T1 is a talking head from S-TH1, T2 a screen tutorial from S-ST1, each cut to a state
  the owner would publish, three times: the baseline in the build current when TX1 starts; the
  checkpoint CP1 after TX3 (T1 again, cutting by deleting words; lane A holds TX4 until it is
  recorded); and the closing run at TX8. Recorded per video in "The owner's trials": its source and
  length; every point where the owner left Frame Job for another tool or gave up, with the tool and
  the reason; each step that took noticeably longer than it should; which bet would have changed it;
  at TX8, TX's figures. The verdict is recorded under this entry ("**Verdict (owner, date):** …"),
  as GR-1's was. Each finding becomes a phase, an amendment or an issue, never only a note in a
  reply. The trial is a one-off judgment and is not a row in `docs/manual-checks.md`; a check it
  leaves that should be repeated before releases becomes a JOB row citing "Source: the creator-jobs
  trial, T1/T2" (the grading trial's precedent, `docs/manual-checks.md:846–856`). Risk accepted: the
  trial may reorder the road map.
- **CJ-6 — The build arrangement.** The integration worktree `.claude/worktrees/creator-jobs`,
  branch `worktree-creator-jobs`, from main. Each phase is one litecode pipeline (design → adversary
  → implement → review → fix) in a lane worktree, gated (`make gate`) and committed there, rebased
  onto the integration branch by one serialized integrator one landing at a time, and gated again.
  At most three lanes; a lane never builds against another lane's unlanded phase. At each landing
  the integrator renumbers what collides: a format bump (provisional from 38) with its
  `schema_vN.rs` and `format_history.rs` paragraph, decision IDs only when two phases claimed one,
  JOB numbers inside their block, screen numbers, and every count of CJ-8 (g). Each landing is
  merged into main by fast-forward (CJ0a's question 1, owner, 2026-11-01).
- **CJ-7 — IDs and records.** Phases are `XXn` (TX, CU, VR, FC, SW, CO, CJ); a split phase is
  `XXna`, `XXnb`…, sharing its block; a lettered phase split again takes a digit (`CU3a1`, `CU3a2`),
  its letter alone naming both halves. Phase XXn's decisions are XX-n0…XX-n9; XX0's are XX-1…XX-9; a
  bet with no zero phase records its scope-level decisions here under its own prefix (VR-1…VR-7,
  TX-70; SW-3 is in SW0's block). Spikes are XX-S1, XX-S2…; each rule is fixed in the road map
  (`designs/creator-jobs.md`) before its run, and each run's `results.json` stores as `rule_sha256` the SHA-256 of that spike's entry
  in "Every spike, with its rule" (the entry's first line, `- **<ID> —`, and every following line
  that begins with two spaces, each with its newline; no blank line and no group heading), so
  records added elsewhere in the road map leave it unchanged. A spike runs at the head of the first phase that
  uses it, in that phase's lane. Manual checks are `JOB-n` in blocks of ten: CJ 1–9, TX 10–19, CU
  20–29, VR 30–39, FC 40–49, SW 50–59, CO 60–69; a bet that needs more takes the next free block
  from 70. Handoffs are `~/.claude/litecode/framejob/cj-<phase id lowercased>`. The road map
  (`designs/creator-jobs.md`) holds each phase's record.
- **CJ-8 — Shared reservations, so lanes do not collide.**
  - (a) The fifth inspector tab is TX's Transcript. Another tab, or a panel beside the inspector,
    needs a decision of its own (`InspectorViewController.swift` is frozen; five titles at the 280
    pt minimum are 56 pt each).
  - (b) The layer pass's `texture(4)` is CO's layer mask and `texture(5)` CU's cursor sprite.
    `LayerUniforms` groups of four are appended in landing order, and the integrator re-pins every
    proof that names the block's size.
  - (c) Every analysis kind of every bet lives in CJ2a's store under `cache/analysis/<kind>/` and
    runs on CJ2a's lane: `shots` and `faces` (CJ), `subjects` (VR), `masks` and `masks_best` (CO),
    `sound_events` (FC). No bet adds a sibling folder or a lane for analysis. Kind names use
    underscores.
  - (d) The road map's tools join dispatch through `AgentServer+CreatorJobs.swift`:
    `creatorHandlers` and `creatorOffMainTools`, merged into the frozen file's `handlers` and
    `offMainTools` by its two existing lines (CJ0c's T8). Only an `opsWithoutTools` entry goes in
    the frozen file, as one line of wiring with its reason (CJ5a's `keep_range`). Dev tools join
    through `AgentServer+DevTools.swift`.
  - (e) A phase that adds a key equivalent records it, and the integrator checks
    `docs/guide/menus-and-shortcuts.md` for a clash before landing.
  - (f) A bet's command is a composite over ops landing as one undo step through
    `performGroupedEdit`, and its tool runs the same planner (SY-1's shape), unless its rule must
    hold inside the core, in which case it is an op.
  - (g) The pinned counts a new tool or op moves — `OP_COUNT`, `PRODUCT_TOOLS`, `OPS`, `TOOLS`,
    `APP_STATE_TOOLS`, root `CLAUDE.md`'s "one hundred and six product tools", `app/CLAUDE.md`'s
    "sixty-four op tools", `documentLevelNames` (nine today: `refused_inside`'s ten less
    `add_adjustment_clip`) with `app/CLAUDE.md`'s stale "eight", `scope.rs:172`'s "fifty-three"
    (the ops that work inside a nest: `OP_COUNT` less `refused_inside`'s arms, 64 − 10 = fifty-four
    today, plus whatever the road map adds), spec §6a's "Ten ops", the dev tools' count in
    `dev_tools.py`, the catalog snapshot, `recording_probe.py`'s last-names assertion, and the
    assistant's tool lists (F4) — are edited by the phase that moves them, listed in its Docs and
    Acceptance, and renumbered by the integrator when two lanes move one.
  - (h) One composition-plan options export, `rc_project_composition_plan_opts(const RcProject *p,
    const char *opts_json)`, memoised per handle and options string: SW9a builds it (option
    `show_tracks`), VR7b adds `framing`. Without options the plan is byte-identical to
    `rc_composition_plan`'s.
  - (i) One action classifier, `core/src/action_class.rs` (`is_zoom`, `is_layout`, `moves`):
    whichever of CU7 and CO6 lands first creates it; the other reuses it. Actions carry no tag
    (CU-5, CO-63).
  - (j) One phrase splitter: TX7 builds it, pure and parameterised (sentence punctuation, a pause on
    the voice grid, a change of clip, track or speaker); FC4's `ClipSentences` calls it with FC-41's
    parameters.
  - (k) One dev hold for analysis, `-RCDevAnalysisHold <s>` (CJ2a), and one canned-analysis switch,
    `-RCDevAnalysisCanned YES` (CJ-26); VR and CO use them and add no hold of their own.
  - (l) **The FFI's Swift side is `ReelCore.swift` and its `ReelCore+<Area>.swift` files** (owner,
    2026-11-01, CJ0a's question 6: "ReelCore.swift should be extended to multiple files"). Each of
    them may call `rc_*` and no other Swift file does; the FFI contract is a Rust export, its header
    entry and its wrapper in one of them. A new wrapper goes in the `ReelCore+<Area>.swift` of its
    area, as a type of its own or an extension of `ReelProject` (a new area is a new file, under the
    400-line cap for new files); a stored property a wrapper needs on `ReelProject` (a memo) is
    added in `ReelCore.swift`. This supersedes the room ledger (every wrapper paid by a doc-only
    cut). `ReelCore.swift` is split at CJ0d's T15: `// MARK: - Containers` through `ReelWebM`
    (411–612) to `ReelCore+MediaFiles.swift`, `// MARK: - Graphics` (614–739) to
    `ReelCore+Graphics.swift`, `takeErrorMessage` and `takeString` losing `private` — one move gated
    alone (766 → about 436 lines); then T15c, gated alone: the one call outside the files today,
    `rc_agent_string_create` in `AgentServer.swift`'s tool callback (:806), moves behind a
    `ReelAgentSocket` member, the frozen file changing that line only. Homes of the planned
    wrappers: `ReelCursor` `ReelCore+Cursor.swift` (CU1a, CU2); `ReelProject.cuts()`
    `ReelCore+Cuts.swift` (TX4); the plan's options wrapper `ReelCore+Plan.swift`, its memo a stored
    property in `ReelCore.swift` (SW9a, (h)); `ReelContainer`'s track index in
    `ReelCore+MediaFiles.swift` (SW5).
- **CJ-9 — The clip ceiling is decided by spike CJ-S1 at CJ6's head.** Its verdict amends this
  entry: `MAX_CLIPS` stays 4,096 and TX and SW design around it (both read `RC_MAX_CLIPS`, so
  nothing spells 4,096), or CJ6 raises it to the spike's N.

The bets' scope-level decisions, recorded at CJ0a (their phases hold the rest):

- **VR-1 — Auto-reframe is in, as analysis plus ordinary actions.** Subjects are found offline by
  Vision's rectangle and saliency requests on the Mac and cached in CJ2a's store; the core plans the
  framing, and the result is placement and actions on the clip. No mask, no shipped model, no pixel
  work outside the one-pass compositor.
- **VR-2 — Bet 3 needs no key.** No VR control is disabled for a missing key.
- **VR-3 — A regenerated copy first; linked versions after it, on the owner's yes (CJ0a's
  question 8, 2026-11-01).** The planner answers a framing path, a similarity per instant from the
  source canvas to the target; the copy composes it into each clip, and linked versions store it
  per framing (VR7a–VR9). If the vertical trial withdraws the yes before VR7a, VR7a–VR9 are filed as
  one issue carrying their design.
- **VR-4 — Subjects are boxes, detected per sample, never tracked by Vision.** Faces come from CJ3's
  `faces`; people (`VNDetectHumanRectanglesRequest` r2, `upperBodyOnly` false) and salient regions
  (`VNGenerateAttentionBasedSaliencyImageRequest` r2) from VR1's `subjects`. A fresh
  `VNImageRequestHandler` per sample; no `VNTrackObjectRequest` or other stateful request. Linking
  boxes across samples is the core planner's (CJ-31); masks are out for framing (E9: they flicker).
- **VR-5 — The planner is the core's, and `reframe_clip` is an op (CJ-8 (f)).** Swift measures and
  caches; the core maps samples into clip time, chooses subjects, plans, enforces coverage and
  writes actions, because coverage (VR-7) needs (★) and `fill_scale` and composition into existing
  action ends needs the actions' own evaluation. The op is a pure function of the project and the
  samples handed to it.
- **VR-6 — No nest is made to make room for framing.** Framing is composed into the clip's own base
  and actions; a nest would cost tracks against `MAX_TRACKS` and wall the clip off from blurred
  backgrounds, filler cuts and the transcript.
- **VR-7 — A followed picture never shows the canvas, with three named exceptions.** The window lies
  inside the clip's picture (scale at least fill, offsets clamped by (★)), every key is a covering
  state, and one curve carries x, y and scale, so every frame between keys covers too (the covering
  placements are convex). Exceptions: **`fit` spans** (the whole picture, the canvas around it,
  unless `backdrop` puts a blurred copy behind; a nest clip has none); **motion** (a `video.motion`
  that moves or turns the layer keeps its motion, and the guarantee excludes its span — the whole
  clip for a During motion; `spin` counts as rotation; `fade` is not an exception); **opacity**
  (fades, transitions and opacity below 1 are the author's).
- **TX-70 — A review pass may strike a phrase the speaker said again, found by comparing the spelled
  words of neighbouring phrases; it offers every strike for review and cuts nothing until the person
  removes it. Amends TR-3, AI-6 and W-9** (the orchestrator's reading of the owner's "Add all: 1-6",
  2026-11-01: bet 1 as the survey wrote it carries survey decision 3's amendment; confirmed by the
  owner, CJ0a's question 7, 2026-11-01). It finds a **restart** (a phrase whose words are the opening words of the next), a
  **retake** (a phrase of four or more words most of whose words recur, in order, at the start of
  one of the next few phrases, TX-71's numbers) and a **repeat** (one to four words said twice in a
  row); the earlier is struck, the last kept. It reads each word's text lowercased with edge
  punctuation trimmed (TR-8's rule, fillers left out), their order, the pauses between them (the
  voice cache) and sentence punctuation; phrases are compared only within one track and, where
  labels exist, one speaker; one take placed twice (the same media's same source ticks) is never a
  retake. No model reads the words, nothing is sent, no key is needed. A false start that repeats no
  words stays the assistant's, on the person's ask (TR-5). Amending lines: **TR-3** "a false start
  that repeats words — a restart, or a line said again — is found by TX-70's comparison of spelled
  words and offered struck for review; one that repeats no words is found only by reading what was
  meant, so no pipeline does it (W-9, AI-6); the assistant may, when the person asks (TR-5)";
  **AI-6** "a pipeline may strike words for review by comparing their spelling, order and timing
  with the phrases beside them; that is not picking words by meaning, and nothing is cut until the
  person removes the strikes"; **W-9** "the Transcript tab's review pass strikes repeated phrases
  for the person to remove, by comparing spelled words, never by a language model; captions are
  untouched". Risk accepted: a deliberate repetition is struck and shown for review.
- **SW-3 — Multicam is in, as a program track over angle tracks.** Synced camera clips (angles) stay
  whole on their own tracks; a program track holds the shots, each an ordinary clip copied from an
  angle at the same time. Switch by Speaker writes the program track, Switch Angle re-picks a shot,
  and the Angle Viewer shows every angle and switches while playing. There is no multicam source
  kind and no nest in point: every shot can be rolled, trimmed, graded and deleted like any clip,
  and spec §2's one kind of track holds.

Bet 2's scope-level decisions, recorded at CU0a (2026-11-01) before any CU code (its phases hold
the rest):

- **CU-1 — The cursor, clicks and scrolls are data; shortcuts are opt-in; the editor draws the
  cursor** (the orchestrator's reading of the owner's "Add all: 1-6" and "The recorder can ask for
  input monitoring", 2026-11-01; CJ0a's question 7 confirms the `recording.md` amendments). Zooms,
  overlays and speed-ups are generated as ordinary edits. No cursor is reconstructed for a recording
  without a cursor file or for an imported screen video; no vision pass looks for a pointer.
- **CU-2 — The cursor file.** One per segment movie, `<movie stem>.fjcursor`, beside the movie in
  `~/Movies/Frame Job Recordings/`. The core owns the format (`cursor_file.rs`'s module doc is its
  specification): Swift writes it and the core reads it back before it is renamed into place.
  Versioned (the core reads every version up to its own and refuses a newer one by name). The header
  carries the stream's content size (points × pixels per point) and `movie_size` (the written
  movie's track size, read back at the segment's close; the encoder rounds an odd dimension up).
  Attached at import as `media.cursor = {path, bookmark?, in_picture}`.
- **CU-3 — Input Monitoring, the recorder's fourth grant.** Read and asked by the pair CU-S1's A11
  picks (`grant_api`): `CGPreflightListenEventAccess()` and `CGRequestListenEventAccess()`, or
  `IOHIDCheckAccess` and `IOHIDRequestAccess` with `kIOHIDRequestTypeListenEvent`; asked from the
  panel only, when Record shortcuts is on and Record is pressed; asked once
  (`FrameJobInputMonitoringAsked`, counted only in a launchd-owned launch, `launchClause` on every
  sentence), after which each press opens `Privacy_ListenEvent`. `record_screen` refuses `keys`
  without it: "Input Monitoring is not granted to Frame Job. Turn it on in System Settings ▸ Privacy
  & Security ▸ Input Monitoring." plus "then relaunch Frame Job." only when CU-S1 says
  `relaunch=needed`, plus `launchClause`. Accessibility is never asked; Frame Job never posts an
  event; no Info.plist key or entitlement unless CU-S1 measures one is needed.
- **CU-4 — The cursor is part of its clip's layer, not a clip of its own.** The layer stage
  composites the sprite and its ripples over the source texel inside `layerSample`
  (`Compositor.metal:800`), before `gradeSample`, so crop, placement, grade, filters, spotlight,
  obscure regions, mattes, transitions, every transform, zoom action, nest and ramp meet it as they
  met a burned pointer. The sprite binds at `texture(5)` (CJ-8 (b)); no frame copy, no new pipeline.
  The core computes the cursor's source time and state; the compositor draws and never opens a file
  or computes a path (CU-37).
- **CU-5 — Planners live in the core, and their results are ordinary ops.** Auto zoom, shortcut
  overlays and typing stretches are pure functions of the cursor file and the project, answering
  lists of existing ops (and CU9a's one new op) applied as one named undo step. Nothing is tagged
  "generated"; re-planning finds zooms by content (`action_class.rs`, CJ-8 (i)). A reversed clip is
  refused by name by every planner and by `get_cursor_events` in clip time ("clip C plays reversed;
  <command> plans only clips that play forward"), since mapping it would put a mirror in the core
  (D4-6).
- **CU-6 — The spikes' rules are CJ0's**, each verdict recorded before the phase that depends on it.
  **Settled at CU0b** (2026-11-01; `designs/creator-jobs.md`'s "CU0b's record", every rule's
  `rule_sha256` equal to CJ0a's): CU-S4 `body=json smoothing=whole-file` (CU-10's body is
  columnar JSON, version 1, and smoothing is prepared over the whole file). Every CU-S1, CU-S2 and
  CU-S3 field is `owed`. The console was locked and the terminal could not post, so those rows were
  skipped by name, and the owner runs them with the person tier (`docs/manual-checks.md` JOB-29)
  before CU1b and CU6. None is a STOP.
- **CU-7 — Keys are private by construction.** A key-down while ⌘ or ⌃ is held is a shortcut, stored
  with its spelled keys; every other key-down and every auto-repeat is a mark with a time and no
  identity; no character, key code or label of a typed key is ever stored, so none can reach a tool
  answer, the project or the Assistant. Nothing is recorded, not even timing, while any process
  holds secure input (`IsSecureEventInputEnabled()`); a password field that does not turn secure
  input on (a Terminal `sudo` prompt without Secure Keyboard Entry) is recorded as time-only marks.
  No "all keys" mode (it would put typed text, passwords included, into the project). The status
  item shows a mark while shortcuts record (CU-61).
- **CU-8 — No recorder's code is carried over.** Cap is AGPL-3.0 (the Concat rule applies);
  OpenScreen (MIT) and the rest are not carried either; algorithms are written from their stated
  rules.
- **CU-9 — The FFI surface is three exports, and their wrapper is a ReelCore file of its own.**
  `rc_cursor_open(bytes, len, err_out)` (parse and validate; a check is an open and a free),
  `rc_cursor_free`, and `rc_cursor_query(tracks, n, project, request_json, err_out)`: every read — a
  frame's state, an image (base64 PNG inside the JSON), events, the path, each planner — is one JSON
  request and answer. The Swift side is `ReelCursor` in `ReelCore+Cursor.swift` (init, `deinit`,
  `query`, about 30 lines), its typed answers in `CursorValues.swift` (no `rc_*`) (CJ-8 (l)); no
  room is paid.

The phases' decisions, recorded at each phase before its code:

- **CJ-50 — `keep_range {from, to}` answers the project holding only `[from, to)` of its top-level
  timeline, moved to start at 0, every track passing THE overlap rule, and only what the kept clips
  play left in `media[]` and `nests[]` (CJ5a, `core/src/edit_keep_range.rs`).** No tool, UI, FFI or
  format change; CJ5b's `new_project_from_range` is its door.
  - (a) **Bounds (N2).** `from` and `to` are each snapped to the frame grid and clamped to 0, as
    every op's ticks are. `to` not after `from` is invalid input, an `Err`: "keep_range's to must be
    after its from (from F, to T ticks, on the frame grid)". `ordered_range` is not followed: an
    empty keep is not an identity.
  - (b) **A nest clip a bound lies strictly inside is refused**, the first in `clips[]` order, at
    `from` and then at `to`: "Clip N is a nest across the range's edge; a nest clip has no in point,
    so a cut there would replay it from its start. Move the edge, or open the nest and unnest it."
    A nest clip exactly at an edge, wholly inside or wholly outside is kept or removed as any clip.
  - (c) **The cut.** Every top-level clip on ANY track, locked or not (the derived document keeps
    its locks; the source document is never edited), that `from` lies strictly inside is cut there
    by `split`'s own cutter (`split_clip`) and its halves paired (`pair_split_halves`); then the same
    at `to`. A ramp (SR-18 (e)), a timed caption page (W-3) and a linked pair (AU-92) follow
    `split`'s rules exactly.
  - (d) **THE overlap rule at the edges (N1)**, judged on the overlaps of the source's tracks. At
    `from`, an overlap `[os, oe)` with `os ≤ from < oe` drops the outgoing clip's piece that starts
    at `from`, and the incoming clip's piece starting at `from` loses its `transition_in` (a hard
    start). At `to`, an overlap with `os < to ≤ oe` drops the incoming clip's piece that ends at
    `to`, so the outgoing clip ends there — except when that piece starts at `from` (both bounds in
    one overlap, `os ≤ from < to ≤ oe`): it is the incoming piece the `from` rule kept, and it
    stays, hard-cut. The edges stay where asked. A dropped piece's linked partner stays unless its
    own track's rule drops it; `finish`'s `settle_links` clears the dangling link.
  - (e) **Keep and move.** Every top-level clip not wholly inside `[from, to)`, and every dropped
    piece, is removed; the rest move by −`from`. Markers with `from ≤ time < to` are kept and moved;
    the others are removed. Every track is kept, empty or not, with its settings and lock; the
    canvas is unchanged; `next_id` only advances.
  - (f) **What a range leaves unused goes.** `nests[]` keeps only the nests the kept top-level clips
    reach, through nest clips inside kept nests too, so a nest no clip showed in the source goes as
    well. `media[]` keeps, in order, a media that a clip of the kept timeline or of a kept nest uses
    as its source, or names in a look (the base look and every action end, `look_media_ids`), or
    that is a kept media's `color.lut`; every other media goes.
  - (g) **Refusals after the cut.** No top-level clip left: "Nothing plays between F and T ticks."
    Then each track of the result passes `check_overlap_rule`; where it fails, the first overlap on
    that track longer than the half-shorter limit is refused as "Keeping F to T ticks would leave
    clips A and B overlapping by D ticks, more than half of the shorter piece (L ticks); move an edge
    further from their transition.", A and B the ids of the SOURCE clips the pieces were cut from
    (an uncut clip is its own source); with none found, the rule's own sentence. The edge rule (d)
    repairs only an overlap an edge lies in; a piece left shorter than twice a transition wholly
    inside the range is refused, never repaired: clips never push each other.
  - (h) **Document-level, with no tool.** It exits through `finish` (an identity when nothing
    changed). It is `refused_inside`'s eleventh arm ("keep_range has no meaning inside nest N": it
    is the document's timeline), `ReelOp.documentLevelNames`' tenth name, and the first entry of
    `AgentServer.opsWithoutTools`, because it discards everything outside a range: only File ▸ New
    Project from Range… and `new_project_from_range` (CJ5b) apply it, to a derived document.

CJ-20…CJ-27 are CJ2a's (the analysis lane, its store and reader, `shots`, the dev tool `analysis_job`), recorded before its code.

- **CJ-20 — Analysis is a cache, made on demand.** It never runs at import, is never project
  state, and is never read by the composition plan or the frame recipe; a planner reads it and
  writes ordinary edits. A render drawn from it (CO's masks) is substituted by Swift, as a reversed
  file is (§5.6). No analysis kind bumps the format, adds an `rc_*` export or changes the core. The
  speech cache's import-time rule stands for speech.
- **CJ-21 — One lane, `AnalysisLane`, process-wide, with two queues:** a picture queue
  (`com.kgalligan.framejob.analysis-picture`, decodes and Vision) and a sound queue
  (`com.kgalligan.framejob.analysis-sound`, audio decodes and Sound Analysis, serial and idle until
  FC3), so a sound job never waits behind a face job. Each is a `DispatchQueue` at `.utility`,
  never the cooperative pool, never `MediaCacheLane`. A job is a source, a window's missing ranges
  and its kind; kinds that share a reader, a size and a grid decode once (`faces` and `subjects`,
  CJ3 and VR1). Jobs are wanted by owners — a document's command, a tool call, an export — as ramp
  audio's renders are (SR-12): `want` replaces an owner's set, an unwanted job is cancelled, a job
  wanted again while running is not, an owner whose `alive()` answers false is dropped at the next
  50 ms poll, `wait` returns on landing, failure, cancellation or its deadline, and an owner's
  `settled` runs on main after a landing or a failure. The lane keeps each of the last 256 jobs'
  runs (queued, started, ended, in process uptime, and the outcome). A job takes no `CachePass` and
  writes only through `AnalysisStore.publish`, inside `CacheLedger.publish(in:for: nil)`, so an
  import pass and an analysis job of the same media never cancel or wait on each other; it
  publishes at each range's end and after every 30 s of wall time. `-RCDevAnalysisHold <s>`
  (`FRAMEJOB_DEV_TOOLS` only) holds each job before its first frame, polling cancellation every
  50 ms. **Spike CJ-S3 (2026-11-01, `rule_sha256` `209c6f01…ce830`, matching CJ0a's table; OS
  build 25F80, Apple M2 Max, on AC, three lanes loading the machine; synthetic files, S-TH4
  owed):** frames a second, median of three, at long sides 256 / 1280 — the 4K HEVC 10-bit HLG
  file direct 213 / 244 and converted 668 / 618, two jobs at once 395 / 484 and 704 / 707; the
  1080p H.264 file direct 582 / 736, two jobs 1,124 / 1,465. **(a) The picture queue's width is
  1** (`AnalysisLane.pictureWidth`): rule (a) is applied at shots' size on each file through the
  reader (c) gives it, and two converted jobs reach only 1.05× one (the 1080p file's direct jobs
  reach 1.93×). **(b), measured with the lane built** (`lane_spike.py --playback`, the Debug
  app): `play_preview` composed 598 of 600 frames over 20 s of a 1080p30 timeline idle and 593
  while another document's ten-minute `shots` job ran (medians of 600 / 580 / 598 and
  593 / 588 / 599), a drop of 0.84 %, under 2 %: the picture queue does not pause while a
  transport plays, and `BackgroundRender.anyPlaying` is not added.
- **CJ-22 — The store.** A kind's results for one media are a marker `cache/analysis/<kind>/<media
  id>.json` and a payload folder `cache/analysis/<kind>/<media id>/` holding the files the kind
  names (`shots` a `frames.bin`, `faces` a `samples.bin`, CO's masks one movie per chunk and its
  mirrored chunks, FC's `sound_events` a `windows.bin`). A kind whose variants must coexist puts
  the variant in its name (`masks`, `masks_best`). Every kind has a grid on source time and stores
  per grid point only values that depend on that point's input and a fixed neighbourhood the kind
  names, never on where a job began or what else is cached; thresholds over time, minimum lengths,
  smoothing and identity are applied when a request is answered. The marker holds the
  `AnalysisStamp`, the payload's files and the COVERAGE: the sorted ranges of grid indices stored,
  merged where they overlap or touch, inclusive. A request is a hit when the coverage holds every
  index of its window plus the kind's read margin; otherwise a job runs only the missing ranges,
  each with the kind's pre-roll, and the coverage grows. **The publish** (`AnalysisStore.publish`):
  under a lock keyed by (cache folder, kind, media id), inside `CacheLedger.publish(in:for: nil)`,
  it re-reads the marker, deletes marker then payload when the on-disk stamp differs from the
  job's, reads the payload as it is on disk, applies the job's merge, writes it through a
  `.partial` and a rename, then writes the marker with the union of the on-disk and the job's
  coverage, sorted keys, `.atomic`; nothing in it waits on the main thread, so two jobs of one
  media merge rather than overwrite. The `AnalysisStamp` is the source's identity (`CacheStamp`'s
  size, modified second and duration; no path), the kind and its version (Vision request revisions
  inside it), a SHA-256 of the sorted-key JSON of the parameters the stored values depend on
  (never T or m), the OS build (`kern.osversion`), the compute device (`cpu` for `shots`), and the
  reader's input (`raw`, or `converted` with the conversion as `ConvertedThumbsStamp` records it).
  A stamp that differs in any field is a miss, compared field by field; relink, consolidate and
  `set_media_color` therefore invalidate as for every cache. Coordinates are normalised 0…1 in
  the media's display orientation, origin top-left, and every answer carries the display size;
  times are forward-media source ticks, so any clip, speed, ramp or reversal reuses them through
  `SourceMap` and `ReverseMirror`.
  **Amended by CO-4 (CO0):** masks keep one payload file per media in the media's folder, the pack
  `masks.pack` (CO-S2's verdict; the draft's one movie per chunk, and its mirrored twin, were not
  kept).
- **CJ-23 — The frame reader.** `AnalysisFrames.swift` has a direct reader
  (`AVAssetReaderTrackOutput` over the first video track, 32BGRA, scaled to the kind's long side,
  turned upright from the track's `preferredTransform`) and a converted reader
  (`AVAssetReaderVideoCompositionOutput` over `MediaImporter.oneClip`'s composition, its
  `renderSize` the kind's size as Preview Quality sets one, read in the compositor's one format,
  64RGBAHalf, through step 0, so analysis sees what the person sees; its `RecipeSource` key is
  unregistered after). **Spike CJ-S3 (c): converted for converting media** — whenever
  `ThumbnailInput(media:urls:)` (a converting Camera Log or a PQ peak) or `ThumbnailInput(track:)`
  (an HLG or PQ track) exists — **and direct for the rest**, unless CJ-S2's rule 5 says otherwise
  for a kind; the converted reader cost 0.32× the direct one per frame on the HLG file. Frames
  arrive in presentation order; a frame's grid index is round(pts × fps) on the media's rate and
  the first frame on an index wins; a sample at k / rate takes the first frame at or after it. **The
  pre-roll is decoded frames, not indices:** a range's read starts two frame durations before its
  first index and, while fewer than two kept frames precede that index, restarts from twice as far
  back, until two do or the media's start is reached; only indices inside requested ranges are
  stored. CO-7 adds a third arm for masks (CO1).
  **Amended by CO-7 (CO0):** the masks' third arm reads with `AVAssetReaderTrackOutput`, every
  frame's presentation time kept, and converts a converting media's frames through step 0's own
  `InputPass` on the GPU, never through the one-clip composition.
- **CJ-24 — `shots`: hard cuts from a deterministic picture difference, no ML.** **Spike CJ-S4
  (2026-11-01, `rule_sha256` `eea6c190…46f9d1`, matching CJ0a's table; S-TH1 missing, so the
  no-cut input is ten minutes of the moving still and S-TH1 is owed):** the signature is a 4 × 4 × 4
  colour histogram (the top two bits of each of R, G, B) of the frame at long side 256, in
  whole-pixel counts; the distance is their L1 summed exactly and divided once by the pixel count
  (0…2, equal counts give equal values), stored as `Float32`. **T = 0.34, m = 12, PASS:** recall
  39 of 39 (100 %) on the 40-clip export at every T from 0.04 to 0.64, with no false cut on the
  ten-minute no-cut input from T = 0.08 (the 32-bin luma histogram also reached 100 %, from 0.20 to
  0.62; the tie went to the wider band, the colour histogram, whose median T is 0.34); every m of
  4, 6, 8 and 12 kept every cut of the fixture. **Stored per frame** (`frames.bin`, one 16-byte
  little-endian record per grid index from 0: `Int64` pts in ticks, −1 for no frame, `Float32` d1,
  `Float32` d2): d1(i), the distance to p1(i), the greatest index below i holding a frame, and
  d2(i), to p2(i), the greatest below p1(i); none → 0. **When answered,** frame i is a cut when
  d1(i) ≥ T; d2(n(i)) ≥ T, n(i) the least index above i holding a frame, the test passing when no
  frame lies in i+1…i+m+1 or at the media's end (a single flash frame returning to the shot is not
  a cut); and d1(i) is the largest d1 over i−m…i+m, an empty index counting 0, ties to the earlier.
  The read margin is m + 1 indices each side, clamped to the media. **Measured limits, stated in
  the guide:** a dissolve whose per-frame distances stay under T is not a cut (the fixture's, between
  two photographs, peaked at 0.16), but a dissolve between flat-coloured pictures (test patterns,
  slides, title cards) moves whole bars across a bin in one frame and peaked at 1.04, so it can be
  answered as one cut; and the flash rule rests on the return frame's d1 not exceeding the flash
  frame's — exact when the flash shares no bin with the shot (a white frame over the fixture: both
  2), not when the frames either side differ in the flash's bin.
- **CJ-25 — `get_media_analysis {media | clip, kind, from?, to?}` reads any kind, running or reusing
  it.** Exactly one of `media` and `clip`; `kind` from the kinds built (`shots` here); `from` and
  `to` integer forward-media source ticks, not snapped; with `clip` they default to, and are
  clamped to, the clip's played source window (`SourceMap`, `ReverseMirror`), and each cut is also
  answered as `clip_time` (ticks from the clip's start in its playing direction, a reversed clip
  through `pivot − source` first) and `timeline` (clip start + `clip_time`). It runs off main
  (`creatorOffMainTools`): one main-thread hop resolves the document, the arguments, the cache
  folder, the file and the request; the call wants it under an owner of its own (alive while the
  document is open and the call is not stopped), waits **holding the agent lane's lock**, as
  `get_transcript` does, and releases the owner on every exit. It answers `ok`, `kind`, `media`,
  `clip`, `from`, `to`, the display `size`, `cached`, the `stamp`, `run` (`queued_at`,
  `started_at`, `ended_at` in process uptime, only when it ran a job), `count`, `cuts`
  (`{frame, source}` and with `clip` `clip_time` and `timeline`) and `project`. **The bound,
  `AnalysisLane.callWaitLimit`, is 60 s** — CJ-S3's ten minutes of 4K HLG through the converted
  reader at 256 (26.9 s), × 2, rounded up to 10 s, inside 30…300 s; past it the call refuses naming
  the seconds of the window covered and "call again to continue", the job's published ranges kept.
  **The cap** is 512 KiB of `cuts` JSON; over it the call refuses naming the largest `to` from
  `from` that fits. Refusals, in order: not exactly one of `media` and `clip`; an unknown id; not a
  media clip, or a media with no moving picture; the file missing; `to` ≤ `from`; the bound; the
  cap. It is `get_transcript`'s counterpart for pictures and sounds; every kind answers through it.
  On device, no network, no key (CJ-3).
- **CJ-26 — A canned analysis is honoured only for a proof:** a marker with `"canned": true`
  carries only the source identity and is read only in a `FRAMEJOB_DEV_TOOLS` build launched with
  `-RCDevAnalysisCanned YES` and a matching `source`, so a planner's proof is byte-exact on any Mac
  and Distribution never reads one. Without the flag a canned marker is a miss and the next store
  replaces it.
- **CJ-27 — `analysis_job`, a dev tool (`FRAMEJOB_DEV_TOOLS` only), stands in for a document's
  command owner (CJ2b) in proofs,** because the MCP server answers one request at a time
  (`core/src/agent.rs`), so no call can overlap a held `get_media_analysis`. `analysis_job
  {project?, media?, kind?, from?, to?, wait?}`, off main: with `media` (then `kind` required, the
  window as `get_media_analysis`'s `media` form) it wants the window's missing ranges under that
  document's dev owner — one owner per document, alive while it is open, each want passing the
  owner's earlier requests too — and returns at once; with `wait` (seconds, 0…`callWaitLimit`) it
  then waits until every dev-wanted request has ended. It answers `{ok, now, wanted: {project,
  media, hit}?, jobs}`, `jobs` being every request a dev owner wanted since launch with its
  `ranges`, `queued_at`, `started_at`, `ended_at` and `outcome` from the lane's runs, and `now` the
  process uptime. Without `media` it targets no document. The assistant never sees it (AI-7's
  dev-tool rule).
