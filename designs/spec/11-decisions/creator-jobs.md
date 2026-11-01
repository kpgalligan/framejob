# Spec §11 — decisions: Creator jobs (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map `designs/creator-jobs.md` builds the six bets of its survey,
`designs/creator-survey.md`, for people who record themselves talking: the words (TX), the cursor
and the recorder (CU), the camera cutout and layouts (CO), vertical versions and framing (VR),
finding clips (FC) and switching between cameras and audio tracks (SW), with the shared work (CJ).
Its IDs follow CJ-7: phase XXn records XX-n0…XX-n9, a zero phase XX-1…XX-9, and a bet with no zero
phase records its scope-level decisions here under its own prefix. Each was recorded before its
code. The series continues in `creator-jobs-2.md` past about 500 lines.

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
